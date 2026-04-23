/// Cairn — offline FEMA P-154 rapid visual screening (web-first Week-1 build).
///
/// Real entry point. The S2 spike page lives at `/spike` for the Week-1
/// flutter_gemma stability checks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';

void main() {
  runApp(const ProviderScope(child: CairnApp()));
}

class CairnApp extends StatelessWidget {
  const CairnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Cairn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F5D62)),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      routerConfig: appRouter,
    );
  }
}
