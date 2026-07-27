import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intakt_app/gait_segmentation/gait_segmentation.dart';
import 'package:intakt_app/imu_import/imu_models.dart';
import 'package:intakt_app/imu_preprocessing/imu_preprocessing.dart';
import 'package:intakt_app/imu_sync/index_time_reconstruction.dart';

void main() {
  const testConfig = GaitSegmentationConfig(
    windowSeconds: 2,
    stepSeconds: 0.5,
    minimumAnalyzableSeconds: 2,
    minimumAnalyzableConfidence: 0.45,
    minimumSpectralConfidence: 0.25,
  );
  const singleTrotConfig = GaitSegmentationConfig(
    windowSeconds: 2,
    stepSeconds: 0.5,
    minimumAnalyzableSeconds: 2,
    minimumAnalyzableConfidence: 0.45,
    minimumSpectralConfidence: 0.25,
    enabledMovementGaits: [GaitLabel.trot],
  );
  const threeGaitConfig = GaitSegmentationConfig(
    windowSeconds: 2,
    stepSeconds: 0.5,
    minimumAnalyzableSeconds: 2,
    minimumAnalyzableConfidence: 0.45,
    minimumSpectralConfidence: 0.25,
    enabledMovementGaits: [
      GaitLabel.walk,
      GaitLabel.trot,
      GaitLabel.gallop,
    ],
  );

  group('Gait segmentation', () {
    test('separates standing, walk, trot and optional gallop', () {
      final input = _input(
        durationSeconds: 35,
        signal: (time) {
          if (time < 5 || time >= 29) return const _Signal(0, 0);
          if (time < 13) return const _Signal(1, 1.5);
          if (time < 21) return const _Signal(1.8, 1.7);
          return const _Signal(3, 1.9);
        },
      );

      final first = const GaitSegmenter(config: threeGaitConfig).segment(input);
      final second =
          const GaitSegmenter(config: threeGaitConfig).segment(input);

      expect(first.status, SegmentationStatus.accepted);
      expect(
        first.segments.map((segment) => segment.gait),
        containsAll([
          GaitLabel.standing,
          GaitLabel.walk,
          GaitLabel.trot,
          GaitLabel.gallop,
        ]),
      );
      expect(first.segments.any((segment) => segment.transition), isTrue);
      expect(
        first.analyzableSegments.map((segment) => segment.gait),
        containsAll([GaitLabel.walk, GaitLabel.trot, GaitLabel.gallop]),
      );
      expect(
        gaitSegmentationReportJson(second),
        gaitSegmentationReportJson(first),
      );
      expect(
        first.segments.every(
          (segment) =>
              segment.confidence >= 0 &&
              segment.confidence <= 1 &&
              segment.uncertainty == 1 - segment.confidence,
        ),
        isTrue,
      );
    });

    test('maps two recording-internal frequency groups to walk and trot only',
        () {
      final result = const GaitSegmenter(config: testConfig).segment(
        _input(
          durationSeconds: 24,
          signal: (time) =>
              time < 12 ? const _Signal(1.1, 1.5) : const _Signal(2.8, 1.8),
        ),
      );

      expect(
        result.segments.map((segment) => segment.gait),
        containsAll([GaitLabel.walk, GaitLabel.trot]),
      );
      expect(
        result.segments.any((segment) => segment.gait == GaitLabel.gallop),
        isFalse,
      );
      expect(
        result.gaitSignalClusters.map((cluster) => cluster.gait),
        [GaitLabel.walk, GaitLabel.trot],
      );
      expect(
        result.gaitSignalClusters.first.centroid,
        lessThan(result.gaitSignalClusters.last.centroid),
      );
    });

    test(
        'forms ordered gait blocks and marks later frequency regressions unknown',
        () {
      final result = const GaitSegmenter(config: testConfig).segment(
        _input(
          durationSeconds: 32,
          signal: (time) {
            if (time < 10) return const _Signal(1.1, 1.5);
            if (time < 18) return const _Signal(2.8, 1.8);
            if (time < 24) return const _Signal(1.1, 1.5);
            return const _Signal(2.8, 1.8);
          },
        ),
      );

      final ordered = result.segments
          .where((segment) => segment.gait != GaitLabel.standing)
          .map((segment) => segment.gait)
          .toList();
      expect(ordered, contains(GaitLabel.walk));
      expect(ordered, contains(GaitLabel.trot));
      expect(ordered, contains(GaitLabel.unknown));
      final firstTrot = ordered.indexOf(GaitLabel.trot);
      expect(ordered.skip(firstTrot + 1).contains(GaitLabel.walk), isFalse);
      expect(ordered, isNot(contains(GaitLabel.gallop)));
    });

    test(
        'uses four-leg AngleZ sign changes for direction and turns while '
        'keeping gait frequency-based', () {
      final input = _input(
        durationSeconds: 20,
        signal: (time) => time >= 9.5 && time < 10.5
            ? const _Signal(0, 0)
            : const _Signal(1.8, 1.7),
        angleZ: (time) => time < 14 ? time * 6 : 168 - time * 6,
      );

      final result =
          const GaitSegmenter(config: singleTrotConfig).segment(input);

      expect(result.segments.any((segment) => segment.interruption), isTrue);
      expect(result.segments.any((segment) => segment.turn), isTrue);
      expect(
        result.segments.map((segment) => segment.ridingDirection),
        containsAll([RidingDirection.left, RidingDirection.right]),
      );
      expect(
        result.segments
            .where((segment) => segment.gait == GaitLabel.trot)
            .map((segment) => segment.dominantFrequencyHz)
            .whereType<double>()
            .every((frequency) => (frequency - 1.8).abs() < 0.15),
        isTrue,
      );
      expect(
        result.segments
            .where((segment) => segment.turn || segment.interruption)
            .every((segment) => !segment.analyzable),
        isTrue,
      );
    });

    test('keeps frequency gait valid when AngleZ direction is unavailable', () {
      final result = const GaitSegmenter(config: singleTrotConfig).segment(
        _input(
          durationSeconds: 10,
          signal: (_) => const _Signal(1.8, 1.7),
          includeAngles: false,
        ),
      );

      expect(result.status, SegmentationStatus.reviewRequired);
      expect(
        result.issues.map((issue) => issue.code),
        contains('leg_orientation_angles_missing'),
      );
      expect(
        result.segments.any((segment) => segment.gait == GaitLabel.trot),
        isTrue,
      );
      expect(
        result.segments.every(
          (segment) =>
              segment.ridingDirection == RidingDirection.unknown &&
              segment.meanAngleZTrendDegreesPerSecond == null,
        ),
        isTrue,
      );
      final report = jsonDecode(gaitSegmentationReportJson(result)) as Map;
      final segment =
          ((report['segmentation'] as Map)['segments'] as List).first as Map;
      expect(segment['direction_valid'], isFalse);
      expect(
        segment['direction_invalid_reason'],
        'four_leg_angle_z_consensus_not_reached_or_signal_missing',
      );
      expect(segment['line_bending_rate_degps'], isNull);
    });

    test('applies traceable manual corrections without hiding uncertainty', () {
      final input = _input(
        durationSeconds: 12,
        signal: (_) => const _Signal(4.6, 1.5),
      );
      const correction = ManualSegmentCorrection(
        startSeconds: 2,
        endSeconds: 10,
        gait: GaitLabel.walk,
        excludeFromAnalysis: false,
        transition: false,
        reason: 'Im synchronisierten Video als Schritt annotiert',
      );

      final result = const GaitSegmenter(
        config: testConfig,
      ).segment(input, corrections: const [correction]);

      expect(result.status, SegmentationStatus.reviewRequired);
      final corrected = result.segments.where(
        (segment) => segment.manuallyCorrected,
      );
      expect(corrected, isNotEmpty);
      expect(
        corrected.every((segment) => segment.gait == GaitLabel.walk),
        isTrue,
      );
      expect(
        corrected.every(
          (segment) =>
              segment.correctionReasons.contains(correction.reason) &&
              segment.uncertainty > 0 &&
              !segment.transition,
        ),
        isTrue,
      );
    });

    test('keeps video times and raw source-line traceability in outputs', () {
      final result = const GaitSegmenter(config: testConfig).segment(
        _input(durationSeconds: 8, signal: (_) => const _Signal(1, 1.5)),
      );
      final report = jsonDecode(gaitSegmentationReportJson(result))
          as Map<String, dynamic>;
      final first = (report['segmentation']['segments'] as List).first as Map;
      final csv = const GaitSegmentationCsv().render(result);
      final svg = const GaitSegmentationSvg().render(result);

      expect(first['video_start_s'], first['start_s']);
      expect(
        (first['source_lines'] as Map).keys,
        containsAll(['VL', 'VR', 'HL', 'HR']),
      );
      expect(csv, contains('video_start_s'));
      expect(csv, contains('analyzable'));
      expect(csv, contains('riding_direction'));
      expect(svg, contains('Videozeit'));
      expect(svg, contains('Wendungskandidat'));
    });

    test('handles noise, irregular cycles and a short gap explicitly', () {
      final result = const GaitSegmenter(config: testConfig).segment(
        _input(
          durationSeconds: 14,
          signal: (time) {
            final varyingFrequency = 1.65 + 0.12 * math.sin(time * 0.7);
            return _Signal(varyingFrequency, 1.7, noiseAmplitude: 0.12);
          },
          missing: (time) => time >= 6 && time < 6.25,
        ),
      );

      expect(result.status, isNot(SegmentationStatus.notPossible));
      expect(
        result.segments
            .where((segment) => segment.coverage < 0.9)
            .every((segment) => !segment.analyzable),
        isTrue,
      );
      expect(
        result.segments.every(
          (segment) =>
              segment.startSeconds.isFinite &&
              segment.endSeconds.isFinite &&
              segment.endSeconds > segment.startSeconds,
        ),
        isTrue,
      );
    });

    test(
      'rejects empty input, missing sensors, NaN, invalid times and short recordings',
      () {
        const empty = ImuPreprocessingResult(
          status: PreprocessingStatus.notPossible,
          gridSamplingRateHz: 100,
          frames: [],
          sensorQuality: {},
          issues: [],
          config: ImuPreprocessingConfig(),
          assumptions: [],
        );
        final missing = _input(
          durationSeconds: 5,
          signal: (_) => const _Signal(1, 1),
          includeHr: false,
        );
        final emptyLegSignal = _input(
          durationSeconds: 5,
          signal: (_) => const _Signal(1, 1),
          missingAllHr: true,
        );
        final nonFinite = _input(
          durationSeconds: 5,
          signal: (_) => const _Signal(1, 1),
          nanAtSeconds: 2,
        );
        final short = _input(
          durationSeconds: 1,
          signal: (_) => const _Signal(1, 1),
        );
        final invalidTimes = _input(
          durationSeconds: 5,
          signal: (_) => const _Signal(1, 1),
        );
        final frames = [...invalidTimes.frames];
        frames[20] = PreprocessedFrame(
          analysisTimeSeconds: frames[19].analysisTimeSeconds,
          values: frames[20].values,
        );
        final invalidTimeInput = ImuPreprocessingResult(
          status: invalidTimes.status,
          gridSamplingRateHz: invalidTimes.gridSamplingRateHz,
          frames: frames,
          sensorQuality: invalidTimes.sensorQuality,
          issues: invalidTimes.issues,
          config: invalidTimes.config,
          assumptions: invalidTimes.assumptions,
        );

        for (final input in [
          empty,
          missing,
          emptyLegSignal,
          nonFinite,
          short,
          invalidTimeInput,
        ]) {
          final result = const GaitSegmenter(config: testConfig).segment(input);
          expect(result.status, SegmentationStatus.notPossible);
          expect(result.segments, isEmpty);
        }
      },
    );

    test('supports a different common sampling rate', () {
      final result = const GaitSegmenter(config: singleTrotConfig).segment(
        _input(
          durationSeconds: 10,
          samplingRateHz: 80,
          signal: (_) => const _Signal(1.8, 1.7),
        ),
      );

      expect(result.status, SegmentationStatus.accepted);
      expect(
        result.analyzableSegments.any(
          (segment) => segment.gait == GaitLabel.trot,
        ),
        isTrue,
      );
    });

    test('rejects invalid configuration and overlapping corrections', () {
      expect(
        () => const GaitSegmenter(
          config: GaitSegmentationConfig(
            movementOffRmsMps2: 1,
            movementOnRmsMps2: 0.5,
          ),
        ).segment(
          _input(durationSeconds: 5, signal: (_) => const _Signal(1, 1)),
        ),
        throwsArgumentError,
      );
      expect(
        () => const GaitSegmenter(
          config: GaitSegmentationConfig(maximumFrequencyHz: double.nan),
        ).segment(
          _input(durationSeconds: 5, signal: (_) => const _Signal(1, 1)),
        ),
        throwsArgumentError,
      );
      expect(
        () => const GaitSegmenter(config: testConfig).segment(
          _input(durationSeconds: 5, signal: (_) => const _Signal(1, 1)),
          corrections: const [
            ManualSegmentCorrection(
              startSeconds: 1,
              endSeconds: 3,
              reason: 'a',
            ),
            ManualSegmentCorrection(
              startSeconds: 2,
              endSeconds: 4,
              reason: 'b',
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => const GaitSegmenter(config: testConfig).segment(
          _input(durationSeconds: 5, signal: (_) => const _Signal(1, 1)),
          corrections: const [
            ManualSegmentCorrection(
              startSeconds: 20,
              endSeconds: 21,
              reason: 'outside',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('loads central configuration and correction schema', () {
      final config = GaitSegmentationConfig.fromJsonString(
        File('config/gangsegmentierung.v1.json').readAsStringSync(),
      );
      final correctionRoot = jsonDecode(
        File(
          'config/gangsegmentierung-korrekturen.beispiel.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final corrections = [
        for (final value in correctionRoot['corrections'] as List)
          ManualSegmentCorrection.fromJson(value as Map<String, dynamic>),
      ];

      expect(config.requiredLegLabels, ['VL', 'VR', 'HL', 'HR']);
      expect(config.movementOffRmsMps2, lessThan(config.movementOnRmsMps2));
      expect(
        config.enabledMovementGaits,
        [GaitLabel.walk, GaitLabel.trot],
      );
      expect(corrections, hasLength(2));
      expect(corrections.first.reason, isNotEmpty);
      expect(
        () => GaitSegmentationConfig.fromJsonString(
          '{"window_seconds":"invalid"}',
        ),
        throwsFormatException,
      );
      expect(
        () => ManualSegmentCorrection.fromJson({
          'start_s': 1,
          'end_s': 2,
          'gait': 'CANTERISH',
          'reason': 'invalid',
        }),
        throwsFormatException,
      );
    });
  });
}

ImuPreprocessingResult _input({
  required double durationSeconds,
  required _Signal Function(double time) signal,
  double samplingRateHz = 100,
  double Function(double time)? angleZ,
  bool includeAngles = true,
  bool Function(double time)? missing,
  bool includeHr = true,
  bool missingAllHr = false,
  double? nanAtSeconds,
}) {
  final rate = samplingRateHz;
  final labels = ['VL', 'VR', 'HL', if (includeHr) 'HR', 'SG'];
  final phases = {'VL': 0.0, 'VR': 0.5, 'HL': 1.0, 'HR': 1.5, 'SG': 0.0};
  final frames = <PreprocessedFrame>[];
  for (var index = 0; index <= durationSeconds * rate; index++) {
    final time = index / rate;
    final current = signal(time);
    final values = <String, PreprocessedImuValue?>{};
    for (final label in labels) {
      if (label == 'HR' && missingAllHr) {
        values[label] = null;
        continue;
      }
      if (label != 'SG' && (missing?.call(time) ?? false)) {
        values[label] = null;
        continue;
      }
      final phase = phases[label]!;
      final noise =
          current.noiseAmplitude * math.sin(2 * math.pi * 8.3 * time + phase);
      final movementZ = label == 'SG'
          ? current.amplitude *
              0.25 *
              math.sin(2 * math.pi * current.frequencyHz * time)
          : current.amplitude *
                  math.sin(
                    2 * math.pi * current.frequencyHz * time + phase,
                  ) +
              noise;
      final gyro = label == 'SG' ? 0.05 : 0.1;
      final nonFinite = nanAtSeconds != null &&
          label == 'VL' &&
          (time - nanAtSeconds).abs() < 0.001;
      values[label] = _value(
        index: index,
        movementZ: nonFinite ? double.nan : movementZ,
        gyro: gyro,
        angleZ: label == 'SG' || !includeAngles
            ? null
            : _wrapDegrees(angleZ?.call(time) ?? time * 5),
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

PreprocessedImuValue _value({
  required int index,
  required double movementZ,
  required double gyro,
  double? angleZ,
}) {
  final raw = ResampledImuValue(
    accelerationMps2: const Vector3(0, 0, 9.80665),
    angularVelocityRadPerSecond: Vector3(0, 0, gyro),
    magneticFieldMicrotesla: null,
    lowerSampleIndex: index,
    upperSampleIndex: index,
    lowerSourceName: 'synthetic.txt',
    lowerSourceLine: index + 2,
    upperSourceName: 'synthetic.txt',
    upperSourceLine: index + 2,
    uncertaintyMilliseconds: 5,
    orientationAnglesDegrees: angleZ == null ? null : Vector3(0, 0, angleZ),
  );
  return PreprocessedImuValue(
    raw: raw,
    cleanedAccelerationMps2: const Vector3(0, 0, 9.80665),
    cleanedAngularVelocityRadPerSecond: Vector3(0, 0, gyro),
    filteredAccelerationSensorFrameMps2: Vector3(0, 0, 9.80665 + movementZ),
    filteredAngularVelocitySensorFrameRadPerSecond: Vector3(0, 0, gyro),
    alignedAccelerationMps2: Vector3(0, 0, 9.80665 + movementZ),
    alignedAngularVelocityRadPerSecond: Vector3(0, 0, gyro),
    gravityMps2: const Vector3(0, 0, 9.80665),
    movementAccelerationMps2: Vector3(0, 0, movementZ),
    alignedMagneticFieldMicrotesla: null,
    outlierReplaced: false,
    processingTemporalResolutionMilliseconds: 25,
  );
}

double _wrapDegrees(double value) {
  while (value > 180) {
    value -= 360;
  }
  while (value < -180) {
    value += 360;
  }
  return value;
}

class _Signal {
  const _Signal(this.frequencyHz, this.amplitude, {this.noiseAmplitude = 0});

  final double frequencyHz;
  final double amplitude;
  final double noiseAmplitude;
}
