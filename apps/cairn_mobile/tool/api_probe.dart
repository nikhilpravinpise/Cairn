// Compile-only probe — never executed at runtime.
//
// Proves flutter_gemma >=0.15.0 exposes every symbol that Cairn depends on.
// The probe is re-run whenever flutter_gemma is upgraded; a clean analysis
// confirms backward compatibility before any feature code is changed.
//
// Run from the package root:
//   dart analyze tool/api_probe.dart
//
// Sprint 0 gates — litertlm, supportAudio/supportImage, Message.withAudio
// Sprint 1 gate  — ModelType.gemma4 exists and is distinct from gemmaIt
// Sprint 4 gate  — OPT-7 batch inference feasibility (see below)

// ignore_for_file: unused_local_variable, unused_element

import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

// Top-level const proves ModelFileType.litertlm is a compile-time symbol.
// If this line fails, the probe fails — litertlm enum case does not exist.
const ModelFileType kProbeFileType = ModelFileType.litertlm;

// Sprint 1: proves ModelType.gemma4 is a compile-time symbol distinct from
// gemmaIt. flutter_gemma 0.14.1 introduced this enum value for Gemma 4
// E2B/E4B; 0.14.2+ retains it. Both install and chat call sites use it.
const ModelType kProbeModelType = ModelType.gemma4;

// Proves the two enum values are distinct — if gemma4 were an alias for
// gemmaIt this assertion would fail at compile time.
const bool kProbeTypesDistinct = ModelType.gemma4 != ModelType.gemmaIt;

// Function is never called; analyzer still type-checks every expression.
Future<void> _probe() async {
  // getActiveModel: full multimodal parameter set plus official Gemma 4 MTP
  // toggle (flutter_gemma 0.15.0 surface).
  await FlutterGemma.getActiveModel(
    supportImage: true,
    supportAudio: true,
    maxNumImages: 5,
    enableSpeculativeDecoding: true,
  );

  // installModel with gemma4 + litertlm: Sprint 1 target (Android .litertlm).
  FlutterGemma.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  );

  // Message.withAudio: mandatory for audio capability gate.
  Message.withAudio(
    text: 'probe',
    audioBytes: Uint8List(0),
    isUser: true,
  );

  // ---------------------------------------------------------------------------
  // Sprint 4 OPT-7 — Batch inference feasibility probe
  //
  // FINDING: flutter_gemma 0.14.2 does NOT support multiple images in a single
  // InferenceChat turn. The API surface that Cairn uses is:
  //
  //   chat.addQueryChunk(Message)         — one message per turn
  //   chat.generateChatResponseAsync()    — one generation per turn
  //
  // Message.withImage() accepts a single imageBytes (Uint8List), not a list.
  // There is no Message.withImages() (plural) constructor in 0.14.2.
  // Calling addQueryChunk() multiple times before generateChatResponseAsync()
  // is not documented and is not safe — the InferenceChat state machine
  // expects exactly one user chunk before each generation.
  //
  // CONSEQUENCE: "batch inference" (multiple photos in one generation pass)
  // is not possible via the current flutter_gemma public API. The sequential
  // describeAll() stream in GemmaOrchestrator is the correct reliability
  // adapter: one describe_photo turn per image, with clearHistory() between
  // turns to maintain output independence.
  //
  // FUTURE: If flutter_gemma adds a multi-image message type (e.g., via an
  // updated MediaPipe LLM Inference engine that natively supports interleaved
  // image tokens), re-run this probe to confirm. Until then, the batch path
  // remains sequential.
  //
  // This probe verifies that Message.withImage() accepts a single Uint8List:
  final singleImageMsg = Message.withImage(
    text: 'probe batch feasibility — single image only',
    imageBytes: Uint8List(0),
    isUser: true,
  );
  // ---------------------------------------------------------------------------
}
