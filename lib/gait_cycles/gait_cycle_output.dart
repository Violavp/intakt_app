import 'dart:convert';
import 'dart:math' as math;

import '../imu_preprocessing/imu_preprocessing.dart';
import 'gait_cycle_models.dart';

String gaitCycleDetectionReportJson(GaitCycleDetectionResult result) =>
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': 1,
      'cycle_detection': result.toJson(),
    });

class GaitCycleCsv {
  const GaitCycleCsv();

  String render(GaitCycleDetectionResult result) {
    final output = StringBuffer(
      'cycle_id,sensor,gait,start_s,liftoff_s,end_s,duration_s,stance_s,'
      'swing_s,start_event_id,liftoff_event_id,end_event_id,'
      'duration_uncertainty_ms,stance_uncertainty_ms,swing_uncertainty_ms,'
      'quality,uncertainty,plausible,user_confirmed,'
      'sample_coverage,duration_deviation_fraction,exclusion_reasons\n',
    );
    for (final cycle in result.cycles) {
      output.writeln([
        cycle.id,
        cycle.sensorLabel,
        cycle.gait.name.toUpperCase(),
        cycle.startSeconds,
        cycle.liftoffSeconds,
        cycle.endSeconds,
        cycle.durationSeconds,
        cycle.stanceSeconds,
        cycle.swingSeconds,
        cycle.startEventId,
        cycle.liftoffEventId,
        cycle.endEventId,
        cycle.durationUncertaintyMilliseconds,
        cycle.stanceUncertaintyMilliseconds,
        cycle.swingUncertaintyMilliseconds,
        cycle.quality,
        1 - cycle.quality,
        cycle.plausible,
        cycle.userConfirmed,
        cycle.sampleCoverage,
        cycle.durationDeviationFraction,
        cycle.exclusionReasons.join('|'),
      ].map(_csv).join(','));
    }
    return output.toString();
  }
}

class GaitEventCsv {
  const GaitEventCsv();

  String render(GaitCycleDetectionResult result) {
    final output = StringBuffer(
      'event_id,sensor,gait,event,time_s,quality,source,'
      'riding_direction,pattern_calibration,pattern_support_count,'
      'pattern_agreement,'
      'canonical_gyro_y_radps,canonical_acc_x_mps2,raw_source,'
      'raw_source_line,source_uncertainty_ms\n',
    );
    for (final event in result.events) {
      output.writeln([
        event.id,
        event.sensorLabel,
        event.gait.name.toUpperCase(),
        event.kind == GaitEventKind.touchdown ? 'TOUCHDOWN' : 'LIFTOFF',
        event.timeSeconds,
        event.quality,
        event.source.name,
        event.ridingDirection.name.toUpperCase(),
        event.patternCalibration,
        event.patternSupportCount,
        event.patternAgreement,
        event.canonicalGyroYRadPerSecond,
        event.canonicalAccelerationXMps2,
        event.sourceName,
        event.sourceLine,
        event.sourceUncertaintyMilliseconds,
      ].map(_csv).join(','));
    }
    return output.toString();
  }
}

/// Static review plot. Blue circles are touchdown hypotheses, red crosses are
/// liftoff hypotheses; implausible cycles are shaded red.
class GaitCycleSvg {
  const GaitCycleSvg({this.maximumPointsPerSensor = 2500});

  final int maximumPointsPerSensor;

  String render(
    ImuPreprocessingResult input,
    GaitCycleDetectionResult result,
  ) {
    if (input.frames.isEmpty) {
      return '<svg xmlns="http://www.w3.org/2000/svg"/>';
    }
    const sensors = ['VL', 'VR', 'HL', 'HR'];
    const width = 1400.0;
    const rowHeight = 230.0;
    const left = 75.0;
    const right = 55.0;
    const top = 55.0;
    final height = top + rowHeight * sensors.length + 50;
    final start = input.frames.first.analysisTimeSeconds;
    final end = input.frames.last.analysisTimeSeconds;
    final duration = math.max(1e-9, end - start);
    double x(double time) =>
        left + (time - start) / duration * (width - left - right);
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
        'height="$height" viewBox="0 0 $width $height">',
      )
      ..writeln('<rect width="100%" height="100%" fill="white"/>')
      ..writeln(
        '<text x="$left" y="25" font-family="sans-serif" font-size="16" '
        'font-weight="bold">Gangereignisse und Gangzyklen</text>',
      )
      ..writeln(
        '<text x="$left" y="44" font-family="sans-serif" font-size="11" '
        'fill="#555">AsY und AccX sind für rechts gespiegelt; blau: Auftreten, '
        'rot: Abheben; Ereignisnamen sind nutzerbestätigte Signalhypothesen.'
        '</text>',
      );
    for (var sensorIndex = 0; sensorIndex < sensors.length; sensorIndex++) {
      final sensor = sensors[sensorIndex];
      final sign = sensor.endsWith('R') ? -1.0 : 1.0;
      final rowTop = top + sensorIndex * rowHeight;
      final values = [
        for (final frame in input.frames)
          if (frame.values[sensor] != null)
            (
              time: frame.analysisTimeSeconds,
              gyro: sign *
                  frame.values[sensor]!
                      .filteredAngularVelocitySensorFrameRadPerSecond.y,
              acc: sign *
                  frame.values[sensor]!.filteredAccelerationSensorFrameMps2.x /
                  9.80665,
            ),
      ];
      final stride =
          math.max(1, (values.length / maximumPointsPerSensor).ceil());
      final plotted = [
        for (var index = 0; index < values.length; index += stride)
          values[index],
      ];
      final gyroMax = plotted.isEmpty
          ? 1.0
          : plotted.map((point) => point.gyro.abs()).reduce(math.max);
      final accMax = plotted.isEmpty
          ? 1.0
          : plotted.map((point) => point.acc.abs()).reduce(math.max);
      final center = rowTop + 105;
      double yGyro(double value) =>
          center - value / math.max(1e-9, gyroMax) * 78;
      double yAcc(double value) => center - value / math.max(1e-9, accMax) * 78;
      buffer
        ..writeln(
          '<text x="${left - 14}" y="${rowTop + 18}" text-anchor="end" '
          'font-family="sans-serif" font-size="13" font-weight="bold">$sensor'
          '</text>',
        )
        ..writeln(
          '<line x1="$left" y1="$center" x2="${width - right}" y2="$center" '
          'stroke="#ccc"/>',
        );
      for (final cycle
          in result.cycles.where((cycle) => cycle.sensorLabel == sensor)) {
        buffer.writeln(
          '<rect x="${x(cycle.startSeconds)}" y="${rowTop + 2}" '
          'width="${x(cycle.endSeconds) - x(cycle.startSeconds)}" '
          'height="196" fill="${cycle.plausible ? '#4c9a62' : '#c44e52'}" '
          'opacity="0.10"><title>${_xml(cycle.id)} · '
          '${cycle.durationSeconds.toStringAsFixed(3)} s · '
          'Q=${cycle.quality.toStringAsFixed(2)}</title></rect>',
        );
      }
      if (plotted.isNotEmpty) {
        buffer
          ..writeln(
            '<polyline fill="none" stroke="#3977b7" stroke-width="1.3" '
            'points="${plotted.map((point) => '${x(point.time)},${yGyro(point.gyro)}').join(' ')}"/>',
          )
          ..writeln(
            '<polyline fill="none" stroke="#e39b37" stroke-width="1.1" '
            'points="${plotted.map((point) => '${x(point.time)},${yAcc(point.acc)}').join(' ')}"/>',
          );
      }
      for (final event
          in result.events.where((event) => event.sensorLabel == sensor)) {
        final eventX = x(event.timeSeconds);
        final color =
            event.kind == GaitEventKind.touchdown ? '#2f6eb5' : '#c43d3d';
        buffer.writeln(
          '<line x1="$eventX" y1="${rowTop + 2}" x2="$eventX" '
          'y2="${rowTop + 198}" stroke="$color" stroke-width="1" '
          'stroke-dasharray="3 3"><title>${_xml(event.id)} · '
          '${event.timeSeconds.toStringAsFixed(3)} s · '
          '${event.kind.name} · Q=${event.quality.toStringAsFixed(2)}</title>'
          '</line>',
        );
      }
      buffer.writeln(
        '<text x="$left" y="${rowTop + 218}" font-family="sans-serif" '
        'font-size="10" fill="#555">AsY rad/s (blau) · AccX g (orange)</text>',
      );
    }
    for (var tick = 0; tick <= 10; tick++) {
      final time = start + duration * tick / 10;
      buffer.writeln(
        '<text x="${x(time)}" y="${height - 15}" text-anchor="middle" '
        'font-family="sans-serif" font-size="10">'
        '${time.toStringAsFixed(1)} s</text>',
      );
    }
    return '${buffer.toString()}</svg>';
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
