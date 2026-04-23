/// Screen 6 — **Humility check** (the differentiator beat).
///
/// Re-queries the lowest-confidence observation. Pass-1 stub — wiring lands
/// in Pass 2.
library;

import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../_pending.dart';

class HumilityScreen extends StatelessWidget {
  const HumilityScreen({super.key});

  @override
  Widget build(BuildContext context) => const PassPlaceholder(
        title: 'One more thing…',
        pass: 'Pass 2',
        summary:
            'Picks the observation with the lowest model_confidence and '
            'asks Gemma to formulate a follow-up question via the '
            '`ask_followup` task. The volunteer answers; the answer becomes '
            'a new Observation that overrides the model.',
        continueRoute: AppRoutes.synthesize,
      );
}
