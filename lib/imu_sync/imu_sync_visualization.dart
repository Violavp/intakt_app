import 'dart:math' as math;

import 'imu_synchronization.dart';

class ImuSynchronizationSvg {
  const ImuSynchronizationSvg({
    this.width = 1200,
    this.panelHeight = 150,
    this.maximumPointsPerSensor = 1200,
  });

  final int width;
  final int panelHeight;
  final int maximumPointsPerSensor;

  String render(ImuSynchronizationResult result) {
    if (!result.hasSynchronizedDataset) {
      throw StateError(
        'Ohne gültigen gemeinsamen Datensatz ist keine Vorschau möglich.',
      );
    }
    final labels = result.sensorQuality.keys.toList();
    final height = 90 + labels.length * panelHeight;
    const left = 74.0;
    final plotWidth = width - left - 28;
    final duration = math.max(
      result.frames.last.elapsedSeconds,
      1 / result.gridSamplingRateHz,
    );
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
        'height="$height" viewBox="0 0 $width $height">',
      )
      ..writeln('<rect width="100%" height="100%" fill="#f7faf7"/>')
      ..writeln(
        '<text x="$left" y="28" font-family="sans-serif" font-size="18" '
        'font-weight="700" fill="#19372a">Synchronisierte '
        'Beschleunigungsbeträge</text>',
      )
      ..writeln(
        '<text x="$left" y="48" font-family="sans-serif" font-size="11" '
        'fill="#53665a">Gemeinsame UTC-Zeitbasis · '
        '${result.gridSamplingRateHz.toStringAsFixed(3)} Hz · '
        'Lücken werden nicht verbunden</text>',
      );

    for (var panel = 0; panel < labels.length; panel++) {
      final label = labels[panel];
      final top = 65.0 + panel * panelHeight;
      final points = <(double, double)?>[];
      var minimum = double.infinity;
      var maximum = double.negativeInfinity;
      final stride =
          math.max(1, result.frames.length ~/ maximumPointsPerSensor);
      for (var index = 0; index < result.frames.length; index += stride) {
        final frame = result.frames[index];
        final value = frame.values[label];
        if (value == null) {
          points.add(null);
          continue;
        }
        final magnitude = math.sqrt(value.accelerationMps2.magnitudeSquared);
        minimum = math.min(minimum, magnitude);
        maximum = math.max(maximum, magnitude);
        points.add((frame.elapsedSeconds, magnitude));
      }
      buffer
        ..writeln(
          '<rect x="$left" y="$top" width="$plotWidth" '
          'height="${panelHeight - 32}" fill="#fff" stroke="#d9e3dc"/>',
        )
        ..writeln(
          '<text x="18" y="${top + 20}" font-family="sans-serif" '
          'font-size="13" font-weight="700" fill="#19372a">$label</text>',
        );
      if (minimum.isFinite && maximum.isFinite) {
        final span = math.max(maximum - minimum, 1e-9);
        final path = StringBuffer();
        var open = false;
        for (final point in points) {
          if (point == null) {
            open = false;
            continue;
          }
          final x = left + point.$1 / duration * plotWidth;
          final y = top + 8 + (maximum - point.$2) / span * (panelHeight - 48);
          path.write('${open ? ' L' : 'M'}'
              '${x.toStringAsFixed(2)},${y.toStringAsFixed(2)}');
          open = true;
        }
        buffer.writeln(
          '<path d="$path" fill="none" stroke="#287f5b" stroke-width="1.2"/>',
        );
      }
      final quality = result.sensorQuality[label]!;
      buffer.writeln(
        '<text x="${left + 8}" y="${top + panelHeight - 14}" '
        'font-family="sans-serif" font-size="10" fill="#53665a">'
        'Offset ${_number(quality.estimatedSignalOffsetMilliseconds)} ms · '
        'Drift ${_number(quality.estimatedDriftPpm)} ppm · '
        'RMSE ${_number(quality.lagResidualRmseMilliseconds)} ms · '
        'Abdeckung ${(quality.outputCoverage * 100).toStringAsFixed(1)} %'
        '</text>',
      );
    }
    buffer
      ..writeln(
        '<text x="$left" y="${height - 10}" font-family="sans-serif" '
        'font-size="10" fill="#53665a">Technische Plausibilitätsprüfung; '
        'keine fachliche Validierung oder Diagnose.</text>',
      )
      ..writeln('</svg>');
    return buffer.toString();
  }
}

String _number(double? value) =>
    value == null ? 'nicht bestimmbar' : value.toStringAsFixed(3);
