import '../gait_cycles/gait_cycles.dart';
import '../gait_segmentation/gait_segmentation.dart';
import '../takt_parameters/takt_parameters.dart';

/// Bridges the existing temporal Takt analysis into a rider-facing tile.
///
/// No physiological cut-offs are introduced here. The presentation exposes
/// descriptive metrics, upstream quality and within-recording comparisons only.
class TaktMetricEvaluator {
  const TaktMetricEvaluator({
    this.analyzer = const TaktParameterAnalyzer(),
  });

  final TaktParameterAnalyzer analyzer;

  TaktTilePresentation evaluate(
    GaitCycleDetectionResult cycleDetection,
    GaitSegmentationResult segmentation,
  ) =>
      TaktTilePresentation.fromResult(
        analyzer.analyze(cycleDetection, segmentation),
      );
}

class TaktTilePresentation {
  const TaktTilePresentation({
    required this.resultLabel,
    required this.details,
    required this.evidenceText,
    required this.validWindowCount,
    required this.totalWindowCount,
    required this.requiresReview,
  });

  final String resultLabel;
  final List<String> details;
  final String evidenceText;
  final int validWindowCount;
  final int totalWindowCount;
  final bool requiresReview;

  factory TaktTilePresentation.empty() => const TaktTilePresentation(
        resultLabel: 'Noch keine Auswertung',
        details: [],
        evidenceText:
            'Sobald eine Rittanalyse ein TaktParameterResult liefert, werden '
            'hier die gemessenen Taktmerkmale und die Datenqualität angezeigt.',
        validWindowCount: 0,
        totalWindowCount: 0,
        requiresReview: false,
      );

  factory TaktTilePresentation.fromResult(TaktParameterResult? result) {
    if (result == null) return TaktTilePresentation.empty();

    final valid = result.validWindows;
    final total = result.windows.length;
    if (valid.isEmpty || result.status == TaktParameterStatus.notPossible) {
      final issue = result.issues.isEmpty ? null : result.issues.first;
      return TaktTilePresentation(
        resultLabel: 'Nicht auswertbar',
        details: [
          'Gültige Analysefenster: 0/$total',
          if (issue != null) 'Grund: ${issue.observation}',
          if (issue != null) 'Nächster Prüfschritt: ${issue.recommendation}',
        ],
        evidenceText: issue == null
            ? 'Der Taktanalyzer konnte aus diesem Ergebnis kein gültiges '
                'Analysefenster bilden.'
            : 'Der Taktanalyzer konnte kein gültiges Fenster bilden. '
                '${issue.uncertainty}',
        validWindowCount: 0,
        totalWindowCount: total,
        requiresReview: true,
      );
    }

    final details = <String>[
      'Gültige Analysefenster: ${valid.length}/$total',
      ..._gaitDetails(valid, GaitLabel.walk, 'Schritt'),
      ..._gaitDetails(valid, GaitLabel.trot, 'Trab'),
    ];

    final comparisonSummary = _comparisonSummary(valid);
    if (comparisonSummary != null) {
      details.add(comparisonSummary);
    }

    final reviewRequired =
        result.status == TaktParameterStatus.reviewRequired ||
            result.issues.isNotEmpty;
    final qualityText = reviewRequired
        ? 'Die zeitlichen Messwerte sind berechnet, der Analyzer markiert '
            'aber ${result.issues.length} Prüfhinweis(e).'
        : 'Die zeitlichen Messwerte erfüllen die technischen '
            'Berechnungsbedingungen des Taktanalyzers.';

    final firstIssue = result.issues.isEmpty ? null : result.issues.first;
    return TaktTilePresentation(
      resultLabel: reviewRequired
          ? '${valid.length} Fenster · Prüfung nötig'
          : '${valid.length} gültige Fenster',
      details: [
        ...details,
        if (firstIssue != null) 'Prüfhinweis: ${firstIssue.observation}',
      ],
      evidenceText:
          '$qualityText Mindestens ${result.config.minimumValidCyclesPerLeg} '
          'gültige Zyklen je Bein werden pro Fenster verlangt.'
          '${firstIssue == null ? '' : ' ${firstIssue.uncertainty}'}',
      validWindowCount: valid.length,
      totalWindowCount: total,
      requiresReview: reviewRequired,
    );
  }

  static List<String> _gaitDetails(
    List<TaktAnalysisWindow> windows,
    GaitLabel gait,
    String label,
  ) {
    final gaitWindows = windows.where((window) => window.gait == gait).toList();
    if (gaitWindows.isEmpty) return const [];

    final variability = _median(
      gaitWindows
          .map((window) => window.cycleDurationVariability)
          .where((metric) => metric.valid)
          .map((metric) => metric.value!)
          .toList(),
    );
    final phaseDispersion = _median(
      gaitWindows
          .map((window) => window.phaseDispersion)
          .where((metric) => metric.valid)
          .map((metric) => metric.value! * 100)
          .toList(),
    );
    final symmetry = _median(
      gaitWindows
          .map((window) => window.temporalSymmetryDeviation)
          .where((metric) => metric.valid)
          .map((metric) => metric.value!)
          .toList(),
    );

    return [
      '$label: ${gaitWindows.length} gültige Fenster',
      if (variability != null)
        '$label · Zyklusvariabilität (Median): ${_format(variability)} %',
      if (phaseDispersion != null)
        '$label · Phasenstreuung (Median): '
            '${_format(phaseDispersion)} % des Zyklus',
      if (symmetry != null)
        '$label · zeitliche Symmetrieabweichung (Median): '
            '${_format(symmetry)} % des Zyklus',
    ];
  }

  static String? _comparisonSummary(List<TaktAnalysisWindow> windows) {
    final comparisons = windows.expand((window) => window.comparisons).toList();
    if (comparisons.isEmpty) return null;

    var improved = 0;
    var worsened = 0;
    var stable = 0;
    for (final comparison in comparisons) {
      switch (comparison.assessment) {
        case TaktChangeAssessment.improved:
          improved++;
          break;
        case TaktChangeAssessment.worsened:
          worsened++;
          break;
        case TaktChangeAssessment.stableWithinUncertainty:
          stable++;
          break;
        case TaktChangeAssessment.changedWithoutValence:
        case TaktChangeAssessment.comparisonUnavailable:
          break;
      }
    }
    if (improved + worsened + stable == 0) return null;
    return 'Vergleichbare Fenster: $improved verbessert, $worsened '
        'verschlechtert, $stable innerhalb der Messunsicherheit stabil';
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    values.sort();
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }

  static String _format(double value) {
    final rounded = value.toStringAsFixed(1);
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }
}
