library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../llm/orchestrator.dart';
import '../models/evidence_packet.dart';
import '../triage/priority.dart';

const kDevScenarioSlots = ['front', 'ground_floor', 'cracks', 'foundation'];

class DevScenario {
  const DevScenario({
    required this.scenarioId,
    required this.title,
    required this.building,
    required this.photos,
    required this.expected,
  });

  final String scenarioId;
  final String title;
  final BuildingInfo building;
  final List<DevScenarioPhoto> photos;
  final ExpectedScenarioOutcome expected;

  factory DevScenario.fromJson(Map<String, Object?> json) => DevScenario(
        scenarioId: json['scenario_id'] as String,
        title: json['title'] as String,
        building: BuildingInfo.fromJson(
            Map<String, Object?>.from(json['building'] as Map)),
        photos: [
          for (final item in json['photos'] as List)
            DevScenarioPhoto.fromJson(Map<String, Object?>.from(item as Map)),
        ],
        expected: ExpectedScenarioOutcome.fromJson(
          Map<String, Object?>.from(json['expected'] as Map),
        ),
      );
}

class DevScenarioPhoto {
  const DevScenarioPhoto({
    required this.slot,
    required this.promptId,
    required this.assetPath,
    required this.expectedTags,
    required this.expectedSeverityBucket,
    required this.expectedStructuralDamage,
  });

  final String slot;
  final String promptId;
  final String assetPath;
  final List<String> expectedTags;
  final int expectedSeverityBucket;
  final bool expectedStructuralDamage;

  factory DevScenarioPhoto.fromJson(Map<String, Object?> json) =>
      DevScenarioPhoto(
        slot: json['slot'] as String,
        promptId: json['prompt_id'] as String,
        assetPath: json['asset_path'] as String,
        expectedTags: (json['expected_tags'] as List).cast<String>(),
        expectedSeverityBucket:
            (json['expected_severity_bucket'] as num).toInt(),
        expectedStructuralDamage:
            json['expected_structural_damage'] as bool? ?? false,
      );
}

class ExpectedScenarioOutcome {
  const ExpectedScenarioOutcome({
    required this.priorityBand,
    required this.priorityScoreMin,
    required this.priorityScoreMax,
    required this.protocolAnswers,
    required this.hazardsFlagged,
  });

  final String priorityBand;
  final int priorityScoreMin;
  final int priorityScoreMax;
  final ProtocolAnswersRecord protocolAnswers;
  final List<HazardFlagRecord> hazardsFlagged;

  factory ExpectedScenarioOutcome.fromJson(Map<String, Object?> json) =>
      ExpectedScenarioOutcome(
        priorityBand: json['priority_band'] as String,
        priorityScoreMin: (json['priority_score_min'] as num).toInt(),
        priorityScoreMax: (json['priority_score_max'] as num).toInt(),
        protocolAnswers: ProtocolAnswersRecord.fromJson(
          Map<String, Object?>.from(json['protocol_answers'] as Map),
        ),
        hazardsFlagged: [
          for (final h in (json['hazards_flagged'] as List? ?? const []))
            HazardFlagRecord.fromJson(Map<String, Object?>.from(h as Map)),
        ],
      );
}

class DevPhotoEval {
  const DevPhotoEval({
    required this.slot,
    required this.imageRefPreserved,
    required this.tagJaccard,
    required this.damagePresenceMatch,
    required this.severityBucketDelta,
    required this.schemaFailures,
    required this.wallclockMs,
    required this.observedTags,
    required this.observedDescription,
  });

  final String slot;
  final bool imageRefPreserved;
  final double tagJaccard;
  final bool damagePresenceMatch;
  final int severityBucketDelta;
  final int schemaFailures;
  final int wallclockMs;
  final List<String> observedTags;
  final String observedDescription;

  Map<String, Object?> toJson() => {
        'slot': slot,
        'image_ref_preserved': imageRefPreserved,
        'tag_jaccard': tagJaccard,
        'damage_presence_match': damagePresenceMatch,
        'severity_bucket_delta': severityBucketDelta,
        'schema_failures': schemaFailures,
        'wallclock_ms': wallclockMs,
        'observed_tags': observedTags,
        'observed_description': observedDescription,
      };
}

class DevScenarioRunResult {
  const DevScenarioRunResult({
    required this.scenarioId,
    required this.title,
    required this.photoEvals,
    required this.priorityScore,
    required this.priorityBand,
    required this.totalWallclockMs,
    required this.schemaFailureCount,
    required this.passed,
  });

  final String scenarioId;
  final String title;
  final List<DevPhotoEval> photoEvals;
  final int priorityScore;
  final String priorityBand;
  final int totalWallclockMs;
  final int schemaFailureCount;
  final bool passed;

  double get visionUnderstandingScore {
    if (photoEvals.isEmpty) return 0;
    var sum = 0.0;
    for (final eval in photoEvals) {
      final severityScore = 1 - (eval.severityBucketDelta.clamp(0, 3) / 3);
      sum += (eval.tagJaccard * 0.45) +
          (eval.damagePresenceMatch ? 0.35 : 0) +
          (severityScore * 0.20);
    }
    return sum / photoEvals.length;
  }

  bool get understandsDamage =>
      photoEvals.every((eval) => eval.damagePresenceMatch);

  bool get severityClose =>
      photoEvals.every((eval) => eval.severityBucketDelta <= 1);

  bool get priorityBandCorrect => passed && schemaFailureCount == 0;

  Map<String, Object?> toJson() => {
        'scenario_id': scenarioId,
        'title': title,
        'vision_understanding_score': visionUnderstandingScore,
        'understands_damage': understandsDamage,
        'severity_close': severityClose,
        'priority_score': priorityScore,
        'priority_band': priorityBand,
        'total_wallclock_ms': totalWallclockMs,
        'schema_failure_count': schemaFailureCount,
        'passed': passed,
        'photo_evals': [for (final eval in photoEvals) eval.toJson()],
      };
}

List<DevScenario> loadBuiltInDevScenarios() => [
      for (final item in jsonDecode(_builtInScenariosJson) as List)
        DevScenario.fromJson(Map<String, Object?>.from(item as Map)),
    ];

Future<DevScenarioRunResult> runDevScenario({
  required DevScenario scenario,
  required GemmaOrchestrator orchestrator,
  AssetBundle? bundle,
}) async {
  final assetBundle = bundle ?? rootBundle;
  final startedAt = DateTime.now();
  final requests = <DescribePhotoRequest>[];
  for (var i = 0; i < scenario.photos.length; i++) {
    final photo = scenario.photos[i];
    final data = await assetBundle.load(photo.assetPath);
    requests.add(DescribePhotoRequest(
      observationId: 'dev-${scenario.scenarioId}-obs-${i + 1}',
      promptId: photo.promptId,
      askedIn: 'en',
      imageBytes: data.buffer.asUint8List(),
      imageRef: 'img-${i + 1}',
    ));
  }

  final results = <DescribePhotoResult>[];
  var schemaFailures = 0;
  await for (final event in orchestrator.describeAll(requests)) {
    switch (event) {
      case DescribePhotoStarted():
        break;
      case DescribePhotoSucceeded(:final result):
        results.add(result);
      case DescribePhotoFailed():
        schemaFailures += 1;
    }
  }

  final evals = <DevPhotoEval>[];
  for (var i = 0; i < scenario.photos.length; i++) {
    final photo = scenario.photos[i];
    final result = i < results.length ? results[i] : null;
    if (result == null) {
      evals.add(DevPhotoEval(
        slot: photo.slot,
        imageRefPreserved: false,
        tagJaccard: 0,
        damagePresenceMatch: false,
        severityBucketDelta: 3,
        schemaFailures: 1,
        wallclockMs: 0,
        observedTags: const [],
        observedDescription: 'describe_photo failed',
      ));
      continue;
    }
    final observedSeverity = severityBucketForTags(result.modelTags);
    final observedDamage = hasStructuralDamage(result.modelTags);
    final refPreserved = result.imageRefs.contains(requests[i].imageRef);
    final bboxFailures = result.bbox.where((box) {
      final coords = box['box_2d'] as List?;
      return coords == null || coords.length != 4;
    }).length;
    evals.add(DevPhotoEval(
      slot: photo.slot,
      imageRefPreserved: refPreserved,
      tagJaccard: tagJaccard(photo.expectedTags, result.modelTags),
      damagePresenceMatch: observedDamage == photo.expectedStructuralDamage,
      severityBucketDelta:
          (observedSeverity - photo.expectedSeverityBucket).abs(),
      schemaFailures: (refPreserved ? 0 : 1) + bboxFailures,
      wallclockMs: result.wallclockMs,
      observedTags: result.modelTags,
      observedDescription: result.modelDescription,
    ));
  }

  schemaFailures +=
      evals.fold<int>(0, (sum, eval) => sum + eval.schemaFailures);
  final score = priorityScore(
    protocolAnswers: ProtocolAnswers(
      visibleCollapse: scenario.expected.protocolAnswers.visibleCollapse,
      buildingOffFoundation:
          scenario.expected.protocolAnswers.buildingOffFoundation,
      leaning: scenario.expected.protocolAnswers.leaning,
      groundFailureAdjacent:
          scenario.expected.protocolAnswers.groundFailureAdjacent,
      fallingHazards: scenario.expected.protocolAnswers.fallingHazards,
      adjacentLeaning: scenario.expected.protocolAnswers.adjacentLeaning,
    ),
    hazardsFlagged: [
      for (final hazard in scenario.expected.hazardsFlagged)
        HazardFlag(code: hazard.code, severity: hazard.severity),
    ],
    building: BuildingMeta(
      type: scenario.building.type,
      storiesAboveGrade: scenario.building.storiesAboveGrade,
    ),
  );
  final band = priorityBandLabel(priorityBand(score));
  final priorityMatches = band == scenario.expected.priorityBand &&
      score >= scenario.expected.priorityScoreMin &&
      score <= scenario.expected.priorityScoreMax;
  final passed = schemaFailures == 0 &&
      evals.length == scenario.photos.length &&
      evals.every((eval) => eval.damagePresenceMatch) &&
      evals.every((eval) => eval.severityBucketDelta <= 1) &&
      priorityMatches;

  return DevScenarioRunResult(
    scenarioId: scenario.scenarioId,
    title: scenario.title,
    photoEvals: evals,
    priorityScore: score,
    priorityBand: band,
    totalWallclockMs: DateTime.now().difference(startedAt).inMilliseconds,
    schemaFailureCount: schemaFailures,
    passed: passed,
  );
}

double tagJaccard(List<String> expected, List<String> observed) {
  final a = expected.toSet();
  final b = observed.toSet();
  if (a.isEmpty && b.isEmpty) return 1;
  final intersection = a.intersection(b).length;
  final union = a.union(b).length;
  return union == 0 ? 0 : intersection / union;
}

bool hasStructuralDamage(List<String> tags) =>
    tags.any((tag) => severityBucketForTags([tag]) >= 2);

int severityBucketForTags(List<String> tags) {
  if (tags.contains('no_visible_damage')) return 0;
  if (tags.any(_isSevereTag)) return 3;
  if (tags.any(_isModerateTag)) return 2;
  if (tags.isNotEmpty) return 1;
  return 0;
}

bool _isSevereTag(String tag) => const {
      'column_base_damage',
      'beam_column_joint_damage',
      'soft_story_condition',
      'out_of_plane_failure',
      'foundation_displacement',
      'exposed_rebar',
      'falling_hazard_unsecured',
    }.contains(tag);

bool _isModerateTag(String tag) => const {
      'diagonal_crack',
      'x_pattern_crack',
      'concrete_spalling',
      'infill_wall_crack',
      'pounding_damage',
      'parapet_damage',
      'chimney_damage',
    }.contains(tag);

const _asset = 'assets/images/s2_probe.jpg';

const _builtInScenariosJson = '''
[
  {
    "scenario_id": "low_no_visible_damage",
    "title": "Low - no visible damage",
    "building": {
      "type": "wood_light_frame",
      "stories_above_grade": 1,
      "occupancy_hint": "residential",
      "year_built_est": 2005
    },
    "photos": [
      {"slot":"front","prompt_id":"fema_p154_q01","asset_path":"$_asset","expected_tags":["no_visible_damage"],"expected_severity_bucket":0,"expected_structural_damage":false},
      {"slot":"ground_floor","prompt_id":"fema_p154_q02","asset_path":"$_asset","expected_tags":["no_visible_damage"],"expected_severity_bucket":0,"expected_structural_damage":false},
      {"slot":"cracks","prompt_id":"fema_p154_q03","asset_path":"$_asset","expected_tags":["no_visible_damage"],"expected_severity_bucket":0,"expected_structural_damage":false},
      {"slot":"foundation","prompt_id":"fema_p154_q04","asset_path":"$_asset","expected_tags":["no_visible_damage"],"expected_severity_bucket":0,"expected_structural_damage":false}
    ],
    "expected": {
      "priority_band": "LOW",
      "priority_score_min": 1,
      "priority_score_max": 3,
      "protocol_answers": {},
      "hazards_flagged": []
    }
  },
  {
    "scenario_id": "medium_cracks_spalling",
    "title": "Medium - cracks and spalling",
    "building": {
      "type": "concrete_moment_frame",
      "stories_above_grade": 3,
      "occupancy_hint": "mixed use",
      "year_built_est": 1985
    },
    "photos": [
      {"slot":"front","prompt_id":"fema_p154_q01","asset_path":"$_asset","expected_tags":["diagonal_crack"],"expected_severity_bucket":2,"expected_structural_damage":true},
      {"slot":"ground_floor","prompt_id":"fema_p154_q02","asset_path":"$_asset","expected_tags":["infill_wall_crack"],"expected_severity_bucket":2,"expected_structural_damage":true},
      {"slot":"cracks","prompt_id":"fema_p154_q03","asset_path":"$_asset","expected_tags":["diagonal_crack","concrete_spalling"],"expected_severity_bucket":2,"expected_structural_damage":true},
      {"slot":"foundation","prompt_id":"fema_p154_q04","asset_path":"$_asset","expected_tags":["uncertain_structural"],"expected_severity_bucket":1,"expected_structural_damage":false}
    ],
    "expected": {
      "priority_band": "MEDIUM",
      "priority_score_min": 4,
      "priority_score_max": 6,
      "protocol_answers": {"falling_hazards": true},
      "hazards_flagged": [
        {"code":"diagonal_crack","severity":"moderate","evidence_refs":["img-3"]}
      ]
    }
  },
  {
    "scenario_id": "high_column_soft_story",
    "title": "High/Critical - column and soft-story indicators",
    "building": {
      "type": "concrete_moment_frame",
      "stories_above_grade": 5,
      "occupancy_hint": "apartment",
      "year_built_est": 1974
    },
    "photos": [
      {"slot":"front","prompt_id":"fema_p154_q01","asset_path":"$_asset","expected_tags":["soft_story_condition"],"expected_severity_bucket":3,"expected_structural_damage":true},
      {"slot":"ground_floor","prompt_id":"fema_p154_q02","asset_path":"$_asset","expected_tags":["soft_story_condition","column_base_damage"],"expected_severity_bucket":3,"expected_structural_damage":true},
      {"slot":"cracks","prompt_id":"fema_p154_q03","asset_path":"$_asset","expected_tags":["exposed_rebar","concrete_spalling"],"expected_severity_bucket":3,"expected_structural_damage":true},
      {"slot":"foundation","prompt_id":"fema_p154_q04","asset_path":"$_asset","expected_tags":["foundation_displacement"],"expected_severity_bucket":3,"expected_structural_damage":true}
    ],
    "expected": {
      "priority_band": "CRITICAL",
      "priority_score_min": 9,
      "priority_score_max": 10,
      "protocol_answers": {"leaning":"severe","building_off_foundation": true},
      "hazards_flagged": [
        {"code":"soft_story_condition","severity":"high","evidence_refs":["img-2"]},
        {"code":"column_base_damage","severity":"high","evidence_refs":["img-2"]},
        {"code":"foundation_displacement","severity":"high","evidence_refs":["img-4"]}
      ]
    }
  }
]
''';
