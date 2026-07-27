import 'dart:convert';

import 'gait_segmentation_models.dart';

String gaitSegmentationReportJson(GaitSegmentationResult result) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'report_version': 1, 'segmentation': result.toJson()});

class GaitSegmentationCsv {
  const GaitSegmentationCsv();

  String render(GaitSegmentationResult result) {
    final buffer = StringBuffer()
      ..writeln(
        'start_s,end_s,video_start_s,video_end_s,gait,confidence,'
        'uncertainty,dominant_leg_frequency_hz,diagonal_synchrony,'
        'movement_rms_mps2,coverage,riding_direction,direction_valid,'
        'direction_invalid_reason,'
        'front_angle_z_trend_degps,hind_angle_z_trend_degps,'
        'mean_angle_z_trend_degps,line_bending_rate_degps,'
        'direction_confidence,'
        'transition,turn_candidate,interruption,analyzable,'
        'manually_corrected,correction_reasons',
      );
    for (final segment in result.segments) {
      final row = <Object?>[
        segment.startSeconds,
        segment.endSeconds,
        segment.startSeconds,
        segment.endSeconds,
        gaitLabelToJson(segment.gait),
        segment.confidence,
        segment.uncertainty,
        segment.dominantFrequencyHz,
        segment.diagonalSynchrony,
        segment.movementRmsMps2,
        segment.coverage,
        segment.ridingDirection.name.toUpperCase(),
        segment.ridingDirection != RidingDirection.unknown &&
            segment.meanAngleZTrendDegreesPerSecond != null,
        segment.ridingDirection == RidingDirection.unknown ||
                segment.meanAngleZTrendDegreesPerSecond == null
            ? 'four_leg_angle_z_consensus_not_reached_or_signal_missing'
            : '',
        segment.frontAngleZTrendDegreesPerSecond,
        segment.hindAngleZTrendDegreesPerSecond,
        segment.meanAngleZTrendDegreesPerSecond,
        segment.meanAngleZTrendDegreesPerSecond,
        segment.directionConfidence,
        segment.transition,
        segment.turn,
        segment.interruption,
        segment.analyzable,
        segment.manuallyCorrected,
        segment.correctionReasons.join(' | '),
      ];
      buffer.writeln(row.map(_csv).join(','));
    }
    return buffer.toString();
  }
}

class GaitSegmentationSvg {
  const GaitSegmentationSvg();

  String render(GaitSegmentationResult result) {
    if (result.segments.isEmpty) {
      return '<svg xmlns="http://www.w3.org/2000/svg" width="1000" '
          'height="180"><text x="20" y="40">Keine Segmente</text></svg>';
    }
    const width = 1200.0;
    const height = 260.0;
    const left = 90.0;
    const right = 30.0;
    const top = 50.0;
    const trackHeight = 74.0;
    final start = result.segments.first.startSeconds;
    final end = result.segments.last.endSeconds;
    final duration = end - start;
    const plotWidth = width - left - right;
    double x(double time) => left + (time - start) / duration * plotWidth;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
        'height="$height" viewBox="0 0 $width $height">',
      )
      ..writeln(
        '<rect width="100%" height="100%" fill="#fbfaf7"/>'
        '<text x="$left" y="26" font-family="sans-serif" font-size="18" '
        'font-weight="bold">Gangart- und Analyseabschnitte – Videozeit</text>',
      );
    for (final segment in result.segments) {
      final segmentX = x(segment.startSeconds);
      final segmentWidth = x(segment.endSeconds) - segmentX;
      final color = switch (segment.gait) {
        GaitLabel.standing => '#aeb7c2',
        GaitLabel.walk => '#69b578',
        GaitLabel.trot => '#4f86c6',
        GaitLabel.gallop => '#8f65b5',
        GaitLabel.unknown => '#d89b45',
      };
      buffer
        ..writeln(
          '<rect x="$segmentX" y="$top" width="$segmentWidth" '
          'height="$trackHeight" fill="$color" opacity="0.88"/>',
        )
        ..writeln(
          '<title>${_xml(gaitLabelToJson(segment.gait))}: '
          '${segment.startSeconds.toStringAsFixed(2)}–'
          '${segment.endSeconds.toStringAsFixed(2)} s; '
          'Richtung ${segment.ridingDirection.name.toUpperCase()}; '
          'AngleZ-Trend '
          '${segment.meanAngleZTrendDegreesPerSecond?.toStringAsFixed(2) ?? "ungültig"} '
          '°/s; Unsicherheit '
          '${segment.uncertainty.toStringAsFixed(2)}</title>',
        );
      if (!segment.analyzable) {
        buffer.writeln(
          '<path d="M $segmentX $top l $segmentWidth $trackHeight '
          'M $segmentX ${top + trackHeight} l $segmentWidth -$trackHeight" '
          'stroke="#692c2c" stroke-width="1" opacity="0.45"/>',
        );
      }
      if (segment.transition || segment.turn || segment.interruption) {
        final markers = [
          if (segment.transition) 'Ü',
          if (segment.turn) 'W',
          if (segment.interruption) 'U',
        ].join('/');
        buffer.writeln(
          '<text x="${segmentX + 3}" y="${top + 17}" '
          'font-family="sans-serif" font-size="12" fill="#111">$markers</text>',
        );
      }
    }
    for (var fraction = 0; fraction <= 10; fraction++) {
      final time = start + duration * fraction / 10;
      final tickX = x(time);
      buffer.writeln(
        '<line x1="$tickX" y1="${top + trackHeight}" x2="$tickX" '
        'y2="${top + trackHeight + 7}" stroke="#333"/>'
        '<text x="$tickX" y="${top + trackHeight + 23}" '
        'text-anchor="middle" font-family="sans-serif" font-size="11">'
        '${time.toStringAsFixed(1)} s</text>',
      );
    }
    buffer
      ..writeln(
        '<text x="$left" y="178" font-family="sans-serif" font-size="12">'
        'Ohne Kreuz = analysierbar; Kreuz = ausgeschlossen. '
        'Ü Übergang · W Wendungskandidat · U Unterbrechung.</text>',
      )
      ..writeln(
        '<text x="$left" y="200" font-family="sans-serif" font-size="12">'
        'Farben: Grau Stillstand · Grün Schritt · Blau Trab · '
        'Violett Galopp · Orange unsicher.</text>',
      )
      ..writeln(
        '<text x="$left" y="226" font-family="sans-serif" font-size="11" '
        'fill="#555">Segmentgrenzen verwenden analysis_time_s = '
        'video_time_s aus der Video-IMU-Zeitrekonstruktion.</text>',
      )
      ..writeln('</svg>');
    return buffer.toString();
  }
}

String _csv(Object? value) {
  if (value == null) return '';
  if (value is num || value is bool) return value.toString();
  return '"${value.toString().replaceAll('"', '""')}"';
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
