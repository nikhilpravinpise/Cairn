/// Runtime selection for Cairn model inference.
library;

enum InferenceRuntime {
  flutterGemma,
  nativeMtp,
}

InferenceRuntime inferenceRuntimeFromDefines({
  String inferenceRuntime = '',
  String benchRuntime = '',
}) {
  final selected =
      inferenceRuntime.isNotEmpty ? inferenceRuntime : benchRuntime;
  return switch (selected) {
    '' || 'flutter_gemma' || 'flutterGemma' => InferenceRuntime.flutterGemma,
    'native_mtp' || 'nativeMtp' => InferenceRuntime.nativeMtp,
    _ => InferenceRuntime.flutterGemma,
  };
}

String inferenceRuntimeName(InferenceRuntime runtime) => switch (runtime) {
      InferenceRuntime.flutterGemma => 'flutter_gemma',
      InferenceRuntime.nativeMtp => 'native_mtp',
    };
