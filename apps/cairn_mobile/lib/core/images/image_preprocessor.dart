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

import 'dart:typed_data';
import 'dart:ui' as ui;

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
    // --- Step 1: probe dimensions without target scaling ---
    final probeCodec = await ui.instantiateImageCodec(rawBytes);
    final probeFrame = await probeCodec.getNextFrame();
    final origW = probeFrame.image.width;
    final origH = probeFrame.image.height;
    probeFrame.image.dispose();
    probeCodec.dispose();

    final longEdge = origW > origH ? origW : origH;
    if (longEdge <= maxLongEdgePx) {
      // Already within bounds — return raw bytes unchanged.
      // No re-encode cost, no format change.
      return rawBytes;
    }

    // --- Step 2: calculate target dimensions, preserving aspect ratio ---
    final int tw, th;
    if (origW >= origH) {
      // Landscape or square — width is the long edge.
      tw = maxLongEdgePx;
      th = (origH * maxLongEdgePx / origW).round().clamp(1, maxLongEdgePx);
    } else {
      // Portrait — height is the long edge.
      th = maxLongEdgePx;
      tw = (origW * maxLongEdgePx / origH).round().clamp(1, maxLongEdgePx);
    }

    // --- Step 3: decode with target dimensions (bilinear by Flutter engine) ---
    final codec = await ui.instantiateImageCodec(
      rawBytes,
      targetWidth: tw,
      targetHeight: th,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // --- Step 4: encode to PNG ---
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    codec.dispose();

    if (byteData == null) {
      // Encoding failure is unexpected but non-fatal — fall back to raw bytes
      // so the inference call can still proceed.
      return rawBytes;
    }
    return byteData.buffer.asUint8List();
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
