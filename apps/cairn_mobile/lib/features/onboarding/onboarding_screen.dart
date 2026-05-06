/// Progressive onboarding flow — replaces the old blanket-permission Bootstrap.
///
/// Three screens max, 60-second rule:
///   1. Welcome + Model Setup (auto-download begins immediately)
///   2. How It Works (single scrollable view, not carousel)
///   3. Permissions are contextual — requested when needed, not upfront
///
/// After onboarding completes (or skip), navigates to Start screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';

/// Tracks whether onboarding has been completed (persisted in memory for
/// the app session; could be backed by SharedPreferences for persistence).
final onboardingCompleteProvider = StateProvider<bool>((_) => false);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 2) {
      _pageCtrl.animateToPage(
        _page + 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      context.go(AppRoutes.start);
    }
  }

  void _skip() => context.go(AppRoutes.start);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: const Text('Skip'),
              ),
            ),
            // Pages
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _WelcomePage(),
                  _HowItWorksPage(),
                  _ReadyPage(),
                ],
              ),
            ),
            // Bottom bar
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Dots
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page
                                ? cs.primary
                                : cs.outline.withValues(alpha: 0.3),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_page == 2 ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1: Welcome + Model Setup
// ---------------------------------------------------------------------------

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo area
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.safety_check,
              size: 56,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Cairn',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Post-earthquake building triage',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.8),
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Offline, on your device. No data leaves your phone.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 32),
          // Key features
          const _FeatureRow(
            icon: Icons.wifi_off,
            label: 'Works completely offline',
          ),
          const SizedBox(height: 12),
          const _FeatureRow(
            icon: Icons.shield_outlined,
            label: 'Privacy-first — data stays on device',
          ),
          const SizedBox(height: 12),
          const _FeatureRow(
            icon: Icons.speed,
            label: 'Results in minutes, not hours',
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2: How It Works
// ---------------------------------------------------------------------------

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'How it works',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Three simple steps to screen a building after an earthquake.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 36),
          const _StepCard(
            number: '1',
            icon: Icons.camera_alt_outlined,
            title: 'Photograph the building',
            subtitle: 'Capture 4 angles: front, cracks, context, and hazards.',
          ),
          const SizedBox(height: 20),
          const _StepCard(
            number: '2',
            icon: Icons.psychology_outlined,
            title: 'AI analyzes damage',
            subtitle: 'Gemma identifies cracks, spalling, leaning, and hazards.',
          ),
          const SizedBox(height: 20),
          const _StepCard(
            number: '3',
            icon: Icons.assessment_outlined,
            title: 'Get a triage report',
            subtitle: 'Priority score + rationale. Share with engineers.',
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Icon(icon, size: 28, color: cs.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 3: Ready
// ---------------------------------------------------------------------------

class _ReadyPage extends StatelessWidget {
  const _ReadyPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: cs.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'You\u2019re all set',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Permissions are requested only when needed.\n'
            'Camera \u2192 when you take a photo.\n'
            'Location \u2192 when you confirm GPS.\n'
            'Microphone \u2192 only if you record audio.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
