/// Screen 7 — **Synthesizing** (Gemma 4 thinking-mode).
/// Pass-1 stub — thinking-mode roll-out + `synthesize` task lands in Pass 3.
library;

import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../_pending.dart';

class SynthesizeScreen extends StatelessWidget {
  const SynthesizeScreen({super.key});

  @override
  Widget build(BuildContext context) => const PassPlaceholder(
        title: 'Synthesizing',
        pass: 'Pass 3',
        summary:
            'Runs the `synthesize` task with isThinking=true. UI streams the '
            'thinking-trace bullets. On completion the deterministic Dart '
            'priorityScore() runs and the draft is sealed.',
        continueRoute: AppRoutes.report,
      );
}
