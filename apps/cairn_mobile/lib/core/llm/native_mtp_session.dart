/// Android LiteRT-LM MTP bridge.
///
/// This runtime is opt-in through `--dart-define=INFERENCE_RUNTIME=native_mtp`.
/// It reuses flutter_gemma's downloaded `.litertlm` file, then calls a small
/// Kotlin MethodChannel wrapper that enables LiteRT-LM speculative decoding.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;
import 'package:path_provider/path_provider.dart';

import 'gemma_session.dart';
import 'model_registry.dart';
import 'perf_log.dart';
import 'session_config.dart';

class NativeMtpGemmaSession
    implements GemmaSessionInterface, BatchGemmaSessionInterface {
  NativeMtpGemmaSession._(
    this._spec, {
    required this.isThinking,
    required SessionConfig config,
  }) : _config = config;

  static const runtimeName = 'native_mtp';
  static const _channel = MethodChannel('app.cairn/native_mtp_gemma');

  static Future<NativeMtpGemmaSession> openForVision(
    ModelSpec spec, {
    required String systemPrompt,
    SessionConfig config = SessionConfig.vision,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) async {
    final s = NativeMtpGemmaSession._(
      spec,
      isThinking: false,
      config: config,
    );
    await s._install(onProgress: onProgress);
    await s._create(systemPrompt: systemPrompt);
    return s;
  }

  static Future<NativeMtpGemmaSession> openForSynthesis(
    ModelSpec spec, {
    required String systemPrompt,
    SessionConfig config = SessionConfig.synthesis,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) async {
    final s = NativeMtpGemmaSession._(
      spec,
      isThinking: true,
      config: config,
    );
    await s._install(onProgress: onProgress);
    await s._create(systemPrompt: systemPrompt);
    return s;
  }

  final ModelSpec _spec;
  final SessionConfig _config;

  @override
  final bool isThinking;

  DateTime? _loadedAt;
  Future<void> _generationTail = Future.value();

  bool get isLoaded => _loadedAt != null;
  DateTime? get loadedAt => _loadedAt;
  SessionConfig get config => _config;

  Future<void> _install({
    void Function(GemmaLoadProgress)? onProgress,
  }) async {
    final url = _spec.resolvedDownloadUrl;
    onProgress?.call(const GemmaLoadProgress(phase: 'download', fraction: 0));
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
    onProgress?.call(const GemmaLoadProgress(phase: 'download', fraction: 1));
    PerfLogger.emit(
      PerfEvent(phase: 'install', wallclockMs: installSw.elapsedMilliseconds),
    );
  }

  Future<void> _create({required String systemPrompt}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('native_mtp is available only on Android.');
    }
    debugPrint('[Cairn/native_mtp] ${_config.toLogString()}');
    final createSw = Stopwatch()..start();
    await _channel.invokeMethod<void>('create', {
      'modelPath': await _modelPath(),
      'systemPrompt': systemPrompt,
      'maxTokens': _config.maxTokens,
      'temperature': _config.temperature,
      'topK': _config.topK,
      'topP': _config.topP,
      'enableMtp': true,
      'enableVision': !isThinking,
      'enableThinking': isThinking,
    });
    createSw.stop();
    _loadedAt = DateTime.now();
    PerfLogger.emit(
      PerfEvent(
        phase: 'engine_create',
        wallclockMs: createSw.elapsedMilliseconds,
      ),
    );
  }

  Future<String> _modelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final base = dir.path.contains('/data/user/0/')
        ? dir.path.replaceFirst('/data/user/0/', '/data/data/')
        : dir.path;
    return '$base/${_spec.taskFilenameAndroid}';
  }

  @override
  Future<GemmaInferenceResult> generate({
    required String userText,
    Uint8List? image,
    Uint8List? audioBytes,
    Duration timeout = const Duration(seconds: 180),
  }) {
    if (audioBytes != null) {
      throw UnsupportedError('native_mtp does not support audio turns.');
    }
    final images = image == null ? const <Uint8List>[] : [image];
    return _queuedGenerate(
        userText: userText, images: images, timeout: timeout);
  }

  @override
  Future<GemmaInferenceResult> generateBatch({
    required String userText,
    required List<Uint8List> images,
    Duration timeout = const Duration(seconds: 240),
  }) {
    return _queuedGenerate(
        userText: userText, images: images, timeout: timeout);
  }

  Future<GemmaInferenceResult> _queuedGenerate({
    required String userText,
    required List<Uint8List> images,
    required Duration timeout,
  }) {
    final run = _generationTail.then(
      (_) =>
          _generateOnce(userText: userText, images: images, timeout: timeout),
    );
    _generationTail = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return run;
  }

  Future<GemmaInferenceResult> _generateOnce({
    required String userText,
    required List<Uint8List> images,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    final result = await _channel.invokeMapMethod<String, Object?>('generate', {
      'text': userText,
      'images': images,
      'timeoutMs': timeout.inMilliseconds,
    }).timeout(timeout);
    sw.stop();

    final text = result?['text'] as String? ?? '';
    final ttftMs =
        (result?['ttftMs'] as num?)?.toInt() ?? sw.elapsedMilliseconds;
    final wallclockMs =
        (result?['wallclockMs'] as num?)?.toInt() ?? sw.elapsedMilliseconds;
    PerfLogger.emit(PerfEvent(
      phase: 'generate',
      wallclockMs: wallclockMs,
      ttftMs: ttftMs,
      outputCharCount: text.length,
      imageSizeBytes: images.fold<int>(0, (sum, b) => sum + b.length),
    ));
    return GemmaInferenceResult(
      text: text,
      thinking: result?['thinking'] as String? ?? '',
      ttftMs: ttftMs,
      wallclockMs: wallclockMs,
      outputCharCount: text.length,
      runtimeName: runtimeName,
    );
  }

  Future<void> close() async {
    await _channel.invokeMethod<void>('close');
    _loadedAt = null;
  }
}
