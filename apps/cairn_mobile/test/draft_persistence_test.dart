/// Tests for draft metadata persistence and SessionDraft serialisation round-trip.
///
/// Uses [createDraftPersistenceForTest] to redirect all I/O to a tmp dir.
/// Also exercises [SessionDraft.toMetaMap] / [SessionDraft.fromMetaMap] in
/// the round-trip tests.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/state/session_controller.dart';
import 'package:cairn_mobile/core/storage/draft_persistence.dart';
import 'package:cairn_mobile/core/storage/file_draft_persistence_io.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a minimal [SessionDraft] with all optional fields populated.
SessionDraft _fullDraft() {
  final draft = SessionDraft(
    packetId: 'draft-01',
    createdAtUtc: DateTime.utc(2025, 3, 15, 8, 30),
    modelName: 'gemma-4-e4b-it',
    modelQuant: 'int4',
  );
  draft.location =
      const GeoLocation(lat: 37.7749, lng: -122.4194, accuracyMeters: 10);
  draft.building =
      const BuildingInfo(type: 'wood_light_frame', storiesAboveGrade: 2);
  draft.observations.add(const Observation(
    observationId: 'obs-1',
    promptId: 'fema_p154_q01',
    askedIn: 'en',
    imageRefs: ['img-1'],
    audioRefs: [],
    modelDescription: 'hairline crack',
    modelTags: ['hairline_crack'],
    modelConfidence: 0.75,
  ));
  draft.turns.add(TurnRecord(
    ts: DateTime.utc(2025, 3, 15, 8, 31),
    task: 'describe_photo',
    observationId: 'obs-1',
    ttftMs: 80,
    wallclockMs: 1200,
    outputCharCount: 96,
  ));
  return draft;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---- SessionDraft serialisation ----

  group('SessionDraft.toMetaMap / fromMetaMap', () {
    test('round-trips scalar fields', () {
      final draft = _fullDraft();
      final meta = draft.toMetaMap();
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: const {}, audioBytes: const {});

      expect(restored.packetId, draft.packetId);
      expect(restored.modelName, draft.modelName);
      expect(restored.modelQuant, draft.modelQuant);
      expect(restored.createdAtUtc, draft.createdAtUtc);
      expect(restored.localeBCP47, draft.localeBCP47);
    });

    test('round-trips location', () {
      final draft = _fullDraft();
      final meta = draft.toMetaMap();
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: const {}, audioBytes: const {});
      expect(restored.location?.lat, draft.location?.lat);
      expect(restored.location?.lng, draft.location?.lng);
    });

    test('round-trips building', () {
      final draft = _fullDraft();
      final meta = draft.toMetaMap();
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: const {}, audioBytes: const {});
      expect(restored.building?.type, 'wood_light_frame');
      expect(restored.building?.storiesAboveGrade, 2);
    });

    test('round-trips observations', () {
      final draft = _fullDraft();
      final meta = draft.toMetaMap();
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: const {}, audioBytes: const {});
      expect(restored.observations.length, 1);
      expect(restored.observations.first.observationId, 'obs-1');
      expect(restored.observations.first.modelDescription, 'hairline crack');
    });

    test('round-trips turns', () {
      final draft = _fullDraft();
      final meta = draft.toMetaMap();
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: const {}, audioBytes: const {});
      expect(restored.turns.length, 1);
      expect(restored.turns.first.task, 'describe_photo');
      expect(restored.turns.first.ttftMs, 80);
      expect(restored.turns.first.observationId, 'obs-1');
    });

    test('round-trips counters', () {
      // Construct a draft where the counters are already advanced.
      final draft = SessionDraft(
        packetId: 'ctr-test',
        createdAtUtc: DateTime.utc(2025),
        modelName: 'x',
        modelQuant: 'y',
        imageCounter: 5,
        audioCounter: 3,
        obsCounter: 7,
      );
      final meta = draft.toMetaMap();
      expect(meta['image_counter'], 5);
      expect(meta['audio_counter'], 3);
      expect(meta['obs_counter'], 7);
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: const {}, audioBytes: const {});
      expect(restored.toMetaMap()['image_counter'], 5);
      expect(restored.toMetaMap()['audio_counter'], 3);
      expect(restored.toMetaMap()['obs_counter'], 7);
    });

    test('photos with matching bytes are restored', () {
      final draft = _fullDraft();
      // Add a photo manually (no bytes needed for meta).
      draft.photos.add(CapturedPhoto(
        ref: 'img-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        widthPx: 10,
        heightPx: 10,
        takenAtUtc: DateTime.utc(2025, 3, 15, 8, 30),
        slot: 'front',
      ));
      final meta = draft.toMetaMap();
      final photoBytes = {'img-1': Uint8List.fromList([1, 2, 3])};
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: photoBytes, audioBytes: const {});
      expect(restored.photos.length, 1);
      expect(restored.photos.first.slot, 'front');
    });

    test('photos with missing bytes are silently omitted', () {
      final draft = _fullDraft();
      draft.photos.add(CapturedPhoto(
        ref: 'img-2',
        bytes: Uint8List.fromList([1, 2, 3]),
        widthPx: 10,
        heightPx: 10,
        takenAtUtc: DateTime.utc(2025),
        slot: 'cracks',
      ));
      final meta = draft.toMetaMap();
      // Pass empty photoBytes → bytes missing.
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: const {}, audioBytes: const {});
      expect(restored.photos, isEmpty);
    });

    test('empty draft round-trips without error', () {
      final draft = SessionDraft(
        packetId: 'empty-001',
        createdAtUtc: DateTime.utc(2025),
        modelName: 'x',
        modelQuant: 'y',
      );
      final meta = draft.toMetaMap();
      final restored = SessionDraft.fromMetaMap(meta,
          photoBytes: const {}, audioBytes: const {});
      expect(restored.packetId, 'empty-001');
      expect(restored.observations, isEmpty);
      expect(restored.turns, isEmpty);
    });
  });

  // ---- TurnRecord serialisation ----

  group('TurnRecord JSON round-trip', () {
    test('toJson includes all set fields', () {
      final t = TurnRecord(
        ts: DateTime.utc(2025, 1, 2, 3, 4, 5),
        task: 'synthesize',
        ttftMs: 150,
        wallclockMs: 5000,
        outputCharCount: 300,
        thinkingChars: 1200,
      );
      final j = t.toJson();
      expect(j['task'], 'synthesize');
      expect(j['ttft_ms'], 150);
      expect(j['thinking_chars'], 1200);
      expect(j.containsKey('observation_id'), isFalse);
    });

    test('fromJson round-trips', () {
      final t = TurnRecord(
        ts: DateTime.utc(2025, 1, 2),
        task: 'describe_photo',
        observationId: 'obs-3',
        ttftMs: 90,
        wallclockMs: 2000,
        outputCharCount: 120,
      );
      final t2 = TurnRecord.fromJson(t.toJson());
      expect(t2.task, t.task);
      expect(t2.ttftMs, t.ttftMs);
      expect(t2.observationId, 'obs-3');
      expect(t2.thinkingChars, 0);
    });
  });

  // ---- _FileBackedDraftPersistence ----

  group('_FileBackedDraftPersistence (file-backed)', () {
    late Directory tmp;
    late DraftPersistence dp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('draft_test_');
      dp = createDraftPersistenceForTest(tmp);
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('hasActiveDraft is false initially', () async {
      expect(await dp.hasActiveDraft(), isFalse);
    });

    test('saveDraftMeta + hasActiveDraft = true', () async {
      final meta = _fullDraft().toMetaMap();
      await dp.saveDraftMeta(meta);
      expect(await dp.hasActiveDraft(), isTrue);
    });

    test('loadDraftMeta returns null before save', () async {
      expect(await dp.loadDraftMeta(), isNull);
    });

    test('round-trips draft meta through file', () async {
      final draft = _fullDraft();
      await dp.saveDraftMeta(draft.toMetaMap());
      final loaded = await dp.loadDraftMeta();
      expect(loaded, isNotNull);
      expect(loaded!['packet_id'], 'draft-01');
      expect((loaded['turns'] as List).length, 1);
    });

    test('clearDraft removes the file', () async {
      await dp.saveDraftMeta(_fullDraft().toMetaMap());
      await dp.clearDraft();
      expect(await dp.hasActiveDraft(), isFalse);
    });

    test('clearDraft is a no-op when file absent', () async {
      await expectLater(dp.clearDraft(), completes);
    });

    test('active.json is not left with a .tmp extension after save', () async {
      await dp.saveDraftMeta(_fullDraft().toMetaMap());
      final draftDir = Directory('${tmp.path}/cairn_draft');
      final tmpFiles = draftDir
          .listSync()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(tmpFiles, isEmpty);
    });
  });

  // ---- NoOpDraftPersistence ----

  group('NoOpDraftPersistence', () {
    test('all methods complete without error', () async {
      final noop = NoOpDraftPersistence();
      await noop.saveDraftMeta({'x': 1});
      expect(await noop.loadDraftMeta(), isNull);
      expect(await noop.hasActiveDraft(), isFalse);
      await noop.clearDraft();
    });
  });
}
