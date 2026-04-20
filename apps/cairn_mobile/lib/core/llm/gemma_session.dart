/// Thin wrapper around `flutter_gemma` that owns the model + chat lifecycle.
///
/// Web-first (Week-1 S2): no `dart:io`, no `path_provider`. MediaPipe manages
/// its own cache (OPFS on web, app-support on mobile once we enable it).
///
/// The real session used by the app ships in Week 2 under `lib/features/…`.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:logging/logging.dart';

import 'model_registry.dart';

class GemmaLoadProgress {
  const GemmaLoadProgress({required this.phase, required this.fraction});
  final String phase;
  final double fraction;
}

class GemmaInferenceResult {
  const GemmaInferenceResult({
    required this.text,
    required this.ttftMs,
    required this.wallclockMs,
    required this.outputCharCount,
  });
  final String text;
  final int ttftMs;
  final int wallclockMs;
  final int outputCharCount;

  Map<String, Object?> toJson() => {
        'text': text,
        'ttft_ms': ttftMs,
        'wallclock_ms': wallclockMs,
        'output_char_count': outputCharCount,
      };
}

class GemmaSession {
  GemmaSession._(this._spec);

  static final _log = Logger('GemmaSession');

  static Future<GemmaSession> open(
    ModelSpec spec, {
    String? loraPath,
    required String systemPrompt,
    void Function(GemmaLoadProgress)? onProgress,
  }) async {
    final s = GemmaSession._(spec);
    await s._install(onProgress: onProgress, loraPath: loraPath);
    await s._create(systemPrompt: systemPrompt, loraPath: loraPath);
    return s;
  }

  final ModelSpec _spec;
  InferenceModel? _model;
  InferenceChat? _chat;
  String? _loraPath;
  DateTime? _loadedAt;

  bool get isLoaded => _model != null && _chat != null;
  String? get loraPath => _loraPath;
  DateTime? get loadedAt => _loadedAt;

  Future<void> _install({
    void Function(GemmaLoadProgress)? onProgress,
    String? loraPath,
  }) async {
    final plugin = FlutterGemmaPlugin.instance;
    _log.info('ensuring ${_spec.key} is installed from ${_spec.hfDownloadUrl}');
    onProgress?.call(const GemmaLoadProgress(phase: 'download', fraction: 0));
    // downloadModelFromNetworkWithProgress is idempotent: on subsequent runs it
    // resolves immediately from OPFS (web) / app-support (mobile) without
    // re-hitting the network.
    final stream = plugin.modelManager.downloadModelFromNetworkWithProgress(
      _spec.hfDownloadUrl,
    );
    await for (final p in stream) {
      onProgress?.call(GemmaLoadProgress(phase: 'download', fraction: p / 100.0));
    }
    onProgress?.call(const GemmaLoadProgress(phase: 'download', fraction: 1.0));
    // NOTE: LoRA is attached at `createChat(loraPath:)` time. On web the
    // `loraPath:` argument is a no-op; we still pass it through so the same
    // Dart code targets both platforms once Android comes online.
  }

  Future<void> _create({required String systemPrompt, String? loraPath}) async {
    final plugin = FlutterGemmaPlugin.instance;
    _model = await plugin.createModel(
      modelType: ModelType.gemmaIt,
      preferredBackend: PreferredBackend.gpu,
      maxTokens: 4096,
      supportImage: _spec.modalities.contains('image'),
      maxNumImages: 5,
    );
    _chat = await _model!.createChat(
      temperature: 0.2,
      topK: 40,
      topP: 0.95,
      supportImage: _spec.modalities.contains('image'),
      loraPath: loraPath,
      systemInstruction: systemPrompt,
    );
    _loraPath = loraPath;
    _loadedAt = DateTime.now();
  }

  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final chat = _chat;
    if (chat == null) {
      throw StateError('GemmaSession not loaded — call open() first.');
    }

    final sw = Stopwatch()..start();
    int? ttftMs;
    final buf = StringBuffer();

    final msg = image == null
        ? Message.text(text: userText, isUser: true)
        : Message.withImage(text: userText, imageBytes: image, isUser: true);
    await chat.addQueryChunk(msg);

    final stream = chat.generateChatResponseAsync();
    await for (final token in stream.timeout(timeout)) {
      ttftMs ??= sw.elapsedMilliseconds;
      buf.write(token);
    }
    sw.stop();
    final text = buf.toString();
    return GemmaInferenceResult(
      text: text,
      ttftMs: ttftMs ?? sw.elapsedMilliseconds,
      wallclockMs: sw.elapsedMilliseconds,
      outputCharCount: text.length,
    );
  }

  Future<void> close() async {
    await _model?.close();
    _chat = null;
    _model = null;
    _loadedAt = null;
  }
}
