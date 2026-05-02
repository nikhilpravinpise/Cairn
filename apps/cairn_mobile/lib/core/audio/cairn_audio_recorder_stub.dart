/// Web / non-native stub for [CairnAudioRecorder].
///
/// All capture operations are no-ops. [isSupported] returns false so the
/// [AudioScreen] can degrade to a skip-only UI on web without crashing.
library;

import 'dart:typed_data';

/// The result of a completed audio recording.
class AudioRecordingResult {
  const AudioRecordingResult({
    required this.bytes,
    required this.durationS,
    required this.sampleRateHz,
    required this.channels,
  });

  final Uint8List bytes;

  /// Wall-clock seconds from start to stop, clamped 0..30.
  final double durationS;

  /// Always 16000 on native; 0 on stub (never reached with [isSupported]=false).
  final int sampleRateHz;

  /// Always 1 (mono).
  final int channels;
}

/// Platform-conditional wrapper around the `record` package.
///
/// The stub (this file) is selected on web where dart:io is unavailable.
/// The real implementation is in [cairn_audio_recorder_native.dart].
class CairnAudioRecorder {
  /// False on web: recording is not supported.
  bool get isSupported => false;

  /// Always returns false on the stub (permission cannot be requested on web).
  Future<bool> hasPermission() async => false;

  /// No-op on stub.
  Future<void> start(String packetId) async {}

  /// Always false on stub.
  Future<bool> isRecording() async => false;

  /// Always returns null on stub.
  Future<AudioRecordingResult?> stop() async => null;

  /// Empty amplitude stream on stub.
  Stream<double> amplitudeStream() => const Stream.empty();

  /// No-op on stub.
  Future<void> cancel() async {}

  /// No-op on stub.
  Future<void> dispose() async {}
}
