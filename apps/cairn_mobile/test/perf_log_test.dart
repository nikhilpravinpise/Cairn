/// Tests for [PerfEvent] and [PerfLogger].
///
/// Coverage:
///   - [PerfEvent.format] produces the correct `phase=… wall=…` line for
///     every lifecycle phase (install, engine_create, generate).
///   - Optional fields (task, ttft, out_chars, thinking_chars, img_bytes) are
///     included only when non-null / non-zero.
///   - Field ordering matches the documented format (phase → task? → wall →
///     ttft? → out_chars? → thinking_chars? → img_bytes?).
///   - [PerfLogger.emit] does not throw for any valid [PerfEvent].
///
/// Sprint 1 gate: dart analyze tool/api_probe.dart passes.
library;

import 'package:cairn_mobile/core/llm/perf_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PerfEvent.format — install phase
  // ---------------------------------------------------------------------------

  group('PerfEvent.format — install', () {
    test('minimal: only phase and wall', () {
      const e = PerfEvent(phase: 'install', wallclockMs: 1234);
      expect(e.format(), 'phase=install wall=1234ms');
    });

    test('zero wall time is still emitted', () {
      const e = PerfEvent(phase: 'install', wallclockMs: 0);
      expect(e.format(), 'phase=install wall=0ms');
    });

    test('no task field by default', () {
      const e = PerfEvent(phase: 'install', wallclockMs: 100);
      expect(e.format(), isNot(contains('task=')));
    });

    test('no ttft field by default', () {
      const e = PerfEvent(phase: 'install', wallclockMs: 100);
      expect(e.format(), isNot(contains('ttft=')));
    });

    test('no out_chars field by default', () {
      const e = PerfEvent(phase: 'install', wallclockMs: 100);
      expect(e.format(), isNot(contains('out_chars=')));
    });

    test('no thinking_chars when 0 (default)', () {
      const e = PerfEvent(phase: 'install', wallclockMs: 100);
      expect(e.format(), isNot(contains('thinking_chars=')));
    });

    test('no img_bytes field by default', () {
      const e = PerfEvent(phase: 'install', wallclockMs: 100);
      expect(e.format(), isNot(contains('img_bytes=')));
    });
  });

  // ---------------------------------------------------------------------------
  // PerfEvent.format — engine_create phase
  // ---------------------------------------------------------------------------

  group('PerfEvent.format — engine_create', () {
    test('minimal: phase and wall only', () {
      const e = PerfEvent(phase: 'engine_create', wallclockMs: 2341);
      expect(e.format(), 'phase=engine_create wall=2341ms');
    });

    test('format starts with phase=', () {
      const e = PerfEvent(phase: 'engine_create', wallclockMs: 99);
      expect(e.format(), startsWith('phase='));
    });
  });

  // ---------------------------------------------------------------------------
  // PerfEvent.format — generate phase
  // ---------------------------------------------------------------------------

  group('PerfEvent.format — generate, vision turn', () {
    test('full vision turn: task + wall + ttft + out_chars + img_bytes', () {
      const e = PerfEvent(
        phase: 'generate',
        wallclockMs: 3456,
        task: 'describe_photo',
        ttftMs: 1234,
        outputCharCount: 156,
        imageSizeBytes: 98304,
      );
      expect(
        e.format(),
        'phase=generate task=describe_photo wall=3456ms ttft=1234ms '
        'out_chars=156 img_bytes=98304',
      );
    });

    test('vision turn without img_bytes (null)', () {
      const e = PerfEvent(
        phase: 'generate',
        wallclockMs: 3456,
        task: 'describe_photo',
        ttftMs: 1234,
        outputCharCount: 156,
      );
      expect(e.format(), isNot(contains('img_bytes=')));
    });
  });

  group('PerfEvent.format — generate, synthesis turn', () {
    test('synthesis turn: task + wall + ttft + out_chars + thinking_chars', () {
      const e = PerfEvent(
        phase: 'generate',
        wallclockMs: 5678,
        task: 'synthesize',
        ttftMs: 3456,
        outputCharCount: 420,
        thinkingChars: 1024,
      );
      expect(
        e.format(),
        'phase=generate task=synthesize wall=5678ms ttft=3456ms '
        'out_chars=420 thinking_chars=1024',
      );
    });

    test('thinkingChars=0 is not included', () {
      const e = PerfEvent(
        phase: 'generate',
        wallclockMs: 1000,
        task: 'synthesize',
        ttftMs: 500,
        outputCharCount: 100,
        thinkingChars: 0,
      );
      expect(e.format(), isNot(contains('thinking_chars=')));
    });
  });

  group('PerfEvent.format — generate, followup turn', () {
    test('ask_followup: no image, no thinking', () {
      const e = PerfEvent(
        phase: 'generate',
        wallclockMs: 800,
        task: 'ask_followup',
        ttftMs: 300,
        outputCharCount: 60,
      );
      expect(e.format(),
          'phase=generate task=ask_followup wall=800ms ttft=300ms out_chars=60');
    });
  });

  // ---------------------------------------------------------------------------
  // PerfEvent.format — field ordering
  // ---------------------------------------------------------------------------

  group('PerfEvent.format — field ordering', () {
    test('phase comes before task', () {
      const e = PerfEvent(
          phase: 'generate', wallclockMs: 100, task: 'describe_photo');
      final f = e.format();
      expect(f.indexOf('phase='), lessThan(f.indexOf('task=')));
    });

    test('task comes before wall', () {
      const e = PerfEvent(
          phase: 'generate', wallclockMs: 100, task: 'describe_photo');
      final f = e.format();
      expect(f.indexOf('task='), lessThan(f.indexOf('wall=')));
    });

    test('wall comes before ttft', () {
      const e = PerfEvent(
          phase: 'generate', wallclockMs: 100, ttftMs: 50);
      final f = e.format();
      expect(f.indexOf('wall='), lessThan(f.indexOf('ttft=')));
    });

    test('ttft comes before out_chars', () {
      const e = PerfEvent(
          phase: 'generate', wallclockMs: 100, ttftMs: 50,
          outputCharCount: 30);
      final f = e.format();
      expect(f.indexOf('ttft='), lessThan(f.indexOf('out_chars=')));
    });

    test('out_chars comes before thinking_chars', () {
      const e = PerfEvent(
          phase: 'generate', wallclockMs: 100, outputCharCount: 30,
          thinkingChars: 10);
      final f = e.format();
      expect(f.indexOf('out_chars='), lessThan(f.indexOf('thinking_chars=')));
    });

    test('thinking_chars comes before img_bytes', () {
      const e = PerfEvent(
          phase: 'generate', wallclockMs: 100, thinkingChars: 10,
          imageSizeBytes: 512);
      final f = e.format();
      expect(f.indexOf('thinking_chars='), lessThan(f.indexOf('img_bytes=')));
    });
  });

  // ---------------------------------------------------------------------------
  // PerfLogger.emit — smoke tests
  // ---------------------------------------------------------------------------

  group('PerfLogger.emit — smoke', () {
    test('does not throw for install event', () {
      expect(
        () => PerfLogger.emit(const PerfEvent(phase: 'install', wallclockMs: 42)),
        returnsNormally,
      );
    });

    test('does not throw for engine_create event', () {
      expect(
        () => PerfLogger.emit(
            const PerfEvent(phase: 'engine_create', wallclockMs: 2000)),
        returnsNormally,
      );
    });

    test('does not throw for full generate event', () {
      expect(
        () => PerfLogger.emit(const PerfEvent(
          phase: 'generate',
          wallclockMs: 3000,
          task: 'describe_photo',
          ttftMs: 1200,
          outputCharCount: 200,
          imageSizeBytes: 65536,
        )),
        returnsNormally,
      );
    });

    test('does not throw for synthesis event with thinking', () {
      expect(
        () => PerfLogger.emit(const PerfEvent(
          phase: 'generate',
          wallclockMs: 6000,
          task: 'synthesize',
          ttftMs: 2000,
          outputCharCount: 350,
          thinkingChars: 900,
        )),
        returnsNormally,
      );
    });
  });
}
