/// Runtime selection for Cairn model inference.
library;

import 'package:flutter/foundation.dart';

enum InferenceRuntime {
  flutterGemma,
  nativeMtp,
}

InferenceRuntime inferenceRuntimeFromDefines({
  String inferenceRuntime = '',
  String benchRuntime = '',
  bool? isAndroid,
}) {
  final selected =
      inferenceRuntime.isNotEmpty ? inferenceRuntime : benchRuntime;
  final requested = switch (selected) {
    '' || 'flutter_gemma' || 'flutterGemma' => InferenceRuntime.flutterGemma,
    'native_mtp' || 'nativeMtp' => InferenceRuntime.nativeMtp,
    _ => InferenceRuntime.flutterGemma,
  };
  if (requested != InferenceRuntime.nativeMtp) return requested;

  final android =
      isAndroid ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  return android ? requested : InferenceRuntime.flutterGemma;
}

String inferenceRuntimeName(InferenceRuntime runtime) => switch (runtime) {
      InferenceRuntime.flutterGemma => 'flutter_gemma',
      InferenceRuntime.nativeMtp => 'native_mtp',
    };
