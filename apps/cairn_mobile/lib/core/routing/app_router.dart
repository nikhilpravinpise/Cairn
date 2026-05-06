/// `GoRouter` configuration for the 9-screen FEMA P-154 flow.
///
/// Routes intentionally form a linear progression: each screen pushes the
/// next; the back button returns to the prior. Reports + the initial start
/// screen are independent.
///
/// All flow screens use a smooth slide-left transition for a polished UX.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/onboarding_screen.dart';
import '../../features/audio/audio_screen.dart';
import '../../features/describe/describe_screen.dart';
import '../../features/humility/humility_screen.dart';
import '../../features/location/location_screen.dart';
import '../../features/photos/photos_screen.dart';
import '../../features/protocol/protocol_screen.dart';
import '../../features/report/report_screen.dart';
import '../../features/start/start_screen.dart';
import '../../features/synthesize/synthesize_screen.dart';
import '../../spike/s2_spike_page.dart';

class AppRoutes {
  static const bootstrap = '/';
  static const start = '/start';
  static const location = '/location';
  static const photos = '/photos';
  static const audio = '/audio';
  static const describe = '/describe';
  static const protocol = '/protocol';
  static const humility = '/humility';
  static const synthesize = '/synthesize';
  static const report = '/report';
  static const spike = '/spike';
}

// ---------------------------------------------------------------------------
// Smooth transitions
// ---------------------------------------------------------------------------

/// Slide-left page transition for the linear screening flow.
CustomTransitionPage<void> _slidePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeInOutCubic));

      final secondaryTween = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.3, 0.0),
      ).chain(CurveTween(curve: Curves.easeInOutCubic));

      return SlideTransition(
        position: secondaryAnimation.drive(secondaryTween),
        child: SlideTransition(
          position: animation.drive(tween),
          child: child,
        ),
      );
    },
  );
}

/// Fade transition for entry/exit screens (start, report).
CustomTransitionPage<void> _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final appRouter = GoRouter(
  initialLocation: AppRoutes.bootstrap,
  routes: [
    GoRoute(
      path: AppRoutes.bootstrap,
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.start,
      pageBuilder: (_, state) => _fadePage(const StartScreen(), state),
    ),
    // ── Linear screening flow with slide transitions ──
    GoRoute(
      path: AppRoutes.location,
      pageBuilder: (_, state) => _slidePage(const LocationScreen(), state),
    ),
    GoRoute(
      path: AppRoutes.photos,
      pageBuilder: (_, state) => _slidePage(const PhotosScreen(), state),
    ),
    GoRoute(
      path: AppRoutes.audio,
      pageBuilder: (_, state) => _slidePage(const AudioScreen(), state),
    ),
    GoRoute(
      path: AppRoutes.describe,
      pageBuilder: (_, state) => _slidePage(const DescribeScreen(), state),
    ),
    GoRoute(
      path: AppRoutes.protocol,
      pageBuilder: (_, state) => _slidePage(const ProtocolScreen(), state),
    ),
    GoRoute(
      path: AppRoutes.humility,
      pageBuilder: (_, state) => _slidePage(const HumilityScreen(), state),
    ),
    GoRoute(
      path: AppRoutes.synthesize,
      pageBuilder: (_, state) => _slidePage(const SynthesizeScreen(), state),
    ),
    GoRoute(
      path: AppRoutes.report,
      pageBuilder: (_, state) => _fadePage(const ReportScreen(), state),
    ),
    // ── Dev tools ──
    GoRoute(
      path: AppRoutes.spike,
      builder: (_, __) => const S2SpikePage(),
    ),
  ],
);
