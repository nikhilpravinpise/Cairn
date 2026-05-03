/// Tests for [FileEvidenceVaultIo].
///
/// All I/O is redirected to a temporary directory so tests are hermetic and
/// don't touch the device's application support directory.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/storage/file_evidence_vault_io.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

EvidencePacket _minimalPacket(String id) => EvidencePacket(
      packetId: id,
      createdAtUtc: DateTime.utc(2025, 1, 1, 12),
      appVersion: '0.1.0',
      protocol: 'FEMA-P-154-L1',
      modelName: 'gemma-4-e4b-it',
      modelQuant: 'int4',
      location:
          const GeoLocation(lat: 37.7749, lng: -122.4194, accuracyMeters: 5),
      building:
          const BuildingInfo(type: 'wood_light_frame', storiesAboveGrade: 1),
      observations: const [],
      hazardsFlagged: const [],
      protocolAnswers: const ProtocolAnswersRecord(),
      triage: const TriageResult(
        priorityScore: 3,
        priorityBand: 'LOW',
        rationaleBullets: ['minor cracking only'],
        uncertaintyNotes: [],
        recommendEngineerFollowup: false,
      ),
      volunteer: const VolunteerAttestation(
        attestation: 'I am not a licensed engineer.',
        signatureHash: 'sha256:abc',
        locale: 'en-US',
      ),
      images: const [],
      audio: const [],
    );

FileEvidenceVaultIo _vault(Directory base) =>
    FileEvidenceVaultIo(testBaseDir: base);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tmp;
  late FileEvidenceVaultIo vault;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vault_test_');
    vault = _vault(tmp);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('savePacket / loadPacket', () {
    test('round-trips a minimal packet', () async {
      final p = _minimalPacket('id-001');
      await vault.savePacket(p);
      final loaded = await vault.loadPacket('id-001');
      expect(loaded, isNotNull);
      expect(loaded!.packetId, 'id-001');
      expect(loaded.triage.priorityScore, 3);
    });

    test('writes atomic: no .tmp file remains', () async {
      await vault.savePacket(_minimalPacket('id-002'));
      final dir =
          Directory('${tmp.path}/cairn_vault/id-002');
      final tmpFiles = dir
          .listSync()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(tmpFiles, isEmpty);
    });

    test('loadPacket returns null for missing id', () async {
      final result = await vault.loadPacket('no-such-id');
      expect(result, isNull);
    });

    test('packet.json is valid JSON with expected keys', () async {
      await vault.savePacket(_minimalPacket('id-003'));
      final f =
          File('${tmp.path}/cairn_vault/id-003/packet.json');
      expect(f.existsSync(), isTrue);
      final raw =
          jsonDecode(await f.readAsString()) as Map<String, Object?>;
      expect(raw['packet_id'], 'id-003');
      expect(raw['protocol'], 'FEMA-P-154-L1');
    });
  });

  group('listPackets', () {
    test('returns empty list when vault dir absent', () async {
      final items = await vault.listPackets();
      expect(items, isEmpty);
    });

    test('lists saved packets in descending date order', () async {
      final older = EvidencePacket(
        packetId: 'older',
        createdAtUtc: DateTime.utc(2025, 1, 1),
        appVersion: '0.1.0',
        protocol: 'FEMA-P-154-L1',
        modelName: 'gemma-4-e4b-it',
        modelQuant: 'int4',
        location:
            const GeoLocation(lat: 0, lng: 0, accuracyMeters: 1),
        building:
            const BuildingInfo(type: 'masonry', storiesAboveGrade: 2),
        observations: const [],
        hazardsFlagged: const [],
        protocolAnswers: const ProtocolAnswersRecord(),
        triage: const TriageResult(
            priorityScore: 5,
            priorityBand: 'MEDIUM',
            rationaleBullets: ['x'],
            uncertaintyNotes: [],
            recommendEngineerFollowup: false),
        volunteer: const VolunteerAttestation(
            attestation: 'a', signatureHash: 'sha256:x', locale: 'en'),
        images: const [],
        audio: const [],
      );
      final newer = EvidencePacket(
        packetId: 'newer',
        createdAtUtc: DateTime.utc(2025, 6, 1),
        appVersion: '0.1.0',
        protocol: 'FEMA-P-154-L1',
        modelName: 'gemma-4-e4b-it',
        modelQuant: 'int4',
        location:
            const GeoLocation(lat: 0, lng: 0, accuracyMeters: 1),
        building:
            const BuildingInfo(type: 'masonry', storiesAboveGrade: 2),
        observations: const [],
        hazardsFlagged: const [],
        protocolAnswers: const ProtocolAnswersRecord(),
        triage: const TriageResult(
            priorityScore: 2,
            priorityBand: 'LOW',
            rationaleBullets: ['y'],
            uncertaintyNotes: [],
            recommendEngineerFollowup: false),
        volunteer: const VolunteerAttestation(
            attestation: 'a', signatureHash: 'sha256:y', locale: 'en'),
        images: const [],
        audio: const [],
      );
      await vault.savePacket(older);
      await vault.savePacket(newer);
      final list = await vault.listPackets();
      expect(list.length, 2);
      expect(list.first.packetId, 'newer');
    });
  });

  group('deletePacket', () {
    test('removes directory and packet from listing', () async {
      await vault.savePacket(_minimalPacket('del-1'));
      await vault.deletePacket('del-1');
      expect(await vault.loadPacket('del-1'), isNull);
      final list = await vault.listPackets();
      expect(list.any((s) => s.packetId == 'del-1'), isFalse);
    });

    test('deletePacket is a no-op for missing id', () async {
      // Must not throw.
      await expectLater(vault.deletePacket('ghost'), completes);
    });
  });

  group('putAsset / getAsset', () {
    test('stores and retrieves image bytes', () async {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      await vault.putAsset('p1', 'img-1', bytes);
      final got = await vault.getAsset('p1', 'img-1');
      expect(got, equals(bytes));
    });

    test('stores and retrieves audio bytes', () async {
      final bytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]); // RIFF
      await vault.putAsset('p1', 'aud-1', bytes);
      final got = await vault.getAsset('p1', 'aud-1');
      expect(got, equals(bytes));
    });

    test('getAsset returns null for unknown ref', () async {
      final got = await vault.getAsset('p1', 'img-99');
      expect(got, isNull);
    });

    test('asset file is named <ref>.jpg for images', () async {
      await vault.putAsset('p2', 'img-1',
          Uint8List.fromList([0xFF, 0xD8]));
      final f = File('${tmp.path}/cairn_vault/p2/img-1.jpg');
      expect(f.existsSync(), isTrue);
    });

    test('asset file is named <ref>.wav for audio', () async {
      await vault.putAsset('p2', 'aud-1',
          Uint8List.fromList([0x52, 0x49]));
      final f = File('${tmp.path}/cairn_vault/p2/aud-1.wav');
      expect(f.existsSync(), isTrue);
    });
  });

  group('saveTurnsJsonl', () {
    test('writes turns.jsonl with one JSON object per line', () async {
      await vault.savePacket(_minimalPacket('turns-1'));
      await vault.saveTurnsJsonl('turns-1', [
        {
          'ts': '2025-01-01T12:00:00.000Z',
          'task': 'synthesize',
          'ttft_ms': 120,
          'wallclock_ms': 4000,
          'output_char_count': 512,
        }
      ]);
      final f = File('${tmp.path}/cairn_vault/turns-1/turns.jsonl');
      expect(f.existsSync(), isTrue);
      final lines = f.readAsLinesSync().where((l) => l.isNotEmpty).toList();
      expect(lines.length, 1);
      final decoded = jsonDecode(lines.first) as Map<String, Object?>;
      expect(decoded['task'], 'synthesize');
    });

    test('no-op when turns list is empty', () async {
      await vault.savePacket(_minimalPacket('turns-2'));
      await vault.saveTurnsJsonl('turns-2', []);
      final f = File('${tmp.path}/cairn_vault/turns-2/turns.jsonl');
      expect(f.existsSync(), isFalse);
    });
  });

  group('saveReportPdf / loadReportPdf', () {
    test('round-trips PDF bytes', () async {
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
      await vault.savePacket(_minimalPacket('pdf-1'));
      await vault.saveReportPdf('pdf-1', bytes);
      final loaded = await vault.loadReportPdf('pdf-1');
      expect(loaded, equals(bytes));
    });

    test('loadReportPdf returns null before PDF is written', () async {
      await vault.savePacket(_minimalPacket('pdf-2'));
      expect(await vault.loadReportPdf('pdf-2'), isNull);
    });
  });
}
