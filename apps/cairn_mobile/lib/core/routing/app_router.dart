/// `GoRouter` configuration for the 9-screen FEMA P-154 flow.
///
/// Routes intentionally form a linear progression: each screen pushes the
/// next; the back button returns to the prior. Reports + the initial start
/// screen are independent.
library;

import 'package:go_router/go_router.dart';

import '../../features/bootstrap/bootstrap_screen.dart';
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
  static const describe = '/describe';
  static const protocol = '/protocol';
  static const humility = '/humility';
  static const synthesize = '/synthesize';
  static const report = '/report';
  static const spike = '/spike';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.bootstrap,
  routes: [
    GoRoute(path: AppRoutes.bootstrap, builder: (_, __) => const BootstrapScreen()),
    GoRoute(path: AppRoutes.start, builder: (_, __) => const StartScreen()),
    GoRoute(
        path: AppRoutes.location, builder: (_, __) => const LocationScreen()),
    GoRoute(path: AppRoutes.photos, builder: (_, __) => const PhotosScreen()),
    GoRoute(
        path: AppRoutes.describe, builder: (_, __) => const DescribeScreen()),
    GoRoute(
        path: AppRoutes.protocol, builder: (_, __) => const ProtocolScreen()),
    GoRoute(
        path: AppRoutes.humility, builder: (_, __) => const HumilityScreen()),
    GoRoute(
        path: AppRoutes.synthesize,
        builder: (_, __) => const SynthesizeScreen()),
    GoRoute(path: AppRoutes.report, builder: (_, __) => const ReportScreen()),
    GoRoute(path: AppRoutes.spike, builder: (_, __) => const S2SpikePage()),
  ],
);
