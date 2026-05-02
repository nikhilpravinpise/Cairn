import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/models/evidence_packet_validator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test fixture helpers
// ---------------------------------------------------------------------------

const _kValidPacketId = '0190c6b0-3f0a-7a7b-bc1c-8cbfb1f9aaaa';
const _kValidSha256 = '0000000000000000000000000000000000000000000000000000000000000000';

ImageAsset _img({String ref = 'img-1'}) => ImageAsset(
      ref: ref,
      filename: '$ref.jpg',
      sha256: _kValidSha256,
      widthPx: 1024,
      heightPx: 768,
      takenAtUtc: DateTime.utc(2026, 5, 2),
    );

AudioAsset _aud({
  String ref = 'aud-1',
  double durationS = 5.0,
  int sampleRateHz = 16000,
  int channels = 1,
}) =>
    AudioAsset(
      ref: ref,
      filename: '$ref.wav',
      sha256: _kValidSha256,
      durationS: durationS,
      sampleRateHz: sampleRateHz,
      channels: channels,
    );

Observation _obs({
  String id = 'obs-1',
  String promptId = 'fema_p154_q01',
  String askedIn = 'en',
  List<String> imageRefs = const ['img-1'],
  List<String> audioRefs = const [],
  List<String> modelTags = const [],
  double confidence = 0.7,
  List<BBox> bboxAnnotations = const [],
  String? modelDescription = 'some description',
}) =>
    Observation(
      observationId: id,
      promptId: promptId,
      askedIn: askedIn,
      imageRefs: imageRefs,
      audioRefs: audioRefs,
      modelDescription: modelDescription,
      modelTags: modelTags,
      modelConfidence: confidence,
      bboxAnnotations: bboxAnnotations,
    );

EvidencePacket _validPacket({
  String packetId = _kValidPacketId,
  String appVersion = '0.1.0',
  String protocol = 'FEMA-P-154-L1',
  String modelQuant = 'int4',
  String buildingType = 'wood_light_frame',
  int stories = 2,
  double lat = 34.05,
  double lng = -118.24,
  String priorityBand = 'HIGH',
  int priorityScore = 7,
  List<String> rationaleBullets = const ['a', 'b'],
  String leaning = 'none',
  List<Observation> observations = const [],
  List<ImageAsset> images = const [],
  List<AudioAsset> audio = const [],
  List<HazardFlagRecord> hazards = const [],
  String locale = 'en-US',
  String signatureHash = 'sha256:$_kValidSha256',
}) =>
    EvidencePacket(
      packetId: packetId,
      createdAtUtc: DateTime.utc(2026, 5, 2),
      appVersion: appVersion,
      protocol: protocol,
      modelName: 'gemma-4-e2b-it',
      modelQuant: modelQuant,
      location: GeoLocation(lat: lat, lng: lng, accuracyMeters: 5),
      building: BuildingInfo(type: buildingType, storiesAboveGrade: stories),
      observations: observations,
      hazardsFlagged: hazards,
      protocolAnswers: ProtocolAnswersRecord(leaning: leaning),
      triage: TriageResult(
        priorityScore: priorityScore,
        priorityBand: priorityBand,
        rationaleBullets: rationaleBullets,
        uncertaintyNotes: const [],
        recommendEngineerFollowup: false,
      ),
      volunteer: VolunteerAttestation(
        attestation: 'I am not a licensed engineer.',
        signatureHash: signatureHash,
        locale: locale,
      ),
      images: images,
      audio: audio,
    );

List<String> _paths(List<ValidationError> errors) =>
    errors.map((e) => e.path).toList();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EvidencePacketValidator — valid packet', () {
    test('fully valid packet produces zero errors', () {
      final p = _validPacket(
        observations: [_obs()],
        images: [_img()],
      );
      expect(EvidencePacketValidator.validate(p), isEmpty);
    });

    test('validateOrThrow does not throw on valid packet', () {
      final p = _validPacket(
        observations: [_obs()],
        images: [_img()],
      );
      expect(() => EvidencePacketValidator.validateOrThrow(p), returnsNormally);
    });

    test('packet with audio passes when audio is compliant', () {
      final p = _validPacket(
        observations: [_obs(imageRefs: [], audioRefs: ['aud-1'])],
        audio: [_aud()],
      );
      expect(EvidencePacketValidator.validate(p), isEmpty);
    });

    test('volunteer-authored observation (null modelDescription) passes', () {
      final p = _validPacket(
        observations: [
          _obs(
            id: 'obs-1',
            promptId: 'volunteer_note_v1',
            modelDescription: null,
            modelTags: [],
            confidence: 1.0,
          ),
        ],
        images: [_img()],
      );
      expect(EvidencePacketValidator.validate(p), isEmpty);
    });
  });

  group('EvidencePacketValidator — top-level', () {
    test('rejects invalid packet_id (not UUIDv7)', () {
      final p = _validPacket(packetId: 'not-a-uuid');
      final errors = EvidencePacketValidator.validate(p);
      expect(_paths(errors), contains('packet_id'));
    });

    test('rejects UUIDv4 (version digit is 4, not 7)', () {
      const v4 = '550e8400-e29b-41d4-a716-446655440000';
      final p = _validPacket(packetId: v4);
      final errors = EvidencePacketValidator.validate(p);
      expect(_paths(errors), contains('packet_id'));
    });

    test('rejects invalid app_version', () {
      final p = _validPacket(appVersion: 'v1.2');
      final errors = EvidencePacketValidator.validate(p);
      expect(_paths(errors), contains('app_version'));
    });

    test('accepts semver with pre-release label', () {
      final p = _validPacket(
        appVersion: '1.2.3-alpha.1',
        observations: [_obs()],
        images: [_img()],
      );
      expect(EvidencePacketValidator.validate(p), isEmpty);
    });

    test('rejects wrong protocol string', () {
      final p = _validPacket(protocol: 'NOT-FEMA');
      final errors = EvidencePacketValidator.validate(p);
      expect(_paths(errors), contains('protocol'));
    });
  });

  group('EvidencePacketValidator — model', () {
    test('rejects unknown quant', () {
      final p = _validPacket(modelQuant: 'int2');
      final errors = EvidencePacketValidator.validate(p);
      expect(_paths(errors), contains('model.quant'));
    });

    test('accepts all allowed quants', () {
      for (final q in EvidencePacketValidator.kAllowedQuants) {
        final p = _validPacket(
          modelQuant: q,
          observations: [_obs()],
          images: [_img()],
        );
        expect(
          EvidencePacketValidator.validate(p).where((e) => e.path == 'model.quant'),
          isEmpty,
          reason: 'quant $q should be accepted',
        );
      }
    });
  });

  group('EvidencePacketValidator — location', () {
    test('rejects lat > 90', () {
      final p = _validPacket(lat: 91.0);
      expect(_paths(EvidencePacketValidator.validate(p)), contains('location.lat'));
    });

    test('rejects lat < -90', () {
      final p = _validPacket(lat: -91.0);
      expect(_paths(EvidencePacketValidator.validate(p)), contains('location.lat'));
    });

    test('rejects lng > 180', () {
      final p = _validPacket(lng: 181.0);
      expect(_paths(EvidencePacketValidator.validate(p)), contains('location.lng'));
    });

    test('rejects lng < -180', () {
      final p = _validPacket(lng: -181.0);
      expect(_paths(EvidencePacketValidator.validate(p)), contains('location.lng'));
    });
  });

  group('EvidencePacketValidator — building', () {
    test('rejects unknown building type', () {
      final p = _validPacket(buildingType: 'mud_hut');
      expect(
          _paths(EvidencePacketValidator.validate(p)), contains('building.type'));
    });

    test('accepts all known building types', () {
      for (final t in EvidencePacketValidator.kAllowedBuildingTypes) {
        final p = _validPacket(
          buildingType: t,
          observations: [_obs()],
          images: [_img()],
        );
        expect(
          EvidencePacketValidator.validate(p).where((e) => e.path == 'building.type'),
          isEmpty,
          reason: 'type $t should be accepted',
        );
      }
    });

    test('rejects stories_above_grade > 200', () {
      final p = _validPacket(stories: 201);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('building.stories_above_grade'));
    });
  });

  group('EvidencePacketValidator — observations', () {
    test('rejects observation_id not matching ^obs-[0-9]+\$', () {
      final p = _validPacket(
        observations: [_obs(id: 'obs-abc')],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].observation_id'),
      );
    });

    test('rejects UUID-style observation_id', () {
      final p = _validPacket(
        observations: [_obs(id: 'obs-550e8400-e29b-41d4-a716-446655440000')],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].observation_id'),
      );
    });

    test('accepts obs-1, obs-99, obs-1000', () {
      for (final id in ['obs-1', 'obs-99', 'obs-1000']) {
        final p = _validPacket(
          observations: [_obs(id: id)],
          images: [_img()],
        );
        expect(
          EvidencePacketValidator.validate(p)
              .where((e) => e.path.contains('observation_id')),
          isEmpty,
          reason: '$id should be accepted',
        );
      }
    });

    test('rejects model_tag not in schema enum', () {
      final p = _validPacket(
        observations: [
          _obs(modelTags: ['user_note'])
        ],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].model_tags[0]'),
      );
    });

    test('rejects user_override model_tag', () {
      final p = _validPacket(
        observations: [
          _obs(modelTags: ['user_override'])
        ],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].model_tags[0]'),
      );
    });

    test('accepts all 19 valid model_tags', () {
      for (final tag in EvidencePacketValidator.kAllowedModelTags) {
        final p = _validPacket(
          observations: [
            _obs(modelTags: [tag])
          ],
          images: [_img()],
        );
        expect(
          EvidencePacketValidator.validate(p)
              .where((e) => e.path.contains('model_tags')),
          isEmpty,
          reason: 'tag $tag should be accepted',
        );
      }
    });

    test('rejects more than 16 observations', () {
      final p = _validPacket(
        observations: List.generate(
          17,
          (i) => _obs(id: 'obs-${i + 1}'),
        ),
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations'),
      );
    });

    test('rejects image_ref in obs not found in assets.images', () {
      final p = _validPacket(
        observations: [_obs(imageRefs: ['img-99'])],
        images: [],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].image_refs[0]'),
      );
    });

    test('rejects audio_ref in obs not found in assets.audio', () {
      final p = _validPacket(
        observations: [_obs(imageRefs: [], audioRefs: ['aud-99'])],
        audio: [],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].audio_refs[0]'),
      );
    });

    test('rejects invalid asked_in language', () {
      final p = _validPacket(
        observations: [_obs(askedIn: 'fr')],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].asked_in'),
      );
    });
  });

  group('EvidencePacketValidator — bbox', () {
    BBox makeBbox({
      String imageRef = 'img-1',
      List<int> box2d = const [0, 0, 500, 500],
      String label = 'crack',
    }) =>
        BBox(imageRef: imageRef, box2d: box2d, label: label);

    test('valid bbox passes', () {
      final p = _validPacket(
        observations: [_obs(bboxAnnotations: [makeBbox()])],
        images: [_img()],
      );
      expect(EvidencePacketValidator.validate(p), isEmpty);
    });

    test('rejects bbox with wrong coordinate count', () {
      final p = _validPacket(
        observations: [
          _obs(bboxAnnotations: [makeBbox(box2d: [0, 0, 500])])
        ],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].bbox_annotations[0].box_2d'),
      );
    });

    test('rejects bbox coord > 1000', () {
      final p = _validPacket(
        observations: [
          _obs(bboxAnnotations: [makeBbox(box2d: [0, 0, 1001, 500])])
        ],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].bbox_annotations[0].box_2d[2]'),
      );
    });

    test('rejects bbox coord < 0', () {
      final p = _validPacket(
        observations: [
          _obs(bboxAnnotations: [makeBbox(box2d: [-1, 0, 500, 500])])
        ],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].bbox_annotations[0].box_2d[0]'),
      );
    });

    test('rejects bbox with empty label', () {
      final p = _validPacket(
        observations: [
          _obs(bboxAnnotations: [makeBbox(label: '')])
        ],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].bbox_annotations[0].label'),
      );
    });

    test('rejects bbox imageRef not in assets.images', () {
      final p = _validPacket(
        observations: [
          _obs(
            imageRefs: ['img-1'],
            bboxAnnotations: [makeBbox(imageRef: 'img-99')],
          )
        ],
        images: [_img()],
      );
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('observations[0].bbox_annotations[0].image_ref'),
      );
    });

    test('boundary coords 0 and 1000 are valid', () {
      final p = _validPacket(
        observations: [
          _obs(bboxAnnotations: [makeBbox(box2d: [0, 0, 1000, 1000])])
        ],
        images: [_img()],
      );
      expect(
        EvidencePacketValidator.validate(p)
            .where((e) => e.path.contains('box_2d')),
        isEmpty,
      );
    });
  });

  group('EvidencePacketValidator — audio assets', () {
    test('rejects aud ref not matching ^aud-[0-9]+\$', () {
      final p = _validPacket(audio: [_aud(ref: 'audio-1')]);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('assets.audio[0].ref'));
    });

    test('rejects duration_s > 30', () {
      final p = _validPacket(audio: [_aud(durationS: 30.1)]);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('assets.audio[0].duration_s'));
    });

    test('rejects duration_s < 0', () {
      final p = _validPacket(audio: [_aud(durationS: -0.1)]);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('assets.audio[0].duration_s'));
    });

    test('accepts duration_s exactly 0 and 30', () {
      for (final d in [0.0, 30.0]) {
        final p = _validPacket(audio: [_aud(durationS: d)]);
        expect(
          EvidencePacketValidator.validate(p)
              .where((e) => e.path.contains('duration_s')),
          isEmpty,
          reason: 'duration $d should be accepted',
        );
      }
    });

    test('rejects sample_rate_hz != 16000', () {
      final p = _validPacket(audio: [_aud(sampleRateHz: 44100)]);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('assets.audio[0].sample_rate_hz'));
    });

    test('rejects channels != 1', () {
      final p = _validPacket(audio: [_aud(channels: 2)]);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('assets.audio[0].channels'));
    });

    test('rejects malformed sha256', () {
      final p = _validPacket(
        audio: [
          const AudioAsset(
            ref: 'aud-1',
            filename: 'aud-1.wav',
            sha256: 'short',
            durationS: 5.0,
            sampleRateHz: 16000,
            channels: 1,
          ),
        ],
      );
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('assets.audio[0].sha256'));
    });
  });

  group('EvidencePacketValidator — image assets', () {
    test('rejects img ref not matching ^img-[0-9]+\$', () {
      final p = _validPacket(
        observations: [_obs(imageRefs: ['image-1'])],
        images: [
          ImageAsset(
            ref: 'image-1',
            filename: 'image-1.jpg',
            sha256: _kValidSha256,
            widthPx: 100,
            heightPx: 100,
            takenAtUtc: DateTime.utc(2026, 5, 2),
          ),
        ],
      );
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          anyOf(
            contains('assets.images[0].ref'),
            contains('observations[0].image_refs[0]'),
          ));
    });

    test('rejects width_px < 1', () {
      final p = _validPacket(
        images: [
          ImageAsset(
            ref: 'img-1',
            filename: 'img-1.jpg',
            sha256: _kValidSha256,
            widthPx: 0,
            heightPx: 100,
            takenAtUtc: DateTime.utc(2026, 5, 2),
          ),
        ],
      );
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('assets.images[0].width_px'));
    });
  });

  group('EvidencePacketValidator — triage', () {
    test('rejects empty rationale_bullets', () {
      final p = _validPacket(rationaleBullets: []);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('triage.rationale_bullets'));
    });

    test('rejects rationale_bullets > 5', () {
      final p =
          _validPacket(rationaleBullets: ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('triage.rationale_bullets'));
    });

    test('rejects empty string in rationale_bullets', () {
      final p = _validPacket(rationaleBullets: ['good', '']);
      expect(
        _paths(EvidencePacketValidator.validate(p)),
        contains('triage.rationale_bullets[1]'),
      );
    });

    test('rejects priority_score < 1', () {
      final p = _validPacket(priorityScore: 0);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('triage.priority_score'));
    });

    test('rejects priority_score > 10', () {
      final p = _validPacket(priorityScore: 11);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('triage.priority_score'));
    });

    test('accepts priority_score 1..10', () {
      for (var s = 1; s <= 10; s++) {
        final p = _validPacket(priorityScore: s);
        expect(
          EvidencePacketValidator.validate(p)
              .where((e) => e.path == 'triage.priority_score'),
          isEmpty,
          reason: 'score $s should be accepted',
        );
      }
    });

    test('rejects unknown priority_band', () {
      final p = _validPacket(priorityBand: 'EXTREME');
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('triage.priority_band'));
    });

    test('accepts all four priority bands', () {
      for (final band in EvidencePacketValidator.kAllowedPriorityBands) {
        final p = _validPacket(priorityBand: band);
        expect(
          EvidencePacketValidator.validate(p)
              .where((e) => e.path == 'triage.priority_band'),
          isEmpty,
          reason: 'band $band should be accepted',
        );
      }
    });
  });

  group('EvidencePacketValidator — protocol_answers', () {
    test('rejects invalid leaning value', () {
      final p = _validPacket(leaning: 'sideways');
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('protocol_answers.leaning'));
    });

    test('accepts all four leaning values', () {
      for (final v in EvidencePacketValidator.kAllowedLeaningValues) {
        final p = _validPacket(leaning: v);
        expect(
          EvidencePacketValidator.validate(p)
              .where((e) => e.path == 'protocol_answers.leaning'),
          isEmpty,
          reason: 'leaning $v should be accepted',
        );
      }
    });
  });

  group('EvidencePacketValidator — volunteer', () {
    test('rejects invalid locale format', () {
      final p = _validPacket(locale: 'English');
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('volunteer.locale'));
    });

    test('accepts en, es, tr base locales', () {
      for (final loc in ['en', 'es', 'tr']) {
        final p = _validPacket(locale: loc);
        expect(
          EvidencePacketValidator.validate(p)
              .where((e) => e.path == 'volunteer.locale'),
          isEmpty,
          reason: 'locale $loc should be accepted',
        );
      }
    });

    test('accepts en-US, es-MX, tr-TR', () {
      for (final loc in ['en-US', 'es-MX', 'tr-TR']) {
        final p = _validPacket(locale: loc);
        expect(
          EvidencePacketValidator.validate(p)
              .where((e) => e.path == 'volunteer.locale'),
          isEmpty,
          reason: 'locale $loc should be accepted',
        );
      }
    });

    test('rejects malformed signature_hash', () {
      final p = _validPacket(signatureHash: 'sha256:tooshort');
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('volunteer.signature_hash'));
    });

    test('rejects signature_hash without sha256 prefix', () {
      final p = _validPacket(signatureHash: _kValidSha256);
      expect(
          _paths(EvidencePacketValidator.validate(p)),
          contains('volunteer.signature_hash'));
    });
  });

  group('EvidencePacketValidator — validateOrThrow', () {
    test('throws SchemaValidationException on invalid packet', () {
      final p = _validPacket(leaning: 'sideways', rationaleBullets: []);
      expect(
        () => EvidencePacketValidator.validateOrThrow(p),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('SchemaValidationException.toString lists all errors', () {
      final p = _validPacket(
        leaning: 'sideways',
        rationaleBullets: [],
        priorityBand: 'EXTREME',
      );
      try {
        EvidencePacketValidator.validateOrThrow(p);
        fail('expected throw');
      } on SchemaValidationException catch (e) {
        expect(e.errors.length, greaterThanOrEqualTo(3));
        expect(e.toString(), contains('SchemaValidationException'));
      }
    });
  });
}
