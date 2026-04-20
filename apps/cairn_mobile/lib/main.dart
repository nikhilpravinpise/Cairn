import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'spike/s2_spike_page.dart';

void main() {
  runApp(const ProviderScope(child: CairnSpikeApp()));
}

class CairnSpikeApp extends StatelessWidget {
  const CairnSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cairn S2 spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F5D62)),
        useMaterial3: true,
      ),
      home: const S2SpikePage(),
    );
  }
}
