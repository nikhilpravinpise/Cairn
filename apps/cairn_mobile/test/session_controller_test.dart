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

  test('addPhoto assigns sequential refs', () {
    final r1 = controller.addPhoto(
        bytes: Uint8List(4), widthPx: 10, heightPx: 10, slot: 'front');
    final r2 = controller.addPhoto(
        bytes: Uint8List(4), widthPx: 10, heightPx: 10, slot: 'cracks');
    expect(r1, 'img-1');
    expect(r2, 'img-2');
    expect(controller.state!.photos.length, 2);
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
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'front',
    );
    controller.addPhoto(
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'front',
    );
    controller.addPhoto(
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'ground_floor',
    );

    expect(controller.state!.requiredPhotoSlotCount, 2);
    expect(controller.state!.hasAllRequiredPhotoSlots, isFalse);

    controller.addPhoto(
      bytes: Uint8List(4),
      widthPx: 10,
      heightPx: 10,
      slot: 'cracks',
    );
    controller.addPhoto(
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
        bytes: Uint8List(4), widthPx: 8, heightPx: 8, slot: 'front');
    expect(identical(controller.state, after1), isFalse,
        reason: 'addPhoto must produce a new SessionDraft instance');
  });

  test('seal + save into vault', () async {
    controller.setLocation(const GeoLocation(lat: 1.0, lng: 2.0, accuracyMeters: 5));
    controller.setBuilding(const BuildingInfo(
        type: 'wood_light_frame', storiesAboveGrade: 1));
    controller.computeAndStoreTriage(
        rationaleBullets: ['x'], uncertaintyNotes: []);
    final vault = InMemoryEvidenceVault();
    final p = await controller.sealAndSave(vault);
    expect(p.packetId, controller.state!.packetId);
    expect(await vault.loadPacket(p.packetId), isNotNull);
    expect(p.volunteer.signatureHash.startsWith('sha256:'), true);
  });
}
