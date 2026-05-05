/// Tests for [GemmaOrchestrator.describeAll] — the Sprint 3 batch stream.
///
/// Coverage:
///   - Events are emitted in order: Started → Succeeded (or Failed).
///   - [DescribePhotoStarted] carries the correct index / total.
///   - [DescribePhotoSucceeded] contains a ready [TurnRecord] with the right
///     task, observationId, ttftMs, wallclockMs, and outputCharCount.
///   - [DescribePhotoFailed] carries the original request and the error.
///   - Errors are isolated: one failure does NOT stop the batch.
///   - Empty list produces no events.
///   - A custom [ImagePreprocessor] is called once per photo.
///   - The default [PassthroughImagePreprocessor] is used when none is given
///     (existing [describePhoto] call-sites remain unaffected).
///
/// All tests are pure-Dart (no Flutter widgets, no native channels).
library;

import 'dart:typed_data';

import 'package:cairn_mobile/core/images/image_preprocessor.dart';
import 'package:cairn_mobile/core/llm/gemma_session.dart';
import 'package:cairn_mobile/core/llm/orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Returns a fixed JSON string regardless of the image bytes sent.
class _FakeSession implements GemmaSessionInterface {
  _FakeSession(this._response, {this.ttftMs = 10, this.wallclockMs = 20});

  final String _response;
  final int ttftMs;
  final int wallclockMs;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    return GemmaInferenceResult(
      text: _response,
      thinking: '',
      ttftMs: ttftMs,
      wallclockMs: wallclockMs,
      outputCharCount: _response.length,
    );
  }
}

/// Always throws [GemmaContractError] — simulates a model parse failure.
class _FailingSession implements GemmaSessionInterface {
  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    throw GemmaContractError(
      'simulated failure',
      rawText: '{}',
      task: 'describe_photo',
    );
  }
}

/// Counts how many times [prepareForInference] is called and notes each
/// input's identity (for verifying preprocessor is called per-photo).
class _CountingPreprocessor implements ImagePreprocessor {
  int callCount = 0;
  final List<Uint8List> received = [];

  @override
  Future<Uint8List> prepareForInference(Uint8List rawBytes) async {
    callCount++;
    received.add(rawBytes);
    return rawBytes;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _validPhoto({
  String obsId = 'obs-1',
  String desc = '"Diagonal crack visible."',
  String tags = '["diagonal_crack"]',
}) =>
    '{"observation_id": "$obsId", "prompt_id": "fema_p154_q01", '
    '"asked_in": "en", "image_refs": ["img-1"], '
    '"model_description": $desc, '
    '"model_tags": $tags, "model_confidence": 0.7, '
    '"bbox_annotations": []}';

GemmaOrchestrator _orch(
  GemmaSessionInterface session, {
  ImagePreprocessor? preprocessor,
}) =>
    preprocessor == null
        ? GemmaOrchestrator(session)
        : GemmaOrchestrator(session, preprocessor: preprocessor);

DescribePhotoRequest _req({
  String obsId = 'obs-1',
  String imageRef = 'img-1',
  Uint8List? bytes,
}) =>
    DescribePhotoRequest(
      observationId: obsId,
      promptId: 'fema_p154_q01',
      askedIn: 'en',
      imageBytes: bytes ?? Uint8List(0),
      imageRef: imageRef,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Empty list
  // -------------------------------------------------------------------------

  group('empty list', () {
    test('produces no events', () async {
      final orch = _orch(_FakeSession(_validPhoto()));
      final events = await orch.describeAll([]).toList();
      expect(events, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Single photo — happy path
  // -------------------------------------------------------------------------

  group('single photo success', () {
    late List<DescribePhotoEvent> events;

    setUp(() async {
      final orch = _orch(_FakeSession(_validPhoto(obsId: 'obs-1')));
      events = await orch.describeAll([_req(obsId: 'obs-1')]).toList();
    });

    test('emits exactly two events: Started then Succeeded', () {
      expect(events.length, 2);
      expect(events[0], isA<DescribePhotoStarted>());
      expect(events[1], isA<DescribePhotoSucceeded>());
    });

    test('DescribePhotoStarted has index=0, total=1', () {
      final e = events[0] as DescribePhotoStarted;
      expect(e.index, 0);
      expect(e.total, 1);
    });

    test('DescribePhotoStarted echoes the original request', () {
      final e = events[0] as DescribePhotoStarted;
      expect(e.request.observationId, 'obs-1');
      expect(e.request.imageRef, 'img-1');
    });

    test('DescribePhotoSucceeded result has the parsed model output', () {
      final e = events[1] as DescribePhotoSucceeded;
      expect(e.result.modelTags, ['diagonal_crack']);
    });
  });

  // -------------------------------------------------------------------------
  // TurnRecord construction in DescribePhotoSucceeded
  // -------------------------------------------------------------------------

  group('TurnRecord construction', () {
    test('task is describe_photo', () async {
      final orch = _orch(_FakeSession(_validPhoto()));
      final events = await orch.describeAll([_req()]).toList();
      final succeeded = events.whereType<DescribePhotoSucceeded>().first;
      expect(succeeded.turn.task, 'describe_photo');
    });

    test('observationId comes from the request', () async {
      final orch = _orch(_FakeSession(_validPhoto(obsId: 'obs-42')));
      final events =
          await orch.describeAll([_req(obsId: 'obs-42')]).toList();
      final succeeded = events.whereType<DescribePhotoSucceeded>().first;
      expect(succeeded.turn.observationId, 'obs-42');
    });

    test('ttftMs and wallclockMs come from session result', () async {
      final orch =
          _orch(_FakeSession(_validPhoto(), ttftMs: 77, wallclockMs: 200));
      final events = await orch.describeAll([_req()]).toList();
      final succeeded = events.whereType<DescribePhotoSucceeded>().first;
      expect(succeeded.turn.ttftMs, 77);
      expect(succeeded.turn.wallclockMs, 200);
    });

    test('outputCharCount is non-negative', () async {
      final orch = _orch(_FakeSession(_validPhoto()));
      final events = await orch.describeAll([_req()]).toList();
      final succeeded = events.whereType<DescribePhotoSucceeded>().first;
      expect(succeeded.turn.outputCharCount, greaterThanOrEqualTo(0));
    });

    test('ts is a recent UTC timestamp', () async {
      final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      final orch = _orch(_FakeSession(_validPhoto()));
      final events = await orch.describeAll([_req()]).toList();
      final succeeded = events.whereType<DescribePhotoSucceeded>().first;
      expect(succeeded.turn.ts.isAfter(before), isTrue);
      expect(succeeded.turn.ts.isUtc, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Single photo — failure path
  // -------------------------------------------------------------------------

  group('single photo failure', () {
    late List<DescribePhotoEvent> events;

    setUp(() async {
      final orch = _orch(_FailingSession());
      events = await orch.describeAll([_req()]).toList();
    });

    test('emits exactly two events: Started then Failed', () {
      expect(events.length, 2);
      expect(events[0], isA<DescribePhotoStarted>());
      expect(events[1], isA<DescribePhotoFailed>());
    });

    test('DescribePhotoFailed carries the original request', () {
      final e = events[1] as DescribePhotoFailed;
      expect(e.request.observationId, 'obs-1');
      expect(e.request.imageRef, 'img-1');
    });

    test('DescribePhotoFailed carries the error', () {
      final e = events[1] as DescribePhotoFailed;
      expect(e.error, isA<GemmaContractError>());
    });
  });

  // -------------------------------------------------------------------------
  // Error isolation — one failure does NOT abort the batch
  // -------------------------------------------------------------------------

  group('error isolation across batch', () {
    test('3 photos: [fail, succeed, succeed] all emit events', () async {
      // Photo 1 will fail (FailingSession), 2 and 3 will succeed.
      // We achieve this by alternating sessions for each photo via a
      // dispatcher fake.
      final responses = [
        null, // photo 1: throw
        _validPhoto(obsId: 'obs-2', tags: '["no_visible_damage"]'),
        _validPhoto(obsId: 'obs-3', tags: '["vertical_crack"]'),
      ];

      final dispatchFake = _DispatchSession(responses);
      final orch = _orch(dispatchFake);
      final reqs = [
        _req(obsId: 'obs-1', imageRef: 'img-1'),
        _req(obsId: 'obs-2', imageRef: 'img-2'),
        _req(obsId: 'obs-3', imageRef: 'img-3'),
      ];

      final events = await orch.describeAll(reqs).toList();

      // Each photo emits Start + (Succeeded or Failed) → 3×2 = 6 events
      expect(events.length, 6);

      final started =
          events.whereType<DescribePhotoStarted>().toList();
      final succeeded =
          events.whereType<DescribePhotoSucceeded>().toList();
      final failed =
          events.whereType<DescribePhotoFailed>().toList();

      expect(started.length, 3, reason: 'all photos emit Started');
      expect(failed.length, 1, reason: 'only photo 1 fails');
      expect(succeeded.length, 2, reason: 'photos 2 and 3 succeed');

      expect(failed.first.request.observationId, 'obs-1');
    });

    test('indices are sequential even when a photo fails', () async {
      final orch = _orch(_FailingSession());
      final reqs = [
        _req(obsId: 'obs-1', imageRef: 'img-1'),
        _req(obsId: 'obs-2', imageRef: 'img-2'),
      ];
      final events = await orch.describeAll(reqs).toList();
      final started = events.whereType<DescribePhotoStarted>().toList();
      expect(started[0].index, 0);
      expect(started[1].index, 1);
      expect(started[0].total, 2);
      expect(started[1].total, 2);
    });
  });

  // -------------------------------------------------------------------------
  // Multiple photos — happy path
  // -------------------------------------------------------------------------

  group('multiple photos happy path', () {
    test('4 photos emit 8 events (4× Started + 4× Succeeded)', () async {
      final orch = _orch(_FakeSession(_validPhoto()));
      final reqs = [
        for (var i = 1; i <= 4; i++)
          _req(obsId: 'obs-$i', imageRef: 'img-$i'),
      ];
      final events = await orch.describeAll(reqs).toList();
      expect(events.length, 8);
      expect(events.whereType<DescribePhotoStarted>().length, 4);
      expect(events.whereType<DescribePhotoSucceeded>().length, 4);
    });

    test('Started events have sequential indices 0..3', () async {
      final orch = _orch(_FakeSession(_validPhoto()));
      final reqs = [
        for (var i = 1; i <= 4; i++)
          _req(obsId: 'obs-$i', imageRef: 'img-$i'),
      ];
      final events = await orch.describeAll(reqs).toList();
      final indices = events
          .whereType<DescribePhotoStarted>()
          .map((e) => e.index)
          .toList();
      expect(indices, [0, 1, 2, 3]);
    });

    test('all total fields equal 4', () async {
      final orch = _orch(_FakeSession(_validPhoto()));
      final reqs = [
        for (var i = 1; i <= 4; i++)
          _req(obsId: 'obs-$i', imageRef: 'img-$i'),
      ];
      final events = await orch.describeAll(reqs).toList();
      for (final e in events.whereType<DescribePhotoStarted>()) {
        expect(e.total, 4);
      }
    });
  });

  // -------------------------------------------------------------------------
  // Preprocessor forwarding
  // -------------------------------------------------------------------------

  group('preprocessor forwarding', () {
    test('preprocessor is called once per photo', () async {
      final counter = _CountingPreprocessor();
      final orch = _orch(_FakeSession(_validPhoto()), preprocessor: counter);
      final reqs = [
        _req(obsId: 'obs-1', imageRef: 'img-1'),
        _req(obsId: 'obs-2', imageRef: 'img-2'),
        _req(obsId: 'obs-3', imageRef: 'img-3'),
      ];
      await orch.describeAll(reqs).toList();
      expect(counter.callCount, 3);
    });

    test('default orchestrator uses PassthroughImagePreprocessor (no crash)',
        () async {
      // When no preprocessor is supplied the default is Passthrough.
      // Verify that describeAll runs without error and produces results.
      final orch = GemmaOrchestrator(_FakeSession(_validPhoto()));
      final events =
          await orch.describeAll([_req()]).toList();
      expect(events.whereType<DescribePhotoSucceeded>().length, 1);
    });

    test('each photo receives its own bytes (distinct Uint8List instances)',
        () async {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);
      final counter = _CountingPreprocessor();
      final orch = _orch(_FakeSession(_validPhoto()), preprocessor: counter);
      await orch.describeAll([
        _req(obsId: 'obs-1', imageRef: 'img-1', bytes: bytes1),
        _req(obsId: 'obs-2', imageRef: 'img-2', bytes: bytes2),
      ]).toList();
      expect(counter.received[0], bytes1);
      expect(counter.received[1], bytes2);
    });
  });

  // -------------------------------------------------------------------------
  // Contract errors are surfaced as DescribePhotoFailed (not thrown upstream)
  // -------------------------------------------------------------------------

  group('contract error surfacing', () {
    test('unknown tag becomes DescribePhotoFailed, not an unhandled throw',
        () async {
      const badResponse = '{"observation_id": "obs-1", '
          '"prompt_id": "fema_p154_q01", "asked_in": "en", '
          '"image_refs": ["img-1"], '
          '"model_description": "desc", '
          '"model_tags": ["RED_TAGGED_BUILDING"], '
          '"model_confidence": 0.7, "bbox_annotations": []}';
      final orch = _orch(_FakeSession(badResponse));
      final events = await orch.describeAll([_req()]).toList();
      expect(events.last, isA<DescribePhotoFailed>());
      final failed = events.last as DescribePhotoFailed;
      expect(failed.error, isA<GemmaContractError>());
    });

    test('after a contract error subsequent photos continue', () async {
      final sessions = [
        null, // first fails
        _validPhoto(obsId: 'obs-2', tags: '["no_visible_damage"]'),
      ];
      final orch =
          _orch(_DispatchSession([null, sessions[1]]));
      final reqs = [
        _req(obsId: 'obs-1', imageRef: 'img-1'),
        _req(obsId: 'obs-2', imageRef: 'img-2'),
      ];
      final events = await orch.describeAll(reqs).toList();
      expect(events.whereType<DescribePhotoSucceeded>().length, 1);
      expect(events.whereType<DescribePhotoFailed>().length, 1);
    });
  });
}

// ---------------------------------------------------------------------------
// Multi-response dispatcher fake
// ---------------------------------------------------------------------------

/// Session fake that serves responses from a list in order.
/// A `null` entry causes a [GemmaContractError] for that turn.
class _DispatchSession implements GemmaSessionInterface {
  _DispatchSession(this._responses);
  final List<String?> _responses;
  int _idx = 0;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final response = _responses[_idx++];
    if (response == null) {
      throw GemmaContractError(
        'dispatch: null entry at index ${_idx - 1}',
        rawText: '',
        task: 'describe_photo',
      );
    }
    return GemmaInferenceResult(
      text: response,
      thinking: '',
      ttftMs: 10,
      wallclockMs: 20,
      outputCharCount: response.length,
    );
  }
}
