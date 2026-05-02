/// Conditional export — dart:io-backed implementation on native targets,
/// no-op stub on web.
///
/// Import this file everywhere: callers always get [CairnAudioRecorder] and
/// [AudioRecordingResult] regardless of platform.
library;

export 'cairn_audio_recorder_stub.dart'
    if (dart.library.io) 'cairn_audio_recorder_native.dart';
