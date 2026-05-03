/// Tests for [buildReportPdf].
///
/// Validates that the function completes without error, produces non-empty
/// bytes that start with the PDF signature `%PDF`, and respects the
/// `imageBytes` argument (smoke test — full visual layout is manual).
library;

import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/pdf/report_pdf_builder.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

EvidencePacket _packet({int score = 3, String band = 'LOW'}) => EvidencePacket(
      packetId: 'pdf-test-001',
      createdAtUtc: DateTime.utc(2025, 4, 15, 10, 0),
      appVersion: '0.1.0',
      protocol: 'FEMA-P-154-L1',
      modelName: 'gemma-4-e4b-it',
      modelQuant: 'int4',
      location: const GeoLocation(
          lat: 37.7749,
          lng: -122.4194,
          accuracyMeters: 5,
          addressText: '100 Main St, San Francisco, CA'),
      building: const BuildingInfo(
          type: 'wood_light_frame',
          storiesAboveGrade: 2,
          yearBuiltEst: 1965),
      observations: const [
        Observation(
          observationId: 'obs-1',
          promptId: 'fema_p154_q01',
          askedIn: 'en',
          imageRefs: ['img-1'],
          audioRefs: [],
          modelDescription: 'Diagonal hairline crack visible in plaster.',
          modelTags: ['diagonal_crack', 'hairline'],
          modelConfidence: 0.82,
        ),
        Observation(
          observationId: 'obs-2',
          promptId: 'volunteer_note_v1',
          askedIn: 'en',
          imageRefs: [],
          audioRefs: [],
          userText: 'Volunteer noted heavy chimney damage.',
          modelTags: [],
          modelConfidence: 1.0,
        ),
      ],
      hazardsFlagged: const [
        HazardFlagRecord(code: 'falling_chimney', severity: 'high'),
      ],
      protocolAnswers: const ProtocolAnswersRecord(
        visibleCollapse: false,
        buildingOffFoundation: false,
        leaning: 'none',
        groundFailureAdjacent: false,
        fallingHazards: true,
        adjacentLeaning: false,
      ),
      triage: TriageResult(
        priorityScore: score,
        priorityBand: band,
        rationaleBullets: [
          'Diagonal cracking observed on ground floor.',
          'Chimney damage flagged as a hazard.',
          'No visible collapse or foundation offset.',
        ],
        uncertaintyNotes: ['Limited visibility of rear elevation.'],
        recommendEngineerFollowup: score >= 4,
      ),
      volunteer: const VolunteerAttestation(
        attestation: 'I am not a licensed engineer. Preliminary only.',
        signatureHash: 'sha256:deadbeef',
        locale: 'en-US',
      ),
      images: [
        ImageAsset(
          ref: 'img-1',
          filename: 'img-1.jpg',
          sha256: 'abc123',
          widthPx: 1920,
          heightPx: 1080,
          takenAtUtc: DateTime.utc(2025, 4, 15, 10, 0),
        ),
      ],
      audio: const [],
    );


// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('buildReportPdf', () {
    test('returns bytes starting with %%PDF signature', () async {
      final bytes = await buildReportPdf(_packet());
      expect(bytes.length, greaterThan(100));
      // PDF magic bytes: %PDF
      expect(bytes[0], 0x25); // %
      expect(bytes[1], 0x50); // P
      expect(bytes[2], 0x44); // D
      expect(bytes[3], 0x46); // F
    });

    test('completes without error for LOW priority', () async {
      await expectLater(buildReportPdf(_packet(score: 2, band: 'LOW')),
          completes);
    });

    test('completes without error for MEDIUM priority', () async {
      await expectLater(buildReportPdf(_packet(score: 4, band: 'MEDIUM')),
          completes);
    });

    test('completes without error for HIGH priority', () async {
      await expectLater(buildReportPdf(_packet(score: 7, band: 'HIGH')),
          completes);
    });

    test('completes without error for CRITICAL priority', () async {
      await expectLater(
          buildReportPdf(_packet(score: 9, band: 'CRITICAL')), completes);
    });

    test('accepts empty imageBytes without error', () async {
      final bytes = await buildReportPdf(_packet(), imageBytes: const {});
      expect(bytes.length, greaterThan(100));
    });

    test('does not throw when image bytes map is provided but empty', () async {
      await expectLater(
        buildReportPdf(_packet(), imageBytes: const {}),
        completes,
      );
    });

    test('accepts packet with no observations', () async {
      final p = EvidencePacket(
        packetId: 'empty-obs',
        createdAtUtc: DateTime.utc(2025),
        appVersion: '0.1.0',
        protocol: 'FEMA-P-154-L1',
        modelName: 'm',
        modelQuant: 'q',
        location:
            const GeoLocation(lat: 0, lng: 0, accuracyMeters: 1),
        building:
            const BuildingInfo(type: 'masonry', storiesAboveGrade: 1),
        observations: const [],
        hazardsFlagged: const [],
        protocolAnswers: const ProtocolAnswersRecord(),
        triage: const TriageResult(
            priorityScore: 1,
            priorityBand: 'LOW',
            rationaleBullets: ['no damage found'],
            uncertaintyNotes: [],
            recommendEngineerFollowup: false),
        volunteer: const VolunteerAttestation(
            attestation: 'a', signatureHash: 'sha256:x', locale: 'en'),
        images: const [],
        audio: const [],
      );
      await expectLater(buildReportPdf(p), completes);
    });
  });
}
