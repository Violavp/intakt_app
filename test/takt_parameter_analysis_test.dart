import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intakt_app/gait_cycles/gait_cycles.dart';
import 'package:intakt_app/gait_segmentation/gait_segmentation.dart';
import 'package:intakt_app/takt_parameters/takt_parameters.dart';

void main() {
  const testConfig = TaktParameterConfig(
    minimumWindowSeconds: 10,
    maximumWindowSeconds: 10,
    stepSeconds: 10,
    minimumValidCyclesPerLeg: 6,
  );

  group('Takt parameter analysis', () {
    test('calculates traceable duration, frequency, variability and phases',
        () {
      final cycles = _regularTrot(durationSeconds: 20, periodSeconds: 1);
      final result = const TaktParameterAnalyzer(config: testConfig).analyze(
        cycles,
        _segmentation(20, GaitLabel.trot),
      );

      expect(result.status, TaktParameterStatus.accepted);
      expect(result.validWindows, hasLength(2));
      final first = result.validWindows.first;
      expect(first.meanCycleDuration.value, closeTo(1, 1e-9));
      expect(first.cycleFrequency.value, closeTo(1, 1e-9));
      expect(first.cycleDurationVariability.value, closeTo(0, 1e-9));
      expect(first.cycleDurationDrift.value, closeTo(0, 1e-9));
      expect(first.legSummaries.keys, ['VL', 'VR', 'HL', 'HR']);
      expect(
        first.legSummaries.values.every(
          (summary) =>
              summary.validCycleCount >= 6 &&
              summary.cycleIds.isNotEmpty &&
              summary.meanCycleDuration.standardUncertainty != null,
        ),
        isTrue,
      );
      final diagonal = first.phaseRelations.singleWhere(
        (relation) =>
            relation.referenceSensor == 'VL' && relation.targetSensor == 'HR',
      );
      expect(diagonal.expectedPhase, 0);
      expect(diagonal.meanPhase.value, closeTo(0, 1e-9));
      expect(diagonal.sourceCycleIds, isNotEmpty);
      expect(first.temporalSymmetryDeviation.value, closeTo(0, 1e-9));
    });

    test('explains worsening only beyond combined uncertainty', () {
      final cycles = _twoWindowTrot(
        firstDurations: const [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        secondDurations: const [
          0.82,
          1.18,
          0.84,
          1.16,
          0.80,
          1.20,
          0.83,
          1.17,
          0.81,
        ],
      );
      final result = const TaktParameterAnalyzer(config: testConfig).analyze(
        cycles,
        _segmentation(20, GaitLabel.trot),
      );

      final current = result.validWindows.last;
      final variability = current.comparisons.singleWhere(
        (comparison) => comparison.component == 'cycle_duration_variability',
      );
      expect(variability.assessment, TaktChangeAssessment.worsened);
      expect(
        current.explanatoryObservations,
        contains('cycle_duration_variability_worsened'),
      );
      final frequency = current.comparisons.singleWhere(
        (comparison) => comparison.component == 'cycle_frequency',
      );
      expect(
        frequency.assessment,
        TaktChangeAssessment.stableWithinUncertainty,
      );
    });

    test('detects a known increase in cycle duration as positive tempo drift',
        () {
      final increasing = [
        for (var index = 0; index < 10; index++) 0.80 + index * 0.04,
      ];
      final result = const TaktParameterAnalyzer(
        config: testConfig,
      ).analyze(
        _cyclesFromDurations(
          gait: GaitLabel.trot,
          durationSeconds: 20,
          durationsForLeg: {
            for (final label in const ['VL', 'VR', 'HL', 'HR'])
              label: increasing,
          },
          phaseOffsets: const {'VL': 0, 'VR': 0.5, 'HL': 0.5, 'HR': 0},
        ),
        _segmentation(20, GaitLabel.trot),
      );

      expect(
          result.validWindows.first.cycleDurationDrift.value, greaterThan(0));
      expect(
        result.validWindows.first.cycleDurationDrift.confidenceIntervalLower,
        greaterThan(0),
      );
    });

    test('measures phase dispersion and known temporal symmetry deviation', () {
      final targetDurations = [
        for (var index = 0; index < 10; index++) index.isEven ? 0.90 : 1.10,
      ];
      final dispersed = const TaktParameterAnalyzer(config: testConfig).analyze(
        _cyclesFromDurations(
          gait: GaitLabel.trot,
          durationSeconds: 20,
          durationsForLeg: {
            'VL': List.filled(10, 1.0),
            'VR': targetDurations,
            'HL': List.filled(10, 1.0),
            'HR': targetDurations,
          },
          phaseOffsets: const {'VL': 0, 'VR': 0.6, 'HL': 0.5, 'HR': 0.1},
        ),
        _segmentation(20, GaitLabel.trot),
      );
      final shifted = const TaktParameterAnalyzer(
        config: testConfig,
      ).analyze(
        _cyclesFromDurations(
          gait: GaitLabel.trot,
          durationSeconds: 20,
          durationsForLeg: {
            for (final label in const ['VL', 'VR', 'HL', 'HR'])
              label: List.filled(10, 1.0),
          },
          phaseOffsets: const {'VL': 0, 'VR': 0.6, 'HL': 0.5, 'HR': 0.1},
        ),
        _segmentation(20, GaitLabel.trot),
      );

      expect(
          dispersed.validWindows.first.phaseDispersion.value, greaterThan(0));
      expect(
        shifted.validWindows.first.temporalSymmetryDeviation.value,
        closeTo(10, 1e-9),
      );
      expect(
        shifted
            .validWindows.first.temporalSymmetryDeviation.standardUncertainty,
        isNotNull,
      );
    });

    test('marks insufficient windows invalid without replacement values', () {
      final cycles = _regularTrot(durationSeconds: 10, periodSeconds: 2);
      final result = const TaktParameterAnalyzer(config: testConfig).analyze(
        cycles,
        _segmentation(10, GaitLabel.trot),
      );

      expect(result.status, TaktParameterStatus.notPossible);
      expect(result.windows, hasLength(1));
      final window = result.windows.single;
      expect(window.valid, isFalse);
      expect(window.invalidReasons, contains('insufficient_valid_cycles_VL'));
      expect(window.meanCycleDuration.value, isNull);
      expect(window.cycleFrequency.value, isNull);
      expect(window.temporalSymmetryDeviation.value, isNull);
    });

    test('extends the window only until every leg has enough cycles', () {
      const adaptiveConfig = TaktParameterConfig(
        minimumWindowSeconds: 10,
        maximumWindowSeconds: 20,
        stepSeconds: 5,
        minimumValidCyclesPerLeg: 6,
      );
      final result =
          const TaktParameterAnalyzer(config: adaptiveConfig).analyze(
        _regularTrot(durationSeconds: 20, periodSeconds: 2),
        _segmentation(20, GaitLabel.trot),
      );

      expect(result.windows.first.valid, isFalse);
      expect(result.validWindows, isNotEmpty);
      expect(
        result.validWindows.every((window) => window.durationSeconds == 15),
        isTrue,
      );
      expect(
        result.validWindows.every(
          (window) => window.legSummaries.values.every(
            (summary) => summary.validCycleCount >= 6,
          ),
        ),
        isTrue,
      );
    });

    test('keeps walk diagonal target explicitly undefined', () {
      final result = const TaktParameterAnalyzer(config: testConfig).analyze(
        _regularWalk(durationSeconds: 10, periodSeconds: 1),
        _segmentation(10, GaitLabel.walk),
      );

      final diagonal = result.validWindows.single.phaseRelations.singleWhere(
        (relation) =>
            relation.referenceSensor == 'VL' && relation.targetSensor == 'HR',
      );
      expect(diagonal.expectedPhase, isNull);
      expect(diagonal.absoluteExpectedPhaseDeviation.valid, isFalse);
      expect(diagonal.absoluteExpectedPhaseDeviation.value, isNull);
    });

    test('serializes reports, uncertainty, invalidity and trend output', () {
      final result = const TaktParameterAnalyzer(config: testConfig).analyze(
        _regularTrot(durationSeconds: 20, periodSeconds: 1),
        _segmentation(20, GaitLabel.trot),
      );
      final report = jsonDecode(taktParameterReportJson(result)) as Map;
      final csv = const TaktWindowCsv().render(result);
      final svg = const TaktTrendSvg().render(result);

      expect(report['takt_parameters']['valid_window_count'], 2);
      expect(
        report['takt_parameters']['windows'][0]['mean_cycle_duration']
            ['confidence_interval_95'],
        isNotNull,
      );
      expect(csv, contains('cycle_duration_cv_percent'));
      expect(csv, contains('comparison_observations'));
      expect(svg, contains('Zeitlicher Taktverlauf'));
      expect(svg, contains('keine Takt-, Reit- oder Medizinwertung'));
    });

    test('loads central configuration and rejects invalid window ranges', () {
      final config = TaktParameterConfig.fromJsonString(
        File('config/taktparameter.v1.json').readAsStringSync(),
      );
      expect(config.minimumWindowSeconds, 10);
      expect(config.maximumWindowSeconds, 20);
      expect(config.stepSeconds, 1);
      expect(config.minimumValidCyclesPerLeg, 6);

      expect(
        () => const TaktParameterAnalyzer(
          config: TaktParameterConfig(
            minimumWindowSeconds: 10,
            maximumWindowSeconds: 5,
          ),
        ).analyze(
          _regularTrot(durationSeconds: 20, periodSeconds: 1),
          _segmentation(20, GaitLabel.trot),
        ),
        throwsArgumentError,
      );
      expect(
        () => TaktParameterConfig.fromJsonString(
          '{"minimum_valid_cycles_per_leg": 6.5}',
        ),
        throwsFormatException,
      );
    });
  });
}

GaitCycleDetectionResult _regularTrot({
  required double durationSeconds,
  required double periodSeconds,
}) =>
    _cyclesFromDurations(
      gait: GaitLabel.trot,
      durationSeconds: durationSeconds,
      durationsForLeg: {
        for (final label in const ['VL', 'VR', 'HL', 'HR'])
          label: [
            for (var time = 0.0;
                time + periodSeconds <= durationSeconds + 1e-9;
                time += periodSeconds)
              periodSeconds,
          ],
      },
      phaseOffsets: const {'VL': 0, 'VR': 0.5, 'HL': 0.5, 'HR': 0},
    );

GaitCycleDetectionResult _regularWalk({
  required double durationSeconds,
  required double periodSeconds,
}) =>
    _cyclesFromDurations(
      gait: GaitLabel.walk,
      durationSeconds: durationSeconds,
      durationsForLeg: {
        for (final label in const ['VL', 'VR', 'HL', 'HR'])
          label: [
            for (var time = 0.0;
                time + periodSeconds <= durationSeconds + 1e-9;
                time += periodSeconds)
              periodSeconds,
          ],
      },
      phaseOffsets: const {'VL': 0, 'VR': 0.5, 'HL': 0.75, 'HR': 0.25},
    );

GaitCycleDetectionResult _twoWindowTrot({
  required List<double> firstDurations,
  required List<double> secondDurations,
}) {
  final durations = [...firstDurations, ...secondDurations];
  return _cyclesFromDurations(
    gait: GaitLabel.trot,
    durationSeconds: 20,
    durationsForLeg: {
      for (final label in const ['VL', 'VR', 'HL', 'HR']) label: durations,
    },
    phaseOffsets: const {'VL': 0, 'VR': 0.5, 'HL': 0.5, 'HR': 0},
  );
}

GaitCycleDetectionResult _cyclesFromDurations({
  required GaitLabel gait,
  required double durationSeconds,
  required Map<String, List<double>> durationsForLeg,
  required Map<String, double> phaseOffsets,
}) {
  final events = <DetectedGaitEvent>[];
  final cycles = <GaitCycle>[];
  for (final label in const ['VL', 'VR', 'HL', 'HR']) {
    final durations = durationsForLeg[label]!;
    var start = phaseOffsets[label]!;
    for (var index = 0; index < durations.length; index++) {
      final duration = durations[index];
      final end = start + duration;
      if (end > durationSeconds + 1e-9) break;
      final startEvent = _event('$label-$index-start', label, gait, start);
      final liftoffEvent =
          _event('$label-$index-liftoff', label, gait, start + duration * 0.55);
      final endEvent = _event('$label-$index-end', label, gait, end);
      events.addAll([startEvent, liftoffEvent, endEvent]);
      cycles.add(
        GaitCycle(
          id: '$label-cycle-$index',
          sensorLabel: label,
          gait: gait,
          startEventId: startEvent.id,
          liftoffEventId: liftoffEvent.id,
          endEventId: endEvent.id,
          startSeconds: start,
          endSeconds: end,
          liftoffSeconds: liftoffEvent.timeSeconds,
          durationUncertaintyMilliseconds: math.sqrt(2),
          stanceUncertaintyMilliseconds: math.sqrt(2),
          swingUncertaintyMilliseconds: math.sqrt(2),
          quality: 1,
          plausible: true,
          exclusionReasons: const [],
          sampleCoverage: 1,
          durationDeviationFraction: 0,
          userConfirmed: true,
        ),
      );
      start = end;
    }
  }
  events.sort((left, right) => left.timeSeconds.compareTo(right.timeSeconds));
  cycles.sort((left, right) => left.startSeconds.compareTo(right.startSeconds));
  return GaitCycleDetectionResult(
    status: GaitCycleDetectionStatus.accepted,
    events: events,
    cycles: cycles,
    issues: const [],
    config: const GaitCycleDetectionConfig(),
    assumptions: const [],
  );
}

DetectedGaitEvent _event(
  String id,
  String sensor,
  GaitLabel gait,
  double time,
) =>
    DetectedGaitEvent(
      id: id,
      sensorLabel: sensor,
      gait: gait,
      kind: id.contains('liftoff')
          ? GaitEventKind.liftoff
          : GaitEventKind.touchdown,
      timeSeconds: time,
      quality: 1,
      source: GaitEventSource.userCorrection,
      canonicalGyroYRadPerSecond: 1,
      canonicalAccelerationXMps2: 1,
      sourceName: 'synthetic.txt',
      sourceLine: (time * 100).round() + 1,
      sourceUncertaintyMilliseconds: 1,
    );

GaitSegmentationResult _segmentation(double duration, GaitLabel gait) =>
    GaitSegmentationResult(
      status: SegmentationStatus.accepted,
      segments: [
        GaitSegment(
          startSeconds: 0,
          endSeconds: duration,
          gait: gait,
          confidence: 1,
          uncertainty: 0,
          dominantFrequencyHz: 1,
          diagonalSynchrony: 1,
          movementRmsMps2: 1,
          coverage: 1,
          transition: false,
          turn: false,
          interruption: false,
          analyzable: true,
          manuallyCorrected: false,
          correctionReasons: const [],
          sourceLines: const {},
          ridingDirection: RidingDirection.left,
        ),
      ],
      issues: const [],
      config: const GaitSegmentationConfig(),
      corrections: const [],
      gaitSignalClusters: const [],
      assumptions: const [],
    );
