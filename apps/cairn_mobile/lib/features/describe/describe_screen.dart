/// Screen 4 — **Describe (voice memo, mono 16 kHz WAV ≤30 s)**.
/// Pass-1 stub — recorder + ASR-text path lands in Pass 2.
library;

import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../_pending.dart';

class DescribeScreen extends StatelessWidget {
  const DescribeScreen({super.key});

  @override
  Widget build(BuildContext context) => const PassPlaceholder(
        title: 'Describe',
        pass: 'Pass 2',
        summary:
            '30-second mono 16 kHz WAV recorder. On web we transcribe via the '
            'browser SpeechRecognition API and feed the text into Gemma; on '
            'Android we pass audio bytes directly. Output is a `user_text` '
            'observation appended to the draft.',
        continueRoute: AppRoutes.protocol,
      );
}
