/// Screen 3 — **Walk around (4 required photos + optional 5th)**.
/// Pass-1 stub — real capture + per-photo `describe_photo` round-trip ships in Pass 2.
library;

import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../_pending.dart';

class PhotosScreen extends StatelessWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context) => const PassPlaceholder(
        title: 'Walk around',
        pass: 'Pass 2',
        summary: 'Capture 4 reference photos (front, ground floor, cracks, '
            'foundation) + optional 5th. Each fires a `describe_photo` turn '
            'against Gemma and records an Observation in the session draft.',
        continueRoute: AppRoutes.describe,
      );
}
