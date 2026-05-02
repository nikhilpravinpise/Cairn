/// Tests for [GemmaOrchestrator.askFollowup].
///
/// The system prompt (§TURN TYPES) specifies two valid shapes for the
/// `ask_followup` response:
///
///   { "followup": null }                             — no question needed
///   { "followup": { "target_observation_id": "...",
///                   "question": "..." } }             — question to pose
///
/// Anything else is a contract violation and must throw [GemmaContractError].
library;

import 'dart:typed_data';

import 'package:cairn_mobile/core/llm/gemma_session.dart';
import 'package:cairn_mobile/core/llm/orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake session — returns a canned response; never touches flutter_gemma.
// ---------------------------------------------------------------------------

class _FakeSession implements GemmaSessionInterface {
  _FakeSession(this._response, {this.ttftMs = 12, this.wallclockMs = 34});

  final String _response;
  final int ttftMs;
  final int wallclockMs;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    return GemmaInferenceResult(
      text: _response,
      thinking: '',
      ttftMs: ttftMs,
      wallclockMs: wallclockMs,
      outputCharCount: _response.length,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GemmaOrchestrator _orch(String response) =>
    GemmaOrchestrator(_FakeSession(response));

const _kTarget = {
  'observation_id': 'obs-1',
  'prompt_id': 'fema_p154_q01',
  'model_description': 'some description',
  'model_confidence': 0.4,
};

Future<AskFollowupResult> _ask(String response) =>
    _orch(response).askFollowup(askedIn: 'en', targetObservationSummary: _kTarget);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('askFollowup — null (no question needed)', () {
    test('followup null → hasFollowup false, question null', () async {
      final res = await _ask('{"followup": null, "asked_in": "en"}');
      expect(res.hasFollowup, isFalse);
      expect(res.question, isNull);
      expect(res.targetObservationId, isNull);
      expect(res.askedIn, 'en');
    });

    test('followup null → does not throw', () async {
      await expectLater(
        _ask('{"followup": null}'),
        completes,
      );
    });
  });

  group('askFollowup — dict (question present)', () {
    const validDict = '{"followup": {'
        '"target_observation_id": "obs-1", '
        '"question": "Can you describe the crack direction?"'
        '}, "asked_in": "en"}';

    test('followup dict → hasFollowup true', () async {
      final res = await _ask(validDict);
      expect(res.hasFollowup, isTrue);
    });

    test('followup dict → question extracted correctly', () async {
      final res = await _ask(validDict);
      expect(res.question, 'Can you describe the crack direction?');
    });

    test('followup dict → targetObservationId extracted', () async {
      final res = await _ask(validDict);
      expect(res.targetObservationId, 'obs-1');
    });

    test('followup dict missing target_observation_id → still valid', () async {
      const noId = '{"followup": {"question": "What colour is the wall?"}}';
      final res = await _ask(noId);
      expect(res.hasFollowup, isTrue);
      expect(res.targetObservationId, isNull);
    });

    test('question is trimmed', () async {
      const padded =
          '{"followup": {"question": "   Is the column base cracked?   "}}';
      final res = await _ask(padded);
      expect(res.question, 'Is the column base cracked?');
    });
  });

  group('askFollowup — TTFT / wallclock propagation', () {
    test('ttftMs and wallclockMs come from the session result', () async {
      final orch = GemmaOrchestrator(
        _FakeSession('{"followup": null}', ttftMs: 55, wallclockMs: 120),
      );
      final res = await orch.askFollowup(
          askedIn: 'en', targetObservationSummary: _kTarget);
      expect(res.ttftMs, 55);
      expect(res.wallclockMs, 120);
    });
  });

  group('askFollowup — contract violations (must throw GemmaContractError)', () {
    test('no JSON object in response → throws', () async {
      await expectLater(
        _ask('sorry I cannot help with that'),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('followup is a plain string → throws', () async {
      await expectLater(
        _ask('{"followup": "What happened to the roof?"}'),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.task,
          'task',
          'ask_followup',
        )),
      );
    });

    test('followup is an integer → throws', () async {
      await expectLater(
        _ask('{"followup": 42}'),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('followup dict with empty question → throws', () async {
      await expectLater(
        _ask('{"followup": {"target_observation_id": "obs-1", "question": ""}}'),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('non-empty'),
        )),
      );
    });

    test('followup dict with whitespace-only question → throws', () async {
      await expectLater(
        _ask(
            '{"followup": {"target_observation_id": "obs-1", "question": "   "}}'),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('followup dict missing question key → throws', () async {
      await expectLater(
        _ask('{"followup": {"target_observation_id": "obs-1"}}'),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('non-empty'),
        )),
      );
    });

    test('followup missing from top-level JSON → treated as null (no question)',
        () async {
      // JSON exists but has no `followup` key — null is the implicit value.
      final res = await _ask('{"asked_in": "en"}');
      expect(res.hasFollowup, isFalse);
    });
  });
}
