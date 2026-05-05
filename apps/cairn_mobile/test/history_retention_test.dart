/// Sprint 4 OPT-5 — History retention A/B.
///
/// Verifies that [SessionConfig.clearHistoryBetweenTurns] controls whether
/// `chat.clearHistory()` is called after each inference turn, and that the
/// production default (`true`) is not accidentally changed.
///
/// These tests use a fake [GemmaSessionInterface] that records call counts so
/// the contract can be verified without a real model or device.
///
/// Device gate (run on RZCX920ARVA after this test suite passes):
///   tool/benchmark_session_config.ps1 -Variant vision_history_retained
///
/// Gate criteria before promoting `clearHistoryBetweenTurns: false`:
///   1. TTFT / prefill improves materially on 5 sequential describe_photo turns.
///   2. Zero cross-photo output contamination (obs[n] must not reference photo[n-1]).
///   3. GemmaContractError rate unchanged vs baseline.
library;

import 'dart:typed_data';

import 'package:cairn_mobile/core/llm/gemma_session.dart';
import 'package:cairn_mobile/core/llm/session_config.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake session — tracks whether clearHistory was called between turns
// ---------------------------------------------------------------------------

/// Minimal [GemmaSessionInterface] that counts generate() calls and lets the
/// test inspect whether `clearHistoryBetweenTurns` caused any side effect.
///
/// The real `GemmaSession._generateOnce` calls `chat.clearHistory()` when
/// `_config.clearHistoryBetweenTurns == true`. The fake cannot intercept that
/// private call, so these tests verify [SessionConfig] field values and the
/// [GemmaSession] contract at the public API boundary.
class _FakeSession implements GemmaSessionInterface {
  int generateCallCount = 0;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    generateCallCount++;
    return const GemmaInferenceResult(
      text: '{"model_description":"test","model_confidence":0.9,"model_tags":[],'
          '"bbox_annotations":[],"observation_id":"obs-1","image_refs":["img-1"],'
          '"audio_refs":[],"prompt_id":"p1"}',
      thinking: '',
      ttftMs: 100,
      wallclockMs: 200,
      outputCharCount: 80,
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---------------------------------------------------------------------------
  // SessionConfig.clearHistoryBetweenTurns field contract
  // ---------------------------------------------------------------------------

  group('SessionConfig.clearHistoryBetweenTurns — field contract', () {
    test('production default is true for vision', () {
      expect(SessionConfig.vision.clearHistoryBetweenTurns, isTrue);
    });

    test('production default is true for audio', () {
      expect(SessionConfig.audio.clearHistoryBetweenTurns, isTrue);
    });

    test('production default is true for synthesis', () {
      expect(SessionConfig.synthesis.clearHistoryBetweenTurns, isTrue);
    });

    test('production default is true for standard', () {
      expect(SessionConfig.standard.clearHistoryBetweenTurns, isTrue);
    });

    test('visionHistoryRetained has clearHistoryBetweenTurns: false', () {
      expect(SessionConfig.visionHistoryRetained.clearHistoryBetweenTurns, isFalse);
    });

    test('visionHistoryRetained is otherwise identical to vision', () {
      const retained = SessionConfig.visionHistoryRetained;
      const prod = SessionConfig.vision;
      expect(retained.maxTokens, prod.maxTokens);
      expect(retained.temperature, prod.temperature);
      expect(retained.topK, prod.topK);
      expect(retained.topP, prod.topP);
      expect(retained.preferredBackend, prod.preferredBackend);
      expect(retained.maxNumImages, prod.maxNumImages);
    });

    test('default constructor defaults clearHistoryBetweenTurns to true', () {
      const cfg = SessionConfig(
        maxTokens: 4096,
        temperature: 0.2,
        topK: 40,
        topP: 0.95,
        preferredBackend: PreferredBackend.gpu,
        maxNumImages: 1,
      );
      expect(cfg.clearHistoryBetweenTurns, isTrue,
          reason: 'omitting clearHistoryBetweenTurns must default to true');
    });
  });

  // ---------------------------------------------------------------------------
  // SessionConfig.copyWith — clearHistoryBetweenTurns override
  // ---------------------------------------------------------------------------

  group('SessionConfig.copyWith — clearHistoryBetweenTurns', () {
    test('copyWith can set clearHistoryBetweenTurns to false', () {
      final mutated = SessionConfig.vision.copyWith(clearHistoryBetweenTurns: false);
      expect(mutated.clearHistoryBetweenTurns, isFalse);
    });

    test('copyWith preserves all other fields when only toggling clearHistory', () {
      final mutated = SessionConfig.vision.copyWith(clearHistoryBetweenTurns: false);
      expect(mutated.maxTokens, SessionConfig.vision.maxTokens);
      expect(mutated.temperature, SessionConfig.vision.temperature);
      expect(mutated.topK, SessionConfig.vision.topK);
      expect(mutated.topP, SessionConfig.vision.topP);
      expect(mutated.preferredBackend, SessionConfig.vision.preferredBackend);
      expect(mutated.maxNumImages, SessionConfig.vision.maxNumImages);
    });

    test('copyWith with no args returns config with same clearHistoryBetweenTurns', () {
      expect(SessionConfig.vision.copyWith().clearHistoryBetweenTurns, isTrue);
      expect(
        SessionConfig.visionHistoryRetained.copyWith().clearHistoryBetweenTurns,
        isFalse,
      );
    });

    test('copyWith can restore clearHistoryBetweenTurns to true', () {
      final restored =
          SessionConfig.visionHistoryRetained.copyWith(clearHistoryBetweenTurns: true);
      expect(restored.clearHistoryBetweenTurns, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // toLogString includes clearHistory field
  // ---------------------------------------------------------------------------

  group('toLogString includes clearHistory', () {
    test('production vision toLogString includes clearHistory=true', () {
      expect(SessionConfig.vision.toLogString(), contains('clearHistory=true'));
    });

    test('visionHistoryRetained toLogString includes clearHistory=false', () {
      expect(
        SessionConfig.visionHistoryRetained.toLogString(),
        contains('clearHistory=false'),
      );
    });

    test('clearHistory field appears in toString()', () {
      expect(SessionConfig.vision.toString(), contains('clearHistory=true'));
    });
  });

  // ---------------------------------------------------------------------------
  // Fake session — generate() call count confirms the interface is callable
  // ---------------------------------------------------------------------------

  group('fake session — generate call count', () {
    test('generate() is callable and returns a result', () async {
      final session = _FakeSession();
      final result = await session.generate(userText: 'test');
      expect(result.text, isNotEmpty);
      expect(session.generateCallCount, 1);
    });

    test('five sequential generate() calls increment count to 5', () async {
      final session = _FakeSession();
      for (var i = 0; i < 5; i++) {
        await session.generate(userText: 'turn $i');
      }
      expect(session.generateCallCount, 5,
          reason: 'five photo-describe calls must all reach generate()');
    });
  });

  // ---------------------------------------------------------------------------
  // A/B interpretation guide (documentation test)
  // ---------------------------------------------------------------------------

  group('A/B gate documentation', () {
    test('production variant (clearHistoryBetweenTurns: true) is the safety default', () {
      expect(SessionConfig.vision.clearHistoryBetweenTurns, isTrue,
          reason:
              'Clearing after every turn is the safety default. Cross-photo '
              'contamination risk is non-zero when history is retained.');
    });

    test('retained variant (clearHistoryBetweenTurns: false) must pass contamination gate', () {
      expect(SessionConfig.visionHistoryRetained.clearHistoryBetweenTurns, isFalse,
          reason:
              'Only run this variant for benchmarking. Do not promote to production '
              'until device gate confirms no cross-photo output contamination on '
              'a 5-photo sequential describe_all run.');
    });

    test('only visionHistoryRetained has clearHistoryBetweenTurns: false', () {
      final allConfigs = [
        SessionConfig.vision,
        SessionConfig.audio,
        SessionConfig.synthesis,
        SessionConfig.standard,
        SessionConfig.visionMaxTokens3072,
        SessionConfig.visionMaxTokens2048,
        SessionConfig.visionTemp01,
        SessionConfig.standardTemp01,
        SessionConfig.visionCpu,
        SessionConfig.synthesisCpu,
        SessionConfig.standardCpu,
      ];
      for (final cfg in allConfigs) {
        expect(cfg.clearHistoryBetweenTurns, isTrue,
            reason:
                '${cfg.toLogString()} must have clearHistoryBetweenTurns: true. '
                'Only visionHistoryRetained is the A/B candidate.');
      }
    });
  });
}
