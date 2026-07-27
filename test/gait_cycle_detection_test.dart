import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intakt_app/gait_cycles/gait_cycles.dart';
import 'package:intakt_app/gait_segmentation/gait_segmentation.dart';
import 'package:intakt_app/imu_import/imu_models.dart';
import 'package:intakt_app/imu_preprocessing/imu_preprocessing.dart';
import 'package:intakt_app/imu_sync/index_time_reconstruction.dart';

void main() {
  group('Gait cycle detection', () {
    test('detects ordered events and touchdown-to-touchdown cycles', () {
      final input = _input(durationSeconds: 8, periodSeconds: 1.2);
      final result = const GaitCycleDetector().detect(
        input,
        _segmentation(8, GaitLabel.walk),
      );

      expect(result.status, isNot(GaitCycleDetectionStatus.notPossible));
      expect(
        result.events.map((event) => event.sensorLabel).toSet(),
        containsAll(['VL', 'VR', 'HL', 'HR']),
      );
      expect(result.cycles, isNotEmpty);
      expect(
        result.cycles.every(
          (cycle) =>
              cycle.startSeconds < cycle.liftoffSeconds &&
              cycle.liftoffSeconds < cycle.endSeconds &&
              cycle.durationSeconds > 0 &&
              cycle.quality >= 0 &&
              cycle.quality <= 1,
        ),
        isTrue,
      );
    });

    test('applies user corrections and canonicalizes mirrored right axes', () {
      final input = _input(durationSeconds: 5, periodSeconds: 1.0);
      const corrections = [
        ManualGaitEventCorrection(
          sensorLabel: 'HR',
          gait: GaitLabel.trot,
          kind: GaitEventKind.touchdown,
          timeSeconds: 1.0,
          source: 'test',
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'HR',
          gait: GaitLabel.trot,
          kind: GaitEventKind.liftoff,
          timeSeconds: 1.5,
          source: 'test',
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'HR',
          gait: GaitLabel.trot,
          kind: GaitEventKind.touchdown,
          timeSeconds: 2.0,
          source: 'test',
        ),
      ];
      final result = const GaitCycleDetector().detect(
        input,
        _segmentation(5, GaitLabel.trot),
        corrections: corrections,
      );

      final corrected = result.events.where(
        (event) =>
            event.sensorLabel == 'HR' &&
            event.source == GaitEventSource.userCorrection,
      );
      expect(corrected.length, 3);
      expect(
        corrected.every(
          (event) => event.canonicalGyroYRadPerSecond >= 0,
        ),
        isTrue,
      );
      expect(
        result.cycles.any(
          (cycle) => cycle.sensorLabel == 'HR' && cycle.userConfirmed,
        ),
        isTrue,
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains('user_event_corrections_applied'),
      );
    });

    test('keeps the confirmed VR walk-right pattern traceable and bounded', () {
      final root = jsonDecode(
        File(
          'config/gangereignisse-test01-nutzerbestaetigt.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final events = (root['events'] as List).cast<Map<String, dynamic>>();
      final vrWalkRight = events
          .where(
            (event) =>
                event['sensor'] == 'VR' &&
                event['gait'] == 'WALK' &&
                event['direction'] == 'RIGHT',
          )
          .toList();

      expect(
        [
          for (final event in vrWalkRight)
            (
              event['event'] as String,
              (event['time_s'] as num).toDouble(),
            ),
        ],
        const [
          ('liftoff', 100.74),
          ('touchdown', 101.26),
          ('liftoff', 101.98),
          ('touchdown', 102.50),
          ('liftoff', 103.20),
          ('touchdown', 103.68),
          ('liftoff', 104.48),
          ('touchdown', 104.96),
          ('liftoff', 105.71),
          ('touchdown', 106.22),
          ('liftoff', 106.96),
          ('touchdown', 107.49),
        ],
      );
      expect(
        vrWalkRight.every(
          (event) =>
              event['source'] == 'user_confirmation' &&
              (event['time_s'] as num) <= 108,
        ),
        isTrue,
      );
    });

    test('marks implausible duration without deleting the cycle', () {
      final input = _input(durationSeconds: 7, periodSeconds: 2.0);
      final result = const GaitCycleDetector().detect(
        input,
        _segmentation(7, GaitLabel.walk),
      );

      expect(result.cycles, isNotEmpty);
      expect(result.cycles.any((cycle) => !cycle.plausible), isTrue);
      expect(
        result.cycles
            .where((cycle) => !cycle.plausible)
            .expand((cycle) => cycle.exclusionReasons),
        contains('cycle_duration_outside_recording_calibration'),
      );
    });

    test('learns signed AsY and AccX event patterns per riding direction', () {
      final input = _input(
        durationSeconds: 6,
        periodSeconds: 1,
        invertedActivitySensors: const {'HL'},
      );
      const corrections = [
        ManualGaitEventCorrection(
          sensorLabel: 'HL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.liftoff,
          timeSeconds: 0.55,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'HL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.touchdown,
          timeSeconds: 1,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'HL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.liftoff,
          timeSeconds: 1.55,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'HL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.touchdown,
          timeSeconds: 2,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'HL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.liftoff,
          timeSeconds: 2.55,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'HL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.touchdown,
          timeSeconds: 3,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
      ];
      final result = const GaitCycleDetector().detect(
        input,
        _segmentation(
          6,
          GaitLabel.trot,
          direction: RidingDirection.left,
        ),
        corrections: corrections,
      );

      final calibrated = result.events.where(
        (event) =>
            event.sensorLabel == 'HL' &&
            event.source == GaitEventSource.automatic &&
            event.timeSeconds > 3.2,
      );
      expect(calibrated, isNotEmpty);
      expect(
        calibrated.every(
          (event) =>
              event.patternCalibration == 'DIRECTION_PATTERN_CALIBRATED' &&
              event.ridingDirection == RidingDirection.left &&
              event.patternSupportCount == corrections.length,
        ),
        isTrue,
      );
      final first = calibrated.first;
      expect(first.kind, GaitEventKind.liftoff);
      expect(first.timeSeconds, closeTo(3.55, 0.12));
    });

    test('learns every leg pattern without transferring it to other direction',
        () {
      final input = _input(
        durationSeconds: 10,
        periodSeconds: 1,
        staggerLegPhases: false,
      );
      final corrections = <ManualGaitEventCorrection>[
        for (final sensor in const ['VL', 'VR', 'HL', 'HR'])
          for (final event in const [
            (GaitEventKind.liftoff, 0.55),
            (GaitEventKind.touchdown, 1.0),
            (GaitEventKind.liftoff, 1.55),
            (GaitEventKind.touchdown, 2.0),
            (GaitEventKind.liftoff, 2.55),
            (GaitEventKind.touchdown, 3.0),
          ])
            ManualGaitEventCorrection(
              sensorLabel: sensor,
              gait: GaitLabel.trot,
              kind: event.$1,
              timeSeconds: event.$2,
              source: 'test',
              ridingDirection: RidingDirection.left,
            ),
      ];
      final result = const GaitCycleDetector().detect(
        input,
        _segmentationWithDirections(),
        corrections: corrections,
      );

      for (final sensor in const ['VL', 'VR', 'HL', 'HR']) {
        final leftAutomatic = result.events.where(
          (event) =>
              event.sensorLabel == sensor &&
              event.source == GaitEventSource.automatic &&
              event.ridingDirection == RidingDirection.left,
        );
        final rightAutomatic = result.events.where(
          (event) =>
              event.sensorLabel == sensor &&
              event.source == GaitEventSource.automatic &&
              event.ridingDirection == RidingDirection.right,
        );
        expect(leftAutomatic, isNotEmpty);
        expect(
          leftAutomatic.every(
            (event) =>
                event.patternCalibration == 'DIRECTION_PATTERN_CALIBRATED',
          ),
          isTrue,
        );
        expect(rightAutomatic, isNotEmpty);
        expect(
          rightAutomatic.every(
            (event) => event.patternCalibration == 'UNCALIBRATED_DEFAULT',
          ),
          isTrue,
        );
      }
    });

    test('uses AccX pattern when AsY alone contains no event shape', () {
      final input = _input(
        durationSeconds: 6,
        periodSeconds: 1,
        accelerationOnlyEvents: true,
      );
      const corrections = [
        ManualGaitEventCorrection(
          sensorLabel: 'VL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.liftoff,
          timeSeconds: 0.55,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'VL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.touchdown,
          timeSeconds: 1,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'VL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.liftoff,
          timeSeconds: 1.55,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'VL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.touchdown,
          timeSeconds: 2,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'VL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.liftoff,
          timeSeconds: 2.55,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
        ManualGaitEventCorrection(
          sensorLabel: 'VL',
          gait: GaitLabel.trot,
          kind: GaitEventKind.touchdown,
          timeSeconds: 3,
          source: 'test',
          ridingDirection: RidingDirection.left,
        ),
      ];
      final result = const GaitCycleDetector().detect(
        input,
        _segmentation(
          6,
          GaitLabel.trot,
          direction: RidingDirection.left,
        ),
        corrections: corrections,
      );

      final automatic = result.events.where(
        (event) =>
            event.sensorLabel == 'VL' &&
            event.source == GaitEventSource.automatic &&
            event.timeSeconds > 3.2 &&
            event.patternCalibration == 'DIRECTION_PATTERN_CALIBRATED',
      );
      expect(automatic, isNotEmpty);
      expect(
        automatic.map((event) => event.kind).toSet(),
        containsAll([GaitEventKind.touchdown, GaitEventKind.liftoff]),
      );
    });

    test('serializes quality, exclusions and review plot', () {
      final input = _input(durationSeconds: 6, periodSeconds: 1.2);
      final result = const GaitCycleDetector().detect(
        input,
        _segmentation(6, GaitLabel.walk),
      );
      final report = jsonDecode(gaitCycleDetectionReportJson(result)) as Map;
      final csv = const GaitCycleCsv().render(result);
      final events = const GaitEventCsv().render(result);
      final svg = const GaitCycleSvg().render(input, result);

      expect(report['cycle_detection']['cycles'], isNotEmpty);
      expect(csv, contains('start_s,liftoff_s,end_s'));
      expect(csv, contains('exclusion_reasons'));
      expect(events, contains('canonical_gyro_y_radps'));
      expect(events, contains('pattern_calibration'));
      expect(svg, contains('Gangereignisse und Gangzyklen'));
      expect(svg, contains('gespiegelt'));
    });

    test('rejects missing dataset and out-of-range correction', () {
      const missing = ImuPreprocessingResult(
        status: PreprocessingStatus.notPossible,
        gridSamplingRateHz: 100,
        frames: [],
        sensorQuality: {},
        issues: [],
        config: ImuPreprocessingConfig(),
        assumptions: [],
      );
      final failed = const GaitCycleDetector().detect(
        missing,
        _segmentation(4, GaitLabel.walk),
      );
      expect(failed.status, GaitCycleDetectionStatus.notPossible);

      expect(
        () => const GaitCycleDetector().detect(
          _input(durationSeconds: 4, periodSeconds: 1.2),
          _segmentation(4, GaitLabel.walk),
          corrections: const [
            ManualGaitEventCorrection(
              sensorLabel: 'VL',
              gait: GaitLabel.walk,
              kind: GaitEventKind.touchdown,
              timeSeconds: 99,
              source: 'test',
            ),
          ],
        ),
        throwsFormatException,
      );
    });
  });
}

ImuPreprocessingResult _input({
  required double durationSeconds,
  required double periodSeconds,
  Set<String> invertedActivitySensors = const {},
  bool staggerLegPhases = true,
  bool accelerationOnlyEvents = false,
}) {
  const rate = 100.0;
  final frames = <PreprocessedFrame>[];
  final count = (durationSeconds * rate).round() + 1;
  for (var index = 0; index < count; index++) {
    final time = index / rate;
    final values = <String, PreprocessedImuValue?>{};
    for (var legIndex = 0; legIndex < 4; legIndex++) {
      final label = const ['VL', 'VR', 'HL', 'HR'][legIndex];
      final phaseOffset = staggerLegPhases ? legIndex * periodSeconds / 4 : 0.0;
      final phase = ((time + phaseOffset) % periodSeconds) / periodSeconds;
      final swing = phase >= 0.55;
      final activityHigh =
          invertedActivitySensors.contains(label) ? !swing : swing;
      final canonicalGyro = accelerationOnlyEvents
          ? 1.0
          : activityHigh
              ? 2.2 + 0.8 * math.sin(phase * math.pi * 2).abs()
              : 0.08;
      final touchdownDistance = math.min(phase, 1 - phase);
      final liftoffDistance = (phase - 0.55).abs();
      final canonicalAcc = accelerationOnlyEvents
          ? math.max(0, 1 - touchdownDistance / 0.08) * 8 -
              math.max(0, 1 - liftoffDistance / 0.08) * 6
          : swing
              ? 4.0 * math.sin(phase * math.pi * 4)
              : 0.15;
      final sign = label.endsWith('R') ? -1.0 : 1.0;
      values[label] = _value(
        time,
        index,
        gyroY: sign * canonicalGyro,
        accelerationX: sign * canonicalAcc,
      );
    }
    frames.add(PreprocessedFrame(analysisTimeSeconds: time, values: values));
  }
  return ImuPreprocessingResult(
    status: PreprocessingStatus.accepted,
    gridSamplingRateHz: rate,
    frames: frames,
    sensorQuality: const {},
    issues: const [],
    config: const ImuPreprocessingConfig(),
    assumptions: const [],
  );
}

PreprocessedImuValue _value(
  double time,
  int line, {
  required double gyroY,
  required double accelerationX,
}) {
  final raw = ResampledImuValue(
    accelerationMps2: Vector3(accelerationX, 0, 9.80665),
    angularVelocityRadPerSecond: Vector3(0, gyroY, 0),
    magneticFieldMicrotesla: null,
    lowerSampleIndex: line,
    upperSampleIndex: line,
    lowerSourceName: 'synthetic.txt',
    lowerSourceLine: line + 1,
    upperSourceName: 'synthetic.txt',
    upperSourceLine: line + 1,
    uncertaintyMilliseconds: 1,
  );
  return PreprocessedImuValue(
    raw: raw,
    cleanedAccelerationMps2: Vector3(accelerationX, 0, 9.80665),
    cleanedAngularVelocityRadPerSecond: Vector3(0, gyroY, 0),
    filteredAccelerationSensorFrameMps2: Vector3(accelerationX, 0, 9.80665),
    filteredAngularVelocitySensorFrameRadPerSecond: Vector3(0, gyroY, 0),
    alignedAccelerationMps2: Vector3(accelerationX, 0, 9.80665),
    alignedAngularVelocityRadPerSecond: Vector3(0, gyroY, 0),
    gravityMps2: const Vector3(0, 0, 9.80665),
    movementAccelerationMps2: Vector3(accelerationX, 0, 0),
    alignedMagneticFieldMicrotesla: null,
    outlierReplaced: false,
    processingTemporalResolutionMilliseconds: 1,
  );
}

GaitSegmentationResult _segmentation(
  double duration,
  GaitLabel gait, {
  RidingDirection direction = RidingDirection.unknown,
}) =>
    GaitSegmentationResult(
      status: SegmentationStatus.accepted,
      segments: [
        GaitSegment(
          startSeconds: 0,
          endSeconds: duration,
          gait: gait,
          confidence: 0.9,
          uncertainty: 0.1,
          dominantFrequencyHz: 1,
          diagonalSynchrony: 0.9,
          movementRmsMps2: 1,
          coverage: 1,
          transition: false,
          turn: false,
          interruption: false,
          analyzable: true,
          manuallyCorrected: false,
          correctionReasons: const [],
          sourceLines: const {},
          ridingDirection: direction,
        ),
      ],
      issues: const [],
      config: const GaitSegmentationConfig(),
      corrections: const [],
      gaitSignalClusters: const [],
      assumptions: const [],
    );

GaitSegmentationResult _segmentationWithDirections() => GaitSegmentationResult(
      status: SegmentationStatus.accepted,
      segments: [
        for (final entry in const [
          (0.0, 5.0, RidingDirection.left),
          (5.0, 10.0, RidingDirection.right),
        ])
          GaitSegment(
            startSeconds: entry.$1,
            endSeconds: entry.$2,
            gait: GaitLabel.trot,
            confidence: 0.9,
            uncertainty: 0.1,
            dominantFrequencyHz: 1,
            diagonalSynchrony: 0.9,
            movementRmsMps2: 1,
            coverage: 1,
            transition: false,
            turn: false,
            interruption: false,
            analyzable: true,
            manuallyCorrected: false,
            correctionReasons: const [],
            sourceLines: const {},
            ridingDirection: entry.$3,
          ),
      ],
      issues: const [],
      config: const GaitSegmentationConfig(),
      corrections: const [],
      gaitSignalClusters: const [],
      assumptions: const [],
    );
