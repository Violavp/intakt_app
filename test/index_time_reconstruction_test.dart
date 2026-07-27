import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intakt_app/imu_import/imu_import.dart';
import 'package:intakt_app/imu_sync/imu_sync.dart';

void main() {
  group('index-based sample-time reconstruction', () {
    test('preserves source order and reconstructs unique indexed sample times',
        () {
      final fixture = _fixture();
      final original = {
        for (final entry in fixture.recordings.entries)
          entry.key: entry.value.samples.toList(),
      };
      final result = const IndexTimeReconstructor().reconstruct(
        fixture,
        _anchors(fixture),
      );

      expect(result.status, TimeReconstructionStatus.reviewRequired);
      expect(result.hasReconstructedDataset, isTrue);
      expect(result.toJson()['time_basis'], 'RECONSTRUCTED_INDEX_TIME');
      expect(result.frames, isNotEmpty);
      for (final entry in result.sensors.entries) {
        final sensor = entry.value;
        expect(sensor.valid, isTrue);
        expect(sensor.nominalSamplingRateHz, 100);
        expect(sensor.effectiveSamplingRateHz, closeTo(100, 0.001));
        expect(sensor.offsetSeconds, closeTo(_offsets[entry.key]!, 1e-9));
        expect(sensor.timeGradient, closeTo(_gradients[entry.key]!, 1e-9));
        expect(
          sensor.estimatedDriftPpm,
          closeTo((_gradients[entry.key]! - 1) * 1000000, 1e-6),
        );
        expect(sensor.anchorResidualRmseMilliseconds, closeTo(0, 1e-8));
        expect(sensor.baseUncertaintyMilliseconds, greaterThan(0));
        expect(sensor.lossDetermination, LossDetermination.notDeterminable);
        expect(sensor.samples, hasLength(101));
        expect(
          sensor.samples.map((sample) => sample.sampleIndex),
          orderedEquals(List<int>.generate(101, (index) => index)),
        );
        expect(
          sensor.samples.map((sample) => sample.analysisTimeSeconds).toSet(),
          hasLength(101),
        );
        for (var index = 0; index < sensor.samples.length; index++) {
          expect(
            identical(
              sensor.samples[index].rawSample,
              original[entry.key]![index],
            ),
            isTrue,
          );
        }
      }
      expect(
        result.frames.skip(1).every(
              (frame) =>
                  frame.analysisTimeSeconds >
                  result.frames[result.frames.indexOf(frame) - 1]
                      .analysisTimeSeconds,
            ),
        isTrue,
      );
      expect(
        result.frames.every(
          (frame) => frame.values.keys.toSet().containsAll(_labels),
        ),
        isTrue,
      );
    });

    test('groups consecutive duplicate timestamps into BLE packets', () {
      final result = const IndexTimeReconstructor().reconstruct(
        _fixture(),
        _anchors(_fixture()),
      );
      final sensor = result.sensors['VL']!;

      expect(sensor.packetCount, 26);
      expect(sensor.packets.first.sampleCount, 4);
      expect(sensor.packets.first.firstSampleIndex, 0);
      expect(sensor.packets.first.lastSampleIndex, 3);
      expect(sensor.packets.last.sampleCount, 1);
      expect(sensor.duplicateReceptionTimestampSamples, 75);
      expect(sensor.samples[3].packetIndex, 0);
      expect(sensor.samples[4].packetIndex, 1);
    });

    test('flags a reception gap but does not invent missing indices', () {
      final fixture = _fixture(packetGapAfterIndex: 39);
      final result = const IndexTimeReconstructor().reconstruct(
        fixture,
        _anchors(fixture),
      );
      final sensor = result.sensors['VL']!;

      expect(sensor.lossDetermination, LossDetermination.suspected);
      expect(sensor.suspectedTransportGaps, isNotEmpty);
      expect(
        sensor.suspectedTransportGaps.first.possibleMissingSamples,
        greaterThan(0),
      );
      expect(sensor.samples, hasLength(101));
      expect(sensor.samples.last.sampleIndex, 100);
      expect(
        result.issues.map((issue) => issue.code),
        contains('suspected_transport_gap'),
      );
    });

    test('uses effective reception rate for a single-anchor gradient', () {
      final fixture = _fixture(receptionRateHz: 80);
      final allAnchors = _anchors(fixture);
      final anchors = allAnchors
          .where((anchor) => anchor.sensorLabel != 'VL')
          .toList()
        ..add(
          allAnchors.firstWhere(
            (anchor) => anchor.sensorLabel == 'VL' && anchor.rawSourceLine == 2,
          ),
        );
      final result =
          const IndexTimeReconstructor().reconstruct(fixture, anchors);
      final sensor = result.sensors['VL']!;

      expect(sensor.anchorEvidence, hasLength(1));
      expect(sensor.effectiveSamplingRateHz, closeTo(80, 0.001));
      expect(sensor.timeGradient, closeTo(1.25, 0.001));
      expect(
        result.issues.map((issue) => issue.code),
        contains('single_anchor_rate_assumption'),
      );
    });

    test('supports configured different nominal rates per sensor', () {
      final fixture = _fixture(sampleCounts: {
        'VL': 81,
        'VR': 101,
        'HL': 121,
        'HR': 91,
      });
      const rates = {'VL': 80.0, 'VR': 100.0, 'HL': 120.0, 'HR': 90.0};
      final result = const IndexTimeReconstructor(
        config: IndexTimeReconstructionConfig(
          nominalSamplingRatesHz: rates,
        ),
      ).reconstruct(
        fixture,
        _anchors(fixture, nominalRates: rates),
      );

      expect(result.hasReconstructedDataset, isTrue);
      for (final entry in rates.entries) {
        expect(
          result.sensors[entry.key]!.nominalSamplingRateHz,
          entry.value,
        );
      }
    });

    test('includes an anchored optional sensor without making it mandatory',
        () {
      final fixture = _fixtureWithOptionalGirth();
      final anchors = _anchors(fixture)
        ..addAll(const [
          VideoImuAnchor(
            id: 'SG_START',
            sensorLabel: 'SG',
            videoTimeSeconds: 1,
            rawSourceLine: 2,
          ),
          VideoImuAnchor(
            id: 'SG_END',
            sensorLabel: 'SG',
            videoTimeSeconds: 2,
            rawSourceLine: 102,
          ),
        ]);
      final result =
          const IndexTimeReconstructor().reconstruct(fixture, anchors);

      expect(result.hasReconstructedDataset, isTrue);
      expect(result.sensors.keys, contains('SG'));
      expect(result.sensors['SG']!.anchorEvidence, hasLength(2));

      fixture.recordings.remove('SG');
      final withoutOptional = const IndexTimeReconstructor().reconstruct(
        fixture,
        anchors.where((anchor) => anchor.sensorLabel != 'SG').toList(),
      );
      expect(withoutOptional.hasReconstructedDataset, isTrue);
      expect(withoutOptional.sensors.keys, isNot(contains('SG')));
    });

    test('measurement noise and irregular motion do not alter the time fit',
        () {
      final clean = _fixture();
      final noisy = _fixture(noise: 0.4, irregularSignal: true);
      final cleanResult = const IndexTimeReconstructor().reconstruct(
        clean,
        _anchors(clean),
      );
      final noisyResult = const IndexTimeReconstructor().reconstruct(
        noisy,
        _anchors(noisy),
      );

      for (final label in _labels) {
        expect(
          noisyResult.sensors[label]!.timeGradient,
          closeTo(cleanResult.sensors[label]!.timeGradient!, 1e-12),
        );
        expect(
          noisyResult.sensors[label]!.offsetSeconds,
          closeTo(cleanResult.sensors[label]!.offsetSeconds!, 1e-12),
        );
      }
    });

    test('is repeatable and renders traceable CSV and SVG outputs', () {
      final fixture = _fixture();
      final anchors = _anchors(fixture);
      final first =
          const IndexTimeReconstructor().reconstruct(fixture, anchors);
      final second =
          const IndexTimeReconstructor().reconstruct(fixture, anchors);

      expect(first.toJson(), second.toJson());
      final samplesCsv = const IndexTimeSamplesCsv().render(first);
      final gridCsv = const IndexTimeGridCsv().render(first);
      final svg = const IndexTimeReconstructionSvg().render(first);
      expect(
        samplesCsv,
        startsWith('time_basis,sensor,sample_index,packet_index'),
      );
      expect(samplesCsv, contains('RECONSTRUCTED_INDEX_TIME'));
      expect(samplesCsv, contains('"VL.txt",2'));
      expect(gridCsv, startsWith('time_basis,analysis_time_s,VL.acc_x_mps2'));
      expect(gridCsv, contains('VL.lower_sample_index'));
      expect(svg, contains('Rekonstruierte Indexzeit'));
      expect(svg, contains('BLE-Empfangszeit'));
      expect(svg, contains('VL_START'));
    });

    test('interpolates AngleZ across the degree wrap without inventing zero',
        () {
      final fixture = _fixture();
      final result = const IndexTimeReconstructor(
        config: IndexTimeReconstructionConfig(targetSamplingRateHz: 200),
      ).reconstruct(fixture, _anchors(fixture));
      final interpolated = result.frames
          .map((frame) => frame.values['VL'])
          .whereType<ResampledImuValue>()
          .firstWhere(
            (value) =>
                value.lowerSampleIndex == 50 && value.upperSampleIndex == 51,
          );

      expect(interpolated.orientationAnglesDegrees, isNotNull);
      expect(interpolated.orientationAnglesDegrees!.z.abs(), greaterThan(170));
      expect(
        const IndexTimeGridCsv().render(result),
        contains('VL.angle_z_deg'),
      );
    });

    test('rejects missing sensor, missing anchor and short input explicitly',
        () {
      final missingSensor = _fixture()..recordings.remove('HR');
      final missingSensorResult = const IndexTimeReconstructor().reconstruct(
        missingSensor,
        _anchors(missingSensor, omitMissingRecordings: true),
      );
      expect(
        missingSensorResult.status,
        TimeReconstructionStatus.notPossible,
      );
      expect(
        missingSensorResult.issues.map((issue) => issue.code),
        contains('missing_required_sensor'),
      );

      final noAnchors = const IndexTimeReconstructor().reconstruct(
        _fixture(),
        const [],
      );
      expect(noAnchors.status, TimeReconstructionStatus.notPossible);
      expect(
        noAnchors.issues.map((issue) => issue.code),
        contains('missing_video_anchor'),
      );

      final short = _fixture(sampleCounts: {
        for (final label in _labels) label: 1,
      });
      final shortResult =
          const IndexTimeReconstructor().reconstruct(short, const []);
      expect(shortResult.status, TimeReconstructionStatus.notPossible);
      expect(shortResult.sensors['VL']!.invalidReason, contains('Weniger'));
    });

    test('rejects NaN, backward timestamps and invalid configurations', () {
      final nanFixture = _fixture();
      final original = nanFixture.recordings['VL']!.samples[10];
      nanFixture.recordings['VL']!.samples[10] = _copy(
        original,
        acceleration: const Vector3(double.nan, 0, 0),
      );
      final nanResult = const IndexTimeReconstructor().reconstruct(
        nanFixture,
        _anchors(nanFixture),
      );
      expect(nanResult.status, TimeReconstructionStatus.notPossible);
      expect(nanResult.sensors['VL']!.invalidReason, contains('endlicher'));

      final backwardFixture = _fixture();
      final backward = backwardFixture.recordings['VR']!.samples;
      backward[20] = _copy(
        backward[20],
        timestamp: backward[19].timestamp.subtract(
              const Duration(milliseconds: 1),
            ),
      );
      final backwardResult = const IndexTimeReconstructor().reconstruct(
        backwardFixture,
        _anchors(backwardFixture),
      );
      expect(backwardResult.status, TimeReconstructionStatus.notPossible);
      expect(
        backwardResult.sensors['VR']!.invalidReason,
        contains('Rückwärts'),
      );

      expect(
        () => const IndexTimeReconstructor(
          config: IndexTimeReconstructionConfig(targetSamplingRateHz: 0),
        ).reconstruct(_fixture(), const []),
        throwsArgumentError,
      );
    });

    test('rejects anchors without distinct indices or raw-line traceability',
        () {
      final fixture = _fixture();
      final anchors = _anchors(fixture)
          .where((anchor) => anchor.sensorLabel != 'VL')
          .toList()
        ..addAll(const [
          VideoImuAnchor(
            id: 'A',
            sensorLabel: 'VL',
            videoTimeSeconds: 1,
            rawSourceLine: 2,
          ),
          VideoImuAnchor(
            id: 'B',
            sensorLabel: 'VL',
            videoTimeSeconds: 2,
            rawSourceLine: 2,
          ),
        ]);
      expect(
        () => const IndexTimeReconstructor().reconstruct(fixture, anchors),
        throwsArgumentError,
      );

      final missingLine = _anchors(fixture)
          .map(
            (anchor) => anchor.sensorLabel == 'HR'
                ? const VideoImuAnchor(
                    id: 'BAD',
                    sensorLabel: 'HR',
                    videoTimeSeconds: 1,
                    rawSourceLine: 99999,
                  )
                : anchor,
          )
          .toList();
      final result =
          const IndexTimeReconstructor().reconstruct(fixture, missingLine);
      expect(result.status, TimeReconstructionStatus.notPossible);
      expect(
        result.sensors['HR']!.invalidReason,
        contains('Rohdatenzeile'),
      );
    });
  });
}

const _labels = ['VL', 'VR', 'HL', 'HR'];
const _offsets = {'VL': 1.0, 'VR': 1.02, 'HL': 0.98, 'HR': 1.01};
const _gradients = {'VL': 1.001, 'VR': 0.999, 'HL': 1.002, 'HR': 0.998};

ImuImportResult _fixture({
  double receptionRateHz = 100,
  int? packetGapAfterIndex,
  Map<String, int>? sampleCounts,
  double noise = 0,
  bool irregularSignal = false,
}) {
  final catalog = SensorCatalog(
    _labels.map(
      (label) => SensorIdentity(
        label: label,
        hardwareId: label.padRight(12, label),
        position: label.toLowerCase(),
      ),
    ),
  );
  final recordings = <String, SensorRecording>{};
  final start = DateTime.utc(2026, 1, 1);
  for (var sensorIndex = 0; sensorIndex < _labels.length; sensorIndex++) {
    final label = _labels[sensorIndex];
    final identity = catalog.sensors.elementAt(sensorIndex);
    final recording = SensorRecording(identity);
    final count = sampleCounts?[label] ?? 101;
    for (var index = 0; index < count; index++) {
      final packetStart = index ~/ 4 * 4;
      var receptionSeconds = packetStart / receptionRateHz;
      if (packetGapAfterIndex != null && packetStart > packetGapAfterIndex) {
        receptionSeconds += 0.2;
      }
      final timestamp = start.add(
        Duration(microseconds: (receptionSeconds * 1000000).round()),
      );
      final phase = irregularSignal ? math.sin(index * index * 0.013) : 0.0;
      final deterministicNoise = noise * math.sin(index * 7.31 + sensorIndex);
      final value = math.sin(index / 10) + phase + deterministicNoise;
      recording.samples.add(
        ImuSample(
          timestamp: timestamp,
          rawTimestamp: timestamp.toIso8601String(),
          accelerationMps2: Vector3(value, value * 0.2, 9.8 + value),
          angularVelocityRadPerSecond:
              Vector3(value * 0.1, -value * 0.2, value * 0.3),
          magneticFieldMicrotesla: const Vector3(20, 5, 30),
          orientationAnglesDegrees: Vector3(
            1,
            2,
            _wrapDegrees(79 + index * 2),
          ),
          sourceName: '$label.txt',
          sourceLine: index + 2,
        ),
      );
    }
    recording.sourceNames.add('$label.txt');
    recordings[label] = recording;
  }
  return ImuImportResult(
    catalog: catalog,
    recordings: recordings,
    messages: const [],
    sourceUnits: const {
      'acceleration': 'm/s^2',
      'angular_velocity': 'rad/s',
      'magnetic_field': 'uT',
    },
    timestampUncertainty: 'Synthetic bundled BLE reception timestamps.',
  );
}

ImuImportResult _fixtureWithOptionalGirth() {
  final base = _fixture();
  final identities = [
    for (final label in _labels)
      SensorIdentity(
        label: label,
        hardwareId: label.padRight(12, label),
        position: label.toLowerCase(),
      ),
    const SensorIdentity(
      label: 'SG',
      hardwareId: 'SGSGSGSGSGSG',
      position: 'girth',
      required: false,
    ),
  ];
  final catalog = SensorCatalog(identities);
  final girth = SensorRecording(catalog.byHardwareId('SGSGSGSGSGSG')!);
  final start = DateTime.utc(2026, 1, 1);
  for (var index = 0; index <= 100; index++) {
    final packetStart = index ~/ 4 * 4;
    final timestamp = start.add(Duration(milliseconds: packetStart * 10));
    girth.samples.add(
      ImuSample(
        timestamp: timestamp,
        rawTimestamp: timestamp.toIso8601String(),
        accelerationMps2: Vector3(index.toDouble(), 0, 9.8),
        angularVelocityRadPerSecond: const Vector3(0, 0, 0),
        sourceName: 'SG.txt',
        sourceLine: index + 2,
      ),
    );
  }
  return ImuImportResult(
    catalog: catalog,
    recordings: {...base.recordings, 'SG': girth},
    messages: base.messages,
    sourceUnits: base.sourceUnits,
    timestampUncertainty: base.timestampUncertainty,
  );
}

List<VideoImuAnchor> _anchors(
  ImuImportResult fixture, {
  Map<String, double> nominalRates = const {
    'VL': 100,
    'VR': 100,
    'HL': 100,
    'HR': 100,
  },
  bool omitMissingRecordings = false,
}) {
  final anchors = <VideoImuAnchor>[];
  for (final label in _labels) {
    final recording = fixture.recordings[label];
    if (recording == null && omitMissingRecordings) continue;
    final count = recording!.samples.length;
    final rate = nominalRates[label]!;
    anchors
      ..add(
        VideoImuAnchor(
          id: '${label}_START',
          sensorLabel: label,
          videoTimeSeconds: _offsets[label]!,
          rawSourceName: '$label.txt',
          rawSourceLine: 2,
          uncertaintyMilliseconds: 10,
        ),
      )
      ..add(
        VideoImuAnchor(
          id: '${label}_END',
          sensorLabel: label,
          videoTimeSeconds:
              _offsets[label]! + _gradients[label]! * (count - 1) / rate,
          rawSourceName: '$label.txt',
          rawSourceLine: count + 1,
          uncertaintyMilliseconds: 10,
        ),
      );
  }
  return anchors;
}

ImuSample _copy(
  ImuSample sample, {
  DateTime? timestamp,
  Vector3? acceleration,
}) =>
    ImuSample(
      timestamp: timestamp ?? sample.timestamp,
      rawTimestamp: (timestamp ?? sample.timestamp).toIso8601String(),
      accelerationMps2: acceleration ?? sample.accelerationMps2,
      angularVelocityRadPerSecond: sample.angularVelocityRadPerSecond,
      magneticFieldMicrotesla: sample.magneticFieldMicrotesla,
      orientationAnglesDegrees: sample.orientationAnglesDegrees,
      sourceName: sample.sourceName,
      sourceLine: sample.sourceLine,
    );

double _wrapDegrees(double value) {
  while (value > 180) {
    value -= 360;
  }
  while (value < -180) {
    value += 360;
  }
  return value;
}
