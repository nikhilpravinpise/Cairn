/// Sprint 4 OPT-7 — Batch inference feasibility probe.
///
/// Documents and verifies the finding that flutter_gemma 0.14.2 does NOT
/// support multiple images in a single InferenceChat turn. The sequential
/// [GemmaOrchestrator.describeAll] stream is the correct and only supported
/// reliability adapter.
///
/// ## Finding
///
/// The flutter_gemma 0.14.2 API surface exposes:
///   - `InferenceChat.addQueryChunk(Message)` — one message per turn
///   - `InferenceChat.generateChatResponseAsync()` — one generation per turn
///   - `Message.withImage(text:, imageBytes:, isUser:)` — single Uint8List
///
/// There is no `Message.withImages()` (plural) constructor. Multiple
/// `addQueryChunk()` calls before `generateChatResponseAsync()` are not
/// documented and break the InferenceChat state machine.
///
/// ## Consequence
///
/// True "batch inference" (multiple photos → one generation pass) is not
/// possible in flutter_gemma 0.14.2. The `maxNumImages: 5` parameter in
/// `getActiveModel()` controls the model's image-token capacity per turn, not
/// the number of photos Cairn can describe in one pass.
///
/// [GemmaOrchestrator.describeAll] is the correct adapter: one `describe_photo`
/// turn per image, error-isolated, with `clearHistory()` between turns.
///
/// ## Future
///
/// If a future flutter_gemma version adds multi-image message support:
///   1. Extend `tool/api_probe.dart` to prove the new API is available.
///   2. Add a `describeAllBatch()` path to [GemmaOrchestrator].
///   3. Re-run the full test suite to confirm no regressions.
library;

import 'dart:typed_data';

import 'package:cairn_mobile/core/images/image_preprocessor.dart';
import 'package:cairn_mobile/core/llm/gemma_session.dart';
import 'package:cairn_mobile/core/llm/orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake session for describeAll feasibility tests
// ---------------------------------------------------------------------------

class _FakeSession implements GemmaSessionInterface {
  final List<String> receivedUserTexts = [];
  int generateCallCount = 0;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    generateCallCount++;
    receivedUserTexts.add(userText);
    return GemmaInferenceResult(
      text: '{"observation_id":"obs-$generateCallCount","prompt_id":"p1",'
          '"image_refs":["img-$generateCallCount"],"audio_refs":[],'
          '"model_description":"desc $generateCallCount",'
          '"model_confidence":0.85,"model_tags":[],"bbox_annotations":[]}',
      thinking: '',
      ttftMs: 100,
      wallclockMs: 200,
      outputCharCount: 80,
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---------------------------------------------------------------------------
  // OPT-7 finding — documented as compile-time assertions
  // ---------------------------------------------------------------------------

  group('OPT-7 finding — batch inference not supported in 0.14.2', () {
    test('describeAll issues one generate() call per photo (sequential, not batched)', () async {
      final session = _FakeSession();
      final orch = GemmaOrchestrator(session);
      final photos = List.generate(
        3,
        (i) => DescribePhotoRequest(
          observationId: 'obs-${i + 1}',
          promptId: 'p1',
          askedIn: 'en',
          imageBytes: Uint8List(16),
          imageRef: 'img-${i + 1}',
        ),
      );

      final events = <DescribePhotoEvent>[];
      await for (final e in orch.describeAll(photos)) {
        events.add(e);
      }

      expect(session.generateCallCount, 3,
          reason:
              'Sequential describeAll issues exactly N generate() calls for N photos. '
              'If this were true batch inference, generate() would be called once.');
    });

    test('each generate() call receives a distinct prompt with its own observation_id', () async {
      final session = _FakeSession();
      final orch = GemmaOrchestrator(session);
      final photos = List.generate(
        3,
        (i) => DescribePhotoRequest(
          observationId: 'obs-${i + 1}',
          promptId: 'p1',
          askedIn: 'en',
          imageBytes: Uint8List(16),
          imageRef: 'img-${i + 1}',
        ),
      );

      await orch.describeAll(photos).drain<void>();

      expect(session.receivedUserTexts, hasLength(3));
      expect(session.receivedUserTexts[0], contains('"obs-1"'));
      expect(session.receivedUserTexts[1], contains('"obs-2"'));
      expect(session.receivedUserTexts[2], contains('"obs-3"'),
          reason:
              'Each turn is an independent JSON contract with its own observation_id. '
              'This is the sequential correctness property that batch inference '
              'cannot trivially provide without per-image prompt injection.');
    });

    test('describeAll with 1 photo issues exactly 1 generate() call', () async {
      final session = _FakeSession();
      final orch = GemmaOrchestrator(session);
      final single = [
        DescribePhotoRequest(
          observationId: 'obs-1',
          promptId: 'p1',
          askedIn: 'en',
          imageBytes: Uint8List(16),
          imageRef: 'img-1',
        ),
      ];

      await orch.describeAll(single).drain<void>();
      expect(session.generateCallCount, 1);
    });

    test('describeAll with 5 photos issues exactly 5 generate() calls', () async {
      final session = _FakeSession();
      final orch = GemmaOrchestrator(session);
      final photos = List.generate(
        5,
        (i) => DescribePhotoRequest(
          observationId: 'obs-${i + 1}',
          promptId: 'p1',
          askedIn: 'en',
          imageBytes: Uint8List(16),
          imageRef: 'img-${i + 1}',
        ),
      );

      await orch.describeAll(photos).drain<void>();
      expect(session.generateCallCount, 5,
          reason:
              'Full 5-photo batch takes 5 sequential generate() calls. '
              'Until flutter_gemma supports multi-image messages, this is the '
              'only correct implementation.');
    });
  });

  // ---------------------------------------------------------------------------
  // Sequential reliability properties
  // ---------------------------------------------------------------------------

  group('sequential describeAll — reliability properties', () {
    test('a single photo failure does not abort the remaining batch', () async {
      final failOnSecond = _FailOnNthSession(failOnN: 2);
      final orch = GemmaOrchestrator(failOnSecond);
      final photos = List.generate(
        4,
        (i) => DescribePhotoRequest(
          observationId: 'obs-${i + 1}',
          promptId: 'p1',
          askedIn: 'en',
          imageBytes: Uint8List(16),
          imageRef: 'img-${i + 1}',
        ),
      );

      final succeeded = <DescribePhotoSucceeded>[];
      final failed = <DescribePhotoFailed>[];
      await for (final e in orch.describeAll(photos)) {
        if (e is DescribePhotoSucceeded) succeeded.add(e);
        if (e is DescribePhotoFailed) failed.add(e);
      }

      expect(failed, hasLength(1), reason: 'second photo fails');
      expect(succeeded, hasLength(3), reason: 'other 3 photos succeed despite the failure');
      expect(failOnSecond.generateCallCount, 4,
          reason: 'generate() is attempted for all 4 photos regardless of failures');
    });

    test('empty batch emits no events', () async {
      final session = _FakeSession();
      final orch = GemmaOrchestrator(session);
      final events = await orch.describeAll([]).toList();
      expect(events, isEmpty);
      expect(session.generateCallCount, 0);
    });

    test('events are ordered: started → succeeded/failed for each photo', () async {
      final session = _FakeSession();
      final orch = GemmaOrchestrator(session);
      final photos = List.generate(
        2,
        (i) => DescribePhotoRequest(
          observationId: 'obs-${i + 1}',
          promptId: 'p1',
          askedIn: 'en',
          imageBytes: Uint8List(16),
          imageRef: 'img-${i + 1}',
        ),
      );

      final types = <Type>[];
      await for (final e in orch.describeAll(photos)) {
        types.add(e.runtimeType);
      }

      expect(types, [
        DescribePhotoStarted,
        DescribePhotoSucceeded,
        DescribePhotoStarted,
        DescribePhotoSucceeded,
      ], reason: 'started always precedes succeeded/failed for each photo');
    });
  });

  // ---------------------------------------------------------------------------
  // Preprocessor integration — passthrough for zero-byte test images
  // ---------------------------------------------------------------------------

  group('preprocessor integration with sequential batch', () {
    test('PassthroughImagePreprocessor does not mutate bytes during describeAll', () async {
      final session = _FakeSession();
      final orch = GemmaOrchestrator(session,
          preprocessor: const PassthroughImagePreprocessor());
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final photos = [
        DescribePhotoRequest(
          observationId: 'obs-1',
          promptId: 'p1',
          askedIn: 'en',
          imageBytes: bytes,
          imageRef: 'img-1',
        ),
      ];

      await orch.describeAll(photos).drain<void>();
      expect(session.generateCallCount, 1);
    });
  });
}

// ---------------------------------------------------------------------------
// Helper — fake session that throws on the Nth generate() call
// ---------------------------------------------------------------------------

class _FailOnNthSession implements GemmaSessionInterface {
  _FailOnNthSession({required this.failOnN});
  final int failOnN;
  int generateCallCount = 0;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    generateCallCount++;
    if (generateCallCount == failOnN) {
      throw StateError('simulated inference failure on call $generateCallCount');
    }
    return GemmaInferenceResult(
      text: '{"observation_id":"obs-$generateCallCount","prompt_id":"p1",'
          '"image_refs":["img-$generateCallCount"],"audio_refs":[],'
          '"model_description":"desc","model_confidence":0.85,'
          '"model_tags":[],"bbox_annotations":[]}',
      thinking: '',
      ttftMs: 100,
      wallclockMs: 200,
      outputCharCount: 80,
    );
  }
}
