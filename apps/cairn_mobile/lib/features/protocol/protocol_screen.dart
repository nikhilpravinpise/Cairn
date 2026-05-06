/// Screen 5 — **Quick protocol questions** (FEMA P-154 Level 1).
///
/// The six fields from `protocol_answers_v1` in the schema, asked one at a
/// time. Tap-based by design on the web fallback — the Android track uses
/// a `protocol_answer` LLM round-trip to map free-text replies onto the
/// same deltas, but for the web demo a tap pattern is clearer and faster
/// and exercises the same `SessionController.applyProtocolDelta` pathway.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/widgets/flow_stepper.dart';

class _Question {
  const _Question({
    required this.key,
    required this.title,
    required this.help,
    required this.kind,
    this.leaningOrder = const <String>[],
  });

  final String key; // matches the ProtocolAnswersRecord field key
  final String title;
  final String help;
  final _QKind kind;

  /// For `leaning` only — ordered 4-way choice.
  final List<String> leaningOrder;
}

enum _QKind { yesNo, leaning }

// Plain-English "Yes/No" language per FEMA P-154 L1, but the semantic
// interpretation (hazard-positive vs negative) lives in `priority.dart`.
const _qs = <_Question>[
  _Question(
    key: 'visible_collapse',
    title: 'Any partial or full collapse?',
    help: 'Even one collapsed floor or corner counts.',
    kind: _QKind.yesNo,
  ),
  _Question(
    key: 'building_off_foundation',
    title: 'Has the building shifted off its foundation?',
    help: 'Any visible offset at the sill plate or stem wall.',
    kind: _QKind.yesNo,
  ),
  _Question(
    key: 'leaning',
    title: 'Is the building leaning?',
    help: 'Relative to neighbouring buildings or the vertical.',
    kind: _QKind.leaning,
    leaningOrder: ['none', 'slight', 'moderate', 'severe'],
  ),
  _Question(
    key: 'ground_failure_adjacent',
    title: 'Is there ground failure right next to the building?',
    help: 'Sand boils, fissures, visible settlement, slope failure.',
    kind: _QKind.yesNo,
  ),
  _Question(
    key: 'falling_hazards',
    title: 'Are there falling hazards above exits or sidewalks?',
    help: 'Chimneys, parapets, cladding, signage, loose masonry.',
    kind: _QKind.yesNo,
  ),
  _Question(
    key: 'adjacent_leaning',
    title: 'Is an adjacent building leaning into this one?',
    help: 'Pounding or contact damage counts as yes.',
    kind: _QKind.yesNo,
  ),
];

class ProtocolScreen extends ConsumerStatefulWidget {
  const ProtocolScreen({super.key});
  @override
  ConsumerState<ProtocolScreen> createState() => _ProtocolScreenState();
}

class _ProtocolScreenState extends ConsumerState<ProtocolScreen> {
  int _i = 0;

  void _answer(Object value) {
    final q = _qs[_i];
    ref.read(sessionControllerProvider.notifier).applyProtocolDelta(
          MapEntry(q.key, value),
        );
    if (_i < _qs.length - 1) {
      setState(() => _i++);
    } else {
      context.push(AppRoutes.humility);
    }
  }

  void _skip() {
    // Leave the field at its default (false / 'none') and advance.
    if (_i < _qs.length - 1) {
      setState(() => _i++);
    } else {
      context.push(AppRoutes.humility);
    }
  }

  void _back() {
    if (_i > 0) setState(() => _i--);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(sessionControllerProvider);
    if (draft == null) {
      return const Scaffold(
        body: Center(child: Text('No active session — return to Start.')),
      );
    }
    final q = _qs[_i];
    final pa = draft.protocolAnswers;
    final current = switch (q.key) {
      'visible_collapse' => pa.visibleCollapse,
      'building_off_foundation' => pa.buildingOffFoundation,
      'leaning' => pa.leaning,
      'ground_failure_adjacent' => pa.groundFailureAdjacent,
      'falling_hazards' => pa.fallingHazards,
      'adjacent_leaning' => pa.adjacentLeaning,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Quick questions  ${_i + 1} / ${_qs.length}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const FlowStepper(
                steps: FlowStepper.kScreeningSteps, currentIndex: 4),
            Expanded(
              child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: (_i + 1) / _qs.length),
              const SizedBox(height: 24),
              Text(q.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(q.help,
                  style:
                      const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 24),
              if (q.kind == _QKind.yesNo)
                _YesNo(current: current as bool, onAnswer: _answer)
              else
                _Leaning(
                  current: current as String,
                  order: q.leaningOrder,
                  onAnswer: _answer,
                ),
              const Spacer(),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _i == 0 ? null : _back,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _skip,
                    child: Text(_i == _qs.length - 1
                        ? 'Skip remaining'
                        : 'Skip this question'),
                  ),
                ],
              ),
            ],
          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YesNo extends StatelessWidget {
  const _YesNo({required this.current, required this.onAnswer});
  final bool current;
  final ValueChanged<bool> onAnswer;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BigButton(
            label: 'Yes',
            selected: current == true,
            color: Colors.red.shade600,
            onPressed: () => onAnswer(true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BigButton(
            label: 'No',
            selected: current == false,
            color: Colors.green.shade700,
            onPressed: () => onAnswer(false),
          ),
        ),
      ],
    );
  }
}

class _Leaning extends StatelessWidget {
  const _Leaning({
    required this.current,
    required this.order,
    required this.onAnswer,
  });
  final String current;
  final List<String> order;
  final ValueChanged<String> onAnswer;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final v in order)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BigButton(
              label: _label(v),
              selected: current == v,
              color: _color(v),
              onPressed: () => onAnswer(v),
            ),
          ),
      ],
    );
  }

  String _label(String v) => switch (v) {
        'none' => 'Not leaning',
        'slight' => 'Slightly leaning',
        'moderate' => 'Noticeably leaning',
        'severe' => 'Severely leaning',
        _ => v,
      };

  Color _color(String v) => switch (v) {
        'none' => Colors.green.shade700,
        'slight' => Colors.amber.shade800,
        'moderate' => Colors.orange.shade800,
        'severe' => Colors.red.shade700,
        _ => Colors.grey,
      };
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: selected ? Colors.white : color,
          backgroundColor: selected ? color : Colors.transparent,
          side: BorderSide(color: color, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(label,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
