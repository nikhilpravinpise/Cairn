/// Single LLM inference turn — provenance record for `turns.jsonl`.
///
/// Lives in the LLM layer (`core/llm/`) so [GemmaOrchestrator] can build and
/// emit [TurnRecord]s in [DescribePhotoEvent.succeeded] without depending on
/// `core/state/session_controller.dart` (which in turn imports orchestrator,
/// creating a circular dependency if we went the other way).
///
/// [SessionController] re-exports this class via
/// `export '../llm/turn_record.dart' show TurnRecord` so all existing
/// imports of `session_controller.dart` continue to resolve [TurnRecord]
/// without any call-site changes.
library;

/// Records a single LLM inference turn for `turns.jsonl` provenance logging.
///
/// Written by [GemmaOrchestrator.describeAll] (for photo turns) and by
/// screens directly for other tasks (ask_followup, synthesize). Persisted to
/// `turns.jsonl` during [SessionController.sealAndSave].
class TurnRecord {
  const TurnRecord({
    required this.ts,
    required this.task,
    this.observationId,
    required this.ttftMs,
    required this.wallclockMs,
    required this.outputCharCount,
    this.thinkingChars = 0,
  });

  /// UTC timestamp when the turn started.
  final DateTime ts;

  /// Orchestrator task name, e.g. `'describe_photo'`, `'synthesize'`.
  final String task;

  /// Links the turn to a [Observation.observationId], if applicable.
  final String? observationId;

  /// Time-to-first-token in milliseconds.
  final int ttftMs;

  /// Wall-clock duration of the full generation in milliseconds.
  final int wallclockMs;

  /// Number of output characters (excluding thinking text).
  final int outputCharCount;

  /// Number of characters in the thinking excerpt, or 0 if not a thinking turn.
  final int thinkingChars;

  Map<String, Object?> toJson() => {
        'ts': ts.toUtc().toIso8601String(),
        'task': task,
        if (observationId != null) 'observation_id': observationId,
        'ttft_ms': ttftMs,
        'wallclock_ms': wallclockMs,
        'output_char_count': outputCharCount,
        if (thinkingChars > 0) 'thinking_chars': thinkingChars,
      };

  factory TurnRecord.fromJson(Map<String, Object?> j) => TurnRecord(
        ts: DateTime.parse(j['ts'] as String).toUtc(),
        task: j['task'] as String,
        observationId: j['observation_id'] as String?,
        ttftMs: (j['ttft_ms'] as num).toInt(),
        wallclockMs: (j['wallclock_ms'] as num).toInt(),
        outputCharCount: (j['output_char_count'] as num).toInt(),
        thinkingChars: (j['thinking_chars'] as num?)?.toInt() ?? 0,
      );
}
