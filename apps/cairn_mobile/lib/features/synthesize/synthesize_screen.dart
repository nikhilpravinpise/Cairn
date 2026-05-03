/// Screen 8 — **Synthesize**.
///
/// Reloads the Gemma session with the `synthesis` profile (thinking=true),
/// calls [GemmaOrchestrator.synthesize], records the turn, calls
/// [SessionController.computeAndStoreTriage] with the LLM rationale, then
/// auto-navigates to the Report screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/session_controller.dart';

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

enum _SynthState { reloadingModel, synthesizing, done, error }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SynthesizeScreen extends ConsumerStatefulWidget {
  const SynthesizeScreen({super.key});

  @override
  ConsumerState<SynthesizeScreen> createState() => _SynthesizeScreenState();
}

class _SynthesizeScreenState extends ConsumerState<SynthesizeScreen> {
  _SynthState _phase = _SynthState.reloadingModel;
  String? _thinkingExcerpt;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  // ---------------------------------------------------------------------------
  // Main flow
  // ---------------------------------------------------------------------------

  Future<void> _run() async {
    final draft = ref.read(sessionControllerProvider);
    if (draft == null) {
      setState(() {
        _phase = _SynthState.error;
        _error = 'No active session. Return to Start.';
      });
      return;
    }

    // Step 1: reload with synthesis profile if needed.
    final session = ref.read(gemmaSessionProvider);
    if (session == null || !session.isThinking) {
      setState(() => _phase = _SynthState.reloadingModel);
      try {
        await ref
            .read(gemmaSessionProvider.notifier)
            .load(profile: SessionProfile.synthesis);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _phase = _SynthState.error;
          _error = 'Failed to load synthesis model: $e';
        });
        return;
      }
    }

    if (!mounted) return;

    // Step 2: run synthesize.
    setState(() => _phase = _SynthState.synthesizing);
    final orch = ref.read(orchestratorProvider);
    if (orch == null) {
      setState(() {
        _phase = _SynthState.error;
        _error = 'Orchestrator unavailable after model reload.';
      });
      return;
    }

    try {
      final result = await orch.synthesize(
        askedIn: draft.askedIn,
        packetSummary: draft.packetSummaryForSynthesis(),
      );

      if (!mounted) return;

      // Approximate output char count from serialised rationale + uncertainty.
      final outputChars = result.rationaleBullets.join(' ').length +
          result.uncertaintyNotes.join(' ').length;

      // Step 3: record the turn for turns.jsonl.
      ref.read(sessionControllerProvider.notifier).recordTurn(
            TurnRecord(
              ts: DateTime.now().toUtc(),
              task: 'synthesize',
              ttftMs: result.ttftMs,
              wallclockMs: result.wallclockMs,
              outputCharCount: outputChars,
              thinkingChars: result.thinkingExcerpt.length,
            ),
          );

      // Step 4: compute deterministic triage and store it.
      ref.read(sessionControllerProvider.notifier).computeAndStoreTriage(
            rationaleBullets: result.rationaleBullets,
            uncertaintyNotes: result.uncertaintyNotes,
          );

      if (!mounted) return;
      setState(() {
        _phase = _SynthState.done;
        _thinkingExcerpt = result.thinkingExcerpt;
      });

      // Step 5: navigate to report.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) context.go(AppRoutes.report);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _SynthState.error;
        _error = e.toString();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Synthesizing')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_phase) {
      _SynthState.reloadingModel => const _PhaseCard(
          icon: Icons.memory_outlined,
          label: 'Loading synthesis model…',
          sublabel: 'Reloading Gemma with thinking mode enabled.',
          showProgress: true,
        ),
      _SynthState.synthesizing => const _PhaseCard(
          icon: Icons.psychology_outlined,
          label: 'Synthesizing findings…',
          sublabel:
              'Gemma is reasoning across all observations, hazards, and '
              'protocol answers.',
          showProgress: true,
        ),
      _SynthState.done => _DoneCard(thinkingExcerpt: _thinkingExcerpt),
      _SynthState.error => _ErrorCard(
          error: _error?.toString() ?? 'Unknown error',
          onRetry: _run,
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    this.showProgress = false,
  });
  final IconData icon;
  final String label;
  final String sublabel;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cs.primary),
          const SizedBox(height: 20),
          Text(label,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(sublabel,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurface.withValues(alpha: 0.7)),
              textAlign: TextAlign.center),
          if (showProgress) ...[
            const SizedBox(height: 28),
            const CircularProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _DoneCard extends StatefulWidget {
  const _DoneCard({this.thinkingExcerpt});
  final String? thinkingExcerpt;

  @override
  State<_DoneCard> createState() => _DoneCardState();
}

class _DoneCardState extends State<_DoneCard> {
  bool _showThinking = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Icon(Icons.check_circle_outline, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('Analysis complete',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Triage computed. Navigating to report…',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          if (widget.thinkingExcerpt != null &&
              widget.thinkingExcerpt!.isNotEmpty) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => setState(() => _showThinking = !_showThinking),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _showThinking
                        ? 'Hide thinking trace'
                        : 'Show thinking trace',
                    style: TextStyle(
                        color: cs.primary,
                        decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
            if (_showThinking) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.thinkingExcerpt!,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.black54),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: cs.error),
          const SizedBox(height: 16),
          Text('Synthesis failed',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: cs.error)),
          const SizedBox(height: 8),
          Text(error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go(AppRoutes.report),
            child: const Text('Skip synthesis → Report'),
          ),
        ],
      ),
    );
  }
}
