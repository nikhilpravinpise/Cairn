import 'dart:convert';

import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:flutter_test/flutter_test.dart';

EvidencePacket _samplePacket() => EvidencePacket(
      packetId: '0190c6b0-3f0a-7a7b-bc1c-8cbfb1f9aaaa',
      createdAtUtc: DateTime.utc(2026, 5, 2, 14, 23, 11),
      appVersion: '0.1.0',
      protocol: 'FEMA-P-154-L1',
      modelName: 'gemma-4-e4b-it',
      modelQuant: 'int4',
      modelLora: 'cairn-protocol-v1',
      location: const GeoLocation(
        lat: 34.05,
        lng: -118.24,
        accuracyMeters: 8.0,
        addressText: '101 Spring St, LA, CA',
      ),
      building: const BuildingInfo(
        type: 'unreinforced_masonry',
        storiesAboveGrade: 3,
        occupancyHint: 'retail+residential',
        yearBuiltEst: 1930,
      ),
      observations: const [
        Observation(
          observationId: 'obs-1',
          promptId: 'fema_p154_q03_visible_collapse',
          askedIn: 'es',
          imageRefs: ['img-1'],
          audioRefs: [],
          modelDescription: 'sample',
          modelTags: ['diagonal_crack'],
          modelConfidence: 0.72,
          bboxAnnotations: [
            BBox(
              imageRef: 'img-1',
              box2d: [120, 40, 340, 280],
              label: 'diagonal_crack',
            )
          ],
        ),
      ],
      hazardsFlagged: const [
        HazardFlagRecord(
            code: 'H01_soft_story',
            severity: 'high',
            evidenceRefs: ['obs-1']),
      ],
      protocolAnswers: const ProtocolAnswersRecord(
        groundFailureAdjacent: true,
        fallingHazards: true,
        leaning: 'slight',
      ),
      triage: const TriageResult(
        priorityScore: 7,
        priorityBand: 'HIGH',
        rationaleBullets: ['a', 'b', 'c'],
        uncertaintyNotes: ['x'],
        recommendEngineerFollowup: true,
      ),
      volunteer: VolunteerAttestation(
        attestation:
            'I am not a licensed engineer. This is preliminary screening only.',
        signatureHash: 'sha256:${'0' * 64}',
        locale: 'es-MX',
      ),
      images: [
        ImageAsset(
          ref: 'img-1',
          filename: 'img-1.jpg',
          sha256: '0' * 64,
          widthPx: 1024,
          heightPx: 768,
          takenAtUtc: DateTime.utc(2026, 5, 2, 14, 22, 11),
        )
      ],
      audio: const [],
    );

void main() {
  group('EvidencePacket round-trip', () {
    test('toJson / fromJson preserves all fields', () {
      final p = _samplePacket();
      final j = jsonEncode(p.toJson());
      final back = EvidencePacket.fromJson(
          jsonDecode(j) as Map<String, Object?>);
      expect(back.packetId, p.packetId);
      expect(back.createdAtUtc, p.createdAtUtc);
      expect(back.modelLora, 'cairn-protocol-v1');
      expect(back.location.addressText, '101 Spring St, LA, CA');
      expect(back.building.yearBuiltEst, 1930);
      expect(back.observations.first.bboxAnnotations.first.box2d,
          [120, 40, 340, 280]);
      expect(back.protocolAnswers.groundFailureAdjacent, true);
      expect(back.protocolAnswers.leaning, 'slight');
      expect(back.triage.priorityBand, 'HIGH');
      expect(back.images.first.sha256.length, 64);
    });

    test('top-level schema string is correct', () {
      expect(_samplePacket().toJson()['schema'], 'cairn.evidence.v1');
    });

    test('omits null model.lora when not set', () {
      final p = EvidencePacket(
        packetId: 'x',
        createdAtUtc: DateTime.utc(2026, 1, 1),
        appVersion: '0.1.0',
        protocol: 'FEMA-P-154-L1',
        modelName: 'gemma-4-e4b-it',
        modelQuant: 'int4',
        modelLora: null,
        location: const GeoLocation(lat: 0, lng: 0, accuracyMeters: 0),
        building: BuildingInfo.unknown,
        observations: const [],
        hazardsFlagged: const [],
        protocolAnswers: const ProtocolAnswersRecord(),
        triage: const TriageResult(
          priorityScore: 1,
          priorityBand: 'LOW',
          rationaleBullets: [],
          uncertaintyNotes: [],
          recommendEngineerFollowup: false,
        ),
        volunteer: const VolunteerAttestation(
          attestation: 'x',
          signatureHash: 'sha256:0',
          locale: 'en-US',
        ),
        images: const [],
        audio: const [],
      );
      final m = p.toJson()['model'] as Map<String, Object?>;
      expect(m.containsKey('lora'), isFalse);
    });
  });
}
