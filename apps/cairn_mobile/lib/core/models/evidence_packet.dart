/// Dart mirror of `docs/schema/evidence_packet_v1.schema.json`.
///
/// Hand-written (no `freezed`/`json_serializable`) to avoid a build_runner
/// step in the web build pipeline. Validation lives in
/// `core/models/evidence_packet_validator.dart` and is unit-tested in
/// `test/evidence_packet_test.dart`.
library;

import 'dart:convert';

const String kSchemaVersion = 'cairn.evidence.v1';

class GeoLocation {
  const GeoLocation({
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
    this.addressText = '',
  });

  final double lat;
  final double lng;
  final double accuracyMeters;
  final String addressText;

  Map<String, Object?> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracy_m': accuracyMeters,
        'address_text': addressText,
      };

  factory GeoLocation.fromJson(Map<String, Object?> j) => GeoLocation(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        accuracyMeters: (j['accuracy_m'] as num).toDouble(),
        addressText: (j['address_text'] as String?) ?? '',
      );
}

class BuildingInfo {
  const BuildingInfo({
    required this.type,
    required this.storiesAboveGrade,
    this.occupancyHint = '',
    this.yearBuiltEst,
  });

  /// One of: concrete_moment_frame, unreinforced_masonry, wood_light_frame,
  /// steel, mixed, unknown
  final String type;
  final int storiesAboveGrade;
  final String occupancyHint;
  final int? yearBuiltEst;

  BuildingInfo copyWith({
    String? type,
    int? storiesAboveGrade,
    String? occupancyHint,
    int? yearBuiltEst,
  }) =>
      BuildingInfo(
        type: type ?? this.type,
        storiesAboveGrade: storiesAboveGrade ?? this.storiesAboveGrade,
        occupancyHint: occupancyHint ?? this.occupancyHint,
        yearBuiltEst: yearBuiltEst ?? this.yearBuiltEst,
      );

  Map<String, Object?> toJson() => {
        'type': type,
        'stories_above_grade': storiesAboveGrade,
        'occupancy_hint': occupancyHint,
        'year_built_est': yearBuiltEst,
      };

  factory BuildingInfo.fromJson(Map<String, Object?> j) => BuildingInfo(
        type: j['type'] as String,
        storiesAboveGrade: (j['stories_above_grade'] as num).toInt(),
        occupancyHint: (j['occupancy_hint'] as String?) ?? '',
        yearBuiltEst: (j['year_built_est'] as num?)?.toInt(),
      );

  static const BuildingInfo unknown = BuildingInfo(
    type: 'unknown',
    storiesAboveGrade: 1,
    occupancyHint: '',
  );
}

class BBox {
  const BBox({
    required this.imageRef,
    required this.box2d,
    required this.label,
  });

  /// References an entry in `assets.images[].ref`.
  final String imageRef;

  /// Gemma vision convention: [y1, x1, y2, x2], integers in 0..1000.
  final List<int> box2d;
  final String label;

  Map<String, Object?> toJson() => {
        'image_ref': imageRef,
        'box_2d': box2d,
        'label': label,
      };

  factory BBox.fromJson(Map<String, Object?> j) => BBox(
        imageRef: j['image_ref'] as String,
        box2d: (j['box_2d'] as List).cast<num>().map((n) => n.toInt()).toList(),
        label: j['label'] as String,
      );
}

class Observation {
  const Observation({
    required this.observationId,
    required this.promptId,
    required this.askedIn,
    required this.imageRefs,
    required this.audioRefs,
    this.userText,
    required this.modelDescription,
    required this.modelTags,
    required this.modelConfidence,
    this.bboxAnnotations = const [],
  });

  final String observationId;
  final String promptId;

  /// "en" | "es" | "tr"
  final String askedIn;
  final List<String> imageRefs;
  final List<String> audioRefs;
  final String? userText;
  final String modelDescription;
  final List<String> modelTags;
  final double modelConfidence;
  final List<BBox> bboxAnnotations;

  Map<String, Object?> toJson() => {
        'observation_id': observationId,
        'prompt_id': promptId,
        'asked_in': askedIn,
        'image_refs': imageRefs,
        'audio_refs': audioRefs,
        'user_text': userText,
        'model_description': modelDescription,
        'model_tags': modelTags,
        'model_confidence': modelConfidence,
        'bbox_annotations': [for (final b in bboxAnnotations) b.toJson()],
      };

  factory Observation.fromJson(Map<String, Object?> j) => Observation(
        observationId: j['observation_id'] as String,
        promptId: j['prompt_id'] as String,
        askedIn: j['asked_in'] as String,
        imageRefs: (j['image_refs'] as List).cast<String>(),
        audioRefs: (j['audio_refs'] as List? ?? const []).cast<String>(),
        userText: j['user_text'] as String?,
        modelDescription: j['model_description'] as String,
        modelTags: (j['model_tags'] as List).cast<String>(),
        modelConfidence: (j['model_confidence'] as num).toDouble(),
        bboxAnnotations: [
          for (final b in (j['bbox_annotations'] as List? ?? const []))
            BBox.fromJson(b as Map<String, Object?>),
        ],
      );
}

class HazardFlagRecord {
  const HazardFlagRecord({
    required this.code,
    required this.severity,
    this.evidenceRefs = const [],
  });

  final String code;
  final String severity; // 'low' | 'moderate' | 'high'
  final List<String> evidenceRefs;

  Map<String, Object?> toJson() => {
        'code': code,
        'severity': severity,
        'evidence_refs': evidenceRefs,
      };

  factory HazardFlagRecord.fromJson(Map<String, Object?> j) => HazardFlagRecord(
        code: j['code'] as String,
        severity: j['severity'] as String,
        evidenceRefs:
            (j['evidence_refs'] as List? ?? const []).cast<String>(),
      );
}

class ProtocolAnswersRecord {
  const ProtocolAnswersRecord({
    this.visibleCollapse = false,
    this.buildingOffFoundation = false,
    this.leaning = 'none',
    this.groundFailureAdjacent = false,
    this.fallingHazards = false,
    this.adjacentLeaning = false,
  });

  final bool visibleCollapse;
  final bool buildingOffFoundation;

  /// 'none' | 'slight' | 'moderate' | 'severe'
  final String leaning;
  final bool groundFailureAdjacent;
  final bool fallingHazards;
  final bool adjacentLeaning;

  ProtocolAnswersRecord copyWith({
    bool? visibleCollapse,
    bool? buildingOffFoundation,
    String? leaning,
    bool? groundFailureAdjacent,
    bool? fallingHazards,
    bool? adjacentLeaning,
  }) =>
      ProtocolAnswersRecord(
        visibleCollapse: visibleCollapse ?? this.visibleCollapse,
        buildingOffFoundation:
            buildingOffFoundation ?? this.buildingOffFoundation,
        leaning: leaning ?? this.leaning,
        groundFailureAdjacent:
            groundFailureAdjacent ?? this.groundFailureAdjacent,
        fallingHazards: fallingHazards ?? this.fallingHazards,
        adjacentLeaning: adjacentLeaning ?? this.adjacentLeaning,
      );

  Map<String, Object?> toJson() => {
        'visible_collapse': visibleCollapse,
        'building_off_foundation': buildingOffFoundation,
        'leaning': leaning,
        'ground_failure_adjacent': groundFailureAdjacent,
        'falling_hazards': fallingHazards,
        'adjacent_leaning': adjacentLeaning,
      };

  factory ProtocolAnswersRecord.fromJson(Map<String, Object?> j) =>
      ProtocolAnswersRecord(
        visibleCollapse: j['visible_collapse'] as bool? ?? false,
        buildingOffFoundation: j['building_off_foundation'] as bool? ?? false,
        leaning: (j['leaning'] as String?) ?? 'none',
        groundFailureAdjacent:
            j['ground_failure_adjacent'] as bool? ?? false,
        fallingHazards: j['falling_hazards'] as bool? ?? false,
        adjacentLeaning: j['adjacent_leaning'] as bool? ?? false,
      );
}

class TriageResult {
  const TriageResult({
    required this.priorityScore,
    required this.priorityBand,
    required this.rationaleBullets,
    required this.uncertaintyNotes,
    required this.recommendEngineerFollowup,
  });

  final int priorityScore;

  /// LOW | MEDIUM | HIGH | CRITICAL
  final String priorityBand;
  final List<String> rationaleBullets;
  final List<String> uncertaintyNotes;
  final bool recommendEngineerFollowup;

  Map<String, Object?> toJson() => {
        'priority_score': priorityScore,
        'priority_band': priorityBand,
        'rationale_bullets': rationaleBullets,
        'uncertainty_notes': uncertaintyNotes,
        'recommend_engineer_followup': recommendEngineerFollowup,
      };

  factory TriageResult.fromJson(Map<String, Object?> j) => TriageResult(
        priorityScore: (j['priority_score'] as num).toInt(),
        priorityBand: j['priority_band'] as String,
        rationaleBullets: (j['rationale_bullets'] as List).cast<String>(),
        uncertaintyNotes:
            (j['uncertainty_notes'] as List? ?? const []).cast<String>(),
        recommendEngineerFollowup:
            j['recommend_engineer_followup'] as bool? ?? false,
      );
}

class VolunteerAttestation {
  const VolunteerAttestation({
    required this.attestation,
    required this.signatureHash,
    required this.locale,
  });

  final String attestation;
  final String signatureHash;

  /// BCP47 like "es-MX"
  final String locale;

  Map<String, Object?> toJson() => {
        'attestation': attestation,
        'signature_hash': signatureHash,
        'locale': locale,
      };

  factory VolunteerAttestation.fromJson(Map<String, Object?> j) =>
      VolunteerAttestation(
        attestation: j['attestation'] as String,
        signatureHash: j['signature_hash'] as String,
        locale: j['locale'] as String,
      );
}

class ImageAsset {
  const ImageAsset({
    required this.ref,
    required this.filename,
    required this.sha256,
    required this.widthPx,
    required this.heightPx,
    required this.takenAtUtc,
  });

  final String ref;
  final String filename;
  final String sha256; // hex, 64 chars
  final int widthPx;
  final int heightPx;
  final DateTime takenAtUtc;

  Map<String, Object?> toJson() => {
        'ref': ref,
        'filename': filename,
        'sha256': sha256,
        'width_px': widthPx,
        'height_px': heightPx,
        'taken_at_utc': takenAtUtc.toUtc().toIso8601String(),
      };

  factory ImageAsset.fromJson(Map<String, Object?> j) => ImageAsset(
        ref: j['ref'] as String,
        filename: j['filename'] as String,
        sha256: j['sha256'] as String,
        widthPx: (j['width_px'] as num).toInt(),
        heightPx: (j['height_px'] as num).toInt(),
        takenAtUtc: DateTime.parse(j['taken_at_utc'] as String).toUtc(),
      );
}

class AudioAsset {
  const AudioAsset({
    required this.ref,
    required this.filename,
    required this.sha256,
    required this.durationS,
    required this.sampleRateHz,
    this.channels = 1,
  });

  final String ref;
  final String filename;
  final String sha256;
  final double durationS;
  final int sampleRateHz; // 16000
  final int channels; // 1 = mono

  Map<String, Object?> toJson() => {
        'ref': ref,
        'filename': filename,
        'sha256': sha256,
        'duration_s': durationS,
        'sample_rate_hz': sampleRateHz,
        'channels': channels,
      };

  factory AudioAsset.fromJson(Map<String, Object?> j) => AudioAsset(
        ref: j['ref'] as String,
        filename: j['filename'] as String,
        sha256: j['sha256'] as String,
        durationS: (j['duration_s'] as num).toDouble(),
        sampleRateHz: (j['sample_rate_hz'] as num).toInt(),
        channels: (j['channels'] as num?)?.toInt() ?? 1,
      );
}

class EvidencePacket {
  const EvidencePacket({
    required this.packetId,
    required this.createdAtUtc,
    required this.appVersion,
    required this.protocol,
    required this.modelName,
    required this.modelQuant,
    this.modelLora,
    required this.location,
    required this.building,
    required this.observations,
    required this.hazardsFlagged,
    required this.protocolAnswers,
    required this.triage,
    required this.volunteer,
    required this.images,
    required this.audio,
  });

  final String packetId; // UUIDv7
  final DateTime createdAtUtc;
  final String appVersion;
  final String protocol; // 'FEMA-P-154-L1'
  final String modelName;
  final String modelQuant;
  final String? modelLora;
  final GeoLocation location;
  final BuildingInfo building;
  final List<Observation> observations;
  final List<HazardFlagRecord> hazardsFlagged;
  final ProtocolAnswersRecord protocolAnswers;
  final TriageResult triage;
  final VolunteerAttestation volunteer;
  final List<ImageAsset> images;
  final List<AudioAsset> audio;

  Map<String, Object?> toJson() => {
        'schema': kSchemaVersion,
        'packet_id': packetId,
        'created_at_utc': createdAtUtc.toUtc().toIso8601String(),
        'app_version': appVersion,
        'protocol': protocol,
        'model': {
          'name': modelName,
          'quant': modelQuant,
          if (modelLora != null) 'lora': modelLora,
        },
        'location': location.toJson(),
        'building': building.toJson(),
        'observations': [for (final o in observations) o.toJson()],
        'hazards_flagged': [for (final h in hazardsFlagged) h.toJson()],
        'protocol_answers': protocolAnswers.toJson(),
        'triage': triage.toJson(),
        'volunteer': volunteer.toJson(),
        'assets': {
          'images': [for (final i in images) i.toJson()],
          'audio': [for (final a in audio) a.toJson()],
        },
      };

  String toJsonString({bool pretty = false}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  factory EvidencePacket.fromJson(Map<String, Object?> j) {
    final model = j['model'] as Map<String, Object?>;
    final assets = j['assets'] as Map<String, Object?>;
    return EvidencePacket(
      packetId: j['packet_id'] as String,
      createdAtUtc:
          DateTime.parse(j['created_at_utc'] as String).toUtc(),
      appVersion: j['app_version'] as String,
      protocol: j['protocol'] as String,
      modelName: model['name'] as String,
      modelQuant: model['quant'] as String,
      modelLora: model['lora'] as String?,
      location: GeoLocation.fromJson(j['location'] as Map<String, Object?>),
      building: BuildingInfo.fromJson(j['building'] as Map<String, Object?>),
      observations: [
        for (final o in (j['observations'] as List))
          Observation.fromJson(o as Map<String, Object?>),
      ],
      hazardsFlagged: [
        for (final h in (j['hazards_flagged'] as List? ?? const []))
          HazardFlagRecord.fromJson(h as Map<String, Object?>),
      ],
      protocolAnswers: ProtocolAnswersRecord.fromJson(
          j['protocol_answers'] as Map<String, Object?>),
      triage:
          TriageResult.fromJson(j['triage'] as Map<String, Object?>),
      volunteer: VolunteerAttestation.fromJson(
          j['volunteer'] as Map<String, Object?>),
      images: [
        for (final i in (assets['images'] as List? ?? const []))
          ImageAsset.fromJson(i as Map<String, Object?>),
      ],
      audio: [
        for (final a in (assets['audio'] as List? ?? const []))
          AudioAsset.fromJson(a as Map<String, Object?>),
      ],
    );
  }
}
