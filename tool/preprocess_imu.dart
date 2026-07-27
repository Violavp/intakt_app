import 'dart:convert';
import 'dart:io';

import 'package:intakt_app/imu_import/imu_import.dart';
import 'package:intakt_app/imu_preprocessing/imu_preprocessing.dart';
import 'package:intakt_app/imu_sync/imu_sync.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    _usage();
    exitCode = arguments.contains('--help') ? 0 : 64;
    return;
  }
  var sensorConfigurationPath = 'config/messkonfiguration.v2.json';
  var preprocessingConfigurationPath = 'config/vorverarbeitung.v1.json';
  var anchorPath = 'recordings/test01/evidence/video_imu_synchronisation.json';
  var outputDirectory = 'outputs/imu_preprocessing';
  var nominalRateHz = 100.0;
  var targetRateHz = 100.0;
  final sourcePaths = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--sensor-config':
        sensorConfigurationPath = _next(arguments, ++index, '--sensor-config');
      case '--preprocessing-config':
        preprocessingConfigurationPath =
            _next(arguments, ++index, '--preprocessing-config');
      case '--anchors':
        anchorPath = _next(arguments, ++index, '--anchors');
      case '--out':
        outputDirectory = _next(arguments, ++index, '--out');
      case '--nominal-rate':
        nominalRateHz = _rate(_next(arguments, ++index, '--nominal-rate'));
      case '--target-rate':
        targetRateHz = _rate(_next(arguments, ++index, '--target-rate'));
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
      await File(sensorConfigurationPath).readAsString(),
    );
    final imported = await ImuTextImporter(catalog: catalog).importFiles(
      sourcePaths.map((path) => ImuSource(file: File(path))).toList(),
    );
    final reconstructed = IndexTimeReconstructor(
      config: IndexTimeReconstructionConfig(
        defaultNominalSamplingRateHz: nominalRateHz,
        targetSamplingRateHz: targetRateHz,
      ),
    ).reconstruct(imported, await _readAnchors(File(anchorPath)));
    final preprocessingConfig = ImuPreprocessingConfig.fromJsonString(
      await File(preprocessingConfigurationPath).readAsString(),
    );
    final result =
        ImuPreprocessor(config: preprocessingConfig).process(reconstructed);
    final output = Directory(outputDirectory);
    await output.create(recursive: true);
    final report = File('${output.path}/preprocessing_report.json');
    await report.writeAsString(preprocessingReportJson(result));
    stdout.writeln('Vorverarbeitungsbericht: ${report.path}');
    if (!result.hasDataset) {
      stderr.writeln(
        'Kein belastbarer Vorverarbeitungsdatensatz erzeugt; der Bericht '
        'bleibt zur Fehlerprüfung erhalten.',
      );
      exitCode = 2;
      return;
    }
    final csv = File('${output.path}/raw_filtered_comparison.csv');
    final svg = File('${output.path}/raw_filtered_preview.svg');
    await csv.writeAsString(const PreprocessedImuCsv().render(result));
    await svg.writeAsString(const ImuPreprocessingSvg().render(result));
    stdout
      ..writeln('Roh-/Filtervergleich: ${csv.path}')
      ..writeln('Grafische Prüfung: ${svg.path}');
    if (result.status == PreprocessingStatus.reviewRequired) {
      stderr.writeln(
        'Die Vorverarbeitung erfordert manuelle Prüfung; Unsicherheiten und '
        'Empfehlungen stehen im Bericht.',
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
    stderr.writeln('Vorverarbeitungsfehler: ${error.message}');
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
  return [
    for (final value in root['anchors'] as List)
      if (value is Map<String, dynamic>)
        VideoImuAnchor(
          id: value['id'] as String,
          sensorLabel: value['sensor'] as String,
          videoTimeSeconds: (value['video_time_s'] as num).toDouble(),
          rawSourceLine: value['raw_source_line'] as int,
          rawSourceName: value['raw_source_name'] as String?,
          uncertaintyMilliseconds:
              (value['uncertainty_ms'] as num?)?.toDouble(),
          assignment: value['assignment'] as String?,
        )
      else
        throw const FormatException('Ungültiger Ankereintrag.'),
  ];
}

String _next(List<String> arguments, int index, String option) {
  if (index >= arguments.length) {
    throw FormatException('Nach $option fehlt ein Wert.');
  }
  return arguments[index];
}

double _rate(String value) {
  final rate = double.tryParse(value);
  if (rate == null || !rate.isFinite || rate <= 0) {
    throw FormatException('Ungültige Abtastrate: "$value".');
  }
  return rate;
}

void _usage() {
  stdout.writeln(
    'Aufruf: dart run tool/preprocess_imu.dart [Optionen] <Rohdatei>...\n'
    '  --sensor-config <json>          Sensorzuordnung\n'
    '  --preprocessing-config <json>   zentrale Filterkonfiguration\n'
    '  --anchors <json>                Video-IMU-Anker\n'
    '  --out <ordner>                  Bericht, Vergleichs-CSV und SVG\n'
    '  --nominal-rate <hz>             konfigurierte Sensorrate\n'
    '  --target-rate <hz>              gemeinsames Raster\n\n'
    'Rohdateien werden ausschließlich gelesen und niemals verändert.',
  );
}
