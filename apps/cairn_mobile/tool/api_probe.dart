// Compile-only probe — never executed at runtime.
//
// Proves flutter_gemma 0.14.0 exposes every symbol that subsequent phases
// depend on before those phases write a single line of feature code.
//
// Run from the package root:
//   dart analyze tool/api_probe.dart
//
// §7 Q4  — does 0.14.0 analyze cleanly?          → yes if this file compiles
// §7 Q5  — ModelFileType values after pin?        → litertlm confirmed below
// Phase 6 gate — supportAudio / supportImage args → confirmed below
// Phase 8 gate — Message.withAudio constructor    → confirmed below

// ignore_for_file: unused_local_variable, unused_element

import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

// Top-level const proves ModelFileType.litertlm is a compile-time symbol.
// If this line fails, the probe fails — litertlm enum case does not exist.
const ModelFileType kProbeFileType = ModelFileType.litertlm;

// Function is never called; analyzer still type-checks every expression.
Future<void> _probe() async {
  // getActiveModel: full multimodal parameter set (Phase 6 surface).
  await FlutterGemma.getActiveModel(
    supportImage: true,
    supportAudio: true,
    maxNumImages: 5,
  );

  // installModel with litertlm: the Android model file type (Phase 5).
  FlutterGemma.installModel(
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
  );

  // Message.withAudio: mandatory for Phase 8 audio capability gate.
  Message.withAudio(
    text: 'probe',
    audioBytes: Uint8List(0),
    isUser: true,
  );
}
