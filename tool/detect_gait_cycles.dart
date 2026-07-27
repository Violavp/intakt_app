import 'dart:convert';
import 'dart:io';

import 'package:intakt_app/gait_cycles/gait_cycles.dart';
import 'package:intakt_app/gait_segmentation/gait_segmentation.dart';
import 'package:intakt_app/imu_import/imu_import.dart';
import 'package:intakt_app/imu_preprocessing/imu_preprocessing.dart';
import 'package:intakt_app/imu_sync/imu_sync.dart';
import 'package:intakt_app/takt_parameters/takt_parameters.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    _usage();
    exitCode = arguments.contains('--help') ? 0 : 64;
    return;
  }
  var sensorConfig = 'config/messkonfiguration.v2.json';
  var preprocessingConfig = 'config/vorverarbeitung.v1.json';
  var segmentationConfig = 'config/gangsegmentierung.v1.json';
  var cycleConfig = 'config/gangzyklen.v1.json';
  var taktConfig = 'config/taktparameter.v1.json';
  var anchors = 'recordings/test01/evidence/video_imu_synchronisation.json';
  String? segmentCorrections;
  String? eventCorrections;
  var outputDirectory = 'outputs/gait_cycles';
  var nominalRateHz = 100.0;
  var targetRateHz = 100.0;
  final sources = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--sensor-config':
        sensorConfig = _next(arguments, ++index, '--sensor-config');
      case '--preprocessing-config':
        preprocessingConfig =
            _next(arguments, ++index, '--preprocessing-config');
      case '--segmentation-config':
        segmentationConfig = _next(arguments, ++index, '--segmentation-config');
      case '--cycle-config':
        cycleConfig = _next(arguments, ++index, '--cycle-config');
      case '--takt-config':
        taktConfig = _next(arguments, ++index, '--takt-config');
      case '--anchors':
        anchors = _next(arguments, ++index, '--anchors');
      case '--segment-corrections':
        segmentCorrections = _next(arguments, ++index, '--segment-corrections');
      case '--event-corrections':
        eventCorrections = _next(arguments, ++index, '--event-corrections');
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
        sources.add(arguments[index]);
    }
  }
  if (sources.isEmpty) {
    stderr.writeln('Keine Rohdatei angegeben.');
    exitCode = 64;
    return;
  }
  try {
    final catalog = SensorCatalog.fromConfigurationJson(
      await File(sensorConfig).readAsString(),
    );
    final imported = await ImuTextImporter(catalog: catalog).importFiles(
      sources.map((path) => ImuSource(file: File(path))).toList(),
    );
    final reconstructed = IndexTimeReconstructor(
      config: IndexTimeReconstructionConfig(
        defaultNominalSamplingRateHz: nominalRateHz,
        targetSamplingRateHz: targetRateHz,
      ),
    ).reconstruct(imported, await _readAnchors(File(anchors)));
    final preprocessed = ImuPreprocessor(
      config: ImuPreprocessingConfig.fromJsonString(
        await File(preprocessingConfig).readAsString(),
      ),
    ).process(reconstructed);
    final segmentation = GaitSegmenter(
      config: GaitSegmentationConfig.fromJsonString(
        await File(segmentationConfig).readAsString(),
      ),
    ).segment(
      preprocessed,
      corrections: segmentCorrections == null
          ? const <ManualSegmentCorrection>[]
          : await _readSegmentCorrections(File(segmentCorrections)),
    );
    final corrections = eventCorrections == null
        ? const <ManualGaitEventCorrection>[]
        : await _readEventCorrections(File(eventCorrections));
    final cycleResult = GaitCycleDetector(
      config: GaitCycleDetectionConfig.fromJsonString(
        await File(cycleConfig).readAsString(),
      ),
    ).detect(preprocessed, segmentation, corrections: corrections);
    final taktResult = TaktParameterAnalyzer(
      config: TaktParameterConfig.fromJsonString(
        await File(taktConfig).readAsString(),
      ),
    ).analyze(cycleResult, segmentation);

    final output = Directory(outputDirectory);
    await output.create(recursive: true);
    final report = File('${output.path}/gait_cycle_report.json');
    final events = File('${output.path}/gait_events.csv');
    final cycles = File('${output.path}/gait_cycles.csv');
    final plot = File('${output.path}/gait_cycle_review.svg');
    final taktReport = File('${output.path}/takt_parameter_report.json');
    final taktWindows = File('${output.path}/takt_windows.csv');
    final taktTrend = File('${output.path}/takt_trend.svg');
    await report.writeAsString(gaitCycleDetectionReportJson(cycleResult));
    await events.writeAsString(const GaitEventCsv().render(cycleResult));
    await cycles.writeAsString(const GaitCycleCsv().render(cycleResult));
    await plot.writeAsString(
      const GaitCycleSvg().render(preprocessed, cycleResult),
    );
    await taktReport.writeAsString(taktParameterReportJson(taktResult));
    await taktWindows.writeAsString(const TaktWindowCsv().render(taktResult));
    await taktTrend.writeAsString(const TaktTrendSvg().render(taktResult));
    stdout
      ..writeln('Gangzyklusbericht: ${report.path}')
      ..writeln('Ereignisse: ${events.path}')
      ..writeln('Gangzyklen: ${cycles.path}')
      ..writeln('Kontrollgrafik: ${plot.path}')
      ..writeln('Plausible Zyklen: ${cycleResult.plausibleCycles.length}')
      ..writeln('Taktparameterbericht: ${taktReport.path}')
      ..writeln('Taktfenster: ${taktWindows.path}')
      ..writeln('Taktverlauf: ${taktTrend.path}')
      ..writeln('Gültige Taktfenster: ${taktResult.validWindows.length}');
    if (cycleResult.status != GaitCycleDetectionStatus.accepted ||
        taktResult.status != TaktParameterStatus.accepted) {
      stderr.writeln(
        'Ergebnis erfordert Prüfung; Unsicherheiten stehen in den Berichten.',
      );
      exitCode = cycleResult.status == GaitCycleDetectionStatus.notPossible ||
              taktResult.status == TaktParameterStatus.notPossible
          ? 2
          : 1;
    }
  } on FormatException catch (error) {
    stderr.writeln('Eingabefehler: ${error.message}');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('Dateifehler: ${error.message} (${error.path ?? ''})');
    exitCode = 2;
  } on ArgumentError catch (error) {
    stderr.writeln('Erkennungsfehler: ${error.message}');
    exitCode = 2;
  }
}

Future<List<VideoImuAnchor>> _readAnchors(File file) async {
  final root = jsonDecode(await file.readAsString());
  if (root is! Map<String, dynamic> || root['anchors'] is! List) {
    throw const FormatException('Ankerdatei benötigt "anchors".');
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

Future<List<ManualGaitEventCorrection>> _readEventCorrections(File file) async {
  final root = jsonDecode(await file.readAsString());
  if (root is! Map<String, dynamic> || root['events'] is! List) {
    throw const FormatException('Ereignisdatei benötigt "events".');
  }
  return [
    for (final value in root['events'] as List)
      if (value is Map<String, dynamic>)
        ManualGaitEventCorrection.fromJson(value)
      else
        throw const FormatException('Ungültige Ereigniskorrektur.'),
  ];
}

Future<List<ManualSegmentCorrection>> _readSegmentCorrections(File file) async {
  final root = jsonDecode(await file.readAsString());
  if (root is! Map<String, dynamic> || root['corrections'] is! List) {
    throw const FormatException(
      'Segmentkorrekturdatei benötigt "corrections".',
    );
  }
  return [
    for (final value in root['corrections'] as List)
      if (value is Map<String, dynamic>)
        ManualSegmentCorrection.fromJson(value)
      else
        throw const FormatException('Ungültige Segmentkorrektur.'),
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
    throw FormatException('Ungültige Abtastrate "$value".');
  }
  return rate;
}

void _usage() {
  stdout.writeln(
    'Aufruf: dart run tool/detect_gait_cycles.dart [Optionen] <Rohdatei>...\n'
    '  --cycle-config <json>       Ereignis- und Zyklusparameter\n'
    '  --takt-config <json>        Fenster und Taktparameter\n'
    '  --segment-corrections <json> nutzerbestätigte Gangartsegmente\n'
    '  --event-corrections <json>  nutzerbestätigte Ereignisse\n'
    '  --out <ordner>              JSON, CSV und SVG\n'
    'Weitere Optionen entsprechen tool/segment_gaits.dart.\n'
    'Rohdaten werden ausschließlich gelesen.',
  );
}
