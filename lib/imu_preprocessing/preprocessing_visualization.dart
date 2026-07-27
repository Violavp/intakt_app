import 'dart:math' as math;

import '../imu_import/imu_models.dart';
import 'preprocessing_models.dart';

class ImuPreprocessingSvg {
  const ImuPreprocessingSvg({
    this.width = 1200,
    this.panelHeight = 190,
    this.maximumPoints = 1800,
  });

  final int width;
  final int panelHeight;
  final int maximumPoints;

  String render(ImuPreprocessingResult result) {
    final labels = result.sensorQuality.keys.toList();
    final height = 105 + labels.length * panelHeight;
    const left = 75.0;
    final right = width - 25.0;
    final plotWidth = right - left;
    final times = result.frames
        .map((frame) => frame.analysisTimeSeconds)
        .toList(growable: false);
    final startTime = times.isEmpty ? 0.0 : times.first;
    final endTime = times.isEmpty ? 1.0 : times.last;
    final duration = math.max(endTime - startTime, 1e-9);
    final stride = math.max(1, (result.frames.length / maximumPoints).ceil());
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
        'height="$height" viewBox="0 0 $width $height">',
      )
      ..writeln('<rect width="100%" height="100%" fill="#fbfaf7"/>')
      ..writeln(
        '<text x="24" y="30" font-family="sans-serif" font-size="21" '
        'font-weight="bold">IMU-Vorverarbeitung: Roh / Butterworth / '
        'Bewegungsanteil</text>',
      )
      ..writeln(
        '<text x="24" y="54" font-family="sans-serif" font-size="12" '
        'fill="#444">Beschleunigungsbetrag in m/s²; Zeitbasis: '
        'rekonstruierte Analysezeit. Rohdaten bleiben unverändert.</text>',
      )
      ..writeln(
        '<line x1="24" y1="74" x2="48" y2="74" stroke="#888" '
        'stroke-width="1"/><text x="53" y="78" font-family="sans-serif" '
        'font-size="11">roh</text>',
      )
      ..writeln(
        '<line x1="105" y1="74" x2="129" y2="74" stroke="#176b87" '
        'stroke-width="2"/><text x="134" y="78" font-family="sans-serif" '
        'font-size="11">gefiltert</text>',
      )
      ..writeln(
        '<line x1="213" y1="74" x2="237" y2="74" stroke="#c65d21" '
        'stroke-width="1.5"/><text x="242" y="78" font-family="sans-serif" '
        'font-size="11">Bewegungsanteil</text>',
      );

    for (var panel = 0; panel < labels.length; panel++) {
      final label = labels[panel];
      final top = 95.0 + panel * panelHeight;
      final bottom = top + panelHeight - 34;
      final raw = <_Point>[];
      final filtered = <_Point>[];
      final movement = <_Point>[];
      for (var index = 0; index < result.frames.length; index += stride) {
        final frame = result.frames[index];
        final value = frame.values[label];
        if (value == null) continue;
        final x = left +
            (frame.analysisTimeSeconds - startTime) / duration * plotWidth;
        raw.add(_Point(x, _magnitude(value.raw.accelerationMps2)));
        filtered.add(_Point(x, _magnitude(value.alignedAccelerationMps2)));
        movement.add(_Point(x, _magnitude(value.movementAccelerationMps2)));
      }
      final allY = [...raw, ...filtered, ...movement].map((point) => point.y);
      final minimum = allY.isEmpty ? 0.0 : allY.reduce(math.min);
      final maximum = allY.isEmpty ? 1.0 : allY.reduce(math.max);
      final range = math.max(maximum - minimum, 1e-9);
      double scaleY(double value) =>
          bottom - (value - minimum) / range * (bottom - top);
      String path(List<_Point> points) => points.isEmpty
          ? ''
          : points
              .asMap()
              .entries
              .map(
                (entry) => '${entry.key == 0 ? 'M' : 'L'}'
                    '${entry.value.x.toStringAsFixed(2)},'
                    '${scaleY(entry.value.y).toStringAsFixed(2)}',
              )
              .join(' ');
      final quality = result.sensorQuality[label]!;
      buffer
        ..writeln(
          '<rect x="$left" y="$top" width="$plotWidth" '
          'height="${bottom - top}" fill="#fff" stroke="#ddd"/>',
        )
        ..writeln(
          '<text x="22" y="${top + 17}" font-family="sans-serif" '
          'font-size="14" font-weight="bold">$label</text>',
        )
        ..writeln(
          '<text x="22" y="${top + 34}" font-family="sans-serif" '
          'font-size="10">Q=${quality.qualityScore.toStringAsFixed(2)}</text>',
        )
        ..writeln(
          '<path d="${path(raw)}" fill="none" stroke="#888" '
          'stroke-width="1" opacity="0.7"/>',
        )
        ..writeln(
          '<path d="${path(filtered)}" fill="none" stroke="#176b87" '
          'stroke-width="2"/>',
        )
        ..writeln(
          '<path d="${path(movement)}" fill="none" stroke="#c65d21" '
          'stroke-width="1.5"/>',
        )
        ..writeln(
          '<text x="$left" y="${bottom + 18}" font-family="sans-serif" '
          'font-size="10">${startTime.toStringAsFixed(2)} s</text>',
        )
        ..writeln(
          '<text x="${right - 50}" y="${bottom + 18}" '
          'font-family="sans-serif" font-size="10">'
          '${endTime.toStringAsFixed(2)} s</text>',
        );
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }
}

class _Point {
  const _Point(this.x, this.y);

  final double x;
  final double y;
}

double _magnitude(Vector3 value) =>
    math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
