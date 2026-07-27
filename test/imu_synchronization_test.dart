import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intakt_app/imu_import/imu_import.dart';
import 'package:intakt_app/imu_sync/imu_sync.dart';

void main() {
  const testConfig = ImuSynchronizationConfig(
    targetSamplingRateHz: 100,
    maximumLag: Duration(milliseconds: 150),
    lagStep: Duration(milliseconds: 1),
    correlationWindow: Duration(milliseconds: 1500),
    correlationWindowStep: Duration(milliseconds: 750),
    minimumSamplesPerSensor: 20,
    minimumCorrelationSamples: 50,
    minimumWindowCorrelation: 0.7,
    maximumLagResidual: Duration(milliseconds: 5),
    minimumCoverage: 0.9,
  );

  group('IMU synchronization', () {
    test('aligns different rates, offsets and affine clock drift', () {
      final input = _synchronizationFixture();
      final originalTimestamps = {
        for (final entry in input.recordings.entries)
          entry.key:
              entry.value.samples.map((sample) => sample.timestamp).toList(),
      };

      final result =
          const ImuSynchronizer(config: testConfig).synchronize(input);

      expect(result.status, SynchronizationStatus.accepted);
      expect(result.hasSynchronizedDataset, isTrue);
      expect(result.gridPeriodMicroseconds, 10000);
      expect(result.gridSamplingRateHz, 100);
      expect(result.frames, isNotEmpty);
      expect(
        result.frames.every(
          (frame) =>
              frame.values.keys.join(',') == 'VL,VR,HL,HR' &&
              frame.values.values.every((value) => value != null),
        ),
        isTrue,
      );
      for (var index = 1; index < result.frames.length; index++) {
        expect(
          result.frames[index].timestamp
              .difference(result.frames[index - 1].timestamp)
              .inMicroseconds,
          10000,
        );
      }

      _expectClock(result, 'VR', offsetMs: 40, driftPpm: 500);
      _expectClock(result, 'HL', offsetMs: -30, driftPpm: -300);
      _expectClock(result, 'HR', offsetMs: 80, driftPpm: 200);
      expect(
        result.sensorQuality.values
            .every((quality) => quality.uncertaintyMilliseconds != null),
        isTrue,
      );
      expect(result.toJson()['time_basis'], contains('UTC'));

      for (final entry in input.recordings.entries) {
        expect(
          entry.value.samples.map((sample) => sample.timestamp),
          orderedEquals(originalTimestamps[entry.key]!),
        );
      }

      final wrapFrames = result.frames.where((frame) {
        final elapsedSeconds = frame.timestamp
                .difference(result.frames.first.timestamp)
                .inMicroseconds /
            Duration.microsecondsPerSecond;
        return elapsedSeconds >= 0.48 && elapsedSeconds <= 0.52;
      });
      expect(wrapFrames, isNotEmpty);
      expect(
        wrapFrames.every(
          (frame) => frame.values.values.every(
            (value) =>
                value!.orientationAnglesDegrees != null &&
                value.orientationAnglesDegrees!.z.abs() > 150,
          ),
        ),
        isTrue,
        reason:
            'AngleZ muss beim Uebergang +180/-180 kreisfoermig interpoliert werden.',
      );
    });

    test('is repeatable for controlled noisy and jittered signals', () {
      final input = _synchronizationFixture(noisy: true, jittered: true);
      final first =
          const ImuSynchronizer(config: testConfig).synchronize(input);
      final second =
          const ImuSynchronizer(config: testConfig).synchronize(input);

      expect(first.status, SynchronizationStatus.accepted);
      expect(second.toJson(), first.toJson());
      expect(
        second.frames.map((frame) => frame.timestamp).toList(),
        orderedEquals(first.frames.map((frame) => frame.timestamp)),
      );
    });

    test('does not interpolate a short source gap and reports coverage', () {
      final result = const ImuSynchronizer(config: testConfig).synchronize(
        _synchronizationFixture(gapSensor: 'VR'),
      );

      expect(result.status, SynchronizationStatus.reviewRequired);
      expect(result.hasSynchronizedDataset, isTrue);
      expect(result.sensorQuality['VR']!.outputCoverage, lessThan(0.9));
      expect(
        result.frames.any((frame) => frame.values['VR'] == null),
        isTrue,
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains('insufficient_output_coverage'),
      );
    });

    test('flat signals are explicitly invalid instead of inventing an offset',
        () {
      final result = const ImuSynchronizer(config: testConfig).synchronize(
        _synchronizationFixture(flatSensor: 'HR'),
      );

      expect(result.status, SynchronizationStatus.notSynchronized);
      expect(result.frames, isEmpty);
      expect(result.sensorQuality['HR']!.valid, isFalse);
      expect(result.sensorQuality['HR']!.estimatedSignalOffsetMilliseconds,
          isNull);
      expect(
        result.issues.map((issue) => issue.code),
        contains('insufficient_signal_alignment'),
      );
    });

    test('missing sensors prevent a synchronized dataset', () {
      final input = _synchronizationFixture();
      input.recordings.remove('HL');

      final result =
          const ImuSynchronizer(config: testConfig).synchronize(input);

      expect(result.status, SynchronizationStatus.notSynchronized);
      expect(result.frames, isEmpty);
      expect(
        result.issues,
        contains(
          isA<SynchronizationIssue>()
              .having((issue) => issue.code, 'code', 'missing_required_sensor')
              .having((issue) => issue.sensorLabel, 'sensor', 'HL'),
        ),
      );
    });

    test('duplicate and backward timestamps are rejected without sorting', () {
      final input = _synchronizationFixture();
      final recording = input.recordings['VR']!;
      final previous = recording.samples[10];
      final original = recording.samples[11];
      recording.samples[11] = _copySample(
        original,
        timestamp: previous.timestamp,
      );

      final result =
          const ImuSynchronizer(config: testConfig).synchronize(input);

      expect(result.status, SynchronizationStatus.notSynchronized);
      expect(result.frames, isEmpty);
      expect(
        result.issues
            .singleWhere(
              (issue) => issue.sensorLabel == 'VR',
            )
            .observation,
        contains('nicht streng steigende'),
      );
      expect(recording.samples[10].timestamp, recording.samples[11].timestamp);
    });

    test('NaN and Infinity are rejected', () {
      for (final invalid in [double.nan, double.infinity]) {
        final input = _synchronizationFixture();
        final recording = input.recordings['HL']!;
        final original = recording.samples[5];
        recording.samples[5] = _copySample(
          original,
          acceleration: Vector3(invalid, 0, 0),
        );

        final result =
            const ImuSynchronizer(config: testConfig).synchronize(input);

        expect(result.status, SynchronizationStatus.notSynchronized);
        expect(
          result.issues.any(
            (issue) =>
                issue.sensorLabel == 'HL' &&
                issue.observation.contains('NaN oder Infinity'),
          ),
          isTrue,
        );
      }
    });

    test('unexpectedly short recordings and invalid configuration fail clearly',
        () {
      final short = _synchronizationFixture(durationSeconds: 0.1);
      final result =
          const ImuSynchronizer(config: testConfig).synchronize(short);
      expect(result.status, SynchronizationStatus.notSynchronized);
      expect(result.frames, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains('invalid_sensor_time_series'),
      );

      expect(
        () => const ImuSynchronizer(
          config: ImuSynchronizationConfig(targetSamplingRateHz: 0),
        ).synchronize(_synchronizationFixture()),
        throwsArgumentError,
      );
    });

    test('CSV and SVG expose common timebase, quality and traceability', () {
      final result = const ImuSynchronizer(config: testConfig)
          .synchronize(_synchronizationFixture());

      final csv = const ImuSynchronizationCsv().render(result);
      final svg = const ImuSynchronizationSvg().render(result);

      expect(csv, startsWith('timestamp_utc,elapsed_s,VL.acc_x_mps2'));
      expect(csv, contains('VL.angle_z_deg'));
      expect(csv, contains('VR.lower_source'));
      expect(csv, contains('"VR.txt"'));
      expect(svg, startsWith('<svg'));
      expect(svg, contains('Gemeinsame UTC-Zeitbasis'));
      for (final label in ['VL', 'VR', 'HL', 'HR']) {
        expect(svg, contains('>$label</text>'));
      }
      expect(svg, contains('Drift'));
      expect(svg, contains('keine fachliche Validierung'));
    });

    test('renderers reject absent synchronized data', () {
      final invalid = const ImuSynchronizer(config: testConfig).synchronize(
        _synchronizationFixture(flatSensor: 'VR'),
      );
      expect(
        () => const ImuSynchronizationCsv().render(invalid),
        throwsStateError,
      );
      expect(
        () => const ImuSynchronizationSvg().render(invalid),
        throwsStateError,
      );
    });
  });
}

void _expectClock(
  ImuSynchronizationResult result,
  String label, {
  required double offsetMs,
  required double driftPpm,
}) {
  final quality = result.sensorQuality[label]!;
  expect(quality.valid, isTrue);
  expect(quality.estimatedSignalOffsetMilliseconds, closeTo(offsetMs, 3));
  expect(quality.estimatedDriftPpm, closeTo(driftPpm, 500));
  expect(quality.lagResidualRmseMilliseconds, lessThanOrEqualTo(5));
  expect(quality.meanWindowCorrelation, greaterThan(0.95));
}

ImuImportResult _synchronizationFixture({
  double durationSeconds = 8,
  bool noisy = false,
  bool jittered = false,
  String? gapSensor,
  String? flatSensor,
}) {
  final catalog = SensorCatalog(const [
    SensorIdentity(label: 'VL', hardwareId: 'AAAAAAAAAAAA', position: 'vl'),
    SensorIdentity(label: 'VR', hardwareId: 'BBBBBBBBBBBB', position: 'vr'),
    SensorIdentity(label: 'HL', hardwareId: 'CCCCCCCCCCCC', position: 'hl'),
    SensorIdentity(label: 'HR', hardwareId: 'DDDDDDDDDDDD', position: 'hr'),
  ]);
  final definitions = {
    'VL': (rate: 100.0, offsetMs: 0.0, driftPpm: 0.0),
    'VR': (rate: 80.0, offsetMs: 40.0, driftPpm: 500.0),
    'HL': (rate: 120.0, offsetMs: -30.0, driftPpm: -300.0),
    'HR': (rate: 90.0, offsetMs: 80.0, driftPpm: 200.0),
  };
  final start = DateTime.utc(2026, 7, 23, 20);
  final recordings = <String, SensorRecording>{};
  for (final identity in catalog.sensors) {
    final definition = definitions[identity.label]!;
    final recording = SensorRecording(identity)
      ..sourceNames.add('${identity.label}.txt');
    final count = (durationSeconds * definition.rate).floor() + 1;
    for (var index = 0; index < count; index++) {
      var trueSeconds = index / definition.rate;
      if (jittered && index > 0 && index < count - 1) {
        trueSeconds += math.sin(index * 1.618) * 0.0008;
      }
      if (gapSensor == identity.label && trueSeconds > 3 && trueSeconds < 4) {
        continue;
      }
      final rawSeconds = trueSeconds * (1 + definition.driftPpm / 1000000) +
          definition.offsetMs / 1000;
      final timestamp =
          start.add(Duration(microseconds: (rawSeconds * 1000000).round()));
      final flat = flatSensor == identity.label;
      final noise =
          noisy ? 0.025 * math.sin(index * 12.345 + definition.rate) : 0.0;
      final signal = flat ? 2.0 : _controlledSignal(trueSeconds) + noise;
      recording.samples.add(
        ImuSample(
          timestamp: timestamp,
          rawTimestamp: timestamp.toIso8601String(),
          accelerationMps2: Vector3(12 + signal, 0.3 * signal, 0.1 * signal),
          angularVelocityRadPerSecond:
              Vector3(signal * 0.2, signal * 0.1, -signal * 0.05),
          magneticFieldMicrotesla:
              Vector3(20 + signal, 5 - signal, 30 + signal * 0.1),
          orientationAnglesDegrees:
              Vector3(1, 2, _wrapDegrees(170 + 20 * trueSeconds)),
          sourceName: '${identity.label}.txt',
          sourceLine: index + 2,
        ),
      );
    }
    recordings[identity.label] = recording;
  }
  return ImuImportResult(
    catalog: catalog,
    recordings: recordings,
    messages: const [],
    sourceUnits: const {
      'acceleration': 'm/s^2',
      'angular_velocity': 'rad/s',
      'magnetic_field': 'uT',
      'orientation_angle': 'degree',
    },
    timestampUncertainty: 'Controlled synthetic fixture.',
  );
}

double _controlledSignal(double time) {
  final wave = math.sin(2 * math.pi * 1.7 * time) +
      0.35 * math.sin(2 * math.pi * 3.13 * time + 0.4);
  final eventA = 1.8 * math.exp(-math.pow((time - 2.35) / 0.12, 2));
  final eventB = -1.3 * math.exp(-math.pow((time - 5.6) / 0.18, 2));
  return wave + eventA + eventB;
}

double _wrapDegrees(double value) {
  var wrapped = value;
  while (wrapped > 180) {
    wrapped -= 360;
  }
  while (wrapped <= -180) {
    wrapped += 360;
  }
  return wrapped;
}

ImuSample _copySample(
  ImuSample original, {
  DateTime? timestamp,
  Vector3? acceleration,
}) =>
    ImuSample(
      timestamp: timestamp ?? original.timestamp,
      rawTimestamp: (timestamp ?? original.timestamp).toIso8601String(),
      accelerationMps2: acceleration ?? original.accelerationMps2,
      angularVelocityRadPerSecond: original.angularVelocityRadPerSecond,
      magneticFieldMicrotesla: original.magneticFieldMicrotesla,
      orientationAnglesDegrees: original.orientationAnglesDegrees,
      sourceName: original.sourceName,
      sourceLine: original.sourceLine,
    );
