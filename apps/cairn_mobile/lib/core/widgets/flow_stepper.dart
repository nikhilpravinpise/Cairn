/// Persistent flow step indicator — shows the user where they are in the
/// 7-step FEMA P-154 screening flow.
///
/// Usage:
///   FlowStepper(
///     steps: FlowStepper.kScreeningSteps,
///     currentIndex: 2, // e.g. on Photos screen
///   )
library;

import 'package:flutter/material.dart';

import '../theme/cairn_theme.dart';

/// One step in the screening flow.
class FlowStep {
  const FlowStep({
    required this.label,
    required this.icon,
    required this.routeName,
  });

  final String label;
  final IconData icon;
  final String routeName;
}

/// A compact, horizontal step indicator for the 7-step screening flow.
///
/// Shows completed steps as filled, the current step as highlighted, and
/// future steps as muted. Designed for disaster-response: large enough to
/// tap (though navigation is linear-only), high-contrast icons, and
/// animates progress with a subtle color fill.
class FlowStepper extends StatelessWidget {
  const FlowStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.compact = false,
  });

  /// The 7 screening steps in order.
  static const kScreeningSteps = [
    FlowStep(label: 'Location', icon: Icons.location_on_outlined, routeName: 'location'),
    FlowStep(label: 'Photos', icon: Icons.camera_alt_outlined, routeName: 'photos'),
    FlowStep(label: 'Audio', icon: Icons.mic_outlined, routeName: 'audio'),
    FlowStep(label: 'Describe', icon: Icons.description_outlined, routeName: 'describe'),
    FlowStep(label: 'Protocol', icon: Icons.checklist_outlined, routeName: 'protocol'),
    FlowStep(label: 'Synthesize', icon: Icons.psychology_outlined, routeName: 'synthesize'),
    FlowStep(label: 'Report', icon: Icons.assessment_outlined, routeName: 'report'),
  ];

  final List<FlowStep> steps;
  final int currentIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: i <= currentIndex
                      ? cs.primary.withValues(alpha: 0.6)
                      : cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            _StepIcon(
              step: steps[i],
              state: i < currentIndex
                  ? _StepState.completed
                  : i == currentIndex
                      ? _StepState.current
                      : _StepState.upcoming,
              compact: compact,
            ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { completed, current, upcoming }

class _StepIcon extends StatelessWidget {
  const _StepIcon({
    required this.step,
    required this.state,
    required this.compact,
  });

  final FlowStep step;
  final _StepState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final icon = switch (state) {
      _StepState.completed => Icons.check_circle,
      _StepState.current => step.icon,
      _StepState.upcoming => step.icon,
    };

    final color = switch (state) {
      _StepState.completed => CairnColors.low,
      _StepState.current => cs.primary,
      _StepState.upcoming => cs.outline.withValues(alpha: 0.4),
    };

    final bgColor = switch (state) {
      _StepState.completed => CairnColors.low.withValues(alpha: 0.1),
      _StepState.current => cs.primary.withValues(alpha: 0.12),
      _StepState.upcoming => Colors.transparent,
    };

    final size = compact ? 28.0 : 36.0;

    return Tooltip(
      message: step.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: state == _StepState.current
                  ? Border.all(color: color, width: 2)
                  : null,
            ),
            child: Icon(icon, size: compact ? 16 : 20, color: color),
          ),
          if (!compact) ...[
            const SizedBox(height: 2),
            Text(
              step.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    state == _StepState.current ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
