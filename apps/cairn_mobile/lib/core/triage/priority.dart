/// Deterministic priority score. Byte-identical to
/// `scripts/cairn/triage.py::priority_score`.
///
/// The LLM never computes this. See plan §2.3 and `docs/schema/README.md`.
library;

enum PriorityBand { low, medium, high, critical }

class ProtocolAnswers {
  const ProtocolAnswers({
    required this.visibleCollapse,
    required this.buildingOffFoundation,
    required this.leaning,
    required this.groundFailureAdjacent,
    required this.fallingHazards,
    required this.adjacentLeaning,
  });

  final bool visibleCollapse;
  final bool buildingOffFoundation;
  final String leaning; // 'none'|'slight'|'moderate'|'severe'
  final bool groundFailureAdjacent;
  final bool fallingHazards;
  final bool adjacentLeaning;
}

class HazardFlag {
  const HazardFlag({required this.code, required this.severity});
  final String code;
  final String severity; // 'low'|'moderate'|'high'
}

class BuildingMeta {
  const BuildingMeta({required this.type, required this.storiesAboveGrade});
  final String type;
  final int storiesAboveGrade;
}

const Map<String, int> kHazardSeverityPoints = {
  'high': 3,
  'moderate': 2,
  'low': 1,
};

int priorityScore({
  required ProtocolAnswers protocolAnswers,
  required List<HazardFlag> hazardsFlagged,
  required BuildingMeta building,
}) {
  if (protocolAnswers.visibleCollapse) return 10;
  if (protocolAnswers.buildingOffFoundation) return 10;
  if (protocolAnswers.leaning == 'severe') return 9;

  var s = 0;
  for (final h in hazardsFlagged) {
    s += kHazardSeverityPoints[h.severity] ?? 0;
  }
  if (protocolAnswers.groundFailureAdjacent) s += 2;
  if (protocolAnswers.fallingHazards) s += 2;
  if (building.type == 'unreinforced_masonry') s += 2;
  if (hazardsFlagged.any((h) => h.code == 'H01_soft_story')) s += 2;

  return s.clamp(1, 10);
}

PriorityBand priorityBand(int score) {
  if (score <= 3) return PriorityBand.low;
  if (score <= 6) return PriorityBand.medium;
  if (score <= 8) return PriorityBand.high;
  return PriorityBand.critical;
}

String priorityBandLabel(PriorityBand b) => switch (b) {
      PriorityBand.low => 'LOW',
      PriorityBand.medium => 'MEDIUM',
      PriorityBand.high => 'HIGH',
      PriorityBand.critical => 'CRITICAL',
    };
