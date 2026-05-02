/// Single import for app-wide Riverpod providers.
///
/// Screens depend on this file; never on the concrete implementations behind
/// it. That way swapping `InMemoryEvidenceVault` for an OPFS-backed vault is
/// a one-line change here.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llm/gemma_session.dart';
import 'llm/model_registry.dart';
import 'llm/orchestrator.dart';
import 'state/session_controller.dart';
import 'storage/evidence_vault.dart';

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
class GemmaSessionNotifier extends Notifier<GemmaSession?> {
  @override
  GemmaSession? build() {
    ref.onDispose(() async {
      await state?.close();
    });
    return null;
  }

  /// Load (or reload) the active Gemma session.
  ///
  /// [profile] selects which capability flags are wired at model/chat
  /// creation time. Defaults to [SessionProfile.vision] because the primary
  /// task is photo description. Callers that drive a different task group
  /// should pass the appropriate profile explicitly.
  Future<void> load({
    SessionProfile profile = SessionProfile.vision,
    String? loraPath,
    void Function(GemmaLoadProgress)? onProgress,
  }) async {
    final previous = state;
    state = null;
    await previous?.close();
    final spec = ref.read(selectedModelSpecProvider);
    final sys = await ref.read(systemPromptProvider.future);
    state = switch (profile) {
      SessionProfile.vision =>
        await GemmaSession.openForVision(spec,
            systemPrompt: sys, loraPath: loraPath, onProgress: onProgress),
      SessionProfile.audio =>
        await GemmaSession.openForAudio(spec,
            systemPrompt: sys, loraPath: loraPath, onProgress: onProgress),
      SessionProfile.synthesis =>
        await GemmaSession.openForSynthesis(spec,
            systemPrompt: sys, loraPath: loraPath, onProgress: onProgress),
      SessionProfile.standard =>
        await GemmaSession.openStandard(spec,
            systemPrompt: sys, loraPath: loraPath, onProgress: onProgress),
    };
  }

  Future<void> unload() async {
    await state?.close();
    state = null;
  }
}

final gemmaSessionProvider =
    NotifierProvider<GemmaSessionNotifier, GemmaSession?>(
        GemmaSessionNotifier.new);

final orchestratorProvider = Provider<GemmaOrchestrator?>((ref) {
  final session = ref.watch(gemmaSessionProvider);
  return session == null ? null : GemmaOrchestrator(session);
});

/// In-memory vault for now. Swap for an OPFS-backed implementation in Pass 4.
final evidenceVaultProvider = Provider<EvidenceVault>((_) {
  return InMemoryEvidenceVault();
});

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionDraft?>(SessionController.new);
