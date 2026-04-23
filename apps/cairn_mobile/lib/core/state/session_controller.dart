/// Owns the in-progress `EvidencePacket` for the current screening session.
///
/// One `SessionDraft` per "Start screening" tap. Mutated by the screens; sealed
/// by Screen 8 (Report) into an `EvidencePacket` and persisted via the vault.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../llm/orchestrator.dart';
import '../models/evidence_packet.dart';
import '../storage/evidence_vault.dart';
import '../triage/priority.dart';

const _kAppVersion = '0.1.0';
const _kAttestationEn =
    'I am not a licensed engineer. This is preliminary screening only.';

class CapturedPhoto {
  const CapturedPhoto({
    required this.ref,
    required this.bytes,
    required this.widthPx,
    required this.heightPx,
    required this.takenAtUtc,
    required this.slot,
  });

  final String ref; // e.g. 'img-1'
  final Uint8List bytes;
  final int widthPx;
  final int heightPx;
  final DateTime takenAtUtc;

  /// 'front' | 'ground_floor' | 'cracks' | 'foundation' | 'extra'
  final String slot;
}

class CapturedAudio {
  const CapturedAudio({
    required this.ref,
    required this.bytes,
    required this.durationS,
    required this.sampleRateHz,
    this.channels = 1,
  });

  final String ref;
  final Uint8List bytes;
  final double durationS;
  final int sampleRateHz;
  final int channels;
}

class SessionDraft {
  SessionDraft({
    required this.packetId,
    required this.createdAtUtc,
    required this.modelName,
    required this.modelQuant,
    this.modelLora,
    this.localeBCP47 = 'en-US',
    this.location,
    this.building,
    List<CapturedPhoto>? photos,
    List<CapturedAudio>? audios,
    List<Observation>? observations,
    List<HazardFlagRecord>? hazardsFlagged,
    ProtocolAnswersRecord? protocolAnswers,
    this.triage,
  })  : photos = photos ?? <CapturedPhoto>[],
        audios = audios ?? <CapturedAudio>[],
        observations = observations ?? <Observation>[],
        hazardsFlagged = hazardsFlagged ?? <HazardFlagRecord>[],
        protocolAnswers = protocolAnswers ?? const ProtocolAnswersRecord();

  final String packetId;
  final DateTime createdAtUtc;
  final String modelName;
  final String modelQuant;
  String? modelLora;
  String localeBCP47;

  GeoLocation? location;
  BuildingInfo? building;

  final List<CapturedPhoto> photos;
  final List<CapturedAudio> audios;
  final List<Observation> observations;
  final List<HazardFlagRecord> hazardsFlagged;
  ProtocolAnswersRecord protocolAnswers;
  TriageResult? triage;

  String get askedIn => localeBCP47.split('-').first;

  /// Shallow copy: new `SessionDraft` instance, same internal list references.
  ///
  /// Riverpod's `Notifier.state` setter skips notification when
  /// `oldState == newState`, and SessionDraft inherits identity-based equality
  /// from `Object`. Every mutator therefore returns state via
  /// `state = s.cloneShallow()` so listeners always fire.
  SessionDraft cloneShallow() => SessionDraft(
        packetId: packetId,
        createdAtUtc: createdAtUtc,
        modelName: modelName,
        modelQuant: modelQuant,
        modelLora: modelLora,
        localeBCP47: localeBCP47,
        location: location,
        building: building,
        photos: photos,
        audios: audios,
        observations: observations,
        hazardsFlagged: hazardsFlagged,
        protocolAnswers: protocolAnswers,
        triage: triage,
      );

  Observation? get lowestConfidenceObservation {
    if (observations.isEmpty) return null;
    final sorted = [...observations]
      ..sort((a, b) => a.modelConfidence.compareTo(b.modelConfidence));
    return sorted.first;
  }

  /// Build the `packet_summary` payload the synthesize task expects.
  Map<String, Object?> packetSummaryForSynthesis() => {
        'building': (building ?? BuildingInfo.unknown).toJson(),
        'observations': [
          for (final o in observations)
            {
              'observation_id': o.observationId,
              'prompt_id': o.promptId,
              'model_description': o.modelDescription,
              'model_tags': o.modelTags,
              'model_confidence': o.modelConfidence,
            }
        ],
        'hazards_flagged': [for (final h in hazardsFlagged) h.toJson()],
        'protocol_answers': protocolAnswers.toJson(),
      };

  EvidencePacket seal({
    required String volunteerSignatureSeed,
  }) {
    final loc = location;
    final bld = building ?? BuildingInfo.unknown;
    final tri = triage;
    if (loc == null || tri == null) {
      throw StateError(
        'cannot seal SessionDraft: location=${loc != null}, triage=${tri != null}',
      );
    }
    final sigHex =
        sha256.convert(volunteerSignatureSeed.codeUnits).toString();
    return EvidencePacket(
      packetId: packetId,
      createdAtUtc: createdAtUtc,
      appVersion: _kAppVersion,
      protocol: 'FEMA-P-154-L1',
      modelName: modelName,
      modelQuant: modelQuant,
      modelLora: modelLora,
      location: loc,
      building: bld,
      observations: observations,
      hazardsFlagged: hazardsFlagged,
      protocolAnswers: protocolAnswers,
      triage: tri,
      volunteer: VolunteerAttestation(
        attestation: _kAttestationEn,
        signatureHash: 'sha256:$sigHex',
        locale: localeBCP47,
      ),
      images: [
        for (final p in photos)
          ImageAsset(
            ref: p.ref,
            filename: '${p.ref}.jpg',
            sha256: sha256.convert(p.bytes).toString(),
            widthPx: p.widthPx,
            heightPx: p.heightPx,
            takenAtUtc: p.takenAtUtc,
          )
      ],
      audio: [
        for (final a in audios)
          AudioAsset(
            ref: a.ref,
            filename: '${a.ref}.wav',
            sha256: sha256.convert(a.bytes).toString(),
            durationS: a.durationS,
            sampleRateHz: a.sampleRateHz,
            channels: a.channels,
          )
      ],
    );
  }
}

class SessionController extends Notifier<SessionDraft?> {
  static const _uuidGen = Uuid();

  @override
  SessionDraft? build() => null;

  /// Start a new screening session (Screen 1 → "Start screening" button).
  void startNew({
    required String modelName,
    required String modelQuant,
    String localeBCP47 = 'en-US',
    String? modelLora,
  }) {
    state = SessionDraft(
      packetId: _uuidGen.v7(),
      createdAtUtc: DateTime.now().toUtc(),
      modelName: modelName,
      modelQuant: modelQuant,
      modelLora: modelLora,
      localeBCP47: localeBCP47,
    );
  }

  void abandon() {
    state = null;
  }

  void setLocation(GeoLocation loc) {
    final s = _require();
    s.location = loc;
    state = s.cloneShallow();
  }

  void setBuilding(BuildingInfo b) {
    final s = _require();
    s.building = b;
    state = s.cloneShallow();
  }

  /// Capture a photo into one of the four required FEMA P-154 slots (front,
  /// ground_floor, cracks, foundation), or 'extra'. Returns the assigned ref.
  String addPhoto({
    required Uint8List bytes,
    required int widthPx,
    required int heightPx,
    required String slot,
  }) {
    final s = _require();
    final ref = 'img-${s.photos.length + 1}';
    s.photos.add(CapturedPhoto(
      ref: ref,
      bytes: bytes,
      widthPx: widthPx,
      heightPx: heightPx,
      takenAtUtc: DateTime.now().toUtc(),
      slot: slot,
    ));
    state = s.cloneShallow();
    return ref;
  }

  String addAudio({
    required Uint8List bytes,
    required double durationS,
    int sampleRateHz = 16000,
    int channels = 1,
  }) {
    final s = _require();
    final ref = 'aud-${s.audios.length + 1}';
    s.audios.add(CapturedAudio(
      ref: ref,
      bytes: bytes,
      durationS: durationS,
      sampleRateHz: sampleRateHz,
      channels: channels,
    ));
    state = s.cloneShallow();
    return ref;
  }

  /// Append a model observation produced by the orchestrator.
  void recordObservation(Observation o) {
    final s = _require();
    s.observations.add(o);
    state = s.cloneShallow();
  }

  /// Replace a single boolean / categorical field in `protocol_answers`.
  /// Called by Screen 5 after a `protocol_answer` orchestrator turn.
  void applyProtocolDelta(MapEntry<String, Object?> delta) {
    final s = _require();
    final pa = s.protocolAnswers;
    s.protocolAnswers = switch (delta.key) {
      'visible_collapse' =>
        pa.copyWith(visibleCollapse: delta.value as bool? ?? false),
      'building_off_foundation' =>
        pa.copyWith(buildingOffFoundation: delta.value as bool? ?? false),
      'leaning' => pa.copyWith(leaning: delta.value as String? ?? 'none'),
      'ground_failure_adjacent' => pa.copyWith(
          groundFailureAdjacent: delta.value as bool? ?? false),
      'falling_hazards' =>
        pa.copyWith(fallingHazards: delta.value as bool? ?? false),
      'adjacent_leaning' =>
        pa.copyWith(adjacentLeaning: delta.value as bool? ?? false),
      _ => throw StateError('unknown protocol_answers key: ${delta.key}'),
    };
    state = s.cloneShallow();
  }

  void addHazard(HazardFlagRecord h) {
    final s = _require();
    s.hazardsFlagged.add(h);
    state = s.cloneShallow();
  }

  /// Run the deterministic Dart scorer (NOT the LLM) and persist the result
  /// into the draft. Called by the synthesize screen after the LLM returns
  /// its rationale bullets.
  void computeAndStoreTriage({
    required List<String> rationaleBullets,
    required List<String> uncertaintyNotes,
  }) {
    final s = _require();
    final score = priorityScore(
      protocolAnswers: ProtocolAnswers(
        visibleCollapse: s.protocolAnswers.visibleCollapse,
        buildingOffFoundation: s.protocolAnswers.buildingOffFoundation,
        leaning: s.protocolAnswers.leaning,
        groundFailureAdjacent: s.protocolAnswers.groundFailureAdjacent,
        fallingHazards: s.protocolAnswers.fallingHazards,
        adjacentLeaning: s.protocolAnswers.adjacentLeaning,
      ),
      hazardsFlagged: [
        for (final h in s.hazardsFlagged)
          HazardFlag(code: h.code, severity: h.severity),
      ],
      building: BuildingMeta(
        type: (s.building ?? BuildingInfo.unknown).type,
        storiesAboveGrade:
            (s.building ?? BuildingInfo.unknown).storiesAboveGrade,
      ),
    );
    s.triage = TriageResult(
      priorityScore: score,
      priorityBand: priorityBandLabel(priorityBand(score)),
      rationaleBullets: rationaleBullets,
      uncertaintyNotes: uncertaintyNotes,
      recommendEngineerFollowup: score >= 4,
    );
    state = s.cloneShallow();
  }

  Future<EvidencePacket> sealAndSave(EvidenceVault vault) async {
    final s = _require();
    final packet = s.seal(volunteerSignatureSeed: '${s.packetId}|$_kAppVersion');
    await vault.savePacket(packet);
    for (final p in s.photos) {
      await vault.putAsset(packet.packetId, p.ref, p.bytes);
    }
    for (final a in s.audios) {
      await vault.putAsset(packet.packetId, a.ref, a.bytes);
    }
    return packet;
  }

  SessionDraft _require() {
    final s = state;
    if (s == null) {
      throw StateError(
        'no active SessionDraft — call startNew() before mutating',
      );
    }
    return s;
  }
}

/// Helper for tests / driver code: hold an `Orchestrator` reference next to
/// the `SessionController` so screens can call `orchestrator.describePhoto`
/// then `controller.recordObservation(...)` in two lines.
class OrchestratorAndController {
  const OrchestratorAndController({
    required this.orchestrator,
    required this.controller,
  });
  final GemmaOrchestrator orchestrator;
  final SessionController controller;
}
