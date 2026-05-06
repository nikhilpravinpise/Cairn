/// Shared Cairn UX widgets — loading skeletons, error cards, and other
/// reusable components used across screening screens.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

/// A pulsing skeleton placeholder used while the model is warming up or
/// inference is running. Prefer this over [CircularProgressIndicator] for
/// anything longer than ~500ms.
class CairnSkeleton extends StatefulWidget {
  const CairnSkeleton({
    super.key,
    this.icon,
    this.label = 'Loading\u2026',
    this.sublabel,
    this.showProgress = false,
  });

  final IconData? icon;
  final String label;
  final String? sublabel;
  final bool showProgress;

  @override
  State<CairnSkeleton> createState() => _CairnSkeletonState();
}

class _CairnSkeletonState extends State<CairnSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(
        opacity: 0.4 + (_ctrl.value * 0.3),
        child: child,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 56, color: cs.primary),
              const SizedBox(height: 20),
            ],
            Text(
              widget.label,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (widget.sublabel != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.sublabel!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (widget.showProgress) ...[
              const SizedBox(height: 24),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error card
// ---------------------------------------------------------------------------

/// A branded error card with a retry action. Use this instead of raw
/// exception text for any user-facing error.
class CairnErrorCard extends StatelessWidget {
  const CairnErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.onDismiss,
    this.retryLabel = 'Retry',
    this.dismissLabel = 'Skip',
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final String retryLabel;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: cs.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null || onDismiss != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onDismiss != null)
                  TextButton(
                    onPressed: onDismiss,
                    child: Text(dismissLabel),
                  ),
                if (onRetry != null) ...[
                  if (onDismiss != null) const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(retryLabel),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Triage badge
// ---------------------------------------------------------------------------

/// A colored badge showing a triage band label (CRITICAL, HIGH, MEDIUM, LOW).
class TriageBadge extends StatelessWidget {
  const TriageBadge({
    super.key,
    required this.band,
    this.score,
    this.large = false,
  });

  final String band;
  final int? score;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = _bandColor(band);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 20 : 14,
        vertical: large ? 10 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(large ? 12 : 8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (score != null) ...[
            Text(
              '$score',
              style: TextStyle(
                fontSize: large ? 22 : 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            band,
            style: TextStyle(
              fontSize: large ? 16 : 13,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Color _bandColor(String band) => switch (band) {
        'CRITICAL' => const Color(0xFFD32F2F),
        'HIGH' => const Color(0xFFE65100),
        'MEDIUM' => const Color(0xFFF9A825),
        'LOW' => const Color(0xFF2E7D32),
        _ => const Color(0xFF757575),
      };
}

// ---------------------------------------------------------------------------
// Slot indicator (for photo capture)
// ---------------------------------------------------------------------------

/// Shows which photo slot the user is on (e.g., "Front · 1/4").
class SlotIndicator extends StatelessWidget {
  const SlotIndicator({
    super.key,
    required this.label,
    required this.current,
    required this.total,
    this.filled = false,
  });

  final String label;
  final int current;
  final int total;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled
            ? cs.primary.withValues(alpha: 0.1)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: filled
              ? cs.primary.withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (filled)
            Icon(Icons.check_circle, size: 14, color: cs.primary)
          else
            Icon(Icons.circle_outlined,
                size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 6),
          Text(
            '$label \u00b7 $current/$total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: filled ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
