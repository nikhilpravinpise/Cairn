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
/// 1120). Feeding a 1600-wide JPEG allocates heavy image decode/prefill work.
/// S23 FE testing promoted 640 px: it preserved 768 px structural accuracy
/// while 512 px lost soft-story / column-base detail.
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
/// | `BoundedImagePreprocessor(768)` | 768           | Conservative fallback          |
/// | `BoundedImagePreprocessor(640)` | 640           | Production default             |
/// | `BoundedImagePreprocessor(512)` | 512           | Rejected: accuracy regression  |
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
/// const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 640);
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
    final decoded = frame.image;

    // Apply EXIF orientation. Many phone cameras encode rotation in EXIF
    // metadata (TAG_ORIENTATION = 0x0112) rather than baking it into the
    // pixels. `dart:ui` does NOT honour EXIF on decode, so a portrait shot
    // can arrive sideways and the VLM scores it against the wrong layout.
    // The Android-native preprocessor already handles this; this is the
    // fallback path used on iOS / desktop / web.
    final orientation = _readJpegExifOrientation(rawBytes);
    final rotated = await _applyOrientation(decoded, orientation);
    if (rotated != decoded) {
      decoded.dispose();
    }

    final byteData = await rotated.toByteData(format: ui.ImageByteFormat.png);
    rotated.dispose();
    codec.dispose();
    if (byteData == null) return rawBytes;
    return byteData.buffer.asUint8List();
  }
}

// ---------------------------------------------------------------------------
// EXIF orientation
// ---------------------------------------------------------------------------

/// EXIF `TAG_ORIENTATION` (0x0112) value, or 1 (no-op) when no EXIF /
/// orientation is found. Only handles JPEG files (which is what the
/// Android camera plugins return).
///
/// EXIF lives in the APP1 marker (0xFFE1) of a JPEG. Layout:
///   0xFFE1 [seg-len 2B BE] "Exif\0\0" [TIFF header 8B] [IFD0 ...]
/// TIFF header byte 0..1 = byte order ("II" little-endian or "MM" big-endian).
/// IFD0 is at the offset stored at TIFF+4 (4 bytes, in the chosen byte order).
/// IFD0 starts with a uint16 entry count, then 12-byte entries.
/// Each entry: [tag 2B][type 2B][count 4B][value-or-offset 4B].
/// We scan for tag 0x0112 (Orientation), type 3 (uint16); the value is in
/// the low 2 bytes of the value-or-offset slot.
int _readJpegExifOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 1;
  var i = 2;
  while (i + 4 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    // Skip 0xFF fill bytes.
    var k = i + 1;
    while (k < bytes.length && bytes[k] == 0xFF) {
      k++;
    }
    if (k >= bytes.length) return 1;
    final marker = bytes[k];
    if (marker == 0x00 ||
        marker == 0xD8 ||
        marker == 0xD9 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i = k + 1;
      continue;
    }
    if (k + 2 >= bytes.length) return 1;
    final segLen = (bytes[k + 1] << 8) | bytes[k + 2];
    if (segLen < 2 || k + 1 + segLen > bytes.length) return 1;

    if (marker == 0xE1 && k + 9 < bytes.length) {
      // Check "Exif\0\0" header at k+3..k+8
      if (bytes[k + 3] == 0x45 &&
          bytes[k + 4] == 0x78 &&
          bytes[k + 5] == 0x69 &&
          bytes[k + 6] == 0x66 &&
          bytes[k + 7] == 0x00 &&
          bytes[k + 8] == 0x00) {
        final tiffStart = k + 9;
        return _readOrientationFromTiff(bytes, tiffStart, segLen - 8);
      }
    }
    i = k + 1 + segLen;
  }
  return 1;
}

int _readOrientationFromTiff(Uint8List bytes, int tiffStart, int maxLen) {
  if (tiffStart + 8 > bytes.length || maxLen < 8) return 1;
  final endLimit = (tiffStart + maxLen).clamp(0, bytes.length);
  // Byte order
  final b0 = bytes[tiffStart];
  final b1 = bytes[tiffStart + 1];
  final little = b0 == 0x49 && b1 == 0x49; // "II"
  final big = b0 == 0x4D && b1 == 0x4D; // "MM"
  if (!little && !big) return 1;
  int u16(int o) =>
      little ? bytes[o] | (bytes[o + 1] << 8) : (bytes[o] << 8) | bytes[o + 1];
  int u32(int o) => little
      ? bytes[o] |
          (bytes[o + 1] << 8) |
          (bytes[o + 2] << 16) |
          (bytes[o + 3] << 24)
      : (bytes[o] << 24) |
          (bytes[o + 1] << 16) |
          (bytes[o + 2] << 8) |
          bytes[o + 3];

  // Magic 42 at TIFF+2.
  if (u16(tiffStart + 2) != 42) return 1;
  final ifd0Off = tiffStart + u32(tiffStart + 4);
  if (ifd0Off + 2 > endLimit) return 1;
  final entryCount = u16(ifd0Off);
  for (var n = 0; n < entryCount; n++) {
    final eOff = ifd0Off + 2 + n * 12;
    if (eOff + 12 > endLimit) return 1;
    final tag = u16(eOff);
    if (tag == 0x0112) {
      // Orientation: SHORT (type 3), count 1. Value in low 2 bytes of slot.
      return u16(eOff + 8);
    }
  }
  return 1;
}

/// Apply the EXIF orientation to a decoded image by drawing it through a
/// [PictureRecorder] with the appropriate transform. Orientation values:
///   1 = no-op  · 3 = rotate 180°  · 6 = rotate 90° CW  · 8 = rotate 90° CCW
/// Mirror/transpose values (2/4/5/7) are uncommon in phone cameras; we
/// fall back to "rotation only" approximations for those.
Future<ui.Image> _applyOrientation(ui.Image src, int orientation) async {
  if (orientation == 1 || orientation == 0) return src;

  final w = src.width.toDouble();
  final h = src.height.toDouble();
  final recorder = ui.PictureRecorder();
  late final int outW, outH;
  final canvas = ui.Canvas(recorder);

  switch (orientation) {
    case 3: // 180°
      outW = src.width;
      outH = src.height;
      canvas.translate(w, h);
      canvas.rotate(3.141592653589793);
      break;
    case 6: // 90° CW
      outW = src.height;
      outH = src.width;
      canvas.translate(h, 0);
      canvas.rotate(3.141592653589793 / 2);
      break;
    case 8: // 90° CCW
      outW = src.height;
      outH = src.width;
      canvas.translate(0, w);
      canvas.rotate(-3.141592653589793 / 2);
      break;
    case 2: // mirror horizontal
      outW = src.width;
      outH = src.height;
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
      break;
    case 4: // mirror vertical
      outW = src.width;
      outH = src.height;
      canvas.translate(0, h);
      canvas.scale(1, -1);
      break;
    case 5: // transpose: mirror + 90° CW
      outW = src.height;
      outH = src.width;
      canvas.translate(h, 0);
      canvas.rotate(3.141592653589793 / 2);
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
      break;
    case 7: // transverse: mirror + 90° CCW
      outW = src.height;
      outH = src.width;
      canvas.translate(0, w);
      canvas.rotate(-3.141592653589793 / 2);
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
      break;
    default:
      return src;
  }
  canvas.drawImage(src, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  final out = await picture.toImage(outW, outH);
  picture.dispose();
  return out;
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
        _channel = channel ?? const MethodChannel('app.cairn/image_preprocess'),
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

// ---------------------------------------------------------------------------
// Bounding-box crop (used by the orchestrator's two-pass retry on low
// confidence — see GemmaOrchestrator.describePhotoWithRetry)
// ---------------------------------------------------------------------------

/// Crop [rawBytes] to the region described by [box2d] (Gemma vision
/// convention: `[y1, x1, y2, x2]` normalized to 0..1000), expanded by
/// [paddingFraction] on each side and clamped to the image bounds.
///
/// Returns PNG bytes of the cropped region, or `null` if [box2d] is invalid
/// or decoding fails. The returned bytes are intended to be fed through the
/// normal `ImagePreprocessor` pipeline a second time.
Future<Uint8List?> cropImageToBox2d(
  Uint8List rawBytes,
  List<int> box2d, {
  double paddingFraction = 0.15,
}) async {
  if (box2d.length != 4) return null;
  final y1 = box2d[0];
  final x1 = box2d[1];
  final y2 = box2d[2];
  final x2 = box2d[3];
  if (y1 < 0 || x1 < 0 || y2 > 1000 || x2 > 1000 || y1 >= y2 || x1 >= x2) {
    return null;
  }

  final codec = await ui.instantiateImageCodec(rawBytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  codec.dispose();

  final imgW = img.width;
  final imgH = img.height;
  final pixX1 = (x1 / 1000.0 * imgW).round();
  final pixY1 = (y1 / 1000.0 * imgH).round();
  final pixX2 = (x2 / 1000.0 * imgW).round();
  final pixY2 = (y2 / 1000.0 * imgH).round();

  final boxW = pixX2 - pixX1;
  final boxH = pixY2 - pixY1;
  final padX = (boxW * paddingFraction).round();
  final padY = (boxH * paddingFraction).round();
  final cx1 = (pixX1 - padX).clamp(0, imgW);
  final cy1 = (pixY1 - padY).clamp(0, imgH);
  final cx2 = (pixX2 + padX).clamp(0, imgW);
  final cy2 = (pixY2 + padY).clamp(0, imgH);
  final cropW = cx2 - cx1;
  final cropH = cy2 - cy1;
  if (cropW <= 1 || cropH <= 1) {
    img.dispose();
    return null;
  }

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final src = ui.Rect.fromLTWH(
      cx1.toDouble(), cy1.toDouble(), cropW.toDouble(), cropH.toDouble());
  final dst = ui.Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble());
  canvas.drawImageRect(img, src, dst, ui.Paint());
  final picture = recorder.endRecording();
  final out = await picture.toImage(cropW, cropH);
  picture.dispose();
  img.dispose();

  final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  if (byteData == null) return null;
  return byteData.buffer.asUint8List();
}

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
