/// Per-profile inference configuration.
///
/// Moves hardcoded values (`maxTokens`, `temperature`, `topK`, `topP`,
/// `preferredBackend`, `maxNumImages`, `clearHistoryBetweenTurns`) out of
/// [GemmaSession] into a single, testable configuration module.
///
/// ## Production defaults
///
/// Vision, audio, and standard profiles use `maxTokens: 4096` and
/// `temperature: 0.1`. The system prompt Rule 11 constrains output to max
/// 3 sentences / 60 words, but 4096 tokens prevents truncation edge cases
/// in longer vision responses. Synthesis stays at `maxTokens: 4096` /
/// `temperature: 0.2` because reasoning-mode output benefits from moderate
/// stochasticity.
///
/// ## Benchmark variants
///
/// Named constants below are benchmark candidates for Sprints 2–4.
/// Pass them to [GemmaSessionNotifier.load] via the optional `config`
/// parameter, then capture `[*/perf]` and `turns.jsonl` evidence on the
/// device. Benchmark scripts in `tool/` drive the variants automatically.
///
/// ## Benchmark matrix
///
/// ### Sprint 2 — token budget + temperature
/// | Variant constant        | maxTokens | temperature | clearHistory | Notes                      |
/// |-------------------------|-----------|-------------|:------------:|----------------------------|
/// | `SessionConfig.vision`  | 4096      | 0.1         | true         | Production baseline         |
/// | `visionMaxTokens3072`   | 3072      | 0.1         | true         | Candidate — must not trunc |
/// | `visionMaxTokens2048`   | 2048      | 0.1         | true         | Candidate — must not trunc |
/// | `visionTemp01`          | 4096      | 0.05        | true         | Candidate — near-greedy    |
/// | `SessionConfig.standard`| 4096      | 0.1         | true         | Baseline protocol/followup |
/// | `standardTemp01`        | 4096      | 0.05        | true         | Candidate — JSON mapping   |
///
/// ### Sprint 4 OPT-5 — history retention A/B
/// | Variant constant          | clearHistory | Notes                              |
/// |---------------------------|:------------:|------------------------------------|
/// | `visionHistoryRetained`   | **false**    | No clear between photo turns       |
///
/// Gate: compare prefill/TTFT and monitor for cross-photo contamination.
/// Do not remove the default `clearHistoryBetweenTurns: true` from production
/// until the device gate confirms: (a) no cross-photo output contamination,
/// (b) TTFT/prefill improves materially, (c) contract failure rate unchanged.
///
/// ### Sprint 4 OPT-6 — CPU/GPU backend diagnostic
/// | Variant constant   | preferredBackend | Notes                       |
/// |--------------------|:----------------:|-----------------------------|
/// | `visionCpu`        | cpu              | Vision turns on CPU         |
/// | `synthesisCpu`     | cpu              | Synthesis turns on CPU      |
/// | `standardCpu`      | cpu              | Protocol/followup on CPU    |
///
/// Synthesis: keep temperature at 0.2; reasoning-mode output benefits from
/// some stochasticity. Lower only after separate synthesis benchmark run.
library;

import 'package:flutter_gemma/flutter_gemma.dart';

/// Inference configuration for a single [GemmaSession].
///
/// All fields are immutable. Use the per-profile static constants as the
/// starting point; override only for benchmarking. Use [copyWith] to apply
/// single-field overrides (e.g., `BENCH_BACKEND=cpu`) without re-specifying
/// every field.
class SessionConfig {
  const SessionConfig({
    required this.maxTokens,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.preferredBackend,
    required this.maxNumImages,
    this.clearHistoryBetweenTurns = true,
  });

  /// Maximum input + output tokens for the engine.
  ///
  /// MediaPipe / LiteRT-LM uses this for KV cache sizing. Lowering the value
  /// reduces peak memory and engine-create time, but risks truncation if the
  /// system prompt + image tokens + user JSON + output exceed the budget.
  /// Do not lower below the measured safe value (see Sprint 2 benchmark matrix).
  final int maxTokens;

  /// Sampling temperature. Higher values increase output diversity.
  ///
  /// 0.2 is the current production value for all profiles. 0.1 is the
  /// benchmark candidate for `vision` and `standard` (more deterministic,
  /// better JSON contract adherence). Do not lower synthesis below 0.2.
  final double temperature;

  /// Top-k sampling parameter.
  final int topK;

  /// Top-p (nucleus) sampling parameter.
  final double topP;

  /// Hardware backend for the LiteRT-LM engine.
  ///
  /// [PreferredBackend.gpu] on Exynos 2200 (`SM-S711B`). Switch to
  /// [PreferredBackend.cpu] only after a per-turn device benchmark confirms
  /// CPU is competitive (see Sprint 4 OPT-6, `tool/benchmark_backend.ps1`).
  final PreferredBackend preferredBackend;

  /// Maximum images the model and chat were created to accept per turn.
  ///
  /// Vision profile uses 5 to support the full required-photo slot set.
  /// All other profiles use 1 (no multimodal input expected).
  final int maxNumImages;

  /// Whether [GemmaSession] calls `chat.clearHistory()` after every turn.
  ///
  /// **Production default: `true`.** Clearing after each turn ensures that
  /// consecutive `describe_photo` turns cannot reference prior photos in their
  /// output — critical for independent, schema-valid observations.
  ///
  /// Set to `false` only for the Sprint 4 OPT-5 history-retention A/B
  /// benchmark (`visionHistoryRetained`). Do not disable in production until
  /// the device gate confirms: (a) no cross-photo output contamination,
  /// (b) prefill/TTFT improves materially.
  final bool clearHistoryBetweenTurns;

  // ---------------------------------------------------------------------------
  // Production defaults
  // ---------------------------------------------------------------------------

  /// Vision profile — `describe_photo` turns.
  ///
  /// `maxTokens: 4096` matches the synthesis profile ceiling. The system
  /// prompt (~500 tokens) + image tokens (~1800 tokens at 768 px) + user JSON
  /// (~200 tokens) sum to ~2695 tokens on device, which exceeds the former
  /// 2048 KV cache limit and causes INVALID_ARGUMENT errors in the engine.
  /// `temperature: 0.1` improves JSON contract adherence and output
  /// determinism for structured describe_photo responses.
  static const vision = SessionConfig(
    maxTokens: 4096,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 5,
  );

  /// Audio profile — `describe_audio` turns.
  /// Same token budget as vision — audio prompt + context can also exceed 2048.
  static const audio = SessionConfig(
    maxTokens: 4096,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 1,
  );

  /// Synthesis profile — `synthesize` turns with thinking mode.
  ///
  /// Do not lower temperature for synthesis; the reasoning output benefits
  /// from moderate stochasticity for coverage of uncertainty notes.
  static const synthesis = SessionConfig(
    maxTokens: 4096,
    temperature: 0.2,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 1,
  );

  /// Standard profile — `protocol_answer` and `ask_followup` turns.
  /// `temperature: 0.1` for better JSON-mapping determinism.
  static const standard = SessionConfig(
    maxTokens: 4096,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 1,
  );

  // ---------------------------------------------------------------------------
  // Sprint 2 benchmark variants
  // Do NOT promote to production until device evidence confirms:
  //   (a) no output truncation, (b) no contract regression.
  // Run: tool/benchmark_session_config.ps1 -Variant <name>
  // ---------------------------------------------------------------------------

  /// Vision — maxTokens 3072 benchmark candidate.
  ///
  /// Tests a midpoint KV cache budget (50% larger than production 2048).
  /// Useful if any prompt exceeds the 2048 budget.
  static const visionMaxTokens3072 = SessionConfig(
    maxTokens: 3072,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 5,
  );

  /// Vision — legacy maxTokens 2048 benchmark entry.
  ///
  /// Downward benchmark candidate (production [vision] uses maxTokens 4096).
  /// Kept for backward compatibility with benchmark scripts.
  static const visionMaxTokens2048 = SessionConfig(
    maxTokens: 2048,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 5,
  );

  /// Vision — temperature 0.05 benchmark candidate.
  ///
  /// Near-greedy sampling. Compare `GemmaContractError` rate and
  /// output brevity against production `vision` (0.1).
  static const visionTemp01 = SessionConfig(
    maxTokens: 4096,
    temperature: 0.05,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 5,
  );

  /// Standard — temperature 0.05 benchmark candidate.
  ///
  /// Near-greedy for JSON-mapping tasks.
  static const standardTemp01 = SessionConfig(
    maxTokens: 4096,
    temperature: 0.05,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 1,
  );

  // ---------------------------------------------------------------------------
  // Sprint 4 OPT-5 — history retention A/B
  // Run: tool/benchmark_session_config.ps1 -Variant vision_history_retained
  // Gate: zero cross-photo contamination + TTFT improvement before promoting.
  // ---------------------------------------------------------------------------

  /// Vision — history retention A/B benchmark candidate.
  ///
  /// Identical to production [vision] but with `clearHistoryBetweenTurns: false`.
  /// Retaining history between sequential `describe_photo` turns may reduce
  /// repeated system-prompt prefill cost; however it risks cross-photo output
  /// contamination where the model references a prior photo in the next turn.
  ///
  /// **Do not promote to production until the device gate passes:**
  /// - prefill/TTFT improves materially on 5 sequential photos.
  /// - No observation references a prior photo incorrectly.
  /// - `GemmaContractError` rate does not increase on the held-out photo set.
  ///
  /// OPT-5 requires flutter_gemma >=0.14.2 (Gemma 4 escape-token leakage fix).
  static const visionHistoryRetained = SessionConfig(
    maxTokens: 4096,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.gpu,
    maxNumImages: 5,
    clearHistoryBetweenTurns: false,
  );

  // ---------------------------------------------------------------------------
  // Sprint 4 OPT-6 — CPU/GPU backend diagnostic
  // Run: tool/benchmark_backend.ps1
  // Gate: device benchmark proves CPU is competitive with GPU on Exynos 2200.
  // ---------------------------------------------------------------------------

  /// Vision — CPU backend benchmark candidate.
  ///
  /// Replaces [PreferredBackend.gpu] with [PreferredBackend.cpu] for vision
  /// turns. Compare `[*/perf]` engine_create, prefill, and decode against
  /// the production [vision] baseline. On Exynos 2200 (`SM-S711B`) GPU is
  /// expected to be faster for multimodal inference, but this must be proven.
  static const visionCpu = SessionConfig(
    maxTokens: 4096,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.cpu,
    maxNumImages: 5,
  );

  /// Synthesis — CPU backend benchmark candidate.
  ///
  /// Replaces [PreferredBackend.gpu] with [PreferredBackend.cpu] for synthesis
  /// turns (thinking mode). Compare prefill/decode timing against production
  /// [synthesis] baseline.
  static const synthesisCpu = SessionConfig(
    maxTokens: 4096,
    temperature: 0.2,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.cpu,
    maxNumImages: 1,
  );

  /// Standard — CPU backend benchmark candidate.
  static const standardCpu = SessionConfig(
    maxTokens: 4096,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
    preferredBackend: PreferredBackend.cpu,
    maxNumImages: 1,
  );

  // ---------------------------------------------------------------------------
  // Derived helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` when [maxTokens] is within the measured-safe range.
  ///
  /// Minimum of 2048 is the floor for the benchmark matrix (the production
  /// default is 4096 after the Sprint 5 token-overflow fix). Maximum is the
  /// MediaPipe LLM Inference ceiling (varies by model; 4096 is the current
  /// cap for E2B). Values below 2048 have not been tested.
  bool get isTokenBudgetInSafeRange => maxTokens >= 2048 && maxTokens <= 4096;

  /// Returns a copy of this config with the specified fields replaced.
  ///
  /// Used by [providers.dart] to apply `BENCH_BACKEND` and similar dart-define
  /// overrides without re-specifying every field at the call site.
  SessionConfig copyWith({
    int? maxTokens,
    double? temperature,
    int? topK,
    double? topP,
    PreferredBackend? preferredBackend,
    int? maxNumImages,
    bool? clearHistoryBetweenTurns,
  }) =>
      SessionConfig(
        maxTokens: maxTokens ?? this.maxTokens,
        temperature: temperature ?? this.temperature,
        topK: topK ?? this.topK,
        topP: topP ?? this.topP,
        preferredBackend: preferredBackend ?? this.preferredBackend,
        maxNumImages: maxNumImages ?? this.maxNumImages,
        clearHistoryBetweenTurns:
            clearHistoryBetweenTurns ?? this.clearHistoryBetweenTurns,
      );

  /// Human-readable summary for logcat / debug screens.
  String toLogString() =>
      'maxTokens=$maxTokens temperature=$temperature '
      'topK=$topK topP=$topP backend=$preferredBackend '
      'maxNumImages=$maxNumImages clearHistory=$clearHistoryBetweenTurns';

  @override
  String toString() => 'SessionConfig(${toLogString()})';
}
