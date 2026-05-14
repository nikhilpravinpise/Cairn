/// Single import for app-wide Riverpod providers.
///
/// Screens depend on this file; never on the concrete implementations behind
/// it. The vault and draft-persistence providers use conditional exports so the
/// file-backed implementations are wired on native targets automatically.
///
/// ## Benchmark dart-defines
///
/// Three dart-defines activate benchmark variants at build time. All default
/// to their production values when not set, so release builds are unaffected.
///
/// ### BENCH_CONFIG — SessionConfig variant selector
///
/// Selects a named [SessionConfig] constant for all sessions loaded during
/// the benchmark run. Only the first matching profile wins; profiles not
/// targeted by the variant use their production defaults.
///
/// ```powershell
/// flutter run --profile -d RZCX920ARVA --dart-define=BENCH_CONFIG=vision_history_retained
/// ```
///
/// Supported values: `vision_3072`, `vision_2048`, `vision_temp01`,
/// `std_temp01`, `vision_history_retained`, `vision_single_image`,
/// `vision_cpu`, `synthesis_cpu`, `standard_cpu`.
///
/// ### BENCH_IMAGE_PX — inference image longest-edge override (Sprint 3)
///
/// Overrides the [BoundedImagePreprocessor.maxLongEdgePx] used in
/// [orchestratorProvider] for the Sprint 3 image-size benchmark.
///
/// ```powershell
/// flutter run --profile -d RZCX920ARVA --dart-define=BENCH_IMAGE_PX=512
/// ```
///
/// Supported values:
/// - `0` (default): use `spec.inferenceMaxLongEdgePx` (currently 640).
/// - `-1`: passthrough — raw capture bytes, no downscaling.
/// - Any positive integer: bound longest edge to that many pixels.
///
/// ### BENCH_NATIVE_IMAGE_PREPROCESS — Android native JPEG sidecar
///
/// Defaults to `true` on Android. Set to `false` to benchmark the legacy Dart
/// PNG resize path.
///
/// ### BENCH_BACKEND — hardware backend override (Sprint 4 OPT-6)
///
/// Overrides [PreferredBackend] for every session loaded during the run.
/// Combine with `BENCH_CONFIG` to target a specific profile.
///
/// ```powershell
/// flutter run --profile -d RZCX920ARVA --dart-define=BENCH_BACKEND=cpu
/// ```
///
/// Supported values: `cpu`, `gpu` (default when not set).
///
/// ### INFERENCE_RUNTIME / BENCH_RUNTIME — runtime selector
///
/// `flutter_gemma` is the production default. With flutter_gemma >=0.15.0,
/// `BENCH_MTP=true` requests official LiteRT-LM speculative decoding through
/// `getActiveModel(enableSpeculativeDecoding: true)`.
///
/// ### BENCH_BATCH / BENCH_MTP
///
/// `native_mtp` enables the legacy Android LiteRT-LM bridge for diagnostics.
/// `BENCH_BATCH=true` enables the native multi-image batch experiment when the
/// selected runtime is `native_mtp`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'images/image_preprocessor.dart';
import 'llm/fake_gemma_session.dart';
import 'llm/gemma_session.dart';
import 'llm/inference_runtime.dart';
import 'llm/model_registry.dart';
import 'llm/native_mtp_session.dart';
import 'llm/orchestrator.dart';
import 'llm/session_config.dart';
import 'state/session_controller.dart';
import 'storage/draft_persistence.dart';
import 'storage/evidence_vault.dart';
import 'storage/file_draft_persistence.dart';
import 'storage/file_evidence_vault.dart';
import 'storage/storage_health.dart';

// ---------------------------------------------------------------------------
// Benchmark dart-define constants
//
// These are compile-time constants: they resolve to their default values in
// release/production builds and carry zero runtime overhead when not set.
// ---------------------------------------------------------------------------

/// BENCH_CONFIG selects a named [SessionConfig] benchmark variant.
/// Empty string = production defaults.
const _kBenchConfig = String.fromEnvironment('BENCH_CONFIG', defaultValue: '');

/// BENCH_IMAGE_PX overrides the inference image longest-edge bound.
/// 0 = use spec default (production). -1 = passthrough. >0 = explicit bound.
const _kBenchImagePx = int.fromEnvironment('BENCH_IMAGE_PX', defaultValue: 0);

/// BENCH_BACKEND overrides the [PreferredBackend] for all sessions.
/// Empty string = gpu (production). 'cpu' = force CPU.
const _kBenchBackend =
    String.fromEnvironment('BENCH_BACKEND', defaultValue: '');

const _kInferenceRuntime =
    String.fromEnvironment('INFERENCE_RUNTIME', defaultValue: '');

const _kBenchRuntime =
    String.fromEnvironment('BENCH_RUNTIME', defaultValue: '');

const _kBenchBatch = bool.fromEnvironment('BENCH_BATCH', defaultValue: false);

/// MTP (speculative decoding) is ON by default in all builds.
/// Sessions 3-4 confirmed zero schema failures and +33% decode speedup on
/// SM-S711B (Exynos 2200). Opt out with --dart-define=BENCH_MTP=false.
const _kBenchMtp = bool.fromEnvironment('BENCH_MTP', defaultValue: true);

const _kNativeImagePreprocess =
    bool.fromEnvironment('BENCH_NATIVE_IMAGE_PREPROCESS', defaultValue: true);

/// DEV_SKIP_MODEL=true replaces every Gemma session with [FakeGemmaSession].
///
/// Use this during UI / flow development to bypass the 4 GB model download
/// and LiteRT engine creation entirely. The fake returns canned JSON that
/// passes all contract validators so the full photo → protocol → synthesize
/// → report flow runs end-to-end in seconds.
///
/// ```bash
/// flutter run -d emulator-5554 --dart-define=DEV_SKIP_MODEL=true
/// flutter run -d chrome        --dart-define=DEV_SKIP_MODEL=true
/// ```
///
/// This constant is false in all production / release builds.
const _kDevSkipModel =
    bool.fromEnvironment('DEV_SKIP_MODEL', defaultValue: false);

final selectedInferenceRuntimeProvider = Provider<InferenceRuntime>((_) {
  return inferenceRuntimeFromDefines(
    inferenceRuntime: _kInferenceRuntime,
    benchRuntime: _kBenchRuntime,
  );
});

/// Maps a [benchKey] string to a [SessionConfig] for the given [profile].
///
/// Returns `null` when [benchKey] is empty (production path) or unknown, so
/// the session load falls through to its per-profile production default.
///
/// Only session-config variants are mapped here; image-px and backend
/// overrides are applied separately after this lookup.
SessionConfig? _benchConfigForKey(String benchKey) {
  if (benchKey.isEmpty) return null;
  return switch (benchKey) {
    'vision_3072' => SessionConfig.visionMaxTokens3072,
    'vision_2048' => SessionConfig.visionMaxTokens2048,
    'vision_temp01' => SessionConfig.visionTemp01,
    'std_temp01' => SessionConfig.standardTemp01,
    'vision_history_retained' => SessionConfig.visionHistoryRetained,
    'vision_single_image' => SessionConfig.visionSingleImage,
    'vision_cpu' => SessionConfig.visionCpu,
    'synthesis_cpu' => SessionConfig.synthesisCpu,
    'standard_cpu' => SessionConfig.standardCpu,
    _ => null,
  };
}

/// Applies the [_kBenchBackend] override to [cfg] if `BENCH_BACKEND=cpu`.
///
/// Returns [cfg] unchanged when [_kBenchBackend] is empty or `'gpu'`.
SessionConfig _applyBenchBackend(SessionConfig cfg) {
  if (_kBenchBackend != 'cpu') return cfg;
  return cfg.copyWith(preferredBackend: PreferredBackend.cpu);
}

/// Locked system prompt — loaded once from `assets/prompts/system_prompt_v1.txt`.
final systemPromptProvider = FutureProvider<String>((ref) async {
  return rootBundle.loadString('assets/prompts/system_prompt_v1.txt');
});

/// Currently-selected model. The user can change it on the Start screen
/// before any session begins; locked once a session is in progress.
final selectedModelKeyProvider = StateProvider<String>((_) => 'e2b');

final selectedModelSpecProvider = Provider<ModelSpec>((ref) {
  final key = ref.watch(selectedModelKeyProvider);
  final spec = models[key];
  if (spec == null) {
    throw StateError('unknown model key $key — see model_registry.dart');
  }
  return spec;
});

final inferenceImageMaxLongEdgePxProvider = Provider<int?>((ref) {
  final spec = ref.watch(selectedModelSpecProvider);
  return switch (_kBenchImagePx) {
    -1 => null,
    0 => spec.inferenceMaxLongEdgePx,
    _ => _kBenchImagePx,
  };
});

final inferenceImagePreprocessorProvider = Provider<ImagePreprocessor>((ref) {
  final maxLongEdgePx = ref.watch(inferenceImageMaxLongEdgePxProvider);
  final ImagePreprocessor basePreprocessor = switch (maxLongEdgePx) {
    null => const PassthroughImagePreprocessor(),
    final px => _boundedPreprocessor(px),
  };
  return CachingImagePreprocessor(basePreprocessor);
});

final uncachedInferenceImagePreprocessorProvider =
    Provider<ImagePreprocessor>((ref) {
  final maxLongEdgePx = ref.watch(inferenceImageMaxLongEdgePxProvider);
  return switch (maxLongEdgePx) {
    null => const PassthroughImagePreprocessor(),
    final px => _boundedPreprocessor(px),
  };
});

ImagePreprocessor _boundedPreprocessor(int maxLongEdgePx) {
  if (!_kNativeImagePreprocess) {
    return BoundedImagePreprocessor(maxLongEdgePx: maxLongEdgePx);
  }
  return AndroidJpegImagePreprocessor(maxLongEdgePx: maxLongEdgePx);
}

/// Capability profile to pass when loading a [GemmaSession].
///
/// Each value maps to a named factory on [GemmaSession] that requests only
/// the model and chat flags required for that task group:
///
/// | Profile   | supportImage | supportAudio | isThinking | Task(s)              |
/// |-----------|:---:|:---:|:---:|-----------------------------|
/// | vision    |  ✓  |     |     | describe_photo              |
/// | audio     |     |  ✓  |     | describe_audio              |
/// | synthesis |     |     |  ✓  | synthesize                  |
/// | standard  |     |     |     | protocol_answer, ask_followup |
enum SessionProfile {
  /// `describe_photo` turns: image=true, audio=false, thinking=false.
  vision,

  /// `describe_audio` turns: image=false, audio=true, thinking=false.
  audio,

  /// `synthesize` turns: image=false, audio=false, thinking=true.
  synthesis,

  /// `protocol_answer` / `ask_followup` turns: all capabilities off.
  standard,
}

/// Holds the live Gemma session. `null` until the user clicks "Load model"
/// on the Start screen. Disposed on app shutdown by Riverpod.
class GemmaSessionNotifier extends Notifier<GemmaSessionInterface?> {
  @override
  GemmaSessionInterface? build() {
    ref.onDispose(() async {
      await _close(state);
    });
    return null;
  }

  /// Load (or reload) the active Gemma session with an optional [config]
  /// override for benchmarking. When [config] is `null` (the normal production
  /// path) each profile uses its own `SessionConfig.<profile>` default, unless
  /// a `BENCH_CONFIG` dart-define selects a named benchmark variant and/or
  /// `BENCH_BACKEND=cpu` forces the CPU backend.
  Future<void> load({
    SessionProfile profile = SessionProfile.vision,
    SessionConfig? config,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) async {
    final previous = state;
    state = null;
    await _close(previous);
    final spec = ref.read(selectedModelSpecProvider);
    final sys = await ref.read(systemPromptProvider.future);
    final runtime = ref.read(selectedInferenceRuntimeProvider);

    // DEV_SKIP_MODEL: bypass all real model loading for UI development.
    if (_kDevSkipModel) {
      debugPrint(
          '[Cairn/DEV_SKIP_MODEL] load() skipped — using FakeGemmaSession');
      state = const FakeGemmaSession();
      return;
    }

    // Benchmark override chain (compile-time constants — zero cost in release):
    //   1. Explicit caller-supplied config takes highest priority.
    //   2. BENCH_CONFIG selects a named SessionConfig variant.
    //   3. Per-profile production default.
    //   4. BENCH_BACKEND applies a backend-only override on top of whichever
    //      config was selected in steps 1–3.
    SessionConfig resolved(SessionConfig productionDefault) =>
        _applyBenchBackend(
            config ?? _benchConfigForKey(_kBenchConfig) ?? productionDefault);

    // native_mtp is a dev-only runtime gated behind
    //   --dart-define=INFERENCE_RUNTIME=native_mtp
    // It is never reachable in production / release builds unless that define
    // is explicitly set. Any PlatformException from the Kotlin bridge is caught
    // here and re-thrown as a user-readable message so the caller can surface
    // a SnackBar instead of silently hanging.
    try {
      if (runtime == InferenceRuntime.nativeMtp) {
        state = switch (profile) {
          SessionProfile.vision => await NativeMtpGemmaSession.openForVision(
              spec,
              systemPrompt: sys,
              config: resolved(SessionConfig.vision),
              enableMtp: _kBenchMtp,
              loraPath: loraPath,
              onProgress: onProgress,
            ),
          SessionProfile.synthesis =>
            await NativeMtpGemmaSession.openForSynthesis(
              spec,
              systemPrompt: sys,
              config: resolved(SessionConfig.synthesis),
              enableMtp: _kBenchMtp,
              loraPath: loraPath,
              onProgress: onProgress,
            ),
          _ => throw UnsupportedError(
              'native_mtp does not support the $profile profile.'),
        };
        return;
      }
    } on PlatformException catch (e) {
      debugPrint(
          '[Cairn/native_mtp] PlatformException — ${e.code}: ${e.message}');
      throw Exception(
        'native_mtp runtime error (${e.code}): ${e.message ?? "unknown"}. '
        'Rebuild without --dart-define=INFERENCE_RUNTIME=native_mtp to use '
        'the stable flutter_gemma runtime.',
      );
    }

    state = switch ((runtime, profile)) {
      (InferenceRuntime.nativeMtp, _) =>
        // Should be unreachable after the try-block above, but keeps the
        // switch exhaustive for the type-checker.
        throw StateError('native_mtp load reached unreachable fallthrough'),
      (_, SessionProfile.vision) => await GemmaSession.openForVision(
          spec,
          systemPrompt: sys,
          config: resolved(SessionConfig.vision),
          enableSpeculativeDecoding: _kBenchMtp,
          loraPath: loraPath,
          onProgress: onProgress,
        ),
      (_, SessionProfile.audio) => await GemmaSession.openForAudio(
          spec,
          systemPrompt: sys,
          config: resolved(SessionConfig.audio),
          enableSpeculativeDecoding: _kBenchMtp,
          loraPath: loraPath,
          onProgress: onProgress,
        ),
      (_, SessionProfile.synthesis) => await GemmaSession.openForSynthesis(
          spec,
          systemPrompt: sys,
          config: resolved(SessionConfig.synthesis),
          enableSpeculativeDecoding: _kBenchMtp,
          loraPath: loraPath,
          onProgress: onProgress,
        ),
      (_, SessionProfile.standard) => await GemmaSession.openStandard(
          spec,
          systemPrompt: sys,
          config: resolved(SessionConfig.standard),
          enableSpeculativeDecoding: _kBenchMtp,
          loraPath: loraPath,
          onProgress: onProgress,
        ),
    };
  }

  Future<void> unload() async {
    await _close(state);
    state = null;
  }

  Future<void> _close(GemmaSessionInterface? session) async {
    if (session is GemmaSession) {
      await session.close();
    } else if (session is NativeMtpGemmaSession) {
      await session.close();
    }
    // FakeGemmaSession and null: no teardown needed.
  }
}

final gemmaSessionProvider =
    NotifierProvider<GemmaSessionNotifier, GemmaSessionInterface?>(
        GemmaSessionNotifier.new);

final orchestratorProvider = Provider<GemmaOrchestrator?>((ref) {
  final session = ref.watch(gemmaSessionProvider);
  if (session == null) return null;
  final preprocessor = ref.watch(inferenceImagePreprocessorProvider);

  final runtime = ref.watch(selectedInferenceRuntimeProvider);
  return GemmaOrchestrator(
    session,
    preprocessor: preprocessor,
    enableBatchVision: runtime == InferenceRuntime.nativeMtp && _kBenchBatch,
  );
});

bool get benchmarkMtpRequested => _kBenchMtp;

/// File-backed vault on native targets; in-memory on web.
///
/// The vault directory is `<appSupportDir>/cairn_vault/<packetId>/` and
/// all writes are atomic (temp-file + rename).
final evidenceVaultProvider = Provider<EvidenceVault>((_) {
  return createFileEvidenceVault();
});

/// File-backed draft persistence on native targets; no-op on web.
///
/// Persists `SessionDraft.toMetaMap()` to
/// `<appSupportDir>/cairn_draft/active.json` so the volunteer can resume
/// after the app is killed mid-flow.
final draftPersistenceProvider = Provider<DraftPersistence>((_) {
  return createDraftPersistence();
});

final storageHealthProvider = Provider<StorageHealthService>((_) {
  return StorageHealthService();
});

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionDraft?>(SessionController.new);
