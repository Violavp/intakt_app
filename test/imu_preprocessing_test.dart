import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intakt_app/imu_import/imu_import.dart';
import 'package:intakt_app/imu_preprocessing/imu_preprocessing.dart';
import 'package:intakt_app/imu_sync/imu_sync.dart';

void main() {
  group('IMU preprocessing', () {
    test('filters noise, aligns gravity, and preserves raw traceability', () {
      final input = _fixture();
      final originalRaw = input.frames[100].values['VL'];
      final result = const ImuPreprocessor().process(input);

      expect(result.hasDataset, isTrue);
      expect(result.frames, hasLength(input.frames.length));
      expect(result.sensorQuality.keys, containsAll(_labels));
      final quality = result.sensorQuality['VL']!;
      expect(quality.orientation.valid, isTrue);
      expect(quality.orientation.gravityMagnitudeMps2, closeTo(9.80665, 0.3));
      expect(quality.filterComparisons, hasLength(2));
      expect(
        quality.filterComparisons.first.roughnessRmsMps2,
        lessThan(quality.filterComparisons.last.roughnessRmsMps2 * 1.4),
      );
      final value = result.frames[100].values['VL']!;
      expect(identical(value.raw, originalRaw), isTrue);
      expect(value.alignedAccelerationMps2.z, closeTo(9.80665, 0.4));
      expect(value.alignedAccelerationMps2.x.abs(), lessThan(0.3));
      expect(value.raw.lowerSourceLine, 102);
    });

    test('replaces an isolated spike but retains a multi-sample event', () {
      final result = const ImuPreprocessor().process(
        _fixture(isolatedSpikeIndex: 250, eventStart: 320),
      );
      final quality = result.sensorQuality['VL']!;

      expect(result.frames[250].values['VL']!.outlierReplaced, isTrue);
      expect(quality.replacedOutlierSamples, greaterThan(0));
      final eventMovement = [
        for (var index = 320; index < 326; index++)
          _magnitude(
            result.frames[index].values['VL']!.movementAccelerationMps2,
          ),
      ];
      expect(eventMovement.reduce(math.max), greaterThan(2));
      final selected = quality.filterComparisons.first;
      expect(
          selected.strongestEventTimeShiftMilliseconds, lessThanOrEqualTo(10));
      expect(
        selected.peakToPeakRetention,
        greaterThanOrEqualTo(
          const ImuPreprocessingConfig().minimumEventPeakRetention,
        ),
      );
    });

    test('does not bridge gaps and reports short residual segments', () {
      final input = _fixture(gapStart: 200, gapLength: 5);
      final result = const ImuPreprocessor().process(input);

      for (var index = 200; index < 205; index++) {
        expect(result.frames[index].values['VL'], isNull);
      }
      expect(result.sensorQuality['VL']!.gapSamples, 5);

      final shortTail = _fixture(gapStart: 480, gapLength: 5);
      final shortResult = const ImuPreprocessor().process(shortTail);
      expect(shortResult.frames.last.values['VL'], isNull);
      expect(
        shortResult.issues.map((issue) => issue.code),
        contains('short_segment_not_filtered'),
      );
    });

    test('handles irregular cycles and different configured sampling rates',
        () {
      final input = _fixture(
        samplingRateHz: 80,
        sampleCount: 400,
        irregularCycles: true,
      );
      const config = ImuPreprocessingConfig(
        lowPassCutoffHz: 16,
        gravityCutoffHz: 0.4,
        minimumSegmentSamples: 16,
      );
      final first = const ImuPreprocessor(config: config).process(input);
      final second = const ImuPreprocessor(config: config).process(input);

      expect(first.hasDataset, isTrue);
      expect(first.toJson(), second.toJson());
      expect(first.frames.length, 400);
      expect(
        first.sensorQuality.values
            .every((quality) => quality.outputSamples > 0),
        isTrue,
      );
    });

    test('rejects empty, non-finite, non-monotonic, and short inputs', () {
      const empty = IndexTimeReconstructionResult(
        status: TimeReconstructionStatus.notPossible,
        gridSamplingRateHz: 100,
        gridPeriodMicroseconds: 10000,
        commonStartSeconds: null,
        commonEndSeconds: null,
        sensors: {},
        frames: [],
        issues: [],
        assumptions: [],
      );
      expect(
        const ImuPreprocessor().process(empty).status,
        PreprocessingStatus.notPossible,
      );

      final nan = _fixture();
      nan.frames[10].values['VL'] = _value(10, accelerationX: double.nan);
      expect(
        const ImuPreprocessor().process(nan).status,
        PreprocessingStatus.notPossible,
      );

      final backward = _fixture();
      backward.frames[20] = ReconstructedTimeFrame(
        analysisTimeSeconds: backward.frames[19].analysisTimeSeconds,
        values: backward.frames[20].values,
      );
      expect(
        const ImuPreprocessor().process(backward).status,
        PreprocessingStatus.notPossible,
      );

      final short = _fixture(sampleCount: 10);
      expect(
        const ImuPreprocessor().process(short).status,
        PreprocessingStatus.notPossible,
      );
    });

    test('marks missing sensor data and unresolved orientation explicitly', () {
      final missing = _fixture();
      for (final frame in missing.frames) {
        frame.values['HR'] = null;
      }
      final missingResult = const ImuPreprocessor().process(missing);
      expect(missingResult.status, PreprocessingStatus.notPossible);
      expect(
        missingResult.issues.map((issue) => issue.code),
        contains('sensor_without_output'),
      );

      final movingOnly = _fixture(alwaysMoving: true);
      final movingResult = const ImuPreprocessor().process(movingOnly);
      expect(movingResult.status, PreprocessingStatus.reviewRequired);
      expect(
        movingResult.issues.map((issue) => issue.code),
        contains('orientation_not_resolved'),
      );
      expect(
        movingResult.sensorQuality['VL']!.orientation.valid,
        isFalse,
      );
    });

    test('renders comparable CSV, SVG, and JSON without altering raw values',
        () {
      final input = _fixture(isolatedSpikeIndex: 250);
      final before = input.frames[250].values['VL']!.accelerationMps2.x;
      final result = const ImuPreprocessor().process(input);
      final csv = const PreprocessedImuCsv().render(result);
      final svg = const ImuPreprocessingSvg(maximumPoints: 100).render(result);
      final report = jsonDecode(preprocessingReportJson(result));

      expect(
        csv,
        startsWith('analysis_time_s,VL.raw_acc_x_mps2'),
      );
      expect(csv, contains('VL.filtered_acc_x_mps2'));
      expect(csv, contains('"HL.txt",252'));
      expect(svg, contains('Roh / Butterworth / Bewegungsanteil'));
      expect(svg, contains('rekonstruierte Analysezeit'));
      expect(report['preprocessing']['config']['low_pass']['cutoff_hz'], 20);
      expect(input.frames[250].values['VL']!.accelerationMps2.x, before);
    });

    test('loads and validates central configuration', () {
      final config = ImuPreprocessingConfig.fromJsonString(
        '{"low_pass_cutoff_hz":15,"gravity_cutoff_hz":0.4,'
        '"butterworth_order":4}',
      );
      expect(config.lowPassCutoffHz, 15);
      expect(config.gravityCutoffHz, 0.4);
      expect(
        () => const ImuPreprocessor(
          config: ImuPreprocessingConfig(lowPassCutoffHz: 50),
        ).process(_fixture()),
        throwsArgumentError,
      );
      expect(
        () => ImuPreprocessingConfig.fromJsonString(
          '{"low_pass_cutoff_hz":"zwanzig"}',
        ),
        throwsFormatException,
      );
    });
  });
}

const _labels = ['VL', 'VR', 'HL', 'HR'];

IndexTimeReconstructionResult _fixture({
  double samplingRateHz = 100,
  int sampleCount = 500,
  int? isolatedSpikeIndex,
  int? eventStart,
  int? gapStart,
  int gapLength = 0,
  bool irregularCycles = false,
  bool alwaysMoving = false,
}) {
  final frames = <ReconstructedTimeFrame>[];
  for (var index = 0; index < sampleCount; index++) {
    final time = index / samplingRateHz;
    frames.add(
      ReconstructedTimeFrame(
        analysisTimeSeconds: time,
        values: {
          for (var sensorIndex = 0; sensorIndex < _labels.length; sensorIndex++)
            _labels[sensorIndex]: gapStart != null &&
                    index >= gapStart &&
                    index < gapStart + gapLength &&
                    sensorIndex == 0
                ? null
                : _value(
                    index,
                    samplingRateHz: samplingRateHz,
                    phase: sensorIndex * 0.08,
                    accelerationX:
                        isolatedSpikeIndex == index && sensorIndex == 0
                            ? 80
                            : null,
                    event: eventStart != null &&
                        index >= eventStart &&
                        index < eventStart + 6 &&
                        sensorIndex == 0,
                    irregularCycles: irregularCycles,
                    alwaysMoving: alwaysMoving,
                  ),
        },
      ),
    );
  }
  return IndexTimeReconstructionResult(
    status: TimeReconstructionStatus.accepted,
    gridSamplingRateHz: samplingRateHz,
    gridPeriodMicroseconds: (1000000 / samplingRateHz).round(),
    commonStartSeconds: 0,
    commonEndSeconds: (sampleCount - 1) / samplingRateHz,
    sensors: {
      for (final label in _labels)
        label: _sensorReconstruction(label, samplingRateHz),
    },
    frames: frames,
    issues: const [],
    assumptions: const [],
  );
}

ResampledImuValue _value(
  int index, {
  double samplingRateHz = 100,
  double phase = 0,
  double? accelerationX,
  bool event = false,
  bool irregularCycles = false,
  bool alwaysMoving = false,
}) {
  final time = index / samplingRateHz;
  final cyclePhase = 2 *
      math.pi *
      (irregularCycles ? 1.2 + 0.15 * math.sin(time) : 1.4) *
      time;
  final quiet = !alwaysMoving && time < 2;
  final movement = quiet ? 0.0 : 1.2 * math.sin(cyclePhase + phase);
  final noise = 0.22 * math.sin(2 * math.pi * 35 * time + phase);
  final eventValue = event ? 6.0 : 0.0;
  const gravity = Vector3(1.95, -0.98, 9.56);
  return ResampledImuValue(
    accelerationMps2: Vector3(
      accelerationX ?? gravity.x + movement + noise + eventValue,
      gravity.y + 0.35 * movement - noise,
      gravity.z + 0.2 * movement + noise,
    ),
    angularVelocityRadPerSecond: Vector3(
      quiet ? 0.01 : 0.35 * math.sin(cyclePhase),
      quiet ? -0.01 : 0.2 * math.cos(cyclePhase),
      quiet ? 0 : 0.1 * math.sin(cyclePhase + phase),
    ),
    magneticFieldMicrotesla: const Vector3(20, -40, 10),
    lowerSampleIndex: index,
    upperSampleIndex: index,
    lowerSourceName: '${_labels[index % _labels.length]}.txt',
    lowerSourceLine: index + 2,
    upperSourceName: '${_labels[index % _labels.length]}.txt',
    upperSourceLine: index + 2,
    uncertaintyMilliseconds: 20,
  );
}

SensorTimeReconstruction _sensorReconstruction(
  String label,
  double samplingRateHz,
) =>
    SensorTimeReconstruction(
      sensorLabel: label,
      valid: true,
      nominalSamplingRateHz: samplingRateHz,
      effectiveSamplingRateHz: samplingRateHz,
      packetCount: 1,
      duplicateReceptionTimestampSamples: 0,
      offsetSeconds: 0,
      timeGradient: 1,
      estimatedDriftPpm: 0,
      anchorResidualRmseMilliseconds: 0,
      maximumAbsoluteAnchorResidualMilliseconds: 0,
      baseUncertaintyMilliseconds: 20,
      lossDetermination: LossDetermination.notObserved,
      lossReason: 'controlled fixture',
      packets: const [],
      suspectedTransportGaps: const [],
      anchorEvidence: const [],
      samples: const [],
      invalidReason: null,
    );

double _magnitude(Vector3 value) => math.sqrt(value.magnitudeSquared);
