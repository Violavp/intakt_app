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
  var outputDirectory = 'outputs/imu_synchronization';
  var samplingRateHz = 100.0;
  String? referenceSensor;
  final sourcePaths = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--config':
        configurationPath = _nextValue(arguments, ++index, '--config');
      case '--out':
        outputDirectory = _nextValue(arguments, ++index, '--out');
      case '--rate':
        final text = _nextValue(arguments, ++index, '--rate');
        samplingRateHz = double.tryParse(text) ??
            (throw FormatException('Ungültige Abtastrate "$text".'));
      case '--reference':
        referenceSensor = _nextValue(arguments, ++index, '--reference');
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
    final synchronization = ImuSynchronizer(
      config: ImuSynchronizationConfig(
        targetSamplingRateHz: samplingRateHz,
        referenceSensorLabel: referenceSensor,
      ),
    ).synchronize(imported);
    final output = Directory(outputDirectory);
    await output.create(recursive: true);

    final reportFile = File('${output.path}/synchronization_report.json');
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'report_version': 1,
        'synchronization': synchronization.toJson(),
      }),
    );
    stdout.writeln('Synchronisationsbericht: ${reportFile.path}');

    if (!synchronization.hasSynchronizedDataset) {
      stderr.writeln(
        'Synchronisation nicht möglich; es wurde kein Ersatzdatensatz erzeugt.',
      );
      exitCode = 2;
      return;
    }
    final dataFile = File('${output.path}/synchronized.csv');
    await dataFile.writeAsString(
      const ImuSynchronizationCsv().render(synchronization),
    );
    final previewFile = File('${output.path}/synchronization_preview.svg');
    await previewFile.writeAsString(
      const ImuSynchronizationSvg().render(synchronization),
    );
    stdout
      ..writeln('Synchronisierter Datensatz: ${dataFile.path}')
      ..writeln('Grafische Prüfung: ${previewFile.path}');
    if (synchronization.status == SynchronizationStatus.reviewRequired) {
      stderr.writeln(
        'Synchronisation erfordert eine manuelle Prüfung; Details stehen im '
        'Bericht.',
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
      'Dateifehler: ${error.message} (${error.path ?? 'unbekannt'})',
    );
    exitCode = 2;
  } on ArgumentError catch (error) {
    stderr.writeln('Synchronisationskonfiguration ungültig: ${error.message}');
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
    'Aufruf: dart run tool/synchronize_imu.dart [Optionen] <Rohdatei>...\n'
    '  --config <json>     Sensorzuordnung\n'
    '  --out <ordner>      Bericht, CSV und SVG\n'
    '  --rate <hz>         gemeinsames Abtastraster (Standard: 100)\n'
    '  --reference <label> Referenzsensor (Standard: erster Pflichtsensor)\n\n'
    'Rohdateien werden ausschließlich gelesen und nie verändert.',
  );
}
