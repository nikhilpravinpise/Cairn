/// Model registry. Mirror of `scripts/cairn/constants.py::MODELS`.
///
/// Changing IDs here must be reflected in the Python constants module or
/// CI (`scripts/tests/test_constants_parity.py`) will fail.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;

class ModelSpec {
  const ModelSpec({
    required this.key,
    required this.display,
    required this.hfRepo,
    required this.taskFilenameWeb,
    required this.taskFilenameAndroid,
    required this.quant,
    required this.modalities,
    required this.contextTokens,
    required this.inferenceMaxLongEdgePx,
  });

  final String key;
  final String display;
  final String hfRepo;
  final String taskFilenameWeb;
  final String taskFilenameAndroid;
  final String quant;
  final Set<String> modalities;
  final int contextTokens;

  /// Maximum longest-edge size (in pixels) for images sent to inference.
  ///
  /// [BoundedImagePreprocessor] uses this value to downscale capture bytes
  /// before passing them to [Message.withImage]. Images already within the
  /// bound are passed through unchanged (no re-encode cost).
  ///
  /// Sprint 3 production default: 768 px (conservative; benchmark 512 px
  /// if the device gate passes). See `docs/optimization-plan.md §OPT-1`.
  ///
  /// | Value | Meaning                                     |
  /// |-------|---------------------------------------------|
  /// | 768   | Sprint 3 default — safe, measurable speedup |
  /// | 512   | Aggressive candidate — benchmark first      |
  final int inferenceMaxLongEdgePx;

  String getTaskFilename(bool isWeb) => isWeb ? taskFilenameWeb : taskFilenameAndroid;

  String hfDownloadUrl(bool isWeb) =>
      'https://huggingface.co/$hfRepo/resolve/main/${getTaskFilename(isWeb)}';

  /// Returns the [ModelFileType] for the given platform.
  ///
  /// - Web `.task` files → [ModelFileType.task].
  /// - Android `.litertlm` files → [ModelFileType.litertlm]
  ///   (Phase 1 confirmed this enum value exists in flutter_gemma 0.14.0).
  ModelFileType fileType({required bool isWeb}) =>
      isWeb ? ModelFileType.task : ModelFileType.litertlm;

  /// Download URL resolved to the current runtime platform.
  ///
  /// Single [kIsWeb] call site for URL resolution — callers use this getter
  /// and never query [kIsWeb] themselves.
  String get resolvedDownloadUrl => hfDownloadUrl(kIsWeb);

  /// [ModelFileType] resolved to the current runtime platform.
  ///
  /// Single [kIsWeb] call site for file-type resolution.
  ModelFileType get resolvedFileType => fileType(isWeb: kIsWeb);
}

const Map<String, ModelSpec> models = {
  'e2b': ModelSpec(
    key: 'e2b',
    display: 'Gemma E2B IT (LiteRT-LM)',
    hfRepo: 'litert-community/gemma-4-E2B-it-litert-lm',
    taskFilenameWeb: 'gemma-4-E2B-it-web.task',
    taskFilenameAndroid: 'gemma-4-E2B-it.litertlm',
    quant: 'int4',
    modalities: {'text', 'image'},
    contextTokens: 8192,
    inferenceMaxLongEdgePx: 768,
  ),
  'e4b': ModelSpec(
    key: 'e4b',
    display: 'Gemma E4B IT (LiteRT-LM)',
    hfRepo: 'litert-community/gemma-4-E4B-it-litert-lm',
    taskFilenameWeb: 'gemma-4-E4B-it-web.task',
    taskFilenameAndroid: 'gemma-4-E4B-it.litertlm',
    quant: 'int4',
    modalities: {'text', 'image'},
    contextTokens: 8192,
    inferenceMaxLongEdgePx: 768,
  ),
};
