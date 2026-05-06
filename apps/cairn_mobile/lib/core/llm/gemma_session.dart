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

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;
import 'package:logging/logging.dart';

import 'cairn_tools.dart';
import 'model_registry.dart';
import 'perf_log.dart';
import 'session_config.dart';

/// Minimal generation interface that [GemmaOrchestrator] depends on.
///
/// [GemmaSession] is the production implementation. Tests supply a fake that
/// returns canned JSON so orchestrator contract logic can be exercised without
/// a real model.
abstract interface class GemmaSessionInterface {
  bool get isThinking;

  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  });
}

abstract interface class BatchGemmaSessionInterface {
  Future<GemmaInferenceResult> generateBatch({
    required String userText,
    required List<Uint8List> images,
    Duration timeout = const Duration(seconds: 240),
  });
}

class GemmaToolCall {
  const GemmaToolCall({required this.name, required this.args});

  final String name;
  final Map<String, Object?> args;

  Map<String, Object?> toJson() => {
        'name': name,
        'args': args,
      };
}

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
    this.toolCalls = const [],
    this.runtimeName = 'test',
  });

  final String text;

  /// Thinking-mode trace (Gemma 4 `<|think|>` block, or DeepSeek-style
  /// ThinkingResponse). Empty string when the chat was created with
  /// `isThinking: false`.
  final String thinking;
  final int ttftMs;
  final int wallclockMs;
  final int outputCharCount;
  final List<GemmaToolCall> toolCalls;
  final String runtimeName;

  Map<String, Object?> toJson() => {
        'text': text,
        'thinking': thinking,
        'ttft_ms': ttftMs,
        'wallclock_ms': wallclockMs,
        'output_char_count': outputCharCount,
        if (toolCalls.isNotEmpty)
          'tool_calls': toolCalls.map((c) => c.toJson()).toList(),
        'runtime_name': runtimeName,
      };
}

class GemmaSession implements GemmaSessionInterface {
  GemmaSession._(
    this._spec, {
    required this.supportImage,
    required this.supportAudio,
    required this.isThinking,
    required SessionConfig config,
  }) : _config = config;

  static final _log = Logger('GemmaSession');
  static const runtimeName = 'flutter_gemma';

  /// Open a session with explicit capability flags.
  ///
  /// Prefer the named task-profile factories ([openForVision], [openForAudio],
  /// [openForSynthesis], [openStandard]) to document intent at the call site.
  static Future<GemmaSession> open(
    ModelSpec spec, {
    required String systemPrompt,
    SessionConfig config = SessionConfig.vision,
    bool supportImage = false,
    bool supportAudio = false,
    bool isThinking = false,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) async {
    final s = GemmaSession._(
      spec,
      supportImage: supportImage,
      supportAudio: supportAudio,
      isThinking: isThinking,
      config: config,
    );
    await s._install(onProgress: onProgress, loraPath: loraPath);
    await s._create(systemPrompt: systemPrompt, loraPath: loraPath);
    return s;
  }

  /// Session profile for `describe_photo` turns.
  /// image=true, audio=false, thinking=false.
  static Future<GemmaSession> openForVision(
    ModelSpec spec, {
    required String systemPrompt,
    SessionConfig config = SessionConfig.vision,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) =>
      open(
        spec,
        systemPrompt: systemPrompt,
        config: config,
        supportImage: true,
        supportAudio: false,
        isThinking: false,
        loraPath: loraPath,
        onProgress: onProgress,
      );

  /// Session profile for `describe_audio` turns.
  /// image=false, audio=true, thinking=false.
  static Future<GemmaSession> openForAudio(
    ModelSpec spec, {
    required String systemPrompt,
    SessionConfig config = SessionConfig.audio,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) =>
      open(
        spec,
        systemPrompt: systemPrompt,
        config: config,
        supportImage: false,
        supportAudio: true,
        isThinking: false,
        loraPath: loraPath,
        onProgress: onProgress,
      );

  /// Session profile for `synthesize` turns.
  /// image=false, audio=false, thinking=true.
  static Future<GemmaSession> openForSynthesis(
    ModelSpec spec, {
    required String systemPrompt,
    SessionConfig config = SessionConfig.synthesis,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) =>
      open(
        spec,
        systemPrompt: systemPrompt,
        config: config,
        supportImage: false,
        supportAudio: false,
        isThinking: true,
        loraPath: loraPath,
        onProgress: onProgress,
      );

  /// Session profile for `protocol_answer` and `ask_followup` turns.
  /// image=false, audio=false, thinking=false.
  static Future<GemmaSession> openStandard(
    ModelSpec spec, {
    required String systemPrompt,
    SessionConfig config = SessionConfig.standard,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) =>
      open(
        spec,
        systemPrompt: systemPrompt,
        config: config,
        supportImage: false,
        supportAudio: false,
        isThinking: false,
        loraPath: loraPath,
        onProgress: onProgress,
      );

  final ModelSpec _spec;
  final SessionConfig _config;

  /// Whether the underlying model and chat were created with image support.
  final bool supportImage;

  /// Whether the underlying model was created with audio support.
  final bool supportAudio;

  @override
  final bool isThinking;

  /// The [SessionConfig] used to create this session.
  ///
  /// Exposed for testing and the benchmark script; do not mutate.
  SessionConfig get config => _config;

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
    final url = _spec.resolvedDownloadUrl;
    _log.info('ensuring ${_spec.key} is installed from $url');
    onProgress?.call(const GemmaLoadProgress(phase: 'download', fraction: 0));
    // Idempotent: on subsequent runs it resolves from the active model store
    // (OPFS on web / app-support on mobile) without re-hitting the network.
    // fileType and URL are resolved by ModelSpec.resolved* — the single
    // TargetPlatform call site lives in model_registry.dart, not here.
    final installSw = Stopwatch()..start();
    final installer = FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: _spec.resolvedFileType,
    );
    await installer
        .fromNetwork(url)
        .withProgress(
          (percent) => onProgress?.call(
            GemmaLoadProgress(phase: 'download', fraction: percent / 100.0),
          ),
        )
        .install();
    installSw.stop();
    onProgress?.call(const GemmaLoadProgress(phase: 'download', fraction: 1.0));
    PerfLogger.emit(PerfEvent(
        phase: 'install', wallclockMs: installSw.elapsedMilliseconds));
    // LoRA is attached at `createChat(loraPath:)` time. On web MediaPipe
    // currently ignores the parameter; on Android the adapter flatbuffer is
    // loaded by MediaPipe LLM Inference.
  }

  Future<void> _create({required String systemPrompt, String? loraPath}) async {
    debugPrint('[Cairn/session] ${_config.toLogString()}');
    final createSw = Stopwatch()..start();
    _model = await FlutterGemma.getActiveModel(
      preferredBackend: _config.preferredBackend,
      maxTokens: _config.maxTokens,
      supportImage: supportImage,
      supportAudio: supportAudio,
      maxNumImages: _config.maxNumImages,
    );
    final tools = toolsForSession(
      supportImage: supportImage,
      supportAudio: supportAudio,
      isThinking: isThinking,
    );
    _chat = await _model!.createChat(
      temperature: _config.temperature,
      topK: _config.topK,
      topP: _config.topP,
      supportImage: supportImage,
      supportAudio: supportAudio,
      isThinking: isThinking,
      loraPath: loraPath,
      modelType: ModelType.gemma4,
      supportsFunctionCalls: tools.isNotEmpty,
      tools: tools,
      toolChoice: tools.isEmpty ? ToolChoice.none : ToolChoice.required,
      systemInstruction: systemPrompt,
    );
    createSw.stop();
    _loraPath = loraPath;
    _loadedAt = DateTime.now();
    PerfLogger.emit(PerfEvent(
        phase: 'engine_create', wallclockMs: createSw.elapsedMilliseconds));
  }

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) {
    final run = _generationTail.then(
      (_) => _generateOnce(
        userText: userText,
        image: image,
        audioBytes: audioBytes,
        timeout: timeout,
      ),
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
    Uint8List? audioBytes,
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
    final toolCalls = <GemmaToolCall>[];

    final Message msg;
    if (image != null) {
      msg = Message.withImage(text: userText, imageBytes: image, isUser: true);
    } else if (audioBytes != null) {
      msg = Message.withAudio(
          text: userText, audioBytes: audioBytes, isUser: true);
    } else {
      msg = Message.text(text: userText, isUser: true);
    }

    try {
      await chat.addQueryChunk(msg);

      final stream = chat.generateChatResponseAsync();
      await for (final response in stream.timeout(timeout)) {
        ttftMs ??= sw.elapsedMilliseconds;
        if (response is TextResponse) {
          textBuf.write(response.token);
        } else if (response is ThinkingResponse) {
          thinkBuf.write(response.content);
        } else if (response is FunctionCallResponse) {
          toolCalls.add(_toolCallFromResponse(response));
        } else if (response is ParallelFunctionCallResponse) {
          toolCalls.addAll(response.calls.map(_toolCallFromResponse));
        }
      }
    } finally {
      // Cairn task turns are independent JSON contracts. Clearing history after
      // each turn prevents cross-photo contamination and is the production
      // default (SessionConfig.clearHistoryBetweenTurns == true).
      //
      // The Sprint 4 OPT-5 history-retention A/B variant sets this to false
      // to measure whether retaining history between same-profile photo turns
      // reduces repeated system-prompt prefill cost. Do not remove the guard
      // until the device gate confirms no output contamination.
      if (_config.clearHistoryBetweenTurns) {
        await chat.clearHistory();
      }
    }
    sw.stop();
    final text = textBuf.toString();
    final thinkText = thinkBuf.toString();
    final structuredChars =
        toolCalls.fold<int>(0, (sum, c) => sum + c.toJson().toString().length);
    PerfLogger.emit(PerfEvent(
      phase: 'generate',
      wallclockMs: sw.elapsedMilliseconds,
      ttftMs: ttftMs ?? sw.elapsedMilliseconds,
      outputCharCount: text.isEmpty ? structuredChars : text.length,
      thinkingChars: thinkText.length,
      imageSizeBytes: image?.length,
    ));
    return GemmaInferenceResult(
      text: text,
      thinking: thinkText,
      ttftMs: ttftMs ?? sw.elapsedMilliseconds,
      wallclockMs: sw.elapsedMilliseconds,
      outputCharCount: text.isEmpty ? structuredChars : text.length,
      toolCalls: toolCalls,
      runtimeName: runtimeName,
    );
  }

  GemmaToolCall _toolCallFromResponse(FunctionCallResponse response) {
    return GemmaToolCall(
      name: response.name,
      args: Map<String, Object?>.from(response.args),
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
