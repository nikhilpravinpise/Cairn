/// Structured performance logging for Cairn model inference turns.
///
/// Emits `[Cairn/perf]` log lines that complement the native `[*/perf]` lines
/// emitted by flutter_gemma >=0.14.2. Both sets appear in `adb logcat` under
/// the same `/perf` filter, giving a complete timing profile that spans:
///
///   native (flutter_gemma 0.14.2+)   Dart (this module)
///   ─────────────────────────────── ─────────────────────────────────────────
///   dylib load                       —
///   [GemmaSession/perf] engine_create  phase=engine_create
///   [InferenceModel/perf] prefill      phase=generate ttft=…
///   [InferenceModel/perf] decode       phase=generate wall=…
///
/// ## Log line format
///
/// ```
/// phase=install          wall=1234ms
/// phase=engine_create    wall=2341ms
/// phase=generate         task=describe_photo  wall=3456ms ttft=1234ms out_chars=156 img_bytes=98304
/// phase=generate         task=synthesize      wall=5678ms ttft=3456ms out_chars=420 thinking_chars=1024
/// ```
///
/// ## Capture
///
/// See `tool/capture_perf_log.ps1` (Windows) or `tool/capture_perf_log.sh`
/// (macOS/Linux) for ready-to-run `adb logcat` capture scripts.
///
/// Quick one-liner (all /perf lines from both flutter_gemma and Cairn):
/// ```
/// adb -s RZCX920ARVA logcat -v time | grep --line-buffered "/perf"
/// ```
library;

import 'package:flutter/foundation.dart';

/// A single timing event from the model install, engine creation, or
/// inference path.
class PerfEvent {
  const PerfEvent({
    required this.phase,
    required this.wallclockMs,
    this.task,
    this.ttftMs,
    this.outputCharCount,
    this.thinkingChars = 0,
    this.imageSizeBytes,
  });

  /// Lifecycle phase: `'install'` | `'engine_create'` | `'generate'`.
  final String phase;

  /// Wall-clock duration for this phase in milliseconds.
  final int wallclockMs;

  /// Orchestrator task name (e.g. `'describe_photo'`).
  /// `null` for task-agnostic phases such as `install` and `engine_create`.
  final String? task;

  /// Time-to-first-token in milliseconds. Meaningful only for `'generate'`.
  final int? ttftMs;

  /// Number of UTF-16 code units in the generated text (excluding thinking).
  /// Meaningful only for `'generate'`.
  final int? outputCharCount;

  /// Number of UTF-16 code units in the thinking excerpt.
  /// `0` when the session was not opened with `isThinking: true`.
  final int thinkingChars;

  /// Byte size of the image passed to inference. `null` when no image.
  final int? imageSizeBytes;

  /// Formats the event as a single `[Cairn/perf]` log line.
  ///
  /// Fields are ordered: phase, task?, wall, ttft?, out_chars?, thinking_chars?,
  /// img_bytes?. Only non-null / non-zero optional fields are included.
  String format() {
    final buf = StringBuffer('phase=$phase');
    if (task != null) buf.write(' task=$task');
    buf.write(' wall=${wallclockMs}ms');
    if (ttftMs != null) buf.write(' ttft=${ttftMs}ms');
    if (outputCharCount != null) buf.write(' out_chars=$outputCharCount');
    if (thinkingChars > 0) buf.write(' thinking_chars=$thinkingChars');
    if (imageSizeBytes != null) buf.write(' img_bytes=$imageSizeBytes');
    return buf.toString();
  }
}

/// Emits [PerfEvent]s as structured `[Cairn/perf]` lines via [debugPrint].
///
/// On Android, [debugPrint] flows to `adb logcat` under the `flutter` tag,
/// alongside flutter_gemma's own `[*/perf]` lines. A single `grep '/perf'`
/// filter captures the complete timing profile from both sources.
///
/// All methods are static; [PerfLogger] has no instance state.
class PerfLogger {
  PerfLogger._();

  /// Emits [event] via [debugPrint].
  ///
  /// The output format is `[Cairn/perf] <event.format()>`, which matches the
  /// `[FfiInferenceModel/perf]`, `[FfiInferenceModelSession/perf]`, and
  /// `[LiteRtLmFfi/perf]` lines emitted by flutter_gemma 0.14.3+. A single
  /// `grep '/perf'` filter on `adb logcat` captures all of them together.
  static void emit(PerfEvent event) =>
      debugPrint('[Cairn/perf] ${event.format()}');
}
