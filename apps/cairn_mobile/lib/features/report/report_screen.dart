/// Screen 8 — **Report** (priority badge + rationale + photos w/ bboxes).
/// Pass-1 stub — final layout + share/PDF triggers land in Pass 3.
library;

import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../_pending.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) => const PassPlaceholder(
        title: 'Report',
        pass: 'Pass 3',
        summary:
            'Priority 1–10 colored badge, 3 rationale bullets, 1–2 '
            'uncertainty notes, photos with overlaid bboxes, action buttons: '
            'Generate PDF · Share packet · Start another.',
        continueRoute: AppRoutes.start,
        continueLabel: 'Done',
      );
}
