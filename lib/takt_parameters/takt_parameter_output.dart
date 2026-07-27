import 'dart:convert';
import 'dart:math' as math;

import 'takt_parameter_models.dart';

String taktParameterReportJson(TaktParameterResult result) =>
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': 1,
      'takt_parameters': result.toJson(),
    });

class TaktWindowCsv {
  const TaktWindowCsv();

  String render(TaktParameterResult result) {
    final output = StringBuffer(
      'window_id,start_s,end_s,gait,riding_direction,valid,invalid_reasons,'
      'mean_cycle_duration_s,mean_cycle_duration_uncertainty_s,'
      'cycle_frequency_hz,cycle_frequency_uncertainty_hz,'
      'cycle_duration_cv_percent,cycle_duration_cv_uncertainty_percent,'
      'cycle_duration_drift_s_per_s,cycle_duration_drift_uncertainty_s_per_s,'
      'phase_dispersion_cycle_fraction,'
      'phase_dispersion_uncertainty_cycle_fraction,'
      'temporal_symmetry_deviation_percent_cycle,'
      'temporal_symmetry_uncertainty_percent_cycle,'
      'VL_cycles,VR_cycles,HL_cycles,HR_cycles,'
      'comparison_observations\n',
    );
    for (final window in result.windows) {
      output.writeln([
        window.id,
        window.startSeconds,
        window.endSeconds,
        window.gait.name.toUpperCase(),
        window.ridingDirection.name.toUpperCase(),
        window.valid,
        window.invalidReasons.join('|'),
        window.meanCycleDuration.value,
        window.meanCycleDuration.standardUncertainty,
        window.cycleFrequency.value,
        window.cycleFrequency.standardUncertainty,
        window.cycleDurationVariability.value,
        window.cycleDurationVariability.standardUncertainty,
        window.cycleDurationDrift.value,
        window.cycleDurationDrift.standardUncertainty,
        window.phaseDispersion.value,
        window.phaseDispersion.standardUncertainty,
        window.temporalSymmetryDeviation.value,
        window.temporalSymmetryDeviation.standardUncertainty,
        window.legSummaries['VL']?.validCycleCount,
        window.legSummaries['VR']?.validCycleCount,
        window.legSummaries['HL']?.validCycleCount,
        window.legSummaries['HR']?.validCycleCount,
        window.explanatoryObservations.join('|'),
      ].map(_csv).join(','));
    }
    return output.toString();
  }
}

class TaktTrendSvg {
  const TaktTrendSvg();

  String render(TaktParameterResult result) {
    const width = 1400.0;
    const height = 720.0;
    const left = 90.0;
    const right = 45.0;
    const top = 65.0;
    const rowHeight = 145.0;
    final windows = result.windows;
    if (windows.isEmpty) {
      return '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
          'height="$height"><text x="20" y="30">Keine Taktfenster</text></svg>';
    }
    final start = windows.first.startSeconds;
    final end = windows.last.endSeconds;
    final duration = math.max(1e-9, end - start);
    double x(double time) =>
        left + (time - start) / duration * (width - left - right);
    final rows = <_PlotRow>[
      _PlotRow(
        label: 'Zyklusvariabilität',
        unit: '%',
        value: (window) => window.cycleDurationVariability.value,
        uncertainty: (window) =>
            window.cycleDurationVariability.standardUncertainty,
      ),
      _PlotRow(
        label: 'Tempoänderung |Steigung|',
        unit: 's/s',
        value: (window) => window.cycleDurationDrift.value?.abs(),
        uncertainty: (window) => window.cycleDurationDrift.standardUncertainty,
      ),
      _PlotRow(
        label: 'Phasenstreuung',
        unit: '% Zyklus',
        value: (window) => window.phaseDispersion.value == null
            ? null
            : window.phaseDispersion.value! * 100,
        uncertainty: (window) =>
            window.phaseDispersion.standardUncertainty == null
                ? null
                : window.phaseDispersion.standardUncertainty! * 100,
      ),
      _PlotRow(
        label: 'zeitliche Symmetrieabweichung',
        unit: '% Zyklus',
        value: (window) => window.temporalSymmetryDeviation.value,
        uncertainty: (window) =>
            window.temporalSymmetryDeviation.standardUncertainty,
      ),
    ];
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
        'height="$height" viewBox="0 0 $width $height">',
      )
      ..writeln('<rect width="100%" height="100%" fill="white"/>')
      ..writeln(
        '<text x="$left" y="28" font-family="sans-serif" font-size="18" '
        'font-weight="bold">Zeitlicher Taktverlauf – adaptive '
        '10–20-s-Fenster</text>',
      )
      ..writeln(
        '<text x="$left" y="48" font-family="sans-serif" font-size="11" '
        'fill="#555">Kleinere Werte bedeuten nur höhere zeitliche Stabilität; '
        'keine Takt-, Reit- oder Medizinwertung.</text>',
      );
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final rowTop = top + rowIndex * rowHeight;
      final values = [
        for (final window in windows)
          if (window.valid && row.value(window) != null)
            (
              time: window.endSeconds,
              value: row.value(window)!,
              uncertainty: row.uncertainty(window) ?? 0,
            ),
      ];
      final maximum = values.isEmpty
          ? 1.0
          : values
              .map((point) => point.value + 1.96 * point.uncertainty)
              .fold(0.0, math.max);
      double y(double value) =>
          rowTop + 105 - value / math.max(1e-9, maximum) * 90;
      buffer
        ..writeln(
          '<text x="${left - 12}" y="${rowTop + 16}" text-anchor="end" '
          'font-family="sans-serif" font-size="12">${_xml(row.label)}</text>',
        )
        ..writeln(
          '<text x="${left - 12}" y="${rowTop + 31}" text-anchor="end" '
          'font-family="sans-serif" font-size="10" fill="#666">'
          '${_xml(row.unit)}</text>',
        )
        ..writeln(
          '<line x1="$left" y1="${rowTop + 105}" x2="${width - right}" '
          'y2="${rowTop + 105}" stroke="#ccc"/>',
        );
      if (values.isNotEmpty) {
        buffer.writeln(
          '<polyline fill="none" stroke="#326f8f" stroke-width="2" '
          'points="${values.map((point) => '${x(point.time)},${y(point.value)}').join(' ')}"/>',
        );
        for (final point in values) {
          buffer
            ..writeln(
              '<line x1="${x(point.time)}" '
              'y1="${y(point.value + 1.96 * point.uncertainty)}" '
              'x2="${x(point.time)}" '
              'y2="${y(math.max(0, point.value - 1.96 * point.uncertainty))}" '
              'stroke="#326f8f" opacity="0.35"/>',
            )
            ..writeln(
              '<circle cx="${x(point.time)}" cy="${y(point.value)}" r="2.3" '
              'fill="#326f8f"><title>${point.time.toStringAsFixed(1)} s · '
              '${point.value.toStringAsFixed(4)} ${_xml(row.unit)}</title>'
              '</circle>',
            );
        }
      }
    }
    for (var tick = 0; tick <= 10; tick++) {
      final time = start + duration * tick / 10;
      buffer.writeln(
        '<text x="${x(time)}" y="${height - 18}" text-anchor="middle" '
        'font-family="sans-serif" font-size="10">'
        '${time.toStringAsFixed(1)} s</text>',
      );
    }
    return '${buffer.toString()}</svg>';
  }
}

class _PlotRow {
  const _PlotRow({
    required this.label,
    required this.unit,
    required this.value,
    required this.uncertainty,
  });

  final String label;
  final String unit;
  final double? Function(TaktAnalysisWindow) value;
  final double? Function(TaktAnalysisWindow) uncertainty;
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
