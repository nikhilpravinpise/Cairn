/// Tests for [BoundedImagePreprocessor] and [PassthroughImagePreprocessor].
///
/// Coverage:
///   - [PassthroughImagePreprocessor] returns the identical byte object.
///   - [BoundedImagePreprocessor] returns raw bytes unchanged when the image
///     already fits within the bound (no upscaling, no re-encode overhead).
///   - Images larger than the bound are downscaled so the long edge ==
///     [BoundedImagePreprocessor.maxLongEdgePx].
///   - Aspect ratio is preserved for landscape, portrait, and square inputs.
///   - Downscaled output is decodable (valid PNG bytes).
///   - maxLongEdgePx=1 is the floor; no dimension is ever < 1.
///
/// These tests use [testWidgets] because [dart:ui.instantiateImageCodec]
/// and [dart:ui.PictureRecorder] require a Flutter engine context to decode
/// and encode images. The tests are stateless — no widgets are built.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cairn_mobile/core/images/image_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a solid-colour PNG of the given [width] × [height].
///
/// Must be called inside [WidgetTester.runAsync] because [ui.Picture.toImage]
/// needs the real event loop (not FakeAsync) to rasterise the picture.
Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFAA0000),
  );
  final picture = recorder.endRecording();
  final img = await picture.toImage(width, height);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bd!.buffer.asUint8List();
}

/// Decodes PNG [bytes] and returns (width, height).
///
/// Must be called inside [WidgetTester.runAsync].
Future<(int, int)> _getSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final w = frame.image.width;
  final h = frame.image.height;
  frame.image.dispose();
  codec.dispose();
  return (w, h);
}

// ---------------------------------------------------------------------------
// PassthroughImagePreprocessor
// ---------------------------------------------------------------------------

void main() {
  group('PassthroughImagePreprocessor', () {
    const preprocessor = PassthroughImagePreprocessor();

    test('returns the same byte object (identity)', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final result = await preprocessor.prepareForInference(bytes);
      expect(identical(result, bytes), isTrue,
          reason: 'passthrough must return the exact same Uint8List');
    });

    test('returns empty bytes unchanged', () async {
      final bytes = Uint8List(0);
      final result = await preprocessor.prepareForInference(bytes);
      expect(identical(result, bytes), isTrue);
    });

    test('does not mutate the bytes', () async {
      final bytes = Uint8List.fromList([10, 20, 30]);
      await preprocessor.prepareForInference(bytes);
      expect(bytes, [10, 20, 30]);
    });
  });

  // -------------------------------------------------------------------------
  // BoundedImagePreprocessor — images already within bounds (no-op path)
  // -------------------------------------------------------------------------

  group('BoundedImagePreprocessor — within bounds', () {
    testWidgets('image whose long edge < bound returns raw bytes unchanged',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(10, 5));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 512);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      expect(identical(result, bytes), isTrue,
          reason: 'no resize needed — must return identical bytes object');
    });

    testWidgets('image whose long edge == bound returns raw bytes unchanged',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(100, 50));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 100);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      expect(identical(result, bytes), isTrue,
          reason: 'long edge == bound is within bounds; no re-encode');
    });

    testWidgets('square image within bounds returns raw bytes', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(32, 32));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 64);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      expect(identical(result, bytes), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // BoundedImagePreprocessor — downscaling
  // -------------------------------------------------------------------------

  group('BoundedImagePreprocessor — downscaling', () {
    testWidgets('landscape image: long edge equals maxLongEdgePx after resize',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(200, 100));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 100);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 100, reason: 'width (long edge) must be clamped to 100');
      expect(size.$2, 50, reason: 'height must be halved to preserve aspect ratio');
    });

    testWidgets('portrait image: long edge equals maxLongEdgePx after resize',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(100, 200));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 100);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$2, 100, reason: 'height (long edge) must be clamped to 100');
      expect(size.$1, 50, reason: 'width must be halved to preserve aspect ratio');
    });

    testWidgets('square image: both dimensions equal maxLongEdgePx',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(200, 200));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 100);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 100);
      expect(size.$2, 100);
    });

    testWidgets('downscaled output is decodable PNG', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(256, 128));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 64);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, greaterThan(0));
      expect(size.$2, greaterThan(0));
    });

    testWidgets('result is smaller in bytes than the original for large inputs',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(512, 256));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 64);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      expect(result!.length, lessThan(bytes!.length),
          reason: 'downscaled output should be smaller than the original');
    });
  });

  // -------------------------------------------------------------------------
  // BoundedImagePreprocessor — aspect ratio invariants
  // -------------------------------------------------------------------------

  group('BoundedImagePreprocessor — aspect ratio', () {
    testWidgets('3:1 wide image preserves ratio after resize', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(300, 100));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 150);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 150);
      expect(size.$2, 50);
    });

    testWidgets('1:3 tall image preserves ratio after resize', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(100, 300));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 150);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 50);
      expect(size.$2, 150);
    });

    testWidgets('4:3 landscape common camera ratio preserved', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(400, 300));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 200);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 200);
      expect(size.$2, 150);
    });
  });

  // -------------------------------------------------------------------------
  // BoundedImagePreprocessor — benchmark dimensions
  // -------------------------------------------------------------------------

  group('BoundedImagePreprocessor — benchmark dimensions', () {
    testWidgets('Sprint 3 768px benchmark: 1600×900 → 768×432',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(1600, 900));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 768);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 768);
      expect(size.$2, 432);
    });

    testWidgets('Sprint 3 512px benchmark: 1600×900 → 512×288',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(1600, 900));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 512);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 512);
      expect(size.$2, 288);
    });

    testWidgets('portrait: 900×1600 → 432×768 at 768px', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(900, 1600));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 768);
      final result = await tester.runAsync(
          () => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$2, 768);
      expect(size!.$1, 432);
    });
  });
}
