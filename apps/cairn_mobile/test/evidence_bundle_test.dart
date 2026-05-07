import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cairn_mobile/core/export/evidence_bundle.dart';
import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/storage/evidence_vault.dart';
import 'package:flutter_test/flutter_test.dart';

EvidencePacket _packet() => EvidencePacket(
      packetId: 'bundle-1',
      createdAtUtc: DateTime.utc(2026, 5, 7),
      appVersion: '0.1.0',
      protocol: 'FEMA-P-154-L1',
      modelName: 'gemma-4-e2b-it',
      modelQuant: 'int4',
      location: const GeoLocation(lat: 0, lng: 0, accuracyMeters: 1),
      building: const BuildingInfo(type: 'unknown', storiesAboveGrade: 1),
      observations: const [],
      hazardsFlagged: const [],
      protocolAnswers: const ProtocolAnswersRecord(),
      triage: const TriageResult(
        priorityScore: 1,
        priorityBand: 'LOW',
        rationaleBullets: ['ok'],
        uncertaintyNotes: [],
        recommendEngineerFollowup: false,
      ),
      volunteer: const VolunteerAttestation(
        attestation: 'test',
        signatureHash: 'sha256:test',
        locale: 'en-US',
      ),
      images: [
        ImageAsset(
          ref: 'img-1',
          filename: 'img-1.jpg',
          sha256:
              '0000000000000000000000000000000000000000000000000000000000000000',
          widthPx: 10,
          heightPx: 10,
          takenAtUtc: DateTime.utc(2026, 5, 7),
        ),
      ],
      audio: const [],
    );

void main() {
  test('buildEvidenceBundle includes packet, pdf, and photos', () async {
    final vault = InMemoryEvidenceVault();
    final packet = _packet();
    await vault.savePacket(packet);
    await vault.putAsset(packet.packetId, 'img-1', Uint8List.fromList([1, 2]));
    await vault.saveReportPdf(packet.packetId, Uint8List.fromList([3, 4]));

    final bundle = await buildEvidenceBundle(vault, packet);
    final archive = ZipDecoder().decodeBytes(bundle.bytes);
    final names = archive.files.map((file) => file.name).toSet();

    expect(names, containsAll(['packet.json', 'report.pdf', 'photos/img-1.jpg']));
    final packetFile =
        archive.files.firstWhere((file) => file.name == 'packet.json');
    final decoded = jsonDecode(utf8.decode(packetFile.content as List<int>))
        as Map<String, Object?>;
    expect(decoded['packet_id'], 'bundle-1');
  });
}
