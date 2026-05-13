import 'dart:typed_data';

import 'package:cairn_mobile/core/llm/gemma_session.dart';
import 'package:cairn_mobile/core/llm/inference_runtime.dart';
import 'package:cairn_mobile/core/llm/native_mtp_session.dart';
import 'package:cairn_mobile/core/llm/orchestrator.dart';
import 'package:cairn_mobile/core/llm/session_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _ToolSession implements GemmaSessionInterface {
  _ToolSession(this.result);

  final GemmaInferenceResult result;
  Uint8List? lastImage;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    lastImage = image;
    return result;
  }
}

class _BatchSession
    implements GemmaSessionInterface, BatchGemmaSessionInterface {
  _BatchSession(this.batchResult);

  final GemmaInferenceResult batchResult;
  int batchCalls = 0;
  int sequentialCalls = 0;

  @override
  bool get isThinking => false;

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    sequentialCalls++;
    return GemmaInferenceResult(
      text: '{"observation_id":"obs-$sequentialCalls","prompt_id":"p1",'
          '"asked_in":"en","image_refs":["img-$sequentialCalls"],'
          '"model_description":"desc $sequentialCalls",'
          '"model_tags":[],"model_confidence":0.7,"bbox_annotations":[]}',
      thinking: '',
      ttftMs: 10,
      wallclockMs: 20,
      outputCharCount: 100,
    );
  }

  @override
  Future<GemmaInferenceResult> generateBatch({
    required String userText,
    required List<Uint8List> images,
    Duration timeout = const Duration(seconds: 240),
  }) async {
    batchCalls++;
    return batchResult;
  }
}

DescribePhotoRequest _req(int i) => DescribePhotoRequest(
      observationId: 'obs-$i',
      promptId: 'p1',
      askedIn: 'en',
      imageBytes: Uint8List(4),
      imageRef: 'img-$i',
    );

void main() {
  group('inferenceRuntimeFromDefines', () {
    test('defaults to flutter_gemma', () {
      expect(
        inferenceRuntimeFromDefines(),
        InferenceRuntime.flutterGemma,
      );
    });

    test('selects native_mtp from INFERENCE_RUNTIME', () {
      expect(
        inferenceRuntimeFromDefines(
          inferenceRuntime: 'native_mtp',
          isAndroid: true,
        ),
        InferenceRuntime.nativeMtp,
      );
    });

    test('native_mtp falls back to flutter_gemma off Android', () {
      expect(
        inferenceRuntimeFromDefines(
          inferenceRuntime: 'native_mtp',
          isAndroid: false,
        ),
        InferenceRuntime.flutterGemma,
      );
    });

    test('INFERENCE_RUNTIME wins over BENCH_RUNTIME', () {
      expect(
        inferenceRuntimeFromDefines(
          inferenceRuntime: 'flutter_gemma',
          benchRuntime: 'native_mtp',
        ),
        InferenceRuntime.flutterGemma,
      );
    });
  });

  group('NativeMtpGemmaSession create payload', () {
    test('includes token budget, backend, image count, and MTP state', () {
      final payload = NativeMtpGemmaSession.buildCreatePayload(
        modelPath: '/tmp/model.litertlm',
        systemPrompt: 'system',
        config: SessionConfig.vision,
        enableVision: true,
        enableThinking: false,
      );

      expect(payload['modelPath'], '/tmp/model.litertlm');
      expect(payload['maxTokens'], SessionConfig.vision.maxTokens);
      expect(payload['maxNumImages'], SessionConfig.vision.maxNumImages);
      expect(payload['backend'], 'gpu');
      expect(payload['visionBackend'], 'gpu');
      expect(payload['enableMtp'], isFalse);
      expect(payload['enableVision'], isTrue);
      expect(payload['enableThinking'], isFalse);
    });

    test('MTP is explicit opt-in for benchmark runs', () {
      final payload = NativeMtpGemmaSession.buildCreatePayload(
        modelPath: '/tmp/model.litertlm',
        systemPrompt: 'system',
        config: SessionConfig.vision,
        enableVision: true,
        enableThinking: false,
        enableMtp: true,
      );

      expect(payload['enableMtp'], isTrue);
    });
  });

  group('Gemma tool-call output', () {
    test('describePhoto accepts matching FunctionCallResponse payload',
        () async {
      final session = _ToolSession(
        const GemmaInferenceResult(
          text: '',
          thinking: '',
          ttftMs: 11,
          wallclockMs: 22,
          outputCharCount: 120,
          runtimeName: GemmaSession.runtimeName,
          toolCalls: [
            GemmaToolCall(
              name: 'describe_photo',
              args: {
                'observation_id': 'obs-1',
                'prompt_id': 'p1',
                'asked_in': 'en',
                'image_refs': ['img-1'],
                'model_description': 'Diagonal crack visible.',
                'model_tags': ['diagonal_crack'],
                'model_confidence': 0.8,
                'bbox_annotations': [],
              },
            ),
          ],
        ),
      );
      final result = await GemmaOrchestrator(session).describePhoto(
        observationId: 'obs-1',
        promptId: 'p1',
        askedIn: 'en',
        imageBytes: Uint8List(4),
        imageRef: 'img-1',
      );

      expect(result.modelTags, ['diagonal_crack']);
      expect(result.ttftMs, 11);
    });

    test(
        'flutter_gemma runtime accepts text-only JSON when no tool call present',
        () async {
      final session = _ToolSession(
        const GemmaInferenceResult(
          text: '{"observation_id":"obs-1","prompt_id":"p1","asked_in":"en",'
              '"image_refs":["img-1"],"model_description":"Crack visible.",'
              '"model_tags":["diagonal_crack"],"model_confidence":0.8,'
              '"bbox_annotations":[]}',
          thinking: '',
          ttftMs: 1,
          wallclockMs: 2,
          outputCharCount: 50,
          runtimeName: GemmaSession.runtimeName,
        ),
      );

      final result = await GemmaOrchestrator(session).describePhoto(
        observationId: 'obs-1',
        promptId: 'p1',
        askedIn: 'en',
        imageBytes: Uint8List(4),
        imageRef: 'img-1',
      );
      expect(result.modelTags, ['diagonal_crack']);
      expect(result.ttftMs, 1);
    });

    test('flutter_gemma contract fails when both tool call and JSON are absent',
        () async {
      final session = _ToolSession(
        const GemmaInferenceResult(
          text: 'I cannot process this image.',
          thinking: '',
          ttftMs: 1,
          wallclockMs: 2,
          outputCharCount: 30,
          runtimeName: GemmaSession.runtimeName,
        ),
      );

      await expectLater(
        GemmaOrchestrator(session).describePhoto(
          observationId: 'obs-1',
          promptId: 'p1',
          askedIn: 'en',
          imageBytes: Uint8List(4),
          imageRef: 'img-1',
        ),
        throwsA(isA<GemmaContractError>().having(
          (e) => e.message,
          'message',
          contains('required tool call "describe_photo" missing'),
        )),
      );
    });

    test('describePhoto uses inference bytes when provided', () async {
      final session = _ToolSession(
        const GemmaInferenceResult(
          text: '{"observation_id":"obs-1","prompt_id":"p1","asked_in":"en",'
              '"image_refs":["img-1"],"model_description":"No visible damage.",'
              '"model_tags":["no_visible_damage"],"model_confidence":0.9,'
              '"bbox_annotations":[]}',
          thinking: '',
          ttftMs: 1,
          wallclockMs: 2,
          outputCharCount: 50,
          runtimeName: GemmaSession.runtimeName,
        ),
      );
      final raw = Uint8List.fromList([1, 2, 3, 4]);
      final inference = Uint8List.fromList([9, 8]);

      await GemmaOrchestrator(session).describePhoto(
        observationId: 'obs-1',
        promptId: 'p1',
        askedIn: 'en',
        imageBytes: raw,
        inferenceImageBytes: inference,
        imageRef: 'img-1',
      );

      expect(identical(session.lastImage, inference), isTrue);
    });

    test('describePhoto removes contradictory no_visible_damage tag', () async {
      final session = _ToolSession(
        const GemmaInferenceResult(
          text: '{"observation_id":"obs-1","prompt_id":"p1","asked_in":"en",'
              '"image_refs":["img-1"],"model_description":"Cracking visible.",'
              '"model_tags":["horizontal_crack","no_visible_damage",'
              '"horizontal_crack","uncertain_structural"],'
              '"model_confidence":0.6,"bbox_annotations":[]}',
          thinking: '',
          ttftMs: 1,
          wallclockMs: 2,
          outputCharCount: 50,
          runtimeName: GemmaSession.runtimeName,
        ),
      );

      final result = await GemmaOrchestrator(session).describePhoto(
        observationId: 'obs-1',
        promptId: 'p1',
        askedIn: 'en',
        imageBytes: Uint8List(4),
        imageRef: 'img-1',
      );

      expect(result.modelTags, ['horizontal_crack', 'uncertain_structural']);
    });
  });

  group('native batch path', () {
    test('describePhotosBatch returns typed fallback on count mismatch',
        () async {
      final session = _BatchSession(
        const GemmaInferenceResult(
          text: '{"observations":[]}',
          thinking: '',
          ttftMs: 10,
          wallclockMs: 20,
          outputCharCount: 20,
          runtimeName: 'native_mtp',
        ),
      );
      final result = await GemmaOrchestrator(session).describePhotosBatch([
        _req(1),
        _req(2),
      ]);

      expect(result.shouldFallback, isTrue);
      expect(result.fallbackReason, contains('returned 0 observations'));
    });

    test('describeAll falls back to sequential after failed native batch',
        () async {
      final session = _BatchSession(
        const GemmaInferenceResult(
          text: '{"observations":[]}',
          thinking: '',
          ttftMs: 10,
          wallclockMs: 20,
          outputCharCount: 20,
          runtimeName: 'native_mtp',
        ),
      );
      final events = await GemmaOrchestrator(
        session,
        enableBatchVision: true,
      ).describeAll([
        _req(1),
        _req(2),
      ]).toList();

      expect(session.batchCalls, 1);
      expect(session.sequentialCalls, 2);
      expect(events.whereType<DescribePhotoSucceeded>(), hasLength(2));
    });
  });
}
