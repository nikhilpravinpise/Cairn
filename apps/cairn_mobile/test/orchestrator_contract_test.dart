/// Phase 6 contract-check tests for [GemmaOrchestrator].
///
/// Verifies that the orchestrator enforces its three new contract invariants:
///
///  1. `describe_photo` / `describe_audio` — each tag in `model_tags` must be
///     a member of [EvidencePacketValidator.kAllowedModelTags].
///  2. `describe_photo` — each `bbox_annotations` entry must have `box_2d`
///     with exactly 4 integers, each in 0..1000 (Gemma vision convention).
///  3. `synthesize` — the model must NOT include `priority_score` or
///     `priority_band` in `triage_draft` (system prompt §HARD RULES rule 8).
///
/// All tests are pure-Dart (no Flutter widgets, no native channels).
library;

import 'dart:typed_data';

import 'package:cairn_mobile/core/llm/gemma_session.dart';
import 'package:cairn_mobile/core/llm/orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake session
// ---------------------------------------------------------------------------

class _FakeSession implements GemmaSessionInterface {
  _FakeSession(this._response, {this.ttftMs = 10, this.wallclockMs = 20});

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

GemmaOrchestrator _orch(String response) =>
    GemmaOrchestrator(_FakeSession(response));

// ---------------------------------------------------------------------------
// Shared payloads
// ---------------------------------------------------------------------------

String _photoJson({
  String imageRefs = '["img-1"]',
  String tags = '["diagonal_crack"]',
  String bbox = '[]',
  String description = '"Some cracking visible."',
  String confidence = '0.7',
}) =>
    '{"observation_id": "obs-1", "prompt_id": "fema_p154_q01", '
    '"asked_in": "en", "image_refs": $imageRefs, '
    '"model_description": $description, '
    '"model_tags": $tags, "model_confidence": $confidence, '
    '"bbox_annotations": $bbox}';

String _audioJson({
  String audioRefs = '["aud-1"]',
  String tags = '["no_visible_damage"]',
  String description = '"Volunteer reported no damage."',
  String confidence = '0.8',
}) =>
    '{"observation_id": "obs-2", "prompt_id": "fema_p154_q01", '
    '"asked_in": "en", "audio_refs": $audioRefs, '
    '"model_description": $description, '
    '"model_tags": $tags, "model_confidence": $confidence}';

String _synthJson({Map<String, Object?>? extra}) {
  final extraKeys = extra == null
      ? ''
      : extra.entries.map((e) => ', "${e.key}": ${e.value}').join();
  return '{"triage_draft": {"rationale_bullets": ["bullet 1"], '
      '"uncertainty_notes": [], '
      '"recommend_engineer_followup": false$extraKeys}}';
}

Future<DescribePhotoResult> _photo(String response) =>
    _orch(response).describePhoto(
      observationId: 'obs-1',
      promptId: 'fema_p154_q01',
      askedIn: 'en',
      imageBytes: Uint8List(0),
      imageRef: 'img-1',
    );

Future<DescribeAudioResult> _audio(String response) =>
    _orch(response).describeAudio(
      observationId: 'obs-2',
      promptId: 'fema_p154_q01',
      askedIn: 'en',
      audioBytes: Uint8List(0),
      audioRef: 'aud-1',
    );

Future<SynthesizeResult> _synth(String response) => _orch(response).synthesize(
      askedIn: 'en',
      packetSummary: {'observations': []},
    );

// ---------------------------------------------------------------------------
// describe_photo — tag validation
// ---------------------------------------------------------------------------

void main() {
  group('describePhoto — tag contract', () {
    test('valid tags → DescribePhotoResult without error', () async {
      final res = await _photo(
          _photoJson(tags: '["diagonal_crack","no_visible_damage"]'));
      // _normalizeDescribePhotoTags strips no_visible_damage when any concrete
      // damage tag is present (diagonal_crack qualifies).
      expect(res.modelTags, ['diagonal_crack']);
    });

    test('empty tags list → ok', () async {
      final res = await _photo(_photoJson(tags: '[]'));
      expect(res.modelTags, isEmpty);
    });

    test('single unknown tag → throws GemmaContractError', () async {
      await expectLater(
        _photo(_photoJson(tags: '["collapsed_building"]')),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('"collapsed_building"'),
        )),
      );
    });

    test('mix of valid + invalid tags → throws on the invalid one', () async {
      await expectLater(
        _photo(_photoJson(tags: '["diagonal_crack","unsafe"]')),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('"unsafe"'),
        )),
      );
    });

    test('task field is describe_photo in thrown error', () async {
      await expectLater(
        _photo(_photoJson(tags: '["red_tagged"]')),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.task,
          'task',
          'describe_photo',
        )),
      );
    });

    test('all 19 allowed tags parse cleanly', () async {
      const allTags = '['
          '"diagonal_crack","horizontal_crack","vertical_crack","x_pattern_crack",'
          '"concrete_spalling","exposed_rebar","column_base_damage",'
          '"beam_column_joint_damage","soft_story_condition","pounding_damage",'
          '"infill_wall_crack","out_of_plane_failure","foundation_displacement",'
          '"chimney_damage","parapet_damage","falling_hazard_unsecured",'
          '"uncertain_structural","uncertain_cosmetic","no_visible_damage"'
          ']';
      final res = await _photo(_photoJson(tags: allTags));
      // Normalization removes no_visible_damage when concrete damage tags are
      // present, so the returned list has 18 elements, not 19.
      expect(res.modelTags.length, 18);
    });
  });

  // ---------------------------------------------------------------------------
  // describePhoto — tag normalisation
  // ---------------------------------------------------------------------------

  group('describePhoto — tag normalisation', () {
    test('no_visible_damage alone is preserved', () async {
      final res = await _photo(_photoJson(tags: '["no_visible_damage"]'));
      expect(res.modelTags, ['no_visible_damage']);
    });

    test(
        'no_visible_damage is stripped when a concrete damage tag is present',
        () async {
      final res = await _photo(
          _photoJson(tags: '["diagonal_crack","no_visible_damage"]'));
      expect(res.modelTags, ['diagonal_crack']);
    });

    test(
        'uncertain tags alone do not suppress no_visible_damage', () async {
      final res = await _photo(_photoJson(
          tags: '["uncertain_structural","no_visible_damage"]'));
      expect(res.modelTags, containsAll(['uncertain_structural', 'no_visible_damage']));
    });

    test('duplicate tags are deduplicated', () async {
      final res = await _photo(
          _photoJson(tags: '["diagonal_crack","diagonal_crack"]'));
      expect(res.modelTags, ['diagonal_crack']);
    });
  });

  // ---------------------------------------------------------------------------
  // describe_photo — bbox validation
  // ---------------------------------------------------------------------------

  group('describePhoto — bbox contract', () {
    test('valid bbox → DescribePhotoResult with bbox data', () async {
      const bbox =
          '[{"box_2d": [100, 200, 300, 400], "label": "crack", "image_ref": "img-1"}]';
      final res = await _photo(_photoJson(bbox: bbox));
      expect(res.bbox.length, 1);
      expect(res.bbox[0]['label'], 'crack');
    });

    test('bbox with exactly 4 elements at boundary values → valid', () async {
      const bbox = '[{"box_2d": [0, 0, 1000, 1000], "label": "test"}]';
      final res = await _photo(_photoJson(bbox: bbox));
      expect(res.bbox.length, 1);
    });

    test('bbox with 3 elements → throws GemmaContractError', () async {
      const bbox = '[{"box_2d": [100, 200, 300], "label": "crack"}]';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('exactly 4'),
        )),
      );
    });

    test('bbox with 5 elements → throws GemmaContractError', () async {
      const bbox = '[{"box_2d": [100, 200, 300, 400, 500], "label": "crack"}]';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('bbox coord > 1000 → throws GemmaContractError', () async {
      const bbox = '[{"box_2d": [100, 200, 300, 1001], "label": "crack"}]';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('1001'),
        )),
      );
    });

    test('bbox coord < 0 → throws GemmaContractError', () async {
      const bbox = '[{"box_2d": [-1, 200, 300, 400], "label": "crack"}]';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('-1'),
        )),
      );
    });

    test('second bbox entry invalid → throws with index in message', () async {
      const bbox = '['
          '{"box_2d": [0, 0, 100, 100], "label": "ok"},'
          '{"box_2d": [0, 0, 100], "label": "bad"}'
          ']';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('[1]'),
        )),
      );
    });

    test('empty bbox list → no error', () async {
      final res = await _photo(_photoJson(bbox: '[]'));
      expect(res.bbox, isEmpty);
    });

    test('bbox y1 >= y2 → throws GemmaContractError (ordering violation)',
        () async {
      const bbox = '[{"box_2d": [300, 100, 100, 400], "label": "crack"}]';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('y1'),
        )),
      );
    });

    test('bbox x1 >= x2 → throws GemmaContractError (ordering violation)',
        () async {
      const bbox = '[{"box_2d": [100, 400, 300, 100], "label": "crack"}]';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('x1'),
        )),
      );
    });

    test('bbox y1 == y2 → throws (degenerate box)', () async {
      const bbox = '[{"box_2d": [200, 100, 200, 400], "label": "crack"}]';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('bbox image_ref mismatch → throws GemmaContractError', () async {
      const bbox =
          '[{"box_2d": [100, 200, 300, 400], "label": "crack", "image_ref": "img-99"}]';
      await expectLater(
        _photo(_photoJson(bbox: bbox)),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('image_ref'),
        )),
      );
    });

    test('bbox missing image_ref is normalised to request image_ref', () async {
      const bbox = '[{"box_2d": [100, 200, 300, 400], "label": "crack"}]';
      final res = await _photo(_photoJson(bbox: bbox));
      expect(res.bbox.single['image_ref'], 'img-1');
    });
  });

  // ---------------------------------------------------------------------------
  // describe_photo — ref / confidence validation
  // ---------------------------------------------------------------------------

  group('describePhoto — ref and confidence contract', () {
    test('omitted image_refs falls back to request imageRef', () async {
      const json = '{"observation_id": "obs-1", "prompt_id": "fema_p154_q01", '
          '"asked_in": "en", '
          '"model_description": "Some cracking visible.", '
          '"model_tags": ["diagonal_crack"], "model_confidence": 0.7, '
          '"bbox_annotations": []}';
      final res = await _photo(json);
      expect(res.imageRefs, ['img-1']);
    });

    test('wrong image_refs value → throws GemmaContractError', () async {
      await expectLater(
        _photo(_photoJson(imageRefs: '["img-99"]')),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('image_refs'),
        )),
      );
    });

    test('empty image_refs → throws GemmaContractError', () async {
      await expectLater(
        _photo(_photoJson(imageRefs: '[]')),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('model_confidence outside 0..1 → throws GemmaContractError', () async {
      await expectLater(
        _photo(_photoJson(confidence: '1.2')),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('model_confidence'),
        )),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // describe_photo — TTFT / wallclock
  // ---------------------------------------------------------------------------

  group('describePhoto — TTFT / wallclock propagation', () {
    test('ttftMs and wallclockMs come from session result', () async {
      final orch = GemmaOrchestrator(
          _FakeSession(_photoJson(), ttftMs: 77, wallclockMs: 200));
      final res = await orch.describePhoto(
        observationId: 'obs-1',
        promptId: 'fema_p154_q01',
        askedIn: 'en',
        imageBytes: Uint8List(0),
        imageRef: 'img-1',
      );
      expect(res.ttftMs, 77);
      expect(res.wallclockMs, 200);
    });
  });

  // ---------------------------------------------------------------------------
  // describe_audio
  // ---------------------------------------------------------------------------

  group('describeAudio — tag contract', () {
    test('valid tags → DescribeAudioResult', () async {
      final res = await _audio(_audioJson(tags: '["no_visible_damage"]'));
      expect(res.modelTags, ['no_visible_damage']);
      expect(res.audioRefs, ['aud-1']);
    });

    test('invalid tag → throws with describe_audio task', () async {
      await expectLater(
        _audio(_audioJson(tags: '["condemned"]')),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.task,
          'task',
          'describe_audio',
        )),
      );
    });

    test('missing model_description → throws GemmaContractError', () async {
      const noDesc = '{"observation_id": "obs-2", "prompt_id": "p1", '
          '"asked_in": "en", "model_tags": [], "model_confidence": 0.5}';
      await expectLater(
        _audio(noDesc),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('no JSON in response → throws', () async {
      await expectLater(
        _audio('sorry, cannot help'),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('ttftMs and wallclockMs propagated', () async {
      final orch = GemmaOrchestrator(
          _FakeSession(_audioJson(), ttftMs: 30, wallclockMs: 90));
      final res = await orch.describeAudio(
        observationId: 'obs-2',
        promptId: 'fema_p154_q01',
        askedIn: 'en',
        audioBytes: Uint8List(0),
        audioRef: 'aud-1',
      );
      expect(res.ttftMs, 30);
      expect(res.wallclockMs, 90);
    });

    test('wrong audio_refs value → throws GemmaContractError', () async {
      await expectLater(
        _audio(_audioJson(audioRefs: '["aud-99"]')),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('audio_refs'),
        )),
      );
    });

    test('model_confidence outside 0..1 → throws GemmaContractError', () async {
      await expectLater(
        _audio(_audioJson(confidence: '-0.1')),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('model_confidence'),
        )),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // synthesize — priority_score / priority_band rejection
  // ---------------------------------------------------------------------------

  group('synthesize — contract', () {
    test('valid response → SynthesizeResult', () async {
      final res = await _synth(_synthJson());
      expect(res.rationaleBullets, ['bullet 1']);
      expect(res.recommendEngineerFollowup, isFalse);
    });

    test('model sets priority_score → throws GemmaContractError', () async {
      await expectLater(
        _synth(_synthJson(extra: {'priority_score': 7})),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('priority_score'),
        )),
      );
    });

    test('model sets priority_band → throws GemmaContractError', () async {
      await expectLater(
        _synth(_synthJson(extra: {'priority_band': '"HIGH"'})),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('priority_band'),
        )),
      );
    });

    test('task in thrown error is synthesize', () async {
      await expectLater(
        _synth(_synthJson(extra: {'priority_score': 5})),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.task,
          'task',
          'synthesize',
        )),
      );
    });

    test('missing triage_draft → throws', () async {
      await expectLater(
        _synth('{"not_a_draft": {}}'),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('no JSON in response → throws', () async {
      await expectLater(
        _synth('I am unable to process this.'),
        throwsA(isA<GemmaContractError>()),
      );
    });

    test('ttftMs and wallclockMs propagated', () async {
      final orch = GemmaOrchestrator(
          _FakeSession(_synthJson(), ttftMs: 88, wallclockMs: 300));
      final res = await orch
          .synthesize(askedIn: 'en', packetSummary: {'observations': []});
      expect(res.ttftMs, 88);
      expect(res.wallclockMs, 300);
    });
  });

  // ---------------------------------------------------------------------------
  // protocolAnswer — key validation
  // ---------------------------------------------------------------------------

  group('protocolAnswer — key validation', () {
    Future<ProtocolAnswerResult> makeProtocol(String key, Object value) =>
        _orch('{"protocol_answers_delta": {"$key": $value}}')
            .protocolAnswer(askedIn: 'en', questionId: 'q1', userText: 'yes');

    test('valid key visible_collapse → result with correct key', () async {
      final res = await makeProtocol('visible_collapse', 'false');
      expect(res.delta.key, 'visible_collapse');
    });

    test('all six allowed keys parse cleanly', () async {
      const keys = [
        'visible_collapse',
        'building_off_foundation',
        'leaning',
        'ground_failure_adjacent',
        'falling_hazards',
        'adjacent_leaning',
      ];
      for (final k in keys) {
        final res = await makeProtocol(k, 'false');
        expect(res.delta.key, k, reason: 'key $k should be allowed');
      }
    });

    test('unknown key → throws GemmaContractError', () async {
      await expectLater(
        makeProtocol('unsafe_building', 'true'),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('"unsafe_building"'),
        )),
      );
    });

    test('unknown key error has task == protocol_answer', () async {
      await expectLater(
        makeProtocol('red_tagged', 'true'),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.task,
          'task',
          'protocol_answer',
        )),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // protocolAnswer — TTFT / wallclock
  // ---------------------------------------------------------------------------

  group('protocolAnswer — TTFT / wallclock propagation', () {
    test('ttftMs and wallclockMs come from session result', () async {
      const response =
          '{"protocol_answers_delta": {"visible_collapse": false}}';
      final orch = GemmaOrchestrator(
          _FakeSession(response, ttftMs: 40, wallclockMs: 150));
      final res = await orch.protocolAnswer(
          askedIn: 'en', questionId: 'q1', userText: 'no');
      expect(res.ttftMs, 40);
      expect(res.wallclockMs, 150);
    });
  });
}
