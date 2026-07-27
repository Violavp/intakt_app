import 'dart:convert';
import 'dart:io';

import 'package:intakt_app/gait_segmentation/gait_segmentation.dart';
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
  var segmentationConfigurationPath = 'config/gangsegmentierung.v1.json';
  var anchorPath = 'recordings/test01/evidence/video_imu_synchronisation.json';
  String? correctionsPath;
  var outputDirectory = 'outputs/gait_segmentation';
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
      case '--segmentation-config':
        segmentationConfigurationPath =
            _next(arguments, ++index, '--segmentation-config');
      case '--anchors':
        anchorPath = _next(arguments, ++index, '--anchors');
      case '--corrections':
        correctionsPath = _next(arguments, ++index, '--corrections');
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
    final preprocessed =
        ImuPreprocessor(config: preprocessingConfig).process(reconstructed);
    final segmentationConfig = GaitSegmentationConfig.fromJsonString(
      await File(segmentationConfigurationPath).readAsString(),
    );
    final corrections = correctionsPath == null
        ? const <ManualSegmentCorrection>[]
        : await _readCorrections(File(correctionsPath));
    final result = GaitSegmenter(config: segmentationConfig).segment(
      preprocessed,
      corrections: corrections,
    );
    final output = Directory(outputDirectory);
    await output.create(recursive: true);
    final report = File('${output.path}/gait_segmentation_report.json');
    await report.writeAsString(gaitSegmentationReportJson(result));
    stdout.writeln('Segmentierungsbericht: ${report.path}');
    if (!result.hasSegments) {
      stderr.writeln(
        'Keine belastbare Segmentierung erzeugt; der Bericht bleibt zur '
        'Fehlerprüfung erhalten.',
      );
      exitCode = 2;
      return;
    }
    final csv = File('${output.path}/gait_segments.csv');
    final svg = File('${output.path}/gait_segments_video_timeline.svg');
    await csv.writeAsString(const GaitSegmentationCsv().render(result));
    await svg.writeAsString(const GaitSegmentationSvg().render(result));
    stdout
      ..writeln('Segmenttabelle: ${csv.path}')
      ..writeln('Video-Prüfzeitleiste: ${svg.path}')
      ..writeln(
        'Analysierbare Abschnitte: ${result.analyzableSegments.length}',
      );
    if (result.status == SegmentationStatus.reviewRequired) {
      stderr.writeln(
        'Die Segmentierung erfordert manuelle Video-Prüfung; Unsicherheiten '
        'und Empfehlungen stehen im Bericht.',
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
    stderr.writeln('Segmentierungsfehler: ${error.message}');
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

Future<List<ManualSegmentCorrection>> _readCorrections(File file) async {
  final root = jsonDecode(await file.readAsString());
  if (root is! Map<String, dynamic> || root['corrections'] is! List) {
    throw const FormatException(
      'Korrekturdatei benötigt ein JSON-Objekt mit "corrections".',
    );
  }
  return [
    for (final value in root['corrections'] as List)
      if (value is Map<String, dynamic>)
        ManualSegmentCorrection.fromJson(value)
      else
        throw const FormatException('Ungültiger Korrektureintrag.'),
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
    'Aufruf: dart run tool/segment_gaits.dart [Optionen] <Rohdatei>...\n'
    '  --sensor-config <json>          Sensorzuordnung\n'
    '  --preprocessing-config <json>   Filterkonfiguration\n'
    '  --segmentation-config <json>    Segmentierungsschwellen\n'
    '  --anchors <json>                Video-IMU-Anker\n'
    '  --corrections <json>            optionale manuelle Korrekturen\n'
    '  --out <ordner>                  Bericht, CSV und Video-SVG\n'
    '  --nominal-rate <hz>             konfigurierte Sensorrate\n'
    '  --target-rate <hz>              gemeinsames Raster\n\n'
    'Rohdateien werden ausschließlich gelesen und niemals verändert.',
  );
}
