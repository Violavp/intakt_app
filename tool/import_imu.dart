import 'dart:convert';
import 'dart:io';

import 'package:intakt_app/imu_import/imu_import.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    _usage();
    exitCode = arguments.contains('--help') ? 0 : 64;
    return;
  }

  var configurationPath = 'config/messkonfiguration.v2.json';
  var outputDirectory = 'outputs/imu_import';
  final sourcePaths = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--config':
        configurationPath = _nextValue(arguments, ++index, '--config');
      case '--out':
        outputDirectory = _nextValue(arguments, ++index, '--out');
      default:
        if (arguments[index].startsWith('--')) {
          stderr.writeln('Unbekannte Option: ${arguments[index]}');
          _usage();
          exitCode = 64;
          return;
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
    final result = await ImuTextImporter(catalog: catalog).importFiles(
      sourcePaths.map((path) => ImuSource(file: File(path))).toList(),
    );
    final quality = const ImuQualityAnalyzer().analyze(result);
    final output = Directory(outputDirectory);
    await output.create(recursive: true);

    final reportFile = File('${output.path}/quality_report.json');
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'report_version': 2,
        'import': result.toSummaryJson(),
        'quality': quality.toJson(),
      }),
    );
    final previewFile = File('${output.path}/preview.svg');
    await previewFile.writeAsString(const ImuPreviewSvg().render(result));

    stdout
      ..writeln(
        '${result.totalRows} Messzeilen aus '
        '${result.recordings.length} Sensoren importiert.',
      )
      ..writeln('Qualitätsbericht: ${reportFile.path}')
      ..writeln('Grafische Prüfung: ${previewFile.path}');
    if (!quality.readyForFurtherAnalysis) {
      stderr.writeln(
        'Datenqualität ist für die weitere Analyse nicht ausreichend. '
        'Details stehen im Qualitätsbericht.',
      );
      exitCode = 2;
    }
  } on ImuImportException catch (error) {
    stderr.writeln(error);
    exitCode = 2;
  } on FormatException catch (error) {
    stderr.writeln('Konfigurationsfehler: ${error.message}');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln(
        'Dateifehler: ${error.message} (${error.path ?? 'unbekannt'})');
    exitCode = 2;
  }
}

String _nextValue(List<String> arguments, int index, String option) {
  if (index >= arguments.length) {
    throw FormatException('Nach $option fehlt ein Wert.');
  }
  return arguments[index];
}

void _usage() {
  stdout.writeln(
    'Aufruf: dart run tool/import_imu.dart [Optionen] <Rohdatei>...\n'
    '  --config <json>  Sensorzuordnung '
    '(Standard: config/messkonfiguration.v2.json)\n'
    '  --out <ordner>   Bericht und SVG '
    '(Standard: outputs/imu_import)\n\n'
    'Rohdateien werden ausschließlich gelesen und nie verändert.',
  );
}
