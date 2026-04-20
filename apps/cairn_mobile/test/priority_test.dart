import 'package:cairn_mobile/core/triage/priority.dart';
import 'package:flutter_test/flutter_test.dart';

ProtocolAnswers _defaultAnswers({
  bool collapse = false,
  bool offFoundation = false,
  String lean = 'none',
  bool ground = false,
  bool falling = false,
  bool adjacentLean = false,
}) =>
    ProtocolAnswers(
      visibleCollapse: collapse,
      buildingOffFoundation: offFoundation,
      leaning: lean,
      groundFailureAdjacent: ground,
      fallingHazards: falling,
      adjacentLeaning: adjacentLean,
    );

void main() {
  group('priorityScore — parity with Python', () {
    test('collapse => 10', () {
      expect(
        priorityScore(
          protocolAnswers: _defaultAnswers(collapse: true),
          hazardsFlagged: const [],
          building: const BuildingMeta(type: 'wood_light_frame', storiesAboveGrade: 2),
        ),
        10,
      );
    });

    test('off-foundation => 10', () {
      expect(
        priorityScore(
          protocolAnswers: _defaultAnswers(offFoundation: true),
          hazardsFlagged: const [],
          building: const BuildingMeta(type: 'wood_light_frame', storiesAboveGrade: 2),
        ),
        10,
      );
    });

    test('severe lean => 9', () {
      expect(
        priorityScore(
          protocolAnswers: _defaultAnswers(lean: 'severe'),
          hazardsFlagged: const [],
          building: const BuildingMeta(type: 'wood_light_frame', storiesAboveGrade: 2),
        ),
        9,
      );
    });

    test('urm + soft_story => 9', () {
      expect(
        priorityScore(
          protocolAnswers: _defaultAnswers(),
          hazardsFlagged: const [
            HazardFlag(code: 'H01_soft_story', severity: 'high'),
            HazardFlag(code: 'H02_unreinforced_masonry', severity: 'moderate'),
          ],
          building: const BuildingMeta(type: 'unreinforced_masonry', storiesAboveGrade: 3),
        ),
        9,
      );
    });

    test('clean building => 1', () {
      expect(
        priorityScore(
          protocolAnswers: _defaultAnswers(),
          hazardsFlagged: const [],
          building: const BuildingMeta(type: 'wood_light_frame', storiesAboveGrade: 2),
        ),
        1,
      );
    });

    test('ground + falling => 4', () {
      expect(
        priorityScore(
          protocolAnswers: _defaultAnswers(ground: true, falling: true),
          hazardsFlagged: const [],
          building: const BuildingMeta(type: 'wood_light_frame', storiesAboveGrade: 2),
        ),
        4,
      );
    });
  });

  group('priorityBand', () {
    test('bands match Python', () {
      expect(priorityBandLabel(priorityBand(1)), 'LOW');
      expect(priorityBandLabel(priorityBand(3)), 'LOW');
      expect(priorityBandLabel(priorityBand(4)), 'MEDIUM');
      expect(priorityBandLabel(priorityBand(6)), 'MEDIUM');
      expect(priorityBandLabel(priorityBand(7)), 'HIGH');
      expect(priorityBandLabel(priorityBand(8)), 'HIGH');
      expect(priorityBandLabel(priorityBand(9)), 'CRITICAL');
      expect(priorityBandLabel(priorityBand(10)), 'CRITICAL');
    });
  });
}
