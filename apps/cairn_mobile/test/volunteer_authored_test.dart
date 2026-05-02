/// Tests for the volunteer-authored observation convention (§1.7).
///
/// Verifies:
///  - `volunteer_note_v1` and `humility_override_v1` are distinct prompt IDs
///  - `model_description` is omitted from toJson when null
///  - `model_tags` is always empty (`[]`)
///  - `model_confidence` is 1.0 (human ground-truth sentinel)
///  - `fromJson` round-trips correctly when model_description is absent
///  - `EvidencePacketValidator` accepts volunteer-authored observations
///  - Filtering by `promptId` (not `model_tags`) works correctly
library;

import 'dart:convert';

import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/models/evidence_packet_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const _kSha256 =
    '0000000000000000000000000000000000000000000000000000000000000000';
const _kPacketId = '0190c6b0-3f0a-7a7b-bc1c-8cbfb1f9aaaa';

Observation _volunteerNote({
  String obsId = 'obs-1',
  String text = 'Gas smell near the meter.',
}) =>
    Observation(
      observationId: obsId,
      promptId: 'volunteer_note_v1',
      askedIn: 'en',
      imageRefs: const ['img-1'],
      audioRefs: const [],
      userText: text,
      // §1.7: model_description intentionally omitted
      modelTags: const [],
      modelConfidence: 1.0,
    );

Observation _humilityOverride({
  String obsId = 'obs-2',
  String text = 'The crack runs diagonally, not horizontally.',
}) =>
    Observation(
      observationId: obsId,
      promptId: 'humility_override_v1',
      askedIn: 'en',
      imageRefs: const ['img-1'],
      audioRefs: const [],
      userText: text,
      // §1.7: model_description intentionally omitted
      modelTags: const [],
      modelConfidence: 1.0,
    );

Observation _modelAuthored({String obsId = 'obs-3'}) => const Observation(
      observationId: 'obs-3',
      promptId: 'fema_p154_q01',
      askedIn: 'en',
      imageRefs: ['img-1'],
      audioRefs: [],
      modelDescription: 'Diagonal cracks visible on the south façade.',
      modelTags: ['diagonal_crack'],
      modelConfidence: 0.72,
    );

EvidencePacket _wrapObservations(List<Observation> obs) => EvidencePacket(
      packetId: _kPacketId,
      createdAtUtc: DateTime.utc(2026, 5, 2),
      appVersion: '0.1.0',
      protocol: 'FEMA-P-154-L1',
      modelName: 'gemma-4-e2b-it',
      modelQuant: 'int4',
      location: const GeoLocation(lat: 34.0, lng: -118.0, accuracyMeters: 5),
      building: const BuildingInfo(type: 'wood_light_frame', storiesAboveGrade: 2),
      observations: obs,
      hazardsFlagged: const [],
      protocolAnswers: const ProtocolAnswersRecord(),
      triage: const TriageResult(
        priorityScore: 2,
        priorityBand: 'LOW',
        rationaleBullets: ['no major damage'],
        uncertaintyNotes: [],
        recommendEngineerFollowup: false,
      ),
      volunteer: const VolunteerAttestation(
        attestation: 'I am not a licensed engineer.',
        signatureHash: 'sha256:$_kSha256',
        locale: 'en-US',
      ),
      images: [
        ImageAsset(
          ref: 'img-1',
          filename: 'img-1.jpg',
          sha256: _kSha256,
          widthPx: 1024,
          heightPx: 768,
          takenAtUtc: DateTime.utc(2026, 5, 2),
        ),
      ],
      audio: const [],
    );

void main() {
  group('volunteer_note_v1 convention (§1.7)', () {
    test('promptId is volunteer_note_v1', () {
      expect(_volunteerNote().promptId, 'volunteer_note_v1');
    });

    test('modelDescription is null', () {
      expect(_volunteerNote().modelDescription, isNull);
    });

    test('modelTags is empty', () {
      expect(_volunteerNote().modelTags, isEmpty);
    });

    test('modelConfidence is 1.0 (human ground-truth sentinel)', () {
      expect(_volunteerNote().modelConfidence, 1.0);
    });

    test('userText holds the volunteer text', () {
      const text = 'I smell gas near the meter.';
      expect(_volunteerNote(text: text).userText, text);
    });

    test('toJson omits model_description key when null', () {
      final j = _volunteerNote().toJson();
      expect(j.containsKey('model_description'), isFalse);
    });

    test('toJson includes user_text', () {
      final j = _volunteerNote(text: 'gas smell').toJson();
      expect(j['user_text'], 'gas smell');
    });

    test('toJson emits empty model_tags array', () {
      final j = _volunteerNote().toJson();
      expect(j['model_tags'], equals(<String>[]));
    });

    test('fromJson round-trips when model_description is absent', () {
      final original = _volunteerNote();
      final json = original.toJson();
      // Simulate a packet.json that was saved without model_description
      expect(json.containsKey('model_description'), isFalse,
          reason: 'precondition: key should be absent');
      final decoded = Observation.fromJson(json);
      expect(decoded.observationId, original.observationId);
      expect(decoded.promptId, 'volunteer_note_v1');
      expect(decoded.modelDescription, isNull);
      expect(decoded.modelTags, isEmpty);
      expect(decoded.modelConfidence, 1.0);
    });
  });

  group('humility_override_v1 convention (§1.7)', () {
    test('promptId is humility_override_v1', () {
      expect(_humilityOverride().promptId, 'humility_override_v1');
    });

    test('modelDescription is null', () {
      expect(_humilityOverride().modelDescription, isNull);
    });

    test('modelTags is empty', () {
      expect(_humilityOverride().modelTags, isEmpty);
    });

    test('modelConfidence is 1.0', () {
      expect(_humilityOverride().modelConfidence, 1.0);
    });

    test('toJson omits model_description key', () {
      final j = _humilityOverride().toJson();
      expect(j.containsKey('model_description'), isFalse);
    });

    test('is distinct from volunteer_note_v1 promptId', () {
      expect(_humilityOverride().promptId,
          isNot(equals('volunteer_note_v1')));
    });

    test('fromJson round-trips correctly', () {
      final decoded = Observation.fromJson(_humilityOverride().toJson());
      expect(decoded.promptId, 'humility_override_v1');
      expect(decoded.modelDescription, isNull);
      expect(decoded.userText, isNotNull);
    });
  });

  group('model-authored vs volunteer-authored distinction', () {
    test('model-authored has non-null modelDescription', () {
      expect(_modelAuthored().modelDescription, isNotNull);
      expect(_modelAuthored().modelDescription, isNotEmpty);
    });

    test('model-authored has non-empty modelTags', () {
      expect(_modelAuthored().modelTags, isNotEmpty);
    });

    test('filter by promptId correctly separates categories', () {
      final allObs = [
        _volunteerNote(obsId: 'obs-1'),
        _humilityOverride(obsId: 'obs-2'),
        _modelAuthored(obsId: 'obs-3'),
      ];
      final modelObs = allObs
          .where((o) =>
              o.promptId != 'volunteer_note_v1' &&
              o.promptId != 'humility_override_v1')
          .toList();
      final volunteerObs = allObs
          .where((o) =>
              o.promptId == 'volunteer_note_v1' ||
              o.promptId == 'humility_override_v1')
          .toList();

      expect(modelObs.length, 1);
      expect(modelObs.first.observationId, 'obs-3');
      expect(volunteerObs.length, 2);
    });

    test('old tag-based filter would fail (regression guard)', () {
      // Proves that model_tags can no longer be used to identify
      // volunteer-authored observations — both categories may have [] tags.
      final volunteerNote = _volunteerNote();
      final humilityObs = _humilityOverride();
      expect(volunteerNote.modelTags, isEmpty);
      expect(humilityObs.modelTags, isEmpty);
      // A model-authored obs with no damage tags also has empty tags:
      const modelNoTags = Observation(
        observationId: 'obs-4',
        promptId: 'fema_p154_q01',
        askedIn: 'en',
        imageRefs: [],
        audioRefs: [],
        modelDescription: 'No visible damage.',
        modelTags: [],
        modelConfidence: 0.9,
      );
      expect(modelNoTags.modelTags, isEmpty);
      // Without promptId filtering you cannot distinguish them via tags alone.
      // This test documents that promptId is the only reliable discriminator.
    });
  });

  group('JSON round-trip across full EvidencePacket', () {
    test('packet with mixed obs survives toJson / fromJson', () {
      final obs = [
        _volunteerNote(obsId: 'obs-1'),
        _humilityOverride(obsId: 'obs-2'),
        _modelAuthored(obsId: 'obs-3'),
      ];
      final packet = _wrapObservations(obs);
      final json = jsonEncode(packet.toJson());
      final decoded = EvidencePacket.fromJson(
          jsonDecode(json) as Map<String, Object?>);

      expect(decoded.observations.length, 3);

      final vol = decoded.observations[0];
      expect(vol.promptId, 'volunteer_note_v1');
      expect(vol.modelDescription, isNull);
      expect(vol.modelTags, isEmpty);

      final hum = decoded.observations[1];
      expect(hum.promptId, 'humility_override_v1');
      expect(hum.modelDescription, isNull);

      final mod = decoded.observations[2];
      expect(mod.promptId, 'fema_p154_q01');
      expect(mod.modelDescription, isNotNull);
      expect(mod.modelTags, contains('diagonal_crack'));
    });

    test('JSON string does not contain model_description for volunteer obs', () {
      final obs = [
        _volunteerNote(obsId: 'obs-1'),
        _modelAuthored(obsId: 'obs-2'),
      ];
      final packet = _wrapObservations(obs);
      final jsonMap = packet.toJson();
      final observations =
          jsonMap['observations'] as List<dynamic>;

      // obs[0] is volunteer — key should be absent
      final vol = observations[0] as Map<String, Object?>;
      expect(vol.containsKey('model_description'), isFalse);

      // obs[1] is model-authored — key should be present
      final mod = observations[1] as Map<String, Object?>;
      expect(mod.containsKey('model_description'), isTrue);
    });
  });

  group('EvidencePacketValidator accepts volunteer-authored observations', () {
    test('packet with volunteer_note_v1 passes validation', () {
      final p = _wrapObservations([_volunteerNote()]);
      final errors = EvidencePacketValidator.validate(p);
      expect(errors, isEmpty, reason: errors.toString());
    });

    test('packet with humility_override_v1 passes validation', () {
      final p = _wrapObservations([_humilityOverride()]);
      final errors = EvidencePacketValidator.validate(p);
      expect(errors, isEmpty, reason: errors.toString());
    });

    test('packet with mixed obs (volunteer + model-authored) passes validation',
        () {
      final p = _wrapObservations([
        _volunteerNote(obsId: 'obs-1'),
        _humilityOverride(obsId: 'obs-2'),
        _modelAuthored(obsId: 'obs-3'),
      ]);
      final errors = EvidencePacketValidator.validate(p);
      expect(errors, isEmpty, reason: errors.toString());
    });
  });
}
