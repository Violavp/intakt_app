import 'dart:math' as math;

import 'index_time_reconstruction.dart';

/// Diagnostic view of index time, BLE reception time and video anchors.
class IndexTimeReconstructionSvg {
  const IndexTimeReconstructionSvg({
    this.width = 1200,
    this.panelHeight = 190,
    this.maximumPointsPerSensor = 1200,
  });

  final int width;
  final int panelHeight;
  final int maximumPointsPerSensor;

  String render(IndexTimeReconstructionResult result) {
    final valid =
        result.sensors.values.where((sensor) => sensor.valid).toList();
    if (valid.isEmpty) {
      throw StateError('Keine gültige Sensorrekonstruktion für die Vorschau.');
    }
    final height = 105 + valid.length * panelHeight;
    const left = 82.0;
    final plotWidth = width - left - 32;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
        'height="$height" viewBox="0 0 $width $height">',
      )
      ..writeln('<rect width="100%" height="100%" fill="#f7faf7"/>')
      ..writeln(
        '<text x="$left" y="27" font-family="sans-serif" font-size="18" '
        'font-weight="700" fill="#19372a">Rekonstruierte Indexzeit</text>',
      )
      ..writeln(
        '<text x="$left" y="48" font-family="sans-serif" font-size="11" '
        'fill="#53665a">Zeitbasis ausdrücklich rekonstruiert · '
        'grün Analysezeit · blau BLE-Empfangszeit · orange Videoanker</text>',
      )
      ..writeln(
        '<text x="$left" y="66" font-family="sans-serif" font-size="10" '
        'fill="#7a4b00">Empfangszeit ist paketiert und kein '
        'individueller Samplezeitstempel.</text>',
      );

    for (var panel = 0; panel < valid.length; panel++) {
      final sensor = valid[panel];
      final top = 82.0 + panel * panelHeight;
      final samples = sensor.samples;
      final stride = math.max(1, samples.length ~/ maximumPointsPerSensor);
      final receptionOrigin =
          samples.first.rawSample.timestamp.microsecondsSinceEpoch / 1000000;
      final analysisOrigin = samples.first.analysisTimeSeconds;
      final lastIndex = math.max(1, samples.length - 1);
      final receptionValues = <double>[];
      final analysisValues = <double>[];
      for (var index = 0; index < samples.length; index += stride) {
        receptionValues.add(
          samples[index].rawSample.timestamp.microsecondsSinceEpoch / 1000000 -
              receptionOrigin,
        );
        analysisValues.add(samples[index].analysisTimeSeconds - analysisOrigin);
      }
      final maximumY = math.max(
        1e-9,
        math.max(
          receptionValues.reduce(math.max),
          analysisValues.reduce(math.max),
        ),
      );
      final plotHeight = panelHeight - 55.0;
      String pathFor(List<double> values) {
        final path = StringBuffer();
        for (var point = 0; point < values.length; point++) {
          final sampleIndex = math.min(point * stride, samples.length - 1);
          final x = left + sampleIndex / lastIndex * plotWidth;
          final y =
              top + 8 + (maximumY - values[point]) / maximumY * plotHeight;
          path.write(
            '${point == 0 ? 'M' : ' L'}'
            '${x.toStringAsFixed(2)},${y.toStringAsFixed(2)}',
          );
        }
        return path.toString();
      }

      buffer
        ..writeln(
          '<rect x="$left" y="$top" width="$plotWidth" '
          'height="$plotHeight" fill="#fff" stroke="#d9e3dc"/>',
        )
        ..writeln(
          '<text x="20" y="${top + 20}" font-family="sans-serif" '
          'font-size="13" font-weight="700" fill="#19372a">'
          '${_escape(sensor.sensorLabel)}</text>',
        )
        ..writeln(
          '<path d="${pathFor(receptionValues)}" fill="none" '
          'stroke="#3273b8" stroke-width="1.2"/>',
        )
        ..writeln(
          '<path d="${pathFor(analysisValues)}" fill="none" '
          'stroke="#287f5b" stroke-width="1.5"/>',
        );
      for (final evidence in sensor.anchorEvidence) {
        final x = left + evidence.sampleIndex / lastIndex * plotWidth;
        final relative = evidence.anchor.videoTimeSeconds - analysisOrigin;
        final y = top + 8 + (maximumY - relative) / maximumY * plotHeight;
        buffer
          ..writeln(
            '<circle cx="${x.toStringAsFixed(2)}" '
            'cy="${y.toStringAsFixed(2)}" r="4" fill="#dc7b16"/>',
          )
          ..writeln(
            '<text x="${(x + 5).toStringAsFixed(2)}" '
            'y="${(y - 5).toStringAsFixed(2)}" font-family="sans-serif" '
            'font-size="9" fill="#7a4b00">${_escape(evidence.anchor.id)}</text>',
          );
      }
      buffer.writeln(
        '<text x="$left" y="${top + panelHeight - 14}" '
        'font-family="sans-serif" font-size="10" fill="#53665a">'
        'nominal ${sensor.nominalSamplingRateHz.toStringAsFixed(3)} Hz · '
        'effektiv ${_number(sensor.effectiveSamplingRateHz)} Hz · '
        'Gradient ${_number(sensor.timeGradient)} · '
        'Unsicherheit ${_number(sensor.baseUncertaintyMilliseconds)} ms · '
        'Verlust ${sensor.lossDetermination.name}</text>',
      );
    }
    buffer
      ..writeln(
        '<text x="$left" y="${height - 10}" font-family="sans-serif" '
        'font-size="10" fill="#53665a">Technische Rekonstruktion; '
        'keine gemessene Sensorzeit und keine medizinische Aussage.</text>',
      )
      ..writeln('</svg>');
    return buffer.toString();
  }
}

String _number(double? value) =>
    value == null ? 'nicht bestimmbar' : value.toStringAsFixed(3);

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
