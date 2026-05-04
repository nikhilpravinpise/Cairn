import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';

/// Entry point that navigates immediately to [AppRoutes.start].
///
/// Permissions (camera, microphone, location) are requested feature-locally:
///   - Camera      → PhotosScreen (image_picker / camera_description flow)
///   - Microphone  → AudioScreen  (_startRecording checks RECORD_AUDIO)
///   - Location    → LocationScreen (LocationService.getLocation)
///
/// A blocking upfront gate here caused false-denial errors on Android and
/// prevented volunteers from reaching the start screen on first run.
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(AppRoutes.start);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
