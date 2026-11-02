import 'package:flutter_test/flutter_test.dart';
import 'package:intakt_app/core_metrics/takt_metric.dart';
import 'package:intakt_app/gait_cycles/gait_cycles.dart';
import 'package:intakt_app/gait_segmentation/gait_segmentation.dart';
import 'package:intakt_app/takt_parameters/takt_parameters.dart';

void main() {
  group('TaktTilePresentation', () {
    test('shows empty state without result', () {
      final presentation = TaktTilePresentation.fromResult(null);

      expect(presentation.resultLabel, 'Noch keine Auswertung');
      expect(presentation.details, isEmpty);
      expect(presentation.validWindowCount, 0);
      expect(presentation.requiresReview, isFalse);
    });

    test('keeps not-possible analysis explicit', () {
      const result = TaktParameterResult(
        status: TaktParameterStatus.notPossible,
        windows: [],
        issues: [
          TaktParameterIssue(
            code: 'no_valid_takt_windows',
            observation: 'Kein gültiges Fenster.',
            uncertainty: 'Ereignisse sind nicht ausreichend sicher.',
            recommendation: 'TD/LO prüfen.',
          ),
        ],
        config: TaktParameterConfig(),
        assumptions: [],
      );

      final presentation = TaktTilePresentation.fromResult(result);

      expect(presentation.resultLabel, 'Nicht auswertbar');
      expect(presentation.requiresReview, isTrue);
      expect(
        presentation.details.join(' '),
        contains('Kein gültiges Fenster.'),
      );
    });

    test('summarizes descriptive metrics without quality cut-offs', () {
      final result = TaktParameterResult(
        status: TaktParameterStatus.accepted,
        windows: [
          _window(
            id: 'w1',
            gait: GaitLabel.trot,
            variability: 3.2,
            phaseDispersion: 0.04,
            symmetry: 1.8,
          ),
        ],
        issues: const [],
        config: const TaktParameterConfig(minimumValidCyclesPerLeg: 6),
        assumptions: const [],
      );

      final presentation = TaktTilePresentation.fromResult(result);

      expect(presentation.resultLabel, '1 gültige Fenster');
      expect(presentation.requiresReview, isFalse);
      expect(
        presentation.details,
        contains('Trab · Zyklusvariabilität (Median): 3.2 %'),
      );
      expect(
        presentation.details,
        contains('Trab · Phasenstreuung (Median): 4 % des Zyklus'),
      );
      expect(
        presentation.details,
        contains(
          'Trab · zeitliche Symmetrieabweichung (Median): 1.8 % des Zyklus',
        ),
      );
    });
  });
}

TaktAnalysisWindow _window({
  required String id,
  required GaitLabel gait,
  required double variability,
  required double phaseDispersion,
  required double symmetry,
}) {
  TaktMetric metric(double value, String unit) => TaktMetric.valid(
        value: value,
        unit: unit,
        standardUncertainty: 0.1,
        confidenceIntervalLower: value - 0.2,
        confidenceIntervalUpper: value + 0.2,
      );

  return TaktAnalysisWindow(
    id: id,
    startSeconds: 0,
    endSeconds: 10,
    gait: gait,
    ridingDirection: RidingDirection.left,
    valid: true,
    invalidReasons: const [],
    legSummaries: const {},
    meanCycleDuration: metric(0.8, 's'),
    cycleFrequency: metric(1.25, 'Hz'),
    cycleDurationVariability: metric(variability, 'percent'),
    cycleDurationDrift: metric(0, 's/s'),
    phaseRelations: const [],
    phaseDispersion: metric(phaseDispersion, 'cycle_fraction'),
    temporalSymmetryDeviation: metric(symmetry, 'percent_cycle'),
    comparisons: const [],
    explanatoryObservations: const [],
  );
}
