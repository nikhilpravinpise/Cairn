/// Screen 5 — **Volunteer text notes** ("Describe what you saw").
///
/// Audio capture moved to Screen 4 ([AudioScreen], route `/audio`). This
/// screen is the text-only complement: the volunteer can add any detail the
/// photos and audio missed — smells, sounds, bystander accounts, etc.
///
/// The user-authored observation is attached as a `volunteer_note_v1` entry
/// with `model_confidence = 1.0` and empty `model_tags`, per the
/// volunteer-authored convention in §1.7.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/evidence_packet.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/widgets/flow_stepper.dart';

class DescribeScreen extends ConsumerStatefulWidget {
  const DescribeScreen({super.key});

  @override
  ConsumerState<DescribeScreen> createState() => _DescribeScreenState();
}

class _DescribeScreenState extends ConsumerState<DescribeScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    final draft = ref.read(sessionControllerProvider);
    if (draft == null) return;
    if (text.isEmpty) {
      context.push(AppRoutes.protocol);
      return;
    }
    final imgRefs = [for (final p in draft.photos) p.ref];
    final obsId =
        ref.read(sessionControllerProvider.notifier).generateObservationId();
    ref.read(sessionControllerProvider.notifier).recordObservation(
          Observation(
            observationId: obsId,
            promptId: 'volunteer_note_v1',
            askedIn: draft.askedIn,
            // Link the note to whatever photos are already captured so the
            // report knows the note isn't free-floating.
            imageRefs: imgRefs,
            audioRefs: const [],
            userText: text,
            // model_description intentionally omitted per §1.7 volunteer convention.
            modelTags: const [],
            // User is ground truth when they explicitly type a note.
            modelConfidence: 1.0,
          ),
        );
    context.push(AppRoutes.protocol);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(sessionControllerProvider);
    if (draft == null) {
      return const Scaffold(
        body: Center(child: Text('No active session — return to Start.')),
      );
    }

    final priorObs = draft.observations
        .where((o) => o.promptId != 'volunteer_note_v1')
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? BackButton(onPressed: () => context.pop())
            : null,
        title: const Text('Describe what you saw'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const FlowStepper(
                steps: FlowStepper.kScreeningSteps, currentIndex: 3),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
            const Text(
              'Add anything the photos might have missed: smells of gas, '
              'sounds of water, occupants still inside, evacuation signs, etc. '
              'Short sentences are fine.',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 8,
              minLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText:
                    'e.g. "Chimney bricks fell onto the driveway; the '
                    'neighbour says the wall shifted about an inch."',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (priorObs.isNotEmpty) ...[
              const Text('What Gemma observed from your photos:',
                  style:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final o in priorObs) _PriorObsTile(obs: o),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => context.push(AppRoutes.protocol),
                child: const Text('Skip — I have nothing to add'),
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
}

class _PriorObsTile extends StatelessWidget {
  const _PriorObsTile({required this.obs});
  final Observation obs;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(obs.imageRefs.join(', '),
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  fontFamily: 'monospace')),
          const SizedBox(height: 4),
          if (obs.modelDescription != null)
            Text(obs.modelDescription!, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
