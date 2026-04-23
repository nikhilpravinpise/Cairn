/// Model registry. Mirror of `scripts/cairn/constants.py::MODELS`.
///
/// Changing IDs here must be reflected in the Python constants module or
/// CI (`scripts/tests/test_constants_parity.py`) will fail.
library;

class ModelSpec {
  const ModelSpec({
    required this.key,
    required this.display,
    required this.hfRepo,
    required this.taskFilename,
    required this.quant,
    required this.modalities,
    required this.contextTokens,
  });

  final String key;
  final String display;
  final String hfRepo;
  final String taskFilename;
  final String quant;
  final Set<String> modalities;
  final int contextTokens;

  String get hfDownloadUrl =>
      'https://huggingface.co/$hfRepo/resolve/main/$taskFilename';
}

const Map<String, ModelSpec> models = {
  'e2b': ModelSpec(
    key: 'e2b',
    display: 'Gemma E2B IT (LiteRT-LM, web/.task)',
    hfRepo: 'litert-community/gemma-4-E2B-it-litert-lm',
    taskFilename: 'gemma-4-E2B-it-web.task',
    quant: 'int4',
    modalities: {'text', 'image'},
    contextTokens: 8192,
  ),
  'e4b': ModelSpec(
    key: 'e4b',
    display: 'Gemma E4B IT (LiteRT-LM, web/.task)',
    hfRepo: 'litert-community/gemma-4-E4B-it-litert-lm',
    taskFilename: 'gemma-4-E4B-it-web.task',
    quant: 'int4',
    modalities: {'text', 'image'},
    contextTokens: 8192,
  ),
};
