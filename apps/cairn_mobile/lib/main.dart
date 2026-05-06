/// Cairn — offline FEMA P-154 rapid visual screening (web-first Week-1 build).
///
/// Real entry point. The S2 spike page lives at `/spike` for the Week-1
/// flutter_gemma stability checks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/routing/app_router.dart';
import 'core/state/session_controller.dart';
import 'core/theme/cairn_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // E4B web .task is ~4 GB which exceeds the ~2 GB ArrayBuffer limit in most
  // browsers. `WebStorageMode.streaming` routes the download through OPFS so
  // memory isn't the bottleneck. On mobile the webStorageMode flag is ignored.
  // See plan §2.4 + docs/week1_pivot.md.
  await FlutterGemma.initialize(
    webStorageMode: WebStorageMode.streaming,
  );

  runApp(const ProviderScope(child: CairnApp()));
}

class CairnApp extends ConsumerWidget {
  const CairnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Auto-save the draft on every session state change so that a process
    // kill mid-flow does not lose the volunteer's work.
    ref.listen<SessionDraft?>(sessionControllerProvider, (_, next) {
      final dp = ref.read(draftPersistenceProvider);
      if (next != null) {
        dp.saveDraftMeta(next.toMetaMap()).ignore();
      } else {
        dp.clearDraft().ignore();
      }
    });

    return MaterialApp.router(
      title: 'Cairn',
      debugShowCheckedModeBanner: false,
      theme: CairnTheme.light(),
      darkTheme: CairnTheme.dark(),
      routerConfig: appRouter,
    );
  }
}
