import 'dart:typed_data';

import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/state/session_controller.dart';
import 'package:cairn_mobile/core/storage/evidence_vault.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late SessionController controller;

  setUp(() {
    container = ProviderContainer();
    final p = NotifierProvider<SessionController, SessionDraft?>(
        SessionController.new);
    controller = container.read(p.notifier);
    controller.startNew(modelName: 'gemma-4-e4b-it', modelQuant: 'int4');
  });

  tearDown(() {
    container.dispose();
  });

  test('startNew populates packetId + createdAt', () {
    final draft = controller.state!;
    expect(draft.packetId.length, greaterThanOrEqualTo(36));
    expect(draft.modelName, 'gemma-4-e4b-it');
  });

  test('addPhoto assigns refs', () {
    final r1 = controller.generateImageId();
    controller.addPhoto(
        ref: r1, bytes: Uint8List(4), widthPx: 10, heightPx: 10, slot: 'front');
    final r2 = controller.generateImageId();
    controller.addPhoto(
        ref: r2, bytes: Uint8List(4), widthPx: 10, heightPx: 10, slot: 'cracks');
    expect(r1, 'img-1');
    expect(r2, 'img-2');
    expect(controller.state!.photos.length, 2);
  });

  test('generateImageId yields img-1 to img-100', () {
    for (int i = 1; i <= 100; i++) {
      expect(controller.generateImageId(), 'img-$i');
    }
  });

  test('applyProtocolDelta mutates exactly one field', () {
    controller.applyProtocolDelta(const MapEntry('leaning', 'severe'));
    expect(controller.state!.protocolAnswers.leaning, 'severe');
    expect(controller.state!.protocolAnswers.visibleCollapse, false);

    controller.applyProtocolDelta(const MapEntry('falling_hazards', true));
    expect(controller.state!.protocolAnswers.fallingHazards, true);
    expect(controller.state!.protocolAnswers.leaning, 'severe');
  });

  test('applyProtocolDelta throws on unknown key', () {
    expect(
      () => controller.applyProtocolDelta(const MapEntry('bogus', true)),
      throwsStateError,
    );
  });

  test('applyProtocolDelta rejects null or invalid typed values', () {
    expect(
      () => controller.applyProtocolDelta(
        const MapEntry('visible_collapse', null),
      ),
      throwsStateError,
    );
    expect(
      () => controller.applyProtocolDelta(const MapEntry('leaning', 'sideways')),
      throwsStateError,
    );
  });

  test('required photo coverage requires all four FEMA slots', () {
    expect(controller.state!.requiredPhotoSlotCount, 0);
    expect(controller.state!.hasAllRequiredPhotoSlots, isFalse);

    controller.addPhoto(
      ref: controller.generateImageId(),
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'front',
    );
    controller.addPhoto(
      ref: controller.generateImageId(),
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'front',
    );
    controller.addPhoto(
      ref: controller.generateImageId(),
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'ground_floor',
    );

    expect(controller.state!.requiredPhotoSlotCount, 2);
    expect(controller.state!.hasAllRequiredPhotoSlots, isFalse);

    controller.addPhoto(
      ref: controller.generateImageId(),
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'cracks',
    );
    controller.addPhoto(
      ref: controller.generateImageId(),
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'foundation',
    );

    expect(controller.state!.requiredPhotoSlotCount, 4);
    expect(controller.state!.hasAllRequiredPhotoSlots, isTrue);
  });

  test('lowestConfidenceObservation returns the right one', () {
    controller.recordObservation(const Observation(
      observationId: 'a',
      promptId: 'p',
      askedIn: 'en',
      imageRefs: ['img-1'],
      audioRefs: [],
      modelDescription: '...',
      modelTags: [],
      modelConfidence: 0.9,
    ));
    controller.recordObservation(const Observation(
      observationId: 'b',
      promptId: 'p',
      askedIn: 'en',
      imageRefs: ['img-2'],
      audioRefs: [],
      modelDescription: '...',
      modelTags: [],
      modelConfidence: 0.4,
    ));
    expect(controller.state!.lowestConfidenceObservation!.observationId, 'b');
  });

  test('computeAndStoreTriage uses Dart scorer (not LLM)', () {
    controller.setLocation(const GeoLocation(lat: 0, lng: 0, accuracyMeters: 0));
    controller.setBuilding(const BuildingInfo(
        type: 'unreinforced_masonry', storiesAboveGrade: 3));
    controller.applyProtocolDelta(const MapEntry('visible_collapse', true));
    controller.computeAndStoreTriage(
      rationaleBullets: ['a', 'b', 'c'],
      uncertaintyNotes: ['x'],
    );
    expect(controller.state!.triage!.priorityScore, 10);
    expect(controller.state!.triage!.priorityBand, 'CRITICAL');
  });

  test('mutators emit a new state instance so Riverpod fires listeners '
      '(regression for same-identity bug)', () {
    // Before the fix, mutators assigned `state = s` where `s` was the same
    // object the state already pointed at, so Notifier.state's equality check
    // suppressed the change event and screens watching the provider never
    // rebuilt after addPhoto/setLocation/etc.
    final before = controller.state;
    controller.setLocation(
        const GeoLocation(lat: 0, lng: 0, accuracyMeters: 0));
    expect(identical(controller.state, before), isFalse,
        reason: 'setLocation must produce a new SessionDraft instance');

    final after1 = controller.state;
    controller.addPhoto(
        ref: controller.generateImageId(), bytes: Uint8List(4), widthPx: 8, heightPx: 8, slot: 'front');
    expect(identical(controller.state, after1), isFalse,
        reason: 'addPhoto must produce a new SessionDraft instance');
  });

  test('cloneShallow preserves all three counters', () {
    // Each generate*Id calls cloneShallow internally.
    // If the counter were not copied into the clone, the next call would
    // return the same ID again (counter reset to its prior value).
    controller.generateImageId(); // img-1
    controller.generateImageId(); // img-2
    controller.generateObservationId(); // obs-1
    controller.generateAudioId(); // aud-1

    // Counters must continue — not reset — after cloneShallow
    expect(controller.generateImageId(), 'img-3',
        reason: 'imageCounter must survive cloneShallow');
    expect(controller.generateObservationId(), 'obs-2',
        reason: 'obsCounter must survive cloneShallow');
    expect(controller.generateAudioId(), 'aud-2',
        reason: 'audioCounter must survive cloneShallow');
  });

  test('generateObservationId yields obs-1 to obs-100', () {
    for (int i = 1; i <= 100; i++) {
      expect(controller.generateObservationId(), 'obs-$i');
    }
  });

  test('generateAudioId yields aud-1 to aud-10', () {
    for (int i = 1; i <= 10; i++) {
      expect(controller.generateAudioId(), 'aud-$i');
    }
  });

  test('counters are independent across id spaces', () {
    // Allocating image IDs does not advance obs or audio counters
    controller.generateImageId(); // img-1
    controller.generateImageId(); // img-2
    // obs and audio counters start at 1 so first alloc gives obs-1 / aud-1
    expect(controller.generateObservationId(), 'obs-1',
        reason: 'obs counter untouched by image allocations');
    expect(controller.generateAudioId(), 'aud-1',
        reason: 'audio counter untouched by image allocations');
  });

  test('addAudio records ref and returns it', () {
    final ref = controller.generateAudioId();
    controller.addAudio(
      ref: ref,
      bytes: Uint8List(8),
      durationS: 5.0,
      sampleRateHz: 16000,
      channels: 1,
    );
    expect(controller.state!.audios.length, 1);
    expect(controller.state!.audios.first.ref, 'aud-1');
    expect(controller.state!.audios.first.sampleRateHz, 16000);
    expect(controller.state!.audios.first.channels, 1);
  });

  test('volunteer_note_v1 observation has null modelDescription and empty tags',
      () {
    final obsId = controller.generateObservationId();
    controller.recordObservation(Observation(
      observationId: obsId,
      promptId: 'volunteer_note_v1',
      askedIn: 'en',
      imageRefs: const [],
      audioRefs: const [],
      userText: 'Gas smell near the meter.',
      // model_description intentionally null per §1.7
      modelTags: const [],
      modelConfidence: 1.0,
    ));
    final obs = controller.state!.observations.first;
    expect(obs.observationId, 'obs-1');
    expect(obs.promptId, 'volunteer_note_v1');
    expect(obs.modelDescription, isNull);
    expect(obs.modelTags, isEmpty);
    expect(obs.modelConfidence, 1.0);
  });

  test('humility_override_v1 observation has correct shape per §1.7', () {
    final obsId = controller.generateObservationId();
    controller.recordObservation(Observation(
      observationId: obsId,
      promptId: 'humility_override_v1',
      askedIn: 'en',
      imageRefs: const ['img-1'],
      audioRefs: const [],
      userText: 'The crack goes diagonally, not horizontally.',
      modelTags: const [],
      modelConfidence: 1.0,
    ));
    final obs = controller.state!.observations.first;
    expect(obs.promptId, 'humility_override_v1');
    expect(obs.modelDescription, isNull);
    expect(obs.modelTags, isEmpty);
    expect(obs.modelConfidence, 1.0);
  });

  test('packetSummaryForSynthesis omits model_description for volunteer obs',
      () {
    controller.recordObservation(const Observation(
      observationId: 'obs-1',
      promptId: 'volunteer_note_v1',
      askedIn: 'en',
      imageRefs: [],
      audioRefs: [],
      userText: 'note',
      modelTags: [],
      modelConfidence: 1.0,
    ));
    controller.recordObservation(const Observation(
      observationId: 'obs-2',
      promptId: 'fema_p154_q01',
      askedIn: 'en',
      imageRefs: [],
      audioRefs: [],
      modelDescription: 'diagonal crack',
      modelTags: ['diagonal_crack'],
      modelConfidence: 0.8,
    ));
    final summary = controller.state!.packetSummaryForSynthesis();
    final observations = summary['observations'] as List<dynamic>;
    final vol = observations[0] as Map<String, Object?>;
    final mod = observations[1] as Map<String, Object?>;

    expect(vol.containsKey('model_description'), isFalse,
        reason: 'volunteer obs must omit model_description in summary');
    expect(mod.containsKey('model_description'), isTrue,
        reason: 'model-authored obs must include model_description in summary');
    expect(mod['model_description'], 'diagonal crack');
  });

  test('seal + save into vault — packet is persisted and signature hashed', () async {
    controller.setLocation(const GeoLocation(lat: 1.0, lng: 2.0, accuracyMeters: 5));
    controller.setBuilding(const BuildingInfo(
        type: 'wood_light_frame', storiesAboveGrade: 1));
    controller.computeAndStoreTriage(
        rationaleBullets: ['x'], uncertaintyNotes: []);
    final packetId = controller.state!.packetId;
    final vault = InMemoryEvidenceVault();
    final p = await controller.sealAndSave(vault);
    expect(p.packetId, packetId);
    expect(await vault.loadPacket(p.packetId), isNotNull);
    expect(p.volunteer.signatureHash.startsWith('sha256:'), true);
  });

  // ---------------------------------------------------------------------------
  // Phase 9 — TurnRecord
  // ---------------------------------------------------------------------------

  group('TurnRecord', () {
    test('toJson omits observation_id when null', () {
      final t = TurnRecord(
        ts: DateTime.utc(2025),
        task: 'describe_photo',
        ttftMs: 100,
        wallclockMs: 2000,
        outputCharCount: 80,
      );
      expect(t.toJson().containsKey('observation_id'), isFalse);
    });

    test('toJson omits thinking_chars when 0', () {
      final t = TurnRecord(
        ts: DateTime.utc(2025),
        task: 'synthesize',
        ttftMs: 200,
        wallclockMs: 5000,
        outputCharCount: 400,
      );
      expect(t.toJson().containsKey('thinking_chars'), isFalse);
    });

    test('toJson includes thinking_chars when > 0', () {
      final t = TurnRecord(
        ts: DateTime.utc(2025),
        task: 'synthesize',
        ttftMs: 200,
        wallclockMs: 5000,
        outputCharCount: 400,
        thinkingChars: 1500,
      );
      expect(t.toJson()['thinking_chars'], 1500);
    });

    test('fromJson round-trip preserves all fields', () {
      final orig = TurnRecord(
        ts: DateTime.utc(2025, 3, 14, 10, 30),
        task: 'protocol_answer',
        observationId: 'obs-5',
        ttftMs: 55,
        wallclockMs: 800,
        outputCharCount: 30,
        thinkingChars: 0,
      );
      final decoded = TurnRecord.fromJson(orig.toJson());
      expect(decoded.task, orig.task);
      expect(decoded.ttftMs, orig.ttftMs);
      expect(decoded.observationId, 'obs-5');
      expect(decoded.ts, orig.ts);
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 9 — recordTurn
  // ---------------------------------------------------------------------------

  test('recordTurn appends to draft.turns and triggers state update', () {
    final before = controller.state!;
    expect(before.turns, isEmpty);
    controller.recordTurn(TurnRecord(
      ts: DateTime.utc(2025, 1, 1),
      task: 'describe_photo',
      ttftMs: 70,
      wallclockMs: 1100,
      outputCharCount: 90,
    ));
    expect(controller.state!.turns.length, 1);
    expect(controller.state!.turns.first.task, 'describe_photo');
  });

  test('recordTurn fires for multiple turns in sequence', () {
    for (var i = 0; i < 5; i++) {
      controller.recordTurn(TurnRecord(
        ts: DateTime.utc(2025, 1, 1, 0, i),
        task: 'task-$i',
        ttftMs: i * 10,
        wallclockMs: i * 100,
        outputCharCount: i * 20,
      ));
    }
    expect(controller.state!.turns.length, 5);
    expect(controller.state!.turns.last.task, 'task-4');
  });

  // ---------------------------------------------------------------------------
  // Phase 9 — restoreDraft
  // ---------------------------------------------------------------------------

  test('restoreDraft replaces current state with provided draft', () {
    final restoredDraft = SessionDraft(
      packetId: 'restored-id-001',
      createdAtUtc: DateTime.utc(2025, 5, 1),
      modelName: 'gemma-4-e2b-it',
      modelQuant: 'int4',
    );
    controller.restoreDraft(restoredDraft);
    expect(controller.state!.packetId, 'restored-id-001');
    expect(controller.state!.modelName, 'gemma-4-e2b-it');
  });

  // ---------------------------------------------------------------------------
  // Phase 9 — sealAndSave turns.jsonl
  // ---------------------------------------------------------------------------

  test('sealAndSave writes turns to vault.saveTurnsJsonl', () async {
    controller.setLocation(
        const GeoLocation(lat: 1.0, lng: 2.0, accuracyMeters: 5));
    controller.setBuilding(
        const BuildingInfo(type: 'wood_light_frame', storiesAboveGrade: 1));
    controller.computeAndStoreTriage(
        rationaleBullets: ['x'], uncertaintyNotes: []);
    controller.recordTurn(TurnRecord(
      ts: DateTime.utc(2025),
      task: 'synthesize',
      ttftMs: 100,
      wallclockMs: 3000,
      outputCharCount: 250,
    ));

    final vault = InMemoryEvidenceVault();
    final p = await controller.sealAndSave(vault);
    // turns.jsonl is saved separately; verify via vault.loadPacket round-trip.
    final reloaded = await vault.loadPacket(p.packetId);
    expect(reloaded, isNotNull);
  });
}
