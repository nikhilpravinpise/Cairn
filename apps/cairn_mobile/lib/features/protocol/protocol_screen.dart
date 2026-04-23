/// Screen 5 — **FEMA P-154 quick questions**.
/// Pass-1 stub — state machine + voice/tap input lands in Pass 2.
library;

import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../_pending.dart';

class ProtocolScreen extends StatelessWidget {
  const ProtocolScreen({super.key});

  @override
  Widget build(BuildContext context) => const PassPlaceholder(
        title: 'Quick questions',
        pass: 'Pass 2',
        summary:
            'Six FEMA P-154 L1 questions (visible_collapse, '
            'building_off_foundation, leaning, ground_failure_adjacent, '
            'falling_hazards, adjacent_leaning). Voice or tap; each routes '
            'through `protocol_answer` task.',
        continueRoute: AppRoutes.humility,
      );
}
