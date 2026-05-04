/// Screen 6 — **Humility check**.
///
/// The single biggest failure mode for an on-device VLM doing safety
/// screening is over-confident hallucination. This screen makes the model
/// admit what it's least sure about:
///
/// 1. pick the observation with the lowest `model_confidence` in the draft;
/// 2. fire a `ask_followup` turn -> Gemma emits a one-sentence follow-up
///    question in the session locale;
/// 3. volunteer answers in free text;
/// 4. we record the answer as a `humility_override_v1` observation with
///    `model_confidence = 1.0` and empty `model_tags`, per the
///    volunteer-authored convention in §1.7 of the design doc.
///
/// If the draft has no observations (user took no photos, skipped notes)
/// or the lowest confidence is already high (>= 0.8), the screen skips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/orchestrator.dart';
import '../../core/models/evidence_packet.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/session_controller.dart';

const _kSkipIfConfidenceAtLeast = 0.8;

class HumilityScreen extends ConsumerStatefulWidget {
  const HumilityScreen({super.key});
  @override
  ConsumerState<HumilityScreen> createState() => _HumilityScreenState();
}

class _HumilityScreenState extends ConsumerState<HumilityScreen> {
  final _ctrl = TextEditingController();
  AskFollowupResult? _q;
  Object? _error;
  bool _loading = false;
  bool _submitting = false;
  Observation? _target;
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _askLLM();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _askLLM() async {
    if (!mounted || _loading) return;
    final draft = ref.read(sessionControllerProvider);
    final orch = ref.read(orchestratorProvider);
    if (draft == null) return;

    final target = draft.lowestConfidenceObservation;
    if (target == null ||
        target.modelConfidence >= _kSkipIfConfidenceAtLeast) {
      // Nothing worth re-asking about; skip straight to synthesize.
      if (!mounted) return;
      setState(() => _skipped = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.synthesize);
      });
      return;
    }
    _target = target;

    if (orch == null) {
      if (!mounted) return;
      setState(() {
        _error = StateError('model not loaded');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await orch.askFollowup(
        askedIn: draft.askedIn,
        targetObservationSummary: {
          'observation_id': target.observationId,
          'prompt_id': target.promptId,
          'model_description': target.modelDescription,
          'model_confidence': target.modelConfidence,
        },
      );
      if (!mounted) return;
      ref.read(sessionControllerProvider.notifier).recordTurn(
            TurnRecord(
              ts: DateTime.now().toUtc(),
              task: 'ask_followup',
              ttftMs: res.ttftMs,
              wallclockMs: res.wallclockMs,
              outputCharCount: (res.question ?? '').length,
            ),
          );
      if (!res.hasFollowup) {
        // Model determined no follow-up is needed; skip to synthesize.
        context.go(AppRoutes.synthesize);
        return;
      }
      setState(() {
        _q = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    final draft = ref.read(sessionControllerProvider);
    final target = _target;
    if (draft == null || target == null) {
      context.go(AppRoutes.synthesize);
      return;
    }
    if (text.isEmpty) {
      context.go(AppRoutes.synthesize);
      return;
    }

    setState(() => _submitting = true);
    final obsId =
        ref.read(sessionControllerProvider.notifier).generateObservationId();
    ref.read(sessionControllerProvider.notifier).recordObservation(
          Observation(
            observationId: obsId,
            promptId: 'humility_override_v1',
            askedIn: draft.askedIn,
            imageRefs: target.imageRefs,
            audioRefs: const [],
            userText: text,
            // model_description intentionally omitted per §1.7 volunteer convention.
            modelTags: const [],
            modelConfidence: 1.0,
          ),
        );
    if (!mounted) return;
    context.go(AppRoutes.synthesize);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(sessionControllerProvider);
    if (draft == null) {
      return const Scaffold(
        body: Center(child: Text('No active session — return to Start.')),
      );
    }
    if (_skipped) return const Scaffold(body: SizedBox.shrink());

    final target = _target;

    return Scaffold(
      appBar: AppBar(title: const Text('One more question')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The assistant is least sure about one of the photos. Please '
                'help clear it up.',
                style: TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 12),
              if (target != null)
                _TargetCard(
                  obs: target,
                  photo: _photoForRefs(draft, target.imageRefs),
                ),
              const SizedBox(height: 16),
              if (_loading)
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Asking the assistant…'),
                  ],
                )
              else if (_error != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Could not generate a follow-up question: $_error',
                          style: TextStyle(color: Colors.red.shade800)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _askLLM,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => context.go(AppRoutes.synthesize),
                            child: const Text('Skip'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else if (_q != null && _q!.hasFollowup) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.question_mark,
                          color: Colors.indigo.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _q!.question!,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Type your answer in your own words…',
                  ),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  TextButton(
                    onPressed: () => context.go(AppRoutes.synthesize),
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        (_q == null || _submitting) ? null : _submit,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Text(_submitting ? 'Saving…' : 'Continue',
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

CapturedPhoto? _photoForRefs(SessionDraft draft, List<String> refs) {
  for (final r in refs) {
    for (final p in draft.photos) {
      if (p.ref == r) return p;
    }
  }
  return null;
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.obs, required this.photo});
  final Observation obs;
  final CapturedPhoto? photo;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                photo!.bytes,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
              ),
            ),
          if (photo != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gemma said (confidence ${obs.modelConfidence.toStringAsFixed(2)}):',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                if (obs.modelDescription != null)
                  Text(obs.modelDescription!,
                      style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
