/// Thin wrapper around `flutter_gemma` that owns the model + chat lifecycle.
///
/// Cross-platform: MediaPipe manages its own cache (OPFS on web, app-support
/// on Android/iOS) so we don't touch `dart:io` directly.
///
/// The returned stream from `flutter_gemma` emits typed `ModelResponse`s
/// (`TextResponse` / `ThinkingResponse` / function-call subclasses); this
/// wrapper joins them into a single `GemmaInferenceResult` with text +
/// thinking trace + latency metrics.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;
import 'package:logging/logging.dart';

import 'model_registry.dart';

class GemmaLoadProgress {
  const GemmaLoadProgress({required this.phase, required this.fraction});
  final String phase;

  /// 0.0 .. 1.0
  final double fraction;
}

class GemmaInferenceResult {
  const GemmaInferenceResult({
    required this.text,
    required this.thinking,
    required this.ttftMs,
    required this.wallclockMs,
    required this.outputCharCount,
  });

  final String text;

  /// Thinking-mode trace (Gemma 4 `<|think|>` block, or DeepSeek-style
  /// ThinkingResponse). Empty string when the chat was created with
  /// `isThinking: false`.
  final String thinking;
  final int ttftMs;
  final int wallclockMs;
  final int outputCharCount;

  Map<String, Object?> toJson() => {
        'text': text,
        'thinking': thinking,
        'ttft_ms': ttftMs,
        'wallclock_ms': wallclockMs,
        'output_char_count': outputCharCount,
      };
}

class GemmaSession {
  GemmaSession._(this._spec, {required this.isThinking});

  static final _log = Logger('GemmaSession');

  static Future<GemmaSession> open(
    ModelSpec spec, {
    String? loraPath,
    required String systemPrompt,
    bool isThinking = false,
    void Function(GemmaLoadProgress)? onProgress,
  }) async {
    final s = GemmaSession._(spec, isThinking: isThinking);
    await s._install(onProgress: onProgress, loraPath: loraPath);
    await s._create(systemPrompt: systemPrompt, loraPath: loraPath);
    return s;
  }

  final ModelSpec _spec;
  final bool isThinking;
  InferenceModel? _model;
  InferenceChat? _chat;
  String? _loraPath;
  DateTime? _loadedAt;
  Future<void> _generationTail = Future.value();

  bool get isLoaded => _model != null && _chat != null;
  String? get loraPath => _loraPath;
  DateTime? get loadedAt => _loadedAt;

  Future<void> _install({
    void Function(GemmaLoadProgress)? onProgress,
    String? loraPath,
  }) async {
    _log.info('ensuring ${_spec.key} is installed from ${_spec.hfDownloadUrl}');
    onProgress?.call(const GemmaLoadProgress(phase: 'download', fraction: 0));
    // Idempotent: on subsequent runs it resolves from the active model store
    // (OPFS on web / app-support on mobile) without re-hitting the network.
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromNetwork(_spec.hfDownloadUrl)
        .withProgress(
          (percent) => onProgress?.call(
            GemmaLoadProgress(phase: 'download', fraction: percent / 100.0),
          ),
        )
        .install();
    onProgress?.call(const GemmaLoadProgress(phase: 'download', fraction: 1.0));
    // LoRA is attached at `createChat(loraPath:)` time. On web MediaPipe
    // currently ignores the parameter; on Android the adapter flatbuffer is
    // loaded by MediaPipe LLM Inference.
  }

  Future<void> _create({required String systemPrompt, String? loraPath}) async {
    final wantImage = _spec.modalities.contains('image');
    _model = await FlutterGemma.getActiveModel(
      preferredBackend: PreferredBackend.gpu,
      maxTokens: 4096,
      supportImage: wantImage,
      maxNumImages: 5,
    );
    _chat = await _model!.createChat(
      temperature: 0.2,
      topK: 40,
      topP: 0.95,
      supportImage: wantImage,
      isThinking: isThinking,
      loraPath: loraPath,
      modelType: ModelType.gemmaIt,
      systemInstruction: systemPrompt,
    );
    _loraPath = loraPath;
    _loadedAt = DateTime.now();
  }

  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Duration timeout = const Duration(seconds: 180),
  }) {
    final run = _generationTail.then(
      (_) => _generateOnce(userText: userText, image: image, timeout: timeout),
    );
    _generationTail = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return run;
  }

  Future<GemmaInferenceResult> _generateOnce({
    required String userText,
    Uint8List? image,
    required Duration timeout,
  }) async {
    final chat = _chat;
    if (chat == null) {
      throw StateError('GemmaSession not loaded — call open() first.');
    }

    final sw = Stopwatch()..start();
    int? ttftMs;
    final textBuf = StringBuffer();
    final thinkBuf = StringBuffer();

    final msg = image == null
        ? Message.text(text: userText, isUser: true)
        : Message.withImage(text: userText, imageBytes: image, isUser: true);
    try {
      await chat.addQueryChunk(msg);

      final stream = chat.generateChatResponseAsync();
      await for (final response in stream.timeout(timeout)) {
        ttftMs ??= sw.elapsedMilliseconds;
        if (response is TextResponse) {
          textBuf.write(response.token);
        } else if (response is ThinkingResponse) {
          thinkBuf.write(response.content);
        }
        // Function-call subclasses are ignored in Cairn (no tools wired).
      }
    } finally {
      // Cairn task turns are independent JSON contracts. Keeping prior photos
      // and answers in chat history both wastes context and can contaminate the
      // next task.
      await chat.clearHistory();
    }
    sw.stop();
    final text = textBuf.toString();
    return GemmaInferenceResult(
      text: text,
      thinking: thinkBuf.toString(),
      ttftMs: ttftMs ?? sw.elapsedMilliseconds,
      wallclockMs: sw.elapsedMilliseconds,
      outputCharCount: text.length,
    );
  }

  Future<void> close() async {
    await _chat?.close();
    _chat = null;
    await _model?.close();
    _model = null;
    _loadedAt = null;
  }
}
