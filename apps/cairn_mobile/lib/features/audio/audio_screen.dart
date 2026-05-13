/// Screen 4 — **Audio observations** (Android audio capture).
///
/// Presents a full record → stop → encode pipeline backed by the `record`
/// package. Four explicit UI states keep the volunteer informed at every step:
///
/// | State     | Recorder state            | UI shown                         |
/// |-----------|---------------------------|----------------------------------|
/// | idle      | not started               | Mic button, hint text            |
/// | recording | [AudioRecorder.start]     | Pulsing indicator, live duration |
/// | processing| [AudioRecorder.stop]      | Spinner, "encoding…"             |
/// | ready     | bytes in SessionDraft     | Success card, optional Gemma status|
/// | error     | hardware / file failure   | Error text, retry button         |
/// | permDenied| RECORD_AUDIO not granted  | Banner, grant-permission button  |
///
/// ### Audio is record-only in v1
///
/// WAV bytes are enrolled in the [SessionDraft] and persisted to the tmp
/// audio cache. Automatic `describe_audio` via Gemma is deferred until the
/// audio quality gate is proven (Sprint 1+).
///
/// ### Web fallback
///
/// [CairnAudioRecorder.isSupported] is false on web. The screen shows a
/// skip-only UI; audio capture is Android-first per §1.3.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/audio/cairn_audio_recorder.dart';
import '../../core/io/audio_cache.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/session_controller.dart';
import '../../core/widgets/flow_stepper.dart';

// ---------------------------------------------------------------------------
// Private state enums
// ---------------------------------------------------------------------------

enum _CaptureState {
  idle, // Mic button visible, no recording in progress.
  permDenied, // RECORD_AUDIO permission denied.
  recording, // AudioRecorder.start() called; amplitude stream live.
  processing, // AudioRecorder.stop() called; reading + enrolling bytes.
  ready, // Bytes enrolled in SessionDraft; Continue enabled.
  error, // Hardware error or file read failure.
}

// ---------------------------------------------------------------------------
// Screen widget
// ---------------------------------------------------------------------------

class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  static final _log = Logger('AudioScreen');

  final _recorder = CairnAudioRecorder();

  _CaptureState _captureState = _CaptureState.idle;

  /// The aud-N ref assigned after successful encode.
  String? _audioRef;

  /// Wall-clock seconds elapsed since recording started (updated by [_ticker]).
  double _durationS = 0.0;

  /// Live amplitude fraction (0.0..1.0), emitted by [CairnAudioRecorder].
  double _amplitude = 0.0;

  /// Error message shown in error / permDenied states.
  String? _errorMessage;

  Timer? _ticker;
  DateTime? _recordingStartedAt;
  StreamSubscription<double>? _amplitudeSub;

  static const _kMaxDurationS = 30.0;
  static const _kTickMs = 100;

  @override
  void dispose() {
    _ticker?.cancel();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Record / stop
  // ---------------------------------------------------------------------------

  Future<void> _startRecording() async {
    if (!_recorder.isSupported) return;

    final draft = ref.read(sessionControllerProvider);
    if (draft == null) return;

    // Check (and request) microphone permission.
    final granted = await _recorder.hasPermission();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        _captureState = _CaptureState.permDenied;
        _errorMessage =
            'Microphone permission is required to record audio observations. '
            'Tap "Grant" to open the permission dialog.';
      });
      return;
    }

    try {
      await _recorder.start(draft.packetId);
      if (!mounted) return;

      _recordingStartedAt = DateTime.now();
      _durationS = 0.0;
      _amplitude = 0.0;

      // Live amplitude via the recorder's dBFS stream.
      _amplitudeSub?.cancel();
      _amplitudeSub = _recorder.amplitudeStream().listen((level) {
        if (mounted) setState(() => _amplitude = level);
      });

      // Tick to update elapsed duration and enforce 30-second cap.
      _ticker?.cancel();
      _ticker = Timer.periodic(
        const Duration(milliseconds: _kTickMs),
        (_) {
          if (!mounted) return;
          final started = _recordingStartedAt;
          if (started == null) return;
          final elapsed =
              DateTime.now().difference(started).inMilliseconds / 1000.0;
          setState(() => _durationS = elapsed.clamp(0.0, _kMaxDurationS));
          if (elapsed >= _kMaxDurationS) {
            _log.info('AudioScreen: auto-stopping at ${_kMaxDurationS}s cap');
            _stopRecording();
          }
        },
      );

      setState(() {
        _captureState = _CaptureState.recording;
        _errorMessage = null;
      });
    } catch (e, st) {
      _log.warning('AudioScreen: start() failed', e, st);
      if (!mounted) return;
      setState(() {
        _captureState = _CaptureState.error;
        _errorMessage = 'Could not start recording: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    _amplitudeSub?.cancel();
    _ticker = null;
    _amplitudeSub = null;

    setState(() => _captureState = _CaptureState.processing);

    AudioRecordingResult? result;
    try {
      result = await _recorder.stop();
    } catch (e, st) {
      _log.warning('AudioScreen: stop() failed', e, st);
      if (!mounted) return;
      setState(() {
        _captureState = _CaptureState.error;
        _errorMessage = 'Failed to save recording: $e';
      });
      return;
    }

    if (!mounted) return;

    if (result == null || result.bytes.isEmpty) {
      setState(() {
        _captureState = _CaptureState.error;
        _errorMessage = 'Recording produced no data. Please try again.';
      });
      return;
    }

    await _enrollAudio(result);
  }

  Future<void> _enrollAudio(AudioRecordingResult result) async {
    final controller = ref.read(sessionControllerProvider.notifier);
    final draft = ref.read(sessionControllerProvider);
    if (draft == null || !mounted) return;

    final ref_ = controller.generateAudioId();
    _audioRef = ref_;

    // Enroll in SessionDraft — even if persist/Gemma fails, the bytes are safe.
    try {
      controller.addAudio(
        ref: ref_,
        bytes: result.bytes,
        durationS: result.durationS,
        sampleRateHz: result.sampleRateHz,
        channels: result.channels,
      );
    } catch (e) {
      _log.warning('AudioScreen: addAudio() rejected (invariant): $e');
      if (!mounted) return;
      setState(() {
        _captureState = _CaptureState.error;
        _errorMessage = 'Audio invariant violation: $e';
      });
      return;
    }

    // Persist bytes to tmp dir (best-effort, non-blocking).
    unawaited(persistCapturedAudio(draft.packetId, ref_, result.bytes));

    if (!mounted) return;
    setState(() {
      _captureState = _CaptureState.ready;
      _durationS = result.durationS;
    });
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    _amplitudeSub?.cancel();
    _ticker = null;
    _amplitudeSub = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _captureState = _CaptureState.idle;
      _durationS = 0.0;
      _amplitude = 0.0;
      _errorMessage = null;
    });
  }

  void _retry() {
    setState(() {
      _captureState = _CaptureState.idle;
      _durationS = 0.0;
      _amplitude = 0.0;
      _audioRef = null;
      _errorMessage = null;
    });
  }

  void _skip() => context.push(AppRoutes.describe);
  void _continue() => context.push(AppRoutes.describe);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(sessionControllerProvider);
    if (draft == null) {
      return const Scaffold(
        body: Center(child: Text('No active session — return to Start.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? BackButton(onPressed: () => context.pop())
            : null,
        title: const Text('Audio observations'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const FlowStepper(
                steps: FlowStepper.kScreeningSteps, currentIndex: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Not-supported banner (web).
                  if (!_recorder.isSupported) ...[
                    const _Banner(
                      color: Colors.amber,
                      icon: Icons.info_outline,
                      text:
                          'Audio capture is not available in this environment. '
                          'Tap Skip to continue.',
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Instruction text.
                  const Text(
                    'Record ambient sounds, structural feedback, or verbal notes '
                    'while you walk around the building. Up to 30 seconds.',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  const SizedBox(height: 24),

                  // Core capture widget.
                  if (!_recorder.isSupported)
                    _NotSupportedCard()
                  else ...[
                    _buildCaptureCard(context),
                  ],

                  const SizedBox(height: 24),

                  // Continue button.
                  FilledButton(
                    onPressed:
                        _captureState == _CaptureState.ready ? _continue : null,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Continue', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Skip is always available.
                  Center(
                    child: TextButton(
                      onPressed: _skip,
                      child: Text(
                        _captureState == _CaptureState.ready
                            ? 'Skip — discard this recording'
                            : 'Skip — no audio to add',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStateWidget(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStateWidget(BuildContext context) {
    switch (_captureState) {
      case _CaptureState.idle:
        return _IdleWidget(onRecord: _startRecording);

      case _CaptureState.permDenied:
        return _PermDeniedWidget(
          message: _errorMessage ?? 'Microphone permission required.',
          onGrant: _startRecording,
        );

      case _CaptureState.recording:
        return _RecordingWidget(
          durationS: _durationS,
          maxDurationS: _kMaxDurationS,
          amplitude: _amplitude,
          onStop: _stopRecording,
          onCancel: _cancel,
        );

      case _CaptureState.processing:
        return const _ProcessingWidget();

      case _CaptureState.ready:
        return _ReadyWidget(
          audioRef: _audioRef ?? 'aud-?',
          durationS: _durationS,
          onRetake: _retry,
        );

      case _CaptureState.error:
        return _ErrorWidget(
          message: _errorMessage ?? 'An unknown error occurred.',
          onRetry: _retry,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _IdleWidget extends StatelessWidget {
  const _IdleWidget({required this.onRecord});
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.mic_none, size: 56, color: Colors.black45),
        const SizedBox(height: 12),
        const Text(
          'Tap to start recording',
          style: TextStyle(fontSize: 15, color: Colors.black54),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRecord,
          icon: const Icon(Icons.mic),
          label: const Text('Start recording'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _PermDeniedWidget extends StatelessWidget {
  const _PermDeniedWidget({required this.message, required this.onGrant});
  final String message;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.mic_off, size: 56, color: Colors.red),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onGrant,
          icon: const Icon(Icons.settings),
          label: const Text('Grant microphone permission'),
        ),
      ],
    );
  }
}

class _RecordingWidget extends StatelessWidget {
  const _RecordingWidget({
    required this.durationS,
    required this.maxDurationS,
    required this.amplitude,
    required this.onStop,
    required this.onCancel,
  });

  final double durationS;
  final double maxDurationS;
  final double amplitude;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  String _fmt(double s) {
    final total = s.toInt();
    final mm = total ~/ 60;
    final ss = total % 60;
    return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = (durationS / maxDurationS).clamp(0.0, 1.0);

    return Column(
      children: [
        // Pulsing mic icon.
        _PulsingMic(amplitude: amplitude),
        const SizedBox(height: 12),

        // Duration / max.
        Text(
          '${_fmt(durationS)}  /  ${_fmt(maxDurationS)}',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),

        // Progress bar.
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.red.shade100,
            color: progress >= 0.9 ? Colors.red.shade900 : Colors.red.shade600,
          ),
        ),
        const SizedBox(height: 8),

        // Amplitude bar.
        _AmplitudeBar(amplitude: amplitude),
        const SizedBox(height: 16),

        // Stop + Cancel.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(foregroundColor: Colors.black54),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PulsingMic extends StatefulWidget {
  const _PulsingMic({required this.amplitude});
  final double amplitude;

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 48.0 + widget.amplitude * 24.0;
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.shade600,
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 28),
      ),
    );
  }
}

class _AmplitudeBar extends StatelessWidget {
  const _AmplitudeBar({required this.amplitude});
  final double amplitude;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final width = constraints.maxWidth;
        // Show 20 bars, height driven by amplitude + some baseline noise.
        const barCount = 20;
        final barWidth = (width - (barCount - 1) * 2) / barCount;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(barCount, (i) {
            // Centre bars taller than edges to create a waveform shape.
            final centreBoost = 1.0 - (i - barCount / 2).abs() / (barCount / 2);
            final barHeight =
                (amplitude * 32 * centreBoost + 4).clamp(4.0, 40.0);
            return Container(
              width: barWidth,
              height: barHeight,
              margin: i < barCount - 1
                  ? const EdgeInsets.only(right: 2)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ProcessingWidget extends StatelessWidget {
  const _ProcessingWidget();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 12),
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Encoding audio…', style: TextStyle(color: Colors.black54)),
        SizedBox(height: 12),
      ],
    );
  }
}

class _ReadyWidget extends StatelessWidget {
  const _ReadyWidget({
    required this.audioRef,
    required this.durationS,
    required this.onRetake,
  });

  final String audioRef;
  final double durationS;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Saved: $audioRef  (${durationS.toStringAsFixed(1)} s)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onRetake,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retake'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.black54,
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  const _ErrorWidget({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.error_outline, size: 48, color: Colors.red.shade600),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

class _NotSupportedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          const Icon(Icons.mic_off, size: 48, color: Colors.black26),
          const SizedBox(height: 8),
          const Text(
            'Audio capture is not available',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black45),
          ),
          const SizedBox(height: 4),
          Text(
            'This feature requires the Android app. '
            'Tap Skip to continue to the text notes screen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final MaterialColor color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color.shade900, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
