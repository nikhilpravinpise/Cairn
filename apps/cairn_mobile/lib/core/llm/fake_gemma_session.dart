/// Dev-only fake Gemma session for --dart-define=DEV_SKIP_MODEL=true.
///
/// Parses the task field from the request JSON and returns a canned response
/// that passes all contract validators, so the full app flow (photo → protocol
/// → synthesize → report) can be exercised on any device/emulator without
/// downloading or loading a real model.
///
/// This file is never compiled in release builds — the
/// [bool.fromEnvironment] guard in providers.dart is a compile-time constant
/// that strips this path entirely when DEV_SKIP_MODEL is not set.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'gemma_session.dart';

class FakeGemmaSession implements GemmaSessionInterface {
  const FakeGemmaSession();

  static const _tag = '[Cairn/DEV_SKIP_MODEL]';

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    // Simulate a short network-free delay so loading spinners behave normally.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final Map<String, Object?> req;
    try {
      req = (jsonDecode(userText) as Map).cast<String, Object?>();
    } catch (_) {
      debugPrint('$_tag could not parse userText as JSON — returning stub');
      return _result('{"followup": null}');
    }

    final task = req['task'] as String? ?? '';
    debugPrint('$_tag fake generate() for task=$task');

    final response = switch (task) {
      'describe_photo' => _photoResponse(req),
      'describe_audio' => _audioResponse(req),
      'describe_photos_batch' => _batchResponse(req),
      'protocol_answer' => _protocolResponse(),
      'synthesize' => _synthResponse(),
      'ask_followup' => '{"followup": null}',
      _ => '{"followup": null}',
    };

    return _result(response);
  }

  // ---------------------------------------------------------------------------
  // Per-task canned responses
  // ---------------------------------------------------------------------------

  String _photoResponse(Map<String, Object?> req) {
    final obsId = req['observation_id'] as String? ?? 'obs-1';
    final promptId = req['prompt_id'] as String? ?? 'fema_p154_q01';
    final askedIn = req['asked_in'] as String? ?? 'en';
    final imageRefs =
        (req['image_refs'] as List?)?.cast<String>() ?? const ['img-1'];
    return jsonEncode({
      'observation_id': obsId,
      'prompt_id': promptId,
      'asked_in': askedIn,
      'image_refs': imageRefs,
      'model_description':
          'DEV_SKIP_MODEL: simulated observation — no structural damage visible.',
      'model_tags': ['no_visible_damage'],
      'model_confidence': 0.75,
      'bbox_annotations': [],
    });
  }

  String _audioResponse(Map<String, Object?> req) {
    final obsId = req['observation_id'] as String? ?? 'obs-1';
    final promptId = req['prompt_id'] as String? ?? 'fema_p154_q01';
    final askedIn = req['asked_in'] as String? ?? 'en';
    final audioRefs =
        (req['audio_refs'] as List?)?.cast<String>() ?? const ['aud-1'];
    return jsonEncode({
      'observation_id': obsId,
      'prompt_id': promptId,
      'asked_in': askedIn,
      'audio_refs': audioRefs,
      'model_description':
          'DEV_SKIP_MODEL: simulated audio note — volunteer reported no damage.',
      'model_tags': ['no_visible_damage'],
      'model_confidence': 0.8,
    });
  }

  String _batchResponse(Map<String, Object?> req) {
    final photos =
        (req['photos'] as List? ?? const []).cast<Map<String, Object?>>();
    final observations = [
      for (final p in photos)
        {
          'observation_id': p['observation_id'] as String? ?? 'obs-1',
          'prompt_id': p['prompt_id'] as String? ?? 'fema_p154_q01',
          'asked_in': p['asked_in'] as String? ?? 'en',
          'image_refs': p['image_refs'] as List? ?? ['img-1'],
          'model_description':
              'DEV_SKIP_MODEL: simulated batch observation — no damage.',
          'model_tags': ['no_visible_damage'],
          'model_confidence': 0.75,
          'bbox_annotations': [],
        }
    ];
    return jsonEncode({'observations': observations});
  }

  String _protocolResponse() => jsonEncode({
        'protocol_answers_delta': {'visible_collapse': false},
      });

  String _synthResponse() => jsonEncode({
        'triage_draft': {
          'rationale_bullets': [
            'No major structural concerns observed in this simulated run.',
            'Building appears intact with no visible damage indicators.',
          ],
          'uncertainty_notes': [
            'DEV_SKIP_MODEL active — responses are canned, not from real inference.',
          ],
          'recommend_engineer_followup': false,
        },
      });

  // ---------------------------------------------------------------------------
  // Helper
  // ---------------------------------------------------------------------------

  GemmaInferenceResult _result(String text) => GemmaInferenceResult(
        text: text,
        thinking: '',
        ttftMs: 100,
        wallclockMs: 600,
        outputCharCount: text.length,
        runtimeName: 'fake_dev',
      );
}
