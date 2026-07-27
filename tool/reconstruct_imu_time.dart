import 'dart:convert';
import 'dart:io';

import 'package:intakt_app/imu_import/imu_import.dart';
import 'package:intakt_app/imu_sync/imu_sync.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    _usage();
    exitCode = arguments.contains('--help') ? 0 : 64;
    return;
  }

  var configurationPath = 'config/messkonfiguration.v2.json';
  var anchorPath = 'recordings/test01/evidence/video_imu_synchronisation.json';
  var outputDirectory = 'outputs/index_time_reconstruction';
  var nominalRateHz = 100.0;
  var targetRateHz = 100.0;
  final sourcePaths = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--config':
        configurationPath = _next(arguments, ++index, '--config');
      case '--anchors':
        anchorPath = _next(arguments, ++index, '--anchors');
      case '--out':
        outputDirectory = _next(arguments, ++index, '--out');
      case '--nominal-rate':
        nominalRateHz = _rate(
          _next(arguments, ++index, '--nominal-rate'),
          '--nominal-rate',
        );
      case '--target-rate':
        targetRateHz = _rate(
          _next(arguments, ++index, '--target-rate'),
          '--target-rate',
        );
      default:
        if (arguments[index].startsWith('--')) {
          throw FormatException('Unbekannte Option: ${arguments[index]}');
        }
        sourcePaths.add(arguments[index]);
    }
  }
  if (sourcePaths.isEmpty) {
    stderr.writeln('Keine Rohdatei angegeben.');
    _usage();
    exitCode = 64;
    return;
  }

  try {
    final catalog = SensorCatalog.fromConfigurationJson(
      await File(configurationPath).readAsString(),
    );
    final imported = await ImuTextImporter(catalog: catalog).importFiles(
      sourcePaths.map((path) => ImuSource(file: File(path))).toList(),
    );
    final anchors = await _readAnchors(File(anchorPath));
    final result = IndexTimeReconstructor(
      config: IndexTimeReconstructionConfig(
        defaultNominalSamplingRateHz: nominalRateHz,
        targetSamplingRateHz: targetRateHz,
      ),
    ).reconstruct(imported, anchors);
    final output = Directory(outputDirectory);
    await output.create(recursive: true);

    final reportFile = File('${output.path}/time_reconstruction_report.json');
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'report_version': 1,
        'reconstruction': result.toJson(),
      }),
    );
    stdout.writeln('Rekonstruktionsbericht: ${reportFile.path}');

    if (result.sensors.values.every((sensor) => sensor.valid)) {
      final samplesFile = File('${output.path}/reconstructed_samples.csv');
      await samplesFile.writeAsString(
        const IndexTimeSamplesCsv().render(result),
      );
      stdout.writeln('Indexbasierter Datensatz: ${samplesFile.path}');
    }
    if (!result.hasReconstructedDataset) {
      stderr.writeln(
        'Kein gemeinsames rekonstruiertes Raster erzeugt; Bericht bleibt '
        'zur Fehlerprüfung erhalten.',
      );
      exitCode = 2;
      return;
    }
    final gridFile = File('${output.path}/reconstructed_common_grid.csv');
    final previewFile = File('${output.path}/time_reconstruction_preview.svg');
    await gridFile.writeAsString(const IndexTimeGridCsv().render(result));
    await previewFile.writeAsString(
      const IndexTimeReconstructionSvg().render(result),
    );
    stdout
      ..writeln('Gemeinsames Raster: ${gridFile.path}')
      ..writeln('Grafische Prüfung: ${previewFile.path}');
    if (result.status == TimeReconstructionStatus.reviewRequired) {
      stderr.writeln(
        'Die rekonstruierte Zeitbasis erfordert manuelle Prüfung; '
        'Unsicherheiten und Verluststatus stehen im Bericht.',
      );
      exitCode = 2;
    }
  } on ImuImportException catch (error) {
    stderr.writeln(error);
    exitCode = 2;
  } on FormatException catch (error) {
    stderr.writeln('Eingabefehler: ${error.message}');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln(
      'Dateifehler: ${error.message} (${error.path ?? 'unbekannt'})',
    );
    exitCode = 2;
  } on ArgumentError catch (error) {
    stderr.writeln('Rekonstruktionsfehler: ${error.message}');
    exitCode = 2;
  }
}

Future<List<VideoImuAnchor>> _readAnchors(File file) async {
  final root = jsonDecode(await file.readAsString());
  if (root is! Map<String, dynamic> || root['anchors'] is! List) {
    throw const FormatException(
      'Ankerdatei benötigt ein JSON-Objekt mit "anchors".',
    );
  }
  final anchors = <VideoImuAnchor>[];
  for (final value in root['anchors'] as List) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Ungültiger Ankereintrag.');
    }
    final id = value['id'];
    final sensor = value['sensor'];
    final videoTime = value['video_time_s'];
    final sourceLine = value['raw_source_line'];
    if (id is! String ||
        sensor is! String ||
        videoTime is! num ||
        sourceLine is! int) {
      throw const FormatException(
        'Jeder Anker benötigt id, sensor, video_time_s und raw_source_line.',
      );
    }
    anchors.add(
      VideoImuAnchor(
        id: id,
        sensorLabel: sensor,
        videoTimeSeconds: videoTime.toDouble(),
        rawSourceLine: sourceLine,
        rawSourceName: value['raw_source_name'] as String?,
        uncertaintyMilliseconds: (value['uncertainty_ms'] as num?)?.toDouble(),
        assignment: value['assignment'] as String?,
      ),
    );
  }
  return anchors;
}

String _next(List<String> arguments, int index, String option) {
  if (index >= arguments.length) {
    throw FormatException('Nach $option fehlt ein Wert.');
  }
  return arguments[index];
}

double _rate(String value, String option) {
  final rate = double.tryParse(value);
  if (rate == null || !rate.isFinite || rate <= 0) {
    throw FormatException('Ungültige Rate für $option: "$value".');
  }
  return rate;
}

void _usage() {
  stdout.writeln(
    'Aufruf: dart run tool/reconstruct_imu_time.dart [Optionen] '
    '<Rohdatei>...\n'
    '  --config <json>       Sensorzuordnung\n'
    '  --anchors <json>      rückverfolgbare Video-IMU-Anker\n'
    '  --out <ordner>        Bericht, Sample-CSV, Raster-CSV und SVG\n'
    '  --nominal-rate <hz>   konfigurierte Sensorrate (Standard: 100)\n'
    '  --target-rate <hz>    gemeinsames Raster (Standard: 100)\n\n'
    'Rohdaten werden ausschließlich gelesen und nie verändert. Alle '
    'ausgegebenen Analysezeiten sind ausdrücklich rekonstruiert.',
  );
}
