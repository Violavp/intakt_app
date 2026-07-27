import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:intakt_app/imu_import/imu_import.dart';

void main() {
  late SensorCatalog catalog;

  setUp(() {
    catalog = SensorCatalog(const [
      SensorIdentity(label: 'VL', hardwareId: 'AAAAAAAAAAAA', position: 'vl'),
      SensorIdentity(label: 'VR', hardwareId: 'BBBBBBBBBBBB', position: 'vr'),
      SensorIdentity(label: 'HL', hardwareId: 'CCCCCCCCCCCC', position: 'hl'),
      SensorIdentity(label: 'HR', hardwareId: 'DDDDDDDDDDDD', position: 'hr'),
      SensorIdentity(
        label: 'SG',
        hardwareId: 'EEEEEEEEEEEE',
        position: 'sg',
        required: false,
      ),
    ]);
  });

  group('IMU import', () {
    test('imports four multiplexed sensors and converts known units', () async {
      final result = await ImuTextImporter(catalog: catalog).importText(
        _fourSensorText(),
      );

      expect(result.recordings.keys, ['VL', 'VR', 'HL', 'HR']);
      expect(result.totalRows, 9);
      expect(
        result.recordings['VL']!.samples.first.accelerationMps2.x,
        closeTo(9.80665, 1e-9),
      );
      expect(
        result.recordings['VL']!.samples.first.angularVelocityRadPerSecond.x,
        closeTo(math.pi, 1e-9),
      );
      expect(
        result.recordings['VL']!.samples.first.magneticFieldMicrotesla!.z,
        3,
      );
      expect(result.sourceUnits['acceleration'], 'g');
      expect(result.sourceUnits['angular_velocity'], 'degree/s');
      expect(result.sourceUnits['orientation_angle'], 'degree');
      expect(
        result.recordings['VL']!.samples.first.orientationAnglesDegrees,
        isNotNull,
      );
      expect(
        result.recordings['VL']!.samples.first.orientationAnglesDegrees!.z,
        179,
      );
    });

    test('supports individual files without device column using explicit ID',
        () async {
      const text =
          'time\tAccX(g)\tAccY(g)\tAccZ(g)\tAsX(°/s)\tAsY(°/s)\tAsZ(°/s)\n'
          '2026-07-23T20:00:00.000\t1\t2\t3\t4\t5\t6\n';
      final result = await ImuTextImporter(catalog: catalog).importText(
        text,
        sourceName: 'vl.txt',
        sourceHardwareId: 'AAAAAAAAAAAA',
      );
      expect(result.recordings.values.single.identity.label, 'VL');
      expect(
        result.recordings.values.single.samples.single.sourceName,
        'vl.txt',
      );
    });

    test('recognizes all four separate sensor files', () async {
      final directory = await Directory.systemTemp.createTemp('intakt_imu_');
      addTearDown(() => directory.delete(recursive: true));
      const header =
          'time\tAccX(g)\tAccY(g)\tAccZ(g)\tAsX(°/s)\tAsY(°/s)\tAsZ(°/s)\n';
      final sources = <ImuSource>[];
      for (final identity in catalog.requiredSensors) {
        final file = File('${directory.path}/${identity.label}.txt');
        await file.writeAsString(
          '${header}2026-07-23T20:00:00.000\t1\t2\t3\t4\t5\t6\n',
        );
        sources.add(ImuSource(file: file, hardwareId: identity.hardwareId));
      }

      final result =
          await ImuTextImporter(catalog: catalog).importFiles(sources);

      expect(result.recordings.keys, ['VL', 'VR', 'HL', 'HR']);
      expect(
          result.recordings.values
              .every((sensor) => sensor.samples.length == 1),
          isTrue);
    });

    test('magnetometer is optional', () async {
      final text = _fourSensorText(includeMagnetometer: false);
      final result = await ImuTextImporter(catalog: catalog).importText(text);
      expect(
        result.recordings.values
            .expand((recording) => recording.samples)
            .every((sample) => sample.magneticFieldMicrotesla == null),
        isTrue,
      );
    });

    test('orientation angles are optional but never partially invented',
        () async {
      final without = _fourSensorText(includeOrientationAngles: false);
      final result =
          await ImuTextImporter(catalog: catalog).importText(without);
      expect(
        result.recordings.values
            .expand((recording) => recording.samples)
            .every((sample) => sample.orientationAnglesDegrees == null),
        isTrue,
      );
      final partial = _fourSensorText().replaceFirst('\tAngleZ(°)', '');
      await expectLater(
        ImuTextImporter(catalog: catalog).importText(partial),
        throwsA(
          isA<ImuImportException>().having(
            (error) => error.code,
            'code',
            'partial_orientation_angle_columns',
          ),
        ),
      );
    });

    test('rejects a missing required column with a clear code', () async {
      final text = _fourSensorText().replaceFirst('\tAsZ(°/s)', '');
      await expectLater(
        ImuTextImporter(catalog: catalog).importText(text),
        throwsA(
          isA<ImuImportException>()
              .having((error) => error.code, 'code', 'missing_column')
              .having((error) => error.column, 'column', contains('z')),
        ),
      );
    });

    test('rejects invalid timestamps without dropping the row', () async {
      final text =
          _fourSensorText().replaceFirst('2026-07-23T20:00:00.000', 'kaputt');
      await expectLater(
        ImuTextImporter(catalog: catalog).importText(text),
        throwsA(
          isA<ImuImportException>()
              .having((error) => error.code, 'code', 'invalid_timestamp')
              .having((error) => error.line, 'line', 2),
        ),
      );
    });

    for (final invalid in ['NaN', 'Infinity', 'null']) {
      test('rejects non-finite or missing required value $invalid', () async {
        final text = _fourSensorText()
            .replaceFirst('\t1\t2\t3\t180', '\t$invalid\t2\t3\t180');
        await expectLater(
          ImuTextImporter(catalog: catalog).importText(text),
          throwsA(
            isA<ImuImportException>().having(
              (error) => error.code,
              'code',
              'invalid_numeric_value',
            ),
          ),
        );
      });
    }

    test('rejects unknown sensor IDs instead of guessing a position', () async {
      final text =
          _fourSensorText().replaceFirst('AAAAAAAAAAAA', 'FFFFFFFFFFFF');
      await expectLater(
        ImuTextImporter(catalog: catalog).importText(text),
        throwsA(
          isA<ImuImportException>()
              .having((error) => error.code, 'code', 'unknown_sensor'),
        ),
      );
    });

    test('rejects partial optional magnetometer triples', () async {
      final text = _fourSensorText().replaceFirst('\tHZ(uT)', '');
      await expectLater(
        ImuTextImporter(catalog: catalog).importText(text),
        throwsA(
          isA<ImuImportException>().having(
            (error) => error.code,
            'code',
            'partial_magnetometer_columns',
          ),
        ),
      );
    });

    test('rejects undocumented units rather than guessing', () async {
      final text = _fourSensorText().replaceAll('(g)', '(foo)');
      await expectLater(
        ImuTextImporter(catalog: catalog).importText(text),
        throwsA(
          isA<ImuImportException>()
              .having((error) => error.code, 'code', 'unsupported_unit'),
        ),
      );
    });

    test('empty input produces understandable error', () async {
      await expectLater(
        ImuTextImporter(catalog: catalog).importText(''),
        throwsA(
          isA<ImuImportException>()
              .having((error) => error.code, 'code', 'empty_file'),
        ),
      );
    });
  });

  group('quality assessment', () {
    test('reports a missing required sensor and blocks further analysis',
        () async {
      final result = await ImuTextImporter(catalog: catalog).importText(
        _fourSensorText()
            .split('\n')
            .where((line) => !line.contains('DDDDDDDDDDDD'))
            .join('\n'),
      );
      final report = const ImuQualityAnalyzer().analyze(result);
      expect(report.readyForFurtherAnalysis, isFalse);
      expect(report.metrics.keys, containsAll(['VL', 'VR', 'HL', 'HR']));
      expect(
        report.metrics['HR']!.status,
        SensorQualityStatus.unusable,
      );
      expect(report.metrics['HR']!.rows, 0);
      expect(
        report.issues,
        contains(
          isA<QualityIssue>()
              .having((issue) => issue.code, 'code', 'missing_required_sensor')
              .having((issue) => issue.sensorLabel, 'sensor', 'HR'),
        ),
      );
    });

    test('detects different lengths, duplicate timestamps and a data gap',
        () async {
      final text = '${_fourSensorText()}'
          '2026-07-23T20:00:00.020\tWIT(AAAAAAAAAAAA)\t1\t2\t3\t180\t90\t0\t1\t2\t3\t1\t2\t179\n'
          '2026-07-23T20:00:00.030\tWIT(AAAAAAAAAAAA)\t1\t2\t3\t180\t90\t0\t1\t2\t3\t1\t2\t179\n'
          '2026-07-23T20:00:01.000\tWIT(AAAAAAAAAAAA)\t1\t2\t3\t180\t90\t0\t1\t2\t3\t1\t2\t179\n';
      final result = await ImuTextImporter(catalog: catalog).importText(text);
      final report = const ImuQualityAnalyzer().analyze(result);
      expect(report.rowCountsDiffer, isTrue);
      expect(report.metrics['VL']!.duplicateTimestampRows, 1);
      expect(report.metrics['VL']!.gaps, 1);
      final gap = report.metrics['VL']!.gapLocations.single;
      expect(
          gap.previousTimestamp.toIso8601String(), '2026-07-23T20:00:00.030');
      expect(gap.currentTimestamp.toIso8601String(), '2026-07-23T20:00:01.000');
      expect(gap.previousSourceLine, 12);
      expect(gap.currentSourceLine, 13);
      expect(gap.estimatedMissingRows, 96);
      expect(
        report.issues.map((issue) => issue.code),
        containsAll([
          'different_file_lengths',
          'duplicate_reception_timestamps',
          'reception_gaps',
        ]),
      );
    });

    test('reports backward timestamps without sorting source rows', () async {
      final text = _fourSensorText().replaceFirst(
        '2026-07-23T20:00:00.010\tWIT(AAAAAAAAAAAA)',
        '2026-07-23T19:59:59.000\tWIT(AAAAAAAAAAAA)',
      );
      final result = await ImuTextImporter(catalog: catalog).importText(text);
      final report = const ImuQualityAnalyzer().analyze(result);
      expect(report.metrics['VL']!.backwardTimestampRows, 1);
      expect(report.readyForFurtherAnalysis, isFalse);
      expect(
        result.recordings['VL']!.samples[1].rawTimestamp,
        '2026-07-23T19:59:59.000',
      );
    });

    test('detects different sampling rates', () async {
      final result = await ImuTextImporter(catalog: catalog).importText(
        _fourSensorText(varyEndTimes: true),
      );
      final report = const ImuQualityAnalyzer().analyze(result);
      expect(report.samplingRatesDiffer, isTrue);
      expect(
        report.issues.map((issue) => issue.code),
        contains('different_sampling_rates'),
      );
    });

    test('assigns usable status and duration to every clean sensor', () {
      final result = _qualityFixture();
      final report = const ImuQualityAnalyzer().analyze(result);

      expect(report.metrics.keys, ['VL', 'VR', 'HL', 'HR']);
      expect(
        report.metrics.values
            .every((metric) => metric.status == SensorQualityStatus.usable),
        isTrue,
      );
      expect(
        report.metrics.values.every((metric) => metric.durationSeconds == 2.75),
        isTrue,
      );
      expect(report.readyForFurtherAnalysis, isTrue);
      expect(report.toJson()['status'], 'QUALITY_ACCEPTED');
    });

    test('localizes irregular intervals without classifying them as gaps', () {
      final result = _qualityFixture(
        timestampsMs: [
          0,
          250,
          500,
          810,
          1060,
          1310,
          1560,
          1810,
          2060,
          2310,
          2560,
          2810,
        ],
      );
      final report = const ImuQualityAnalyzer().analyze(result);
      final metric = report.metrics['VL']!;

      expect(metric.gapLocations, isEmpty);
      expect(metric.irregularIntervalLocations, hasLength(1));
      expect(metric.irregularIntervalLocations.single.intervalMs, 310);
      expect(metric.irregularIntervalLocations.single.currentSourceLine, 5);
      expect(metric.status, SensorQualityStatus.reviewRequired);
      expect(report.readyForFurtherAnalysis, isFalse);
    });

    test('marks frozen runs and extreme outliers without changing samples', () {
      final result = _qualityFixture(anomalousVlValues: true);
      final originalSamples =
          List<ImuSample>.of(result.recordings['VL']!.samples);
      final originalOutlier = originalSamples[10].accelerationMps2.x;

      final report = const ImuQualityAnalyzer().analyze(result);
      final metric = report.metrics['VL']!;

      expect(
        metric.frozenSegments,
        contains(
          isA<ValueMarker>()
              .having((marker) => marker.channel, 'channel', 'acc_y')
              .having((marker) => marker.sampleCount, 'sample count', 12)
              .having((marker) => marker.startSourceLine, 'start line', 2)
              .having((marker) => marker.endSourceLine, 'end line', 13),
        ),
      );
      expect(
        metric.extremeOutliers,
        contains(
          isA<ValueMarker>()
              .having((marker) => marker.channel, 'channel', 'acc_x')
              .having((marker) => marker.unit, 'unit', 'm/s^2')
              .having((marker) => marker.value, 'value', 1000)
              .having((marker) => marker.startSourceLine, 'line', 12),
        ),
      );
      expect(metric.status, SensorQualityStatus.reviewRequired);
      expect(result.recordings['VL']!.samples, orderedEquals(originalSamples));
      expect(
        result.recordings['VL']!.samples[10].accelerationMps2.x,
        originalOutlier,
      );
    });

    test('short recordings are unusable and cannot continue silently', () {
      final result = _qualityFixture(
        timestampsMs: [0, 250, 500, 750],
      );
      final report = const ImuQualityAnalyzer().analyze(result);

      expect(
        report.metrics.values
            .every((metric) => metric.status == SensorQualityStatus.unusable),
        isTrue,
      );
      expect(report.readyForFurtherAnalysis, isFalse);
      expect(report.toJson()['status'], 'QUALITY_NOT_SUFFICIENT');
      expect(
        report.issues.map((issue) => issue.code),
        contains('unexpectedly_short_recording'),
      );
    });

    test('quality JSON contains status and localized value markers', () {
      final report = const ImuQualityAnalyzer().analyze(
        _qualityFixture(anomalousVlValues: true),
      );
      final qualityJson = report.toJson();
      final sensors = qualityJson['sensors']! as List<Object?>;
      final vl = sensors.cast<Map<String, Object?>>().singleWhere(
            (sensor) => sensor['label'] == 'VL',
          );

      expect(vl['quality_status'], 'REVIEW_REQUIRED');
      expect(vl['duration_s'], 2.75);
      expect(vl['frozen_segments'], isNotEmpty);
      expect(vl['extreme_outliers'], isNotEmpty);
      expect(qualityJson['ready_for_further_analysis'], isFalse);
    });

    test('blank source rows are visible and block automatic continuation', () {
      final clean = _qualityFixture();
      final result = ImuImportResult(
        catalog: clean.catalog,
        recordings: clean.recordings,
        messages: const [
          ImportMessage(
            code: 'blank_line',
            message: 'Leere Zeile wurde als fehlender Datensatz gemeldet.',
            severity: ImportMessageSeverity.warning,
            sourceName: 'qa.txt',
            line: 7,
          ),
        ],
        sourceUnits: clean.sourceUnits,
        timestampUncertainty: clean.timestampUncertainty,
      );

      final report = const ImuQualityAnalyzer().analyze(result);

      expect(
        report.issues,
        contains(
          isA<QualityIssue>()
              .having((issue) => issue.code, 'code', 'missing_source_rows')
              .having(
                (issue) => issue.observation,
                'location',
                contains('qa.txt:7'),
              ),
        ),
      );
      expect(
        report.metrics.values.every(
          (metric) => metric.status == SensorQualityStatus.reviewRequired,
        ),
        isTrue,
      );
      expect(report.readyForFurtherAnalysis, isFalse);
    });
  });

  test('SVG preview contains every imported sensor and unit', () async {
    final result =
        await ImuTextImporter(catalog: catalog).importText(_fourSensorText());
    final svg = const ImuPreviewSvg().render(result);
    expect(svg, startsWith('<svg'));
    for (final label in ['VL', 'VR', 'HL', 'HR']) {
      expect(svg, contains('>$label</text>'));
    }
    expect(svg, contains('m/s²'));
    expect(svg, contains('keine Bewegungsanalyse'));
  });
}

ImuImportResult _qualityFixture({
  List<int>? timestampsMs,
  bool anomalousVlValues = false,
}) {
  final times = timestampsMs ??
      const [
        0,
        250,
        500,
        750,
        1000,
        1250,
        1500,
        1750,
        2000,
        2250,
        2500,
        2750,
      ];
  final catalog = SensorCatalog(const [
    SensorIdentity(label: 'VL', hardwareId: 'AAAAAAAAAAAA', position: 'vl'),
    SensorIdentity(label: 'VR', hardwareId: 'BBBBBBBBBBBB', position: 'vr'),
    SensorIdentity(label: 'HL', hardwareId: 'CCCCCCCCCCCC', position: 'hl'),
    SensorIdentity(label: 'HR', hardwareId: 'DDDDDDDDDDDD', position: 'hr'),
  ]);
  final recordings = <String, SensorRecording>{};
  final start = DateTime.parse('2026-07-23T20:00:00.000');
  for (final identity in catalog.sensors) {
    final recording = SensorRecording(identity)..sourceNames.add('qa.txt');
    for (var index = 0; index < times.length; index++) {
      final anomalous = anomalousVlValues && identity.label == 'VL';
      recording.samples.add(
        ImuSample(
          timestamp: start.add(Duration(milliseconds: times[index])),
          rawTimestamp:
              start.add(Duration(milliseconds: times[index])).toIso8601String(),
          accelerationMps2: Vector3(
            anomalous && index == 10 ? 1000 : index.toDouble(),
            anomalous ? 5 : index + 0.25,
            index + 0.5,
          ),
          angularVelocityRadPerSecond: Vector3(
            index + 0.75,
            index + 1.0,
            index + 1.25,
          ),
          sourceName: 'qa.txt',
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
    },
    timestampUncertainty: 'Test fixture with explicit ISO timestamps.',
  );
}

String _fourSensorText({
  bool includeMagnetometer = true,
  bool includeOrientationAngles = true,
  bool varyEndTimes = false,
}) {
  final magnetometerHeader =
      includeMagnetometer ? '\tHX(uT)\tHY(uT)\tHZ(uT)' : '';
  final magnetometerValues = includeMagnetometer ? '\t1\t2\t3' : '';
  final orientationHeader =
      includeOrientationAngles ? '\tAngleX(°)\tAngleY(°)\tAngleZ(°)' : '';
  final orientationValues = includeOrientationAngles ? '\t1\t2\t179' : '';
  final rows = <String>[];
  final sensors = {
    'AAAAAAAAAAAA': 10,
    'BBBBBBBBBBBB': varyEndTimes ? 20 : 10,
    'CCCCCCCCCCCC': varyEndTimes ? 30 : 10,
    'DDDDDDDDDDDD': varyEndTimes ? 40 : 10,
  };
  for (final entry in sensors.entries) {
    rows
      ..add(
        '2026-07-23T20:00:00.000\tWIT(${entry.key})'
        '\t1\t2\t3\t180\t90\t0$magnetometerValues$orientationValues',
      )
      ..add(
        '2026-07-23T20:00:00.${entry.value.toString().padLeft(3, '0')}'
        '\tWIT(${entry.key})\t2\t3\t4\t90\t45\t0'
        '$magnetometerValues$orientationValues',
      );
  }
  // A duplicate reception timestamp for VL is intentional in the fixture.
  rows.add(
    '2026-07-23T20:00:00.010\tWIT(AAAAAAAAAAAA)'
    '\t3\t4\t5\t0\t0\t0$magnetometerValues$orientationValues',
  );
  return 'time\tDeviceName\tAccX(g)\tAccY(g)\tAccZ(g)'
      '\tAsX(°/s)\tAsY(°/s)\tAsZ(°/s)$magnetometerHeader'
      '$orientationHeader\n'
      '${rows.join('\n')}\n';
}
