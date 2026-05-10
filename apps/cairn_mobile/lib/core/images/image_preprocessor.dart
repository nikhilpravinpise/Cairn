/// Image preprocessing seam for inference.
///
/// Separates the image bytes stored in [SessionDraft] (original capture
/// quality) from the bytes sent to the Gemma vision model (bounded size for
/// faster prefill). The original bytes are *never* modified; preprocessing
/// only happens at the moment [GemmaOrchestrator.describePhoto] calls
/// [prepareForInference].
///
/// ## Why this matters
///
/// Gemma 4 uses variable-resolution vision tokens (70 / 140 / 280 / 560 /
/// 1120). Feeding a 1600-wide JPEG allocates the maximum token budget and
/// dominates prefill time. Down-scaling to 768 or 512 on the long edge can
/// cut prefill time materially with no change to the JSON contract.
///
/// ## Adapters
///
/// - [BoundedImagePreprocessor]: production path. Resizes so the longest
///   edge ≤ [maxLongEdgePx], preserving aspect ratio. Images already within
///   the bound are returned unchanged (no upscaling, no re-encode cost).
///
/// - [PassthroughImagePreprocessor]: no-op. Used in tests and benchmarks
///   that need to measure the raw-bytes baseline.
///
/// ## Benchmark variants
///
/// | Constant                        | maxLongEdgePx | Notes                          |
/// |---------------------------------|---------------|--------------------------------|
/// | `BoundedImagePreprocessor(768)` | 768           | Sprint 3 conservative default  |
/// | `BoundedImagePreprocessor(512)` | 512           | Aggressive candidate           |
/// | `PassthroughImagePreprocessor`  | —             | Baseline (raw capture bytes)   |
///
/// See `docs/optimization-plan.md §OPT-1` and `tool/benchmark_session_config.ps1`
/// for the benchmark runner.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Preprocessing contract for the inference image path.
///
/// Callers pass raw capture bytes; implementations return bytes suitable for
/// [Message.withImage] in [GemmaSession.generate].
abstract interface class ImagePreprocessor {
  /// Return bytes ready for model inference.
  ///
  /// Implementations may downscale, change format, or return [rawBytes]
  /// unchanged. Callers must not assume the returned bytes are identical to
  /// [rawBytes] even when the implementation is [PassthroughImagePreprocessor].
  Future<Uint8List> prepareForInference(Uint8List rawBytes);
}

/// In-memory wrapper that avoids repeated decode/re-encode work for identical
/// photo byte objects during one screening session.
final class CachingImagePreprocessor implements ImagePreprocessor {
  CachingImagePreprocessor(this._inner, {int maxEntries = 16})
      : assert(maxEntries > 0, 'maxEntries must be > 0'),
        _maxEntries = maxEntries;

  final ImagePreprocessor _inner;
  final int _maxEntries;
  final _cache = <Uint8List, Future<Uint8List>>{};

  int get entryCount => _cache.length;

  @override
  Future<Uint8List> prepareForInference(Uint8List rawBytes) {
    final existing = _cache[rawBytes];
    if (existing != null) return existing;

    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    final prepared = _inner.prepareForInference(rawBytes);
    _cache[rawBytes] = prepared;
    return prepared;
  }
}

// ---------------------------------------------------------------------------
// Header-only dimension reader
// ---------------------------------------------------------------------------

/// Reads image dimensions from JPEG or PNG header bytes without a full decode.
///
/// Returns `(width, height)` when the format is recognized; `null` otherwise.
/// Callers that receive `null` fall back to the codec-probe path.
///
/// **PNG**: IHDR chunk always starts at byte offset 8. Width/height are
/// big-endian uint32 at offsets 16-19 / 20-23 respectively.
///
/// **JPEG**: Scans for SOF0 (0xC0), SOF1 (0xC1), or SOF2 (0xC2) markers.
/// Fill bytes (extra 0xFF bytes before a marker type) are skipped per the
/// JPEG spec. 0xFF 0x00 byte-stuffed sequences in compressed data are skipped.
/// SOF layout from the marker-type byte: `[segLen 2B][precision 1B][H 2B][W 2B]`,
/// so height is at `marker+4..5` and width at `marker+6..7` (big-endian uint16).
(int, int)? _dimensionsFromHeader(Uint8List bytes) {
  if (bytes.length < 24) return null;

  // PNG signature: 0x89 'P' 'N' 'G'
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final w =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final h =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return (w > 0 && h > 0) ? (w, h) : null;
  }

  // JPEG signature: FF D8 (SOI)
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    int i = 2;
    while (i < bytes.length) {
      // Each JPEG marker begins with one or more 0xFF bytes followed by the
      // actual marker-type byte (non-0xFF, non-0x00).
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      // Skip fill bytes — the spec allows any number of 0xFF bytes before
      // the marker type (e.g. 0xFF 0xFF 0xFF 0xC0 is a valid SOF0 marker).
      int k = i + 1;
      while (k < bytes.length && bytes[k] == 0xFF) {
        k++;
      }
      if (k >= bytes.length) break;

      final marker = bytes[k]; // Real marker-type byte (never 0xFF here).
      if (marker == 0x00) {
        // 0xFF 0x00 is byte-stuffing inside compressed scan data, not a marker.
        i = k + 1;
        continue;
      }

      // SOF0 (baseline), SOF1 (extended seq.), SOF2 (progressive JPEG).
      // Layout from marker byte: [segLen 2B][precision 1B][height 2B][width 2B]
      if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        if (k + 7 >= bytes.length) break; // need k+4..k+7
        final h = (bytes[k + 4] << 8) | bytes[k + 5];
        final w = (bytes[k + 6] << 8) | bytes[k + 7];
        return (w > 0 && h > 0) ? (w, h) : null;
      }

      // SOI (D8), EOI (D9), RST0..RST7 (D0..D7): no payload.
      if (marker == 0xD8 ||
          marker == 0xD9 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i = k + 1;
        continue;
      }

      // All other markers carry a 2-byte length (inclusive of those 2 bytes).
      if (k + 2 >= bytes.length) break;
      final segLen = (bytes[k + 1] << 8) | bytes[k + 2];
      if (segLen < 2) break;
      i = k + 1 + segLen; // Advance past this segment.
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Production adapter
// ---------------------------------------------------------------------------

/// Downscales images so the longest edge is at most [maxLongEdgePx] pixels,
/// preserving aspect ratio. Images already within the bound are returned
/// unchanged (no re-encode, zero overhead).
///
/// Resized output is PNG (lossless, accepted by `Message.withImage`).
///
/// ```dart
/// const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 768);
/// final inferenceBytes = await preprocessor.prepareForInference(captureBytes);
/// ```
final class BoundedImagePreprocessor implements ImagePreprocessor {
  const BoundedImagePreprocessor({required this.maxLongEdgePx})
      : assert(maxLongEdgePx > 0, 'maxLongEdgePx must be > 0');

  /// Maximum size of the longest dimension in the output image, in pixels.
  final int maxLongEdgePx;

  @override
  Future<Uint8List> prepareForInference(Uint8List rawBytes) async {
    // --- Fast path: read dimensions from JPEG/PNG header (no decode needed) ---
    //
    // Camera photos are almost always JPEG. Parsing the header avoids decoding
    // the full native image (up to ~48 MB ARGB for a 12 MP shot) just to read
    // two integers. Falls back to the codec probe path for other formats.
    final headerDims = _dimensionsFromHeader(rawBytes);
    if (headerDims != null) {
      final (origW, origH) = headerDims;
      final longEdge = origW > origH ? origW : origH;
      if (longEdge <= maxLongEdgePx) return rawBytes;
      return _decodeAndEncode(rawBytes, origW: origW, origH: origH);
    }

    // --- Fallback: probe decode for unrecognized formats ---
    final probeCodec = await ui.instantiateImageCodec(rawBytes);
    final probeFrame = await probeCodec.getNextFrame();
    final origW = probeFrame.image.width;
    final origH = probeFrame.image.height;
    probeFrame.image.dispose();
    probeCodec.dispose();

    final longEdge = origW > origH ? origW : origH;
    if (longEdge <= maxLongEdgePx) return rawBytes;
    return _decodeAndEncode(rawBytes, origW: origW, origH: origH);
  }

  Future<Uint8List> _decodeAndEncode(
    Uint8List rawBytes, {
    required int origW,
    required int origH,
  }) async {
    final int tw, th;
    if (origW >= origH) {
      tw = maxLongEdgePx;
      th = (origH * maxLongEdgePx / origW).round().clamp(1, maxLongEdgePx);
    } else {
      th = maxLongEdgePx;
      tw = (origW * maxLongEdgePx / origH).round().clamp(1, maxLongEdgePx);
    }
    final codec = await ui.instantiateImageCodec(
      rawBytes,
      targetWidth: tw,
      targetHeight: th,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    codec.dispose();
    if (byteData == null) return rawBytes;
    return byteData.buffer.asUint8List();
  }
}

/// Android-native bounded preprocessor.
///
/// Uses `BitmapFactory` + platform JPEG encoding through a MethodChannel. This
/// avoids the Dart fallback's PNG re-encode for resized camera photos, which is
/// usually much larger than a quality-bounded JPEG and increases image-transfer
/// and model-side decode/prefill overhead.
final class AndroidJpegImagePreprocessor implements ImagePreprocessor {
  AndroidJpegImagePreprocessor({
    required this.maxLongEdgePx,
    this.quality = 82,
    ImagePreprocessor? fallback,
    MethodChannel? channel,
    TargetPlatform? targetPlatformForTesting,
  })  : assert(maxLongEdgePx > 0, 'maxLongEdgePx must be > 0'),
        assert(quality >= 1 && quality <= 100, 'quality must be 1..100'),
        _fallback =
            fallback ?? BoundedImagePreprocessor(maxLongEdgePx: maxLongEdgePx),
        _channel =
            channel ?? const MethodChannel('app.cairn/image_preprocess'),
        _targetPlatformForTesting = targetPlatformForTesting;

  final int maxLongEdgePx;
  final int quality;
  final ImagePreprocessor _fallback;
  final MethodChannel _channel;
  final TargetPlatform? _targetPlatformForTesting;

  @override
  Future<Uint8List> prepareForInference(Uint8List rawBytes) async {
    final platform = _targetPlatformForTesting ?? defaultTargetPlatform;
    if (kIsWeb || platform != TargetPlatform.android) {
      return _fallback.prepareForInference(rawBytes);
    }
    try {
      final prepared = await _channel.invokeMethod<Uint8List>(
        'resizeJpeg',
        {
          'bytes': rawBytes,
          'maxLongEdgePx': maxLongEdgePx,
          'quality': quality,
        },
      );
      if (prepared != null && prepared.isNotEmpty) return prepared;
    } on MissingPluginException {
      // Unit tests and non-Android shells do not register the native channel.
    } on PlatformException {
      // Keep capture/inference robust; the Dart path preserves behavior.
    }
    return _fallback.prepareForInference(rawBytes);
  }
}

// ---------------------------------------------------------------------------
// Diagnostic / test adapter
// ---------------------------------------------------------------------------

/// No-op preprocessor: returns [rawBytes] unchanged.
///
/// Use this in:
/// - Unit tests that need deterministic byte identity.
/// - Benchmark runs measuring the raw-bytes baseline.
/// - Any context where preprocessing should be explicitly skipped.
final class PassthroughImagePreprocessor implements ImagePreprocessor {
  const PassthroughImagePreprocessor();

  @override
  Future<Uint8List> prepareForInference(Uint8List rawBytes) async => rawBytes;
}
