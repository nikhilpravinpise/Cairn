/// Internal — small reusable widget for screens that ship as stubs in Pass 1.
/// Each screen still navigates correctly so Pass 2/3 can implement bodies
/// in isolation.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PassPlaceholder extends StatelessWidget {
  const PassPlaceholder({
    super.key,
    required this.title,
    required this.pass,
    required this.summary,
    required this.continueRoute,
    this.continueLabel = 'Continue',
  });

  final String title;
  final String pass; // e.g. "Pass 2"
  final String summary;
  final String continueRoute;
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                color: Colors.amber.shade100,
                child: Text('Stub — implemented in $pass',
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 16),
              Text(summary, style: const TextStyle(fontSize: 16)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push(continueRoute),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(continueLabel,
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
