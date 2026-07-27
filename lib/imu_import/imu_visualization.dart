import 'dart:math' as math;

import 'imu_models.dart';

/// Dependency-free SVG preview of acceleration magnitude in source order.
class ImuPreviewSvg {
  const ImuPreviewSvg({
    this.width = 1200,
    this.panelHeight = 180,
    this.maxPointsPerSensor = 1000,
  });

  final int width;
  final int panelHeight;
  final int maxPointsPerSensor;

  String render(ImuImportResult result) {
    if (result.recordings.isEmpty) {
      throw ArgumentError('Für eine Vorschau sind importierte Sensoren nötig.');
    }
    const left = 78.0;
    const right = 24.0;
    const top = 72.0;
    const bottom = 50.0;
    final height = top + result.recordings.length * panelHeight + bottom;
    final plotWidth = width - left - right;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="$width" height="${height.round()}" '
        'viewBox="0 0 $width ${height.round()}">',
      )
      ..writeln('<rect width="100%" height="100%" fill="#f7f8f7"/>')
      ..writeln(
        '<text x="$left" y="30" font-family="sans-serif" font-size="20" '
        'font-weight="700" fill="#173d28">InTakt IMU-Import – '
        'Plausibilitätsvorschau</text>',
      )
      ..writeln(
        '<text x="$left" y="52" font-family="sans-serif" font-size="12" '
        'fill="#53665a">Beschleunigungsbetrag [m/s²] · X-Achse: '
        'unveränderte Quellreihenfolge (nicht rekonstruierte Einzelzeit)</text>',
      );

    var panel = 0;
    for (final recording in result.recordings.values) {
      final yTop = top + panel * panelHeight;
      final plotHeight = panelHeight - 48.0;
      final points = _downsample(recording.samples);
      final magnitudes = points
          .map((sample) => math.sqrt(sample.accelerationMps2.magnitudeSquared))
          .toList();
      var minValue = magnitudes.reduce(math.min);
      var maxValue = magnitudes.reduce(math.max);
      if (minValue == maxValue) {
        minValue -= 0.5;
        maxValue += 0.5;
      }
      final path = StringBuffer();
      for (var index = 0; index < magnitudes.length; index++) {
        final x = left +
            (magnitudes.length == 1
                ? 0
                : index / (magnitudes.length - 1) * plotWidth);
        final y = yTop +
            plotHeight -
            (magnitudes[index] - minValue) / (maxValue - minValue) * plotHeight;
        path.write(index == 0 ? 'M' : ' L');
        path.write('${x.toStringAsFixed(2)},${y.toStringAsFixed(2)}');
      }
      buffer
        ..writeln(
          '<rect x="$left" y="$yTop" width="$plotWidth" '
          'height="$plotHeight" rx="6" fill="#ffffff" stroke="#d8ded9"/>',
        )
        ..writeln(
          '<path d="$path" fill="none" stroke="#1c6b3a" '
          'stroke-width="1.4"/>',
        )
        ..writeln(
          '<text x="18" y="${yTop + 22}" font-family="sans-serif" '
          'font-size="16" font-weight="700" fill="#173d28">'
          '${_escape(recording.identity.label)}</text>',
        )
        ..writeln(
          '<text x="18" y="${yTop + 40}" font-family="sans-serif" '
          'font-size="10" fill="#53665a">'
          '${recording.samples.length} Zeilen</text>',
        )
        ..writeln(
          '<text x="${left + 5}" y="${yTop + 14}" font-family="sans-serif" '
          'font-size="10" fill="#53665a">'
          '${maxValue.toStringAsFixed(2)}</text>',
        )
        ..writeln(
          '<text x="${left + 5}" y="${yTop + plotHeight - 5}" '
          'font-family="sans-serif" font-size="10" fill="#53665a">'
          '${minValue.toStringAsFixed(2)}</text>',
        );
      panel++;
    }
    buffer
      ..writeln(
        '<text x="$left" y="${height - 18}" font-family="sans-serif" '
        'font-size="11" fill="#53665a">Darstellung ist eine technische '
        'Plausibilitätsprüfung, keine Bewegungsanalyse oder Diagnose.</text>',
      )
      ..writeln('</svg>');
    return buffer.toString();
  }

  List<ImuSample> _downsample(List<ImuSample> samples) {
    if (samples.length <= maxPointsPerSensor) return samples;
    final selected = <ImuSample>[];
    for (var index = 0; index < maxPointsPerSensor; index++) {
      final sourceIndex =
          (index * (samples.length - 1) / (maxPointsPerSensor - 1)).round();
      selected.add(samples[sourceIndex]);
    }
    return selected;
  }
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
