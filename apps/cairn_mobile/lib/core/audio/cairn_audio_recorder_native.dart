/// dart:io + `record` — real audio capture for Android (and other native
/// targets).
///
/// Encodes mono 16 kHz WAV via [RecordConfig], satisfying the Gemma audio
/// contract (§8.4). After [stop] the raw WAV bytes are returned; the caller
/// is responsible for persisting them via [persistCapturedAudio] and enrolling
/// them in the [SessionDraft] via [SessionController.addAudio].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const _kSampleRate = 16000;
const _kChannels = 1;
const _kMaxDurationS = 30.0;

/// The result of a completed audio recording.
class AudioRecordingResult {
  const AudioRecordingResult({
    required this.bytes,
    required this.durationS,
    required this.sampleRateHz,
    required this.channels,
  });

  final Uint8List bytes;

  /// Wall-clock seconds from start to stop, clamped 0..[_kMaxDurationS].
  final double durationS;

  /// Always 16000 on native.
  final int sampleRateHz;

  /// Always 1 (mono).
  final int channels;
}

/// Platform-conditional wrapper around the `record` package.
///
/// This file is selected on platforms where dart:io is available (Android,
/// iOS, desktop). The web stub is in [cairn_audio_recorder_stub.dart].
///
/// Usage:
/// ```dart
/// final recorder = CairnAudioRecorder();
/// if (recorder.isSupported && await recorder.hasPermission()) {
///   await recorder.start(packetId);
///   // ... user stops recording ...
///   final result = await recorder.stop();
///   // enrol result in SessionController
/// }
/// await recorder.dispose();
/// ```
class CairnAudioRecorder {
  final _recorder = AudioRecorder();
  DateTime? _startedAt;
  String? _activePath;

  /// Always true on native.
  bool get isSupported => true;

  /// Checks (and requests, on Android) microphone permission.
  ///
  /// On Android, calling this triggers the system permission dialog the first
  /// time. Returns true only when permission is granted.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Start recording a WAV file to a temp path under [packetId].
  ///
  /// Config: mono, 16 kHz, WAV encoder, no noise-suppression / AGC so the
  /// Gemma audio model receives unprocessed PCM.
  Future<void> start(String packetId) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/cairn_audio_${packetId}_tmp.wav';
    _activePath = path;
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: _kSampleRate,
        numChannels: _kChannels,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
      path: path,
    );
    _startedAt = DateTime.now();
  }

  /// Whether a recording is currently in progress.
  Future<bool> isRecording() => _recorder.isRecording();

  /// Stop the active recording and return the WAV bytes + metadata.
  ///
  /// Returns null if no recording was in progress or the file could not be
  /// read. The temporary file is deleted after the bytes are read.
  Future<AudioRecordingResult?> stop() async {
    final path = await _recorder.stop();
    final endedAt = DateTime.now();
    final started = _startedAt;
    _startedAt = null;
    _activePath = null;

    if (path == null || started == null) return null;

    final durationS = endedAt.difference(started).inMilliseconds / 1000.0;

    final file = File(path);
    if (!file.existsSync()) return null;

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return null;
    }

    try {
      await file.delete();
    } catch (_) {
      // Best-effort cleanup — not fatal.
    }

    return AudioRecordingResult(
      bytes: bytes,
      durationS: durationS.clamp(0.0, _kMaxDurationS),
      sampleRateHz: _kSampleRate,
      channels: _kChannels,
    );
  }

  /// Live amplitude level as a normalised fraction (0.0 = silence, 1.0 = peak).
  ///
  /// Maps dBFS (typically −160..0) to 0.0..1.0 with a −60 dB noise floor
  /// so that ambient room noise shows some activity rather than a flat line.
  Stream<double> amplitudeStream() {
    return _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .map((amp) => _normaliseDbfs(amp.current));
  }

  /// Cancel and discard the current recording without saving bytes.
  Future<void> cancel() async {
    await _recorder.cancel();
    _startedAt = null;
    final path = _activePath;
    _activePath = null;
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  /// Release the underlying [AudioRecorder] resources.
  Future<void> dispose() => _recorder.dispose();

  // ---------------------------------------------------------------------------

  static double _normaliseDbfs(double dbfs) {
    const minDb = -60.0;
    const maxDb = 0.0;
    if (dbfs <= minDb) return 0.0;
    if (dbfs >= maxDb) return 1.0;
    return (dbfs - minDb) / (maxDb - minDb);
  }
}
