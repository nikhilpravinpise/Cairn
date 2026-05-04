/// Verifies that every successful orchestrator model turn is recorded in
/// [SessionDraft.turns], which is persisted to `turns.jsonl` on
/// [SessionController.sealAndSave].
///
/// Sprint 1 requirement: `turns.jsonl` must contain every successful model
/// turn (docs/optimization-plan.md §Sprint-1 item 5).
///
/// Expected tasks (per screen → orchestrator mapping):
///   describe_photo  — PhotosScreen → orchestrator.describePhoto (BUG-5, Sprint 0)
///   ask_followup    — HumilityScreen → orchestrator.askFollowup (BUG-5, Sprint 0)
///   synthesize      — SynthesizeScreen → orchestrator.synthesize (Phase 9)
///
/// Not recorded (by design):
///   describe_audio  — audio is record-only in v1 (BUG-4 Option A, Sprint 0)
///   protocol_answer — tap-only UI; no model call made
library;

import 'package:cairn_mobile/core/state/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TurnRecord _turn(String task, {String? obsId, int thinkingChars = 0}) =>
    TurnRecord(
      ts: DateTime.utc(2026, 5, 1, 10),
      task: task,
      observationId: obsId,
      ttftMs: 100,
      wallclockMs: 200,
      outputCharCount: 50,
      thinkingChars: thinkingChars,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ProviderContainer container;
  late SessionController ctrl;

  setUp(() {
    container = ProviderContainer();
    final p =
        NotifierProvider<SessionController, SessionDraft?>(SessionController.new);
    ctrl = container.read(p.notifier);
    ctrl.startNew(modelName: 'gemma-4-e2b-it', modelQuant: 'int4');
  });

  tearDown(() => container.dispose());

  // ---------------------------------------------------------------------------
  // Individual tasks
  // ---------------------------------------------------------------------------

  group('individual task turns', () {
    test('describe_photo turn is recorded', () {
      ctrl.recordTurn(_turn('describe_photo', obsId: 'obs-1'));
      final turns = ctrl.state!.turns;
      expect(turns, hasLength(1));
      expect(turns.first.task, 'describe_photo');
      expect(turns.first.observationId, 'obs-1');
    });

    test('ask_followup turn is recorded', () {
      ctrl.recordTurn(_turn('ask_followup'));
      final turns = ctrl.state!.turns;
      expect(turns.first.task, 'ask_followup');
    });

    test('synthesize turn is recorded with thinkingChars', () {
      ctrl.recordTurn(_turn('synthesize', thinkingChars: 512));
      final turns = ctrl.state!.turns;
      expect(turns.first.task, 'synthesize');
      expect(turns.first.thinkingChars, 512);
    });
  });

  // ---------------------------------------------------------------------------
  // All three tasks together
  // ---------------------------------------------------------------------------

  group('all three model tasks in sequence', () {
    void recordAllThree() {
      ctrl.recordTurn(_turn('describe_photo', obsId: 'obs-1'));
      ctrl.recordTurn(_turn('ask_followup'));
      ctrl.recordTurn(_turn('synthesize', thinkingChars: 256));
    }

    test('three turns are present', () {
      recordAllThree();
      expect(ctrl.state!.turns, hasLength(3));
    });

    test('all three task names are present', () {
      recordAllThree();
      final tasks = ctrl.state!.turns.map((t) => t.task).toSet();
      expect(tasks, containsAll(['describe_photo', 'ask_followup', 'synthesize']));
    });

    test('turns are in insertion order', () {
      recordAllThree();
      final tasks = ctrl.state!.turns.map((t) => t.task).toList();
      expect(tasks[0], 'describe_photo');
      expect(tasks[1], 'ask_followup');
      expect(tasks[2], 'synthesize');
    });
  });

  // ---------------------------------------------------------------------------
  // Multiple describe_photo turns (one per photo)
  // ---------------------------------------------------------------------------

  group('multiple describe_photo turns', () {
    test('five photos produce five describe_photo turns', () {
      for (var i = 1; i <= 5; i++) {
        ctrl.recordTurn(_turn('describe_photo', obsId: 'obs-$i'));
      }
      final photoTurns =
          ctrl.state!.turns.where((t) => t.task == 'describe_photo').toList();
      expect(photoTurns, hasLength(5));
    });

    test('each photo turn has distinct observationId', () {
      for (var i = 1; i <= 3; i++) {
        ctrl.recordTurn(_turn('describe_photo', obsId: 'obs-$i'));
      }
      final obsIds = ctrl.state!.turns.map((t) => t.observationId).toList();
      expect(obsIds.toSet().length, 3, reason: 'all obsIds must be unique');
    });
  });

  // ---------------------------------------------------------------------------
  // TurnRecord JSON round-trip (feeds turns.jsonl)
  // ---------------------------------------------------------------------------

  group('TurnRecord toJson / fromJson round-trip', () {
    test('describe_photo turn survives round-trip', () {
      final orig = TurnRecord(
        ts: DateTime.utc(2026, 5, 4, 12, 30),
        task: 'describe_photo',
        observationId: 'obs-3',
        ttftMs: 1234,
        wallclockMs: 2345,
        outputCharCount: 156,
      );
      final decoded = TurnRecord.fromJson(orig.toJson());
      expect(decoded.task, orig.task);
      expect(decoded.observationId, orig.observationId);
      expect(decoded.ttftMs, orig.ttftMs);
      expect(decoded.wallclockMs, orig.wallclockMs);
      expect(decoded.outputCharCount, orig.outputCharCount);
      expect(decoded.thinkingChars, 0);
    });

    test('synthesize turn with thinkingChars survives round-trip', () {
      final orig = TurnRecord(
        ts: DateTime.utc(2026, 5, 4, 13),
        task: 'synthesize',
        ttftMs: 3456,
        wallclockMs: 5678,
        outputCharCount: 420,
        thinkingChars: 1024,
      );
      final decoded = TurnRecord.fromJson(orig.toJson());
      expect(decoded.task, 'synthesize');
      expect(decoded.thinkingChars, 1024);
    });

    test('ask_followup turn (no obsId, no thinking) survives round-trip', () {
      final orig = TurnRecord(
        ts: DateTime.utc(2026, 5, 4, 14),
        task: 'ask_followup',
        ttftMs: 400,
        wallclockMs: 800,
        outputCharCount: 65,
      );
      final decoded = TurnRecord.fromJson(orig.toJson());
      expect(decoded.observationId, isNull);
      expect(decoded.thinkingChars, 0);
    });

    test('toJson omits thinkingChars key when 0', () {
      final t = TurnRecord(
        ts: DateTime.utc(2026, 5, 4),
        task: 'describe_photo',
        ttftMs: 100,
        wallclockMs: 200,
        outputCharCount: 50,
      );
      expect(t.toJson().containsKey('thinking_chars'), isFalse);
    });

    test('toJson omits observation_id key when null', () {
      final t = TurnRecord(
        ts: DateTime.utc(2026, 5, 4),
        task: 'ask_followup',
        ttftMs: 100,
        wallclockMs: 200,
        outputCharCount: 50,
      );
      expect(t.toJson().containsKey('observation_id'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // turns.jsonl lines (one JSON object per turn)
  // ---------------------------------------------------------------------------

  group('turns.jsonl format (toJson correctness)', () {
    test('all three turns produce distinct valid JSON maps', () {
      ctrl.recordTurn(_turn('describe_photo', obsId: 'obs-1'));
      ctrl.recordTurn(_turn('ask_followup'));
      ctrl.recordTurn(_turn('synthesize', thinkingChars: 100));

      for (final t in ctrl.state!.turns) {
        final j = t.toJson();
        expect(j['task'], isA<String>());
        expect(j['ttft_ms'], isA<int>());
        expect(j['wallclock_ms'], isA<int>());
        expect(j['output_char_count'], isA<int>());
        expect(j['ts'], isA<String>());
      }
    });
  });
}
