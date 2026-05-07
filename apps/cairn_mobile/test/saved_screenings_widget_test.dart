import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/providers.dart';
import 'package:cairn_mobile/core/storage/evidence_vault.dart';
import 'package:cairn_mobile/features/dev_model_test/dev_model_test_screen.dart';
import 'package:cairn_mobile/features/saved/saved_screenings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

EvidencePacket _packet() => EvidencePacket(
      packetId: 'packet-1',
      createdAtUtc: DateTime.utc(2026, 5, 7, 8),
      appVersion: '0.1.0',
      protocol: 'FEMA-P-154-L1',
      modelName: 'gemma-4-e2b-it',
      modelQuant: 'int4',
      location: const GeoLocation(
        lat: 37,
        lng: -122,
        accuracyMeters: 4,
        addressText: '123 Test St',
      ),
      building:
          const BuildingInfo(type: 'wood_light_frame', storiesAboveGrade: 1),
      observations: const [],
      hazardsFlagged: const [],
      protocolAnswers: const ProtocolAnswersRecord(),
      triage: const TriageResult(
        priorityScore: 2,
        priorityBand: 'LOW',
        rationaleBullets: ['No visible damage'],
        uncertaintyNotes: [],
        recommendEngineerFollowup: false,
      ),
      volunteer: const VolunteerAttestation(
        attestation: 'test',
        signatureHash: 'sha256:test',
        locale: 'en-US',
      ),
      images: const [],
      audio: const [],
    );

void main() {
  testWidgets('SavedScreeningsScreen renders saved packet summaries',
      (tester) async {
    final vault = InMemoryEvidenceVault();
    await vault.savePacket(_packet());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [evidenceVaultProvider.overrideWithValue(vault)],
        child: const MaterialApp(home: SavedScreeningsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('LOW'), findsOneWidget);
    expect(find.textContaining('123 Test St'), findsOneWidget);
  });

  testWidgets('DevModelTestScreen lists starter scenarios', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DevModelTestScreen()),
      ),
    );

    expect(find.text('Developer Model Test'), findsOneWidget);
    expect(find.textContaining('Low - no visible damage'), findsOneWidget);
    expect(find.textContaining('Medium - cracks and spalling'), findsOneWidget);
    expect(find.textContaining('High/Critical'), findsOneWidget);
  });
}
