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

import 'dart:ui' as ui;

import 'package:cairn_mobile/core/images/image_preprocessor.dart';
import 'package:flutter/services.dart';
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

class _CountingPreprocessor implements ImagePreprocessor {
  int calls = 0;

  @override
  Future<Uint8List> prepareForInference(Uint8List rawBytes) async {
    calls++;
    return Uint8List.fromList([...rawBytes, calls]);
  }
}

class _EchoFallbackPreprocessor implements ImagePreprocessor {
  int calls = 0;

  @override
  Future<Uint8List> prepareForInference(Uint8List rawBytes) async {
    calls++;
    return Uint8List.fromList([...rawBytes, 9]);
  }
}

/// Builds minimal JPEG header bytes containing a SOF0 dimension marker.
///
/// The bytes are NOT a complete decodable JPEG image; they should only be
/// used with [BoundedImagePreprocessor] when the encoded dimensions are
/// ≤ [maxLongEdgePx], so [prepareForInference] returns the bytes unchanged
/// via the header-parse fast path without invoking [dart:ui.instantiateImageCodec].
///
/// Structure:
///   SOI + APP0(16 B) + [fillBytesBeforeSof × 0xFF] + SOF0(w, h) + EOI
Uint8List _makeMinimalJpegHeader({
  required int width,
  required int height,
  int fillBytesBeforeSof = 0,
}) {
  final bytes = <int>[
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x10, // APP0 marker, segLen = 16
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 14 filler bytes of APP0 data
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00,
    0xFF, // marker prefix
  ];
  for (var f = 0; f < fillBytesBeforeSof; f++) {
    bytes.add(0xFF); // fill bytes
  }
  bytes.addAll([
    0xC0, // SOF0 marker type
    0x00, 0x0B, // segLen = 11
    0x08, // precision = 8 bits
    (height >> 8) & 0xFF, height & 0xFF,
    (width >> 8) & 0xFF, width & 0xFF,
    0x01, 0x01, 0x11, 0x00, // 1 component
    0xFF, 0xD9, // EOI
  ]);
  return Uint8List.fromList(bytes);
}

// ---------------------------------------------------------------------------
// PassthroughImagePreprocessor
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('CachingImagePreprocessor', () {
    test('returns stable bytes for the same source object', () async {
      final inner = _CountingPreprocessor();
      final preprocessor = CachingImagePreprocessor(inner);
      final bytes = Uint8List.fromList([1, 2, 3]);

      final first = await preprocessor.prepareForInference(bytes);
      final second = await preprocessor.prepareForInference(bytes);

      expect(identical(first, second), isTrue);
      expect(inner.calls, 1);
      expect(preprocessor.entryCount, 1);
    });

    test('invalidates when a different byte object is used', () async {
      final inner = _CountingPreprocessor();
      final preprocessor = CachingImagePreprocessor(inner);

      final first = await preprocessor.prepareForInference(
        Uint8List.fromList([1, 2, 3]),
      );
      final second = await preprocessor.prepareForInference(
        Uint8List.fromList([1, 2, 3]),
      );

      expect(identical(first, second), isFalse);
      expect(inner.calls, 2);
      expect(preprocessor.entryCount, 2);
    });
  });

  group('AndroidJpegImagePreprocessor', () {
    const channel = MethodChannel('test.cairn/image_preprocess');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('uses native JPEG channel on Android', (tester) async {
      final input = Uint8List.fromList([1, 2, 3]);
      final output = Uint8List.fromList([0xFF, 0xD8, 4, 5]);
      Object? args;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'resizeJpeg');
        args = call.arguments;
        return output;
      });

      final preprocessor = AndroidJpegImagePreprocessor(
        maxLongEdgePx: 640,
        quality: 80,
        channel: channel,
        targetPlatformForTesting: TargetPlatform.android,
      );

      final result = await preprocessor.prepareForInference(input);

      expect(result, output);
      expect(args, {
        'bytes': input,
        'maxLongEdgePx': 640,
        'quality': 80,
      });
    });

    testWidgets('falls back when native channel fails', (tester) async {
      final input = Uint8List.fromList([1, 2, 3]);
      final fallback = _EchoFallbackPreprocessor();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });

      final preprocessor = AndroidJpegImagePreprocessor(
        maxLongEdgePx: 640,
        fallback: fallback,
        channel: channel,
        targetPlatformForTesting: TargetPlatform.android,
      );

      final result = await preprocessor.prepareForInference(input);

      expect(result, [1, 2, 3, 9]);
      expect(fallback.calls, 1);
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
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      expect(identical(result, bytes), isTrue,
          reason: 'no resize needed — must return identical bytes object');
    });

    testWidgets('image whose long edge == bound returns raw bytes unchanged',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(100, 50));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 100);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      expect(identical(result, bytes), isTrue,
          reason: 'long edge == bound is within bounds; no re-encode');
    });

    testWidgets('square image within bounds returns raw bytes', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(32, 32));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 64);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
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
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 100, reason: 'width (long edge) must be clamped to 100');
      expect(size.$2, 50,
          reason: 'height must be halved to preserve aspect ratio');
    });

    testWidgets('portrait image: long edge equals maxLongEdgePx after resize',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(100, 200));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 100);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$2, 100,
          reason: 'height (long edge) must be clamped to 100');
      expect(size.$1, 50,
          reason: 'width must be halved to preserve aspect ratio');
    });

    testWidgets('square image: both dimensions equal maxLongEdgePx',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(200, 200));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 100);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 100);
      expect(size.$2, 100);
    });

    testWidgets('downscaled output is decodable PNG', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(256, 128));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 64);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, greaterThan(0));
      expect(size.$2, greaterThan(0));
    });

    testWidgets('result is smaller in bytes than the original for large inputs',
        (tester) async {
      final bytes = await tester.runAsync(() => _makePng(512, 256));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 64);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
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
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 150);
      expect(size.$2, 50);
    });

    testWidgets('1:3 tall image preserves ratio after resize', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(100, 300));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 150);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 50);
      expect(size.$2, 150);
    });

    testWidgets('4:3 landscape common camera ratio preserved', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(400, 300));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 200);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 200);
      expect(size.$2, 150);
    });
  });

  // -------------------------------------------------------------------------
  // BoundedImagePreprocessor — JPEG header fast path
  // -------------------------------------------------------------------------

  group('BoundedImagePreprocessor — JPEG header fast path', () {
    test('reads dims from JPEG with no fill bytes; returns rawBytes unchanged',
        () async {
      // SOI + APP0 + SOF0(200×100) + EOI — no fill bytes.
      final bytes =
          _makeMinimalJpegHeader(width: 200, height: 100);
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 768);
      final result = await preprocessor.prepareForInference(bytes);
      expect(identical(result, bytes), isTrue,
          reason:
              'dims 200×100 ≤ 768; header-parse fast path must return identical bytes');
    });

    test(
        'reads dims from JPEG with 1 fill byte before SOF0; returns rawBytes unchanged',
        () async {
      // 1 extra 0xFF fill byte is inserted before the SOF0 marker type.
      // Prior to the fix, the scanner misread the fill byte as a segment with
      // type 0xFF, computed a garbage segLen (~49 KB), jumped past EOF, and
      // returned null — falling back to the codec probe which throws on these
      // non-decodable bytes.  The fixed scanner skips fill bytes and parses
      // the SOF0 correctly.
      final bytes =
          _makeMinimalJpegHeader(width: 200, height: 100, fillBytesBeforeSof: 1);
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 768);
      final result = await preprocessor.prepareForInference(bytes);
      expect(identical(result, bytes), isTrue,
          reason:
              'fill bytes before SOF0 must not corrupt header parsing');
    });
  });

  // -------------------------------------------------------------------------
  // BoundedImagePreprocessor — benchmark dimensions
  // -------------------------------------------------------------------------

  group('BoundedImagePreprocessor — benchmark dimensions', () {
    testWidgets('Sprint 3 768px benchmark: 1600×900 → 768×432', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(1600, 900));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 768);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 768);
      expect(size.$2, 432);
    });

    testWidgets('Sprint 3 512px benchmark: 1600×900 → 512×288', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(1600, 900));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 512);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$1, 512);
      expect(size.$2, 288);
    });

    testWidgets('portrait: 900×1600 → 432×768 at 768px', (tester) async {
      final bytes = await tester.runAsync(() => _makePng(900, 1600));
      const preprocessor = BoundedImagePreprocessor(maxLongEdgePx: 768);
      final result =
          await tester.runAsync(() => preprocessor.prepareForInference(bytes!));
      final size = await tester.runAsync(() => _getSize(result!));
      expect(size!.$2, 768);
      expect(size.$1, 432);
    });
  });
}
