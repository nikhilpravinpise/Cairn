import 'dart:convert';
import 'dart:typed_data';

import 'package:cairn_mobile/core/dev_model/dev_scenario.dart';
import 'package:cairn_mobile/core/llm/gemma_session.dart';
import 'package:cairn_mobile/core/llm/orchestrator.dart';
import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) throw StateError('Unable to load asset: $key');
    return ByteData.view(bytes.buffer);
  }
}

class _FakeVisionSession implements GemmaSessionInterface {
  _FakeVisionSession(this.tagsByCall);

  final List<List<String>> tagsByCall;
  var calls = 0;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    calls++;
    final payload = jsonDecode(userText) as Map<String, Object?>;
    final tags = tagsByCall[calls - 1];
    return GemmaInferenceResult(
      text: jsonEncode({
        'observation_id': payload['observation_id'],
        'prompt_id': payload['prompt_id'],
        'asked_in': payload['asked_in'],
        'image_refs': payload['image_refs'],
        'model_description': 'observed ${tags.join(', ')}',
        'model_tags': tags,
        'model_confidence': 0.82,
        'bbox_annotations': [],
      }),
      thinking: '',
      ttftMs: 3,
      wallclockMs: 7,
      outputCharCount: 80,
    );
  }
}

void main() {
  test('built-in manifest exposes 3 scenarios with 4 photos each', () {
    final scenarios = loadBuiltInDevScenarios();
    expect(scenarios, hasLength(3));
    expect(scenarios.every((s) => s.photos.length == 4), isTrue);
    expect(scenarios.expand((s) => s.photos).map((p) => p.slot).toSet(),
        containsAll(kDevScenarioSlots));
  });

  test('tagJaccard handles overlap and empty sets', () {
    expect(tagJaccard(const [], const []), 1);
    expect(tagJaccard(const ['a', 'b'], const ['b', 'c']), 1 / 3);
  });

  test('severity and damage helpers map structural tags conservatively', () {
    expect(severityBucketForTags(const ['no_visible_damage']), 0);
    expect(severityBucketForTags(const ['vertical_crack']), 1);
    expect(severityBucketForTags(const ['diagonal_crack']), 2);
    expect(severityBucketForTags(const ['column_base_damage']), 3);
    expect(hasStructuralDamage(const ['column_base_damage']), isTrue);
    expect(hasStructuralDamage(const ['uncertain_cosmetic']), isFalse);
  });

  test('runDevScenario passes when observed tags match expectations', () async {
    final scenario = loadBuiltInDevScenarios().first;
    final bundle = _MemoryAssetBundle({
      for (final photo in scenario.photos) photo.assetPath: Uint8List(8),
    });
    final session = _FakeVisionSession([
      for (final photo in scenario.photos) photo.expectedTags,
    ]);

    final result = await runDevScenario(
      scenario: scenario,
      orchestrator: GemmaOrchestrator(session),
      bundle: bundle,
    );

    expect(result.schemaFailureCount, 0);
    expect(result.priorityBand, 'LOW');
    expect(result.passed, isTrue);
    expect(result.photoEvals.every((eval) => eval.imageRefPreserved), isTrue);
  });

  test('runDevScenario fails pass gate on missing asset', () async {
    final scenario = loadBuiltInDevScenarios().first;
    await expectLater(
      runDevScenario(
        scenario: scenario,
        orchestrator: GemmaOrchestrator(_FakeVisionSession(const [])),
        bundle: _MemoryAssetBundle(const {}),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('priority-band matching fails when deterministic score is outside band',
      () async {
    final base = loadBuiltInDevScenarios().first;
    final badScenario = DevScenario(
      scenarioId: base.scenarioId,
      title: base.title,
      building: base.building,
      photos: base.photos,
      expected: ExpectedScenarioOutcome(
        priorityBand: 'CRITICAL',
        priorityScoreMin: 9,
        priorityScoreMax: 10,
        protocolAnswers: const ProtocolAnswersRecord(),
        hazardsFlagged: const [],
      ),
    );
    final bundle = _MemoryAssetBundle({
      for (final photo in badScenario.photos) photo.assetPath: Uint8List(8),
    });
    final result = await runDevScenario(
      scenario: badScenario,
      orchestrator: GemmaOrchestrator(_FakeVisionSession([
        for (final photo in badScenario.photos) photo.expectedTags,
      ])),
      bundle: bundle,
    );

    expect(result.priorityBand, 'LOW');
    expect(result.passed, isFalse);
  });
}
