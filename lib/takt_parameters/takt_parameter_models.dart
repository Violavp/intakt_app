import 'dart:convert';

import '../gait_segmentation/gait_segmentation.dart';

enum TaktParameterStatus { accepted, reviewRequired, notPossible }

enum TaktChangeAssessment {
  improved,
  worsened,
  stableWithinUncertainty,
  changedWithoutValence,
  comparisonUnavailable,
}

class TaktParameterConfig {
  const TaktParameterConfig({
    this.minimumWindowSeconds = 10,
    this.maximumWindowSeconds = 20,
    this.stepSeconds = 1,
    this.minimumValidCyclesPerLeg = 6,
    this.confidenceIntervalMultiplier = 1.96,
    this.requiredLegLabels = const ['VL', 'VR', 'HL', 'HR'],
  });

  final double minimumWindowSeconds;
  final double maximumWindowSeconds;
  final double stepSeconds;
  final int minimumValidCyclesPerLeg;
  final double confidenceIntervalMultiplier;
  final List<String> requiredLegLabels;

  factory TaktParameterConfig.fromJsonString(String text) {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic>) {
      throw const FormatException(
        'Taktparameterkonfiguration muss ein JSON-Objekt sein.',
      );
    }

    double number(String key, double fallback) {
      final value = root[key] ?? fallback;
      if (value is! num) throw FormatException('"$key" muss eine Zahl sein.');
      return value.toDouble();
    }

    int integer(String key, int fallback) {
      final value = root[key] ?? fallback;
      if (value is! int) {
        throw FormatException('"$key" muss eine ganze Zahl sein.');
      }
      return value;
    }

    final labels = root['required_leg_labels'];
    if (labels != null &&
        (labels is! List || labels.any((value) => value is! String))) {
      throw const FormatException(
        '"required_leg_labels" muss eine Liste von Sensorkürzeln sein.',
      );
    }
    return TaktParameterConfig(
      minimumWindowSeconds: number('minimum_window_seconds', 10),
      maximumWindowSeconds: number('maximum_window_seconds', 20),
      stepSeconds: number('step_seconds', 1),
      minimumValidCyclesPerLeg: integer('minimum_valid_cycles_per_leg', 6),
      confidenceIntervalMultiplier:
          number('confidence_interval_multiplier', 1.96),
      requiredLegLabels: labels == null
          ? const ['VL', 'VR', 'HL', 'HR']
          : labels.cast<String>(),
    );
  }

  Map<String, Object> toJson() => {
        'minimum_window_seconds': minimumWindowSeconds,
        'maximum_window_seconds': maximumWindowSeconds,
        'step_seconds': stepSeconds,
        'window_selection':
            'shortest window containing the required cycles on all legs',
        'comparison_windows_overlap': false,
        'minimum_valid_cycles_per_leg': minimumValidCyclesPerLeg,
        'confidence_interval_multiplier': confidenceIntervalMultiplier,
        'required_leg_labels': requiredLegLabels,
        'interpretation':
            'technical prototype settings; not physiological thresholds',
      };
}

class TaktMetric {
  const TaktMetric.valid({
    required this.value,
    required this.unit,
    required this.standardUncertainty,
    required this.confidenceIntervalLower,
    required this.confidenceIntervalUpper,
  })  : valid = true,
        invalidReason = null;

  const TaktMetric.invalid({
    required this.unit,
    required this.invalidReason,
  })  : valid = false,
        value = null,
        standardUncertainty = null,
        confidenceIntervalLower = null,
        confidenceIntervalUpper = null;

  final bool valid;
  final double? value;
  final String unit;
  final double? standardUncertainty;
  final double? confidenceIntervalLower;
  final double? confidenceIntervalUpper;
  final String? invalidReason;

  Map<String, Object?> toJson() => {
        'valid': valid,
        'value': value,
        'unit': unit,
        'standard_uncertainty': standardUncertainty,
        'confidence_interval_95':
            valid ? [confidenceIntervalLower, confidenceIntervalUpper] : null,
        'invalid_reason': invalidReason,
      };
}

class LegTaktSummary {
  const LegTaktSummary({
    required this.sensorLabel,
    required this.validCycleCount,
    required this.cycleIds,
    required this.meanCycleDuration,
    required this.cycleDurationStandardDeviation,
    required this.cycleDurationCoefficientOfVariation,
    required this.cycleFrequency,
  });

  final String sensorLabel;
  final int validCycleCount;
  final List<String> cycleIds;
  final TaktMetric meanCycleDuration;
  final TaktMetric cycleDurationStandardDeviation;
  final TaktMetric cycleDurationCoefficientOfVariation;
  final TaktMetric cycleFrequency;

  Map<String, Object> toJson() => {
        'sensor': sensorLabel,
        'valid_cycle_count': validCycleCount,
        'cycle_ids': cycleIds,
        'mean_cycle_duration': meanCycleDuration.toJson(),
        'cycle_duration_standard_deviation':
            cycleDurationStandardDeviation.toJson(),
        'cycle_duration_coefficient_of_variation':
            cycleDurationCoefficientOfVariation.toJson(),
        'cycle_frequency': cycleFrequency.toJson(),
      };
}

class TaktPhaseRelation {
  const TaktPhaseRelation({
    required this.referenceSensor,
    required this.targetSensor,
    required this.sampleCount,
    required this.meanPhase,
    required this.circularStandardDeviation,
    required this.expectedPhase,
    required this.absoluteExpectedPhaseDeviation,
    required this.sourceCycleIds,
  });

  final String referenceSensor;
  final String targetSensor;
  final int sampleCount;
  final TaktMetric meanPhase;
  final TaktMetric circularStandardDeviation;
  final double? expectedPhase;
  final TaktMetric absoluteExpectedPhaseDeviation;
  final List<String> sourceCycleIds;

  Map<String, Object?> toJson() => {
        'reference_sensor': referenceSensor,
        'target_sensor': targetSensor,
        'sample_count': sampleCount,
        'mean_phase': meanPhase.toJson(),
        'circular_standard_deviation': circularStandardDeviation.toJson(),
        'expected_phase': expectedPhase,
        'absolute_expected_phase_deviation':
            absoluteExpectedPhaseDeviation.toJson(),
        'source_cycle_ids': sourceCycleIds,
      };
}

class TaktMetricComparison {
  const TaktMetricComparison({
    required this.component,
    required this.assessment,
    required this.currentValue,
    required this.comparisonValue,
    required this.delta,
    required this.combinedStandardUncertainty,
    required this.comparisonWindowId,
  });

  final String component;
  final TaktChangeAssessment assessment;
  final double? currentValue;
  final double? comparisonValue;
  final double? delta;
  final double? combinedStandardUncertainty;
  final String? comparisonWindowId;

  Map<String, Object?> toJson() => {
        'component': component,
        'assessment': switch (assessment) {
          TaktChangeAssessment.improved => 'IMPROVED',
          TaktChangeAssessment.worsened => 'WORSENED',
          TaktChangeAssessment.stableWithinUncertainty =>
            'STABLE_WITHIN_UNCERTAINTY',
          TaktChangeAssessment.changedWithoutValence =>
            'CHANGED_WITHOUT_VALENCE',
          TaktChangeAssessment.comparisonUnavailable =>
            'COMPARISON_UNAVAILABLE',
        },
        'current_value': currentValue,
        'comparison_value': comparisonValue,
        'delta': delta,
        'combined_standard_uncertainty': combinedStandardUncertainty,
        'comparison_window_id': comparisonWindowId,
      };
}

class TaktAnalysisWindow {
  const TaktAnalysisWindow({
    required this.id,
    required this.startSeconds,
    required this.endSeconds,
    required this.gait,
    required this.ridingDirection,
    required this.valid,
    required this.invalidReasons,
    required this.legSummaries,
    required this.meanCycleDuration,
    required this.cycleFrequency,
    required this.cycleDurationVariability,
    required this.cycleDurationDrift,
    required this.phaseRelations,
    required this.phaseDispersion,
    required this.temporalSymmetryDeviation,
    required this.comparisons,
    required this.explanatoryObservations,
  });

  final String id;
  final double startSeconds;
  final double endSeconds;
  final GaitLabel gait;
  final RidingDirection ridingDirection;
  final bool valid;
  final List<String> invalidReasons;
  final Map<String, LegTaktSummary> legSummaries;
  final TaktMetric meanCycleDuration;
  final TaktMetric cycleFrequency;
  final TaktMetric cycleDurationVariability;
  final TaktMetric cycleDurationDrift;
  final List<TaktPhaseRelation> phaseRelations;
  final TaktMetric phaseDispersion;
  final TaktMetric temporalSymmetryDeviation;
  final List<TaktMetricComparison> comparisons;
  final List<String> explanatoryObservations;

  double get durationSeconds => endSeconds - startSeconds;

  TaktAnalysisWindow withComparison({
    required List<TaktMetricComparison> comparisons,
    required List<String> explanatoryObservations,
  }) =>
      TaktAnalysisWindow(
        id: id,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        gait: gait,
        ridingDirection: ridingDirection,
        valid: valid,
        invalidReasons: invalidReasons,
        legSummaries: legSummaries,
        meanCycleDuration: meanCycleDuration,
        cycleFrequency: cycleFrequency,
        cycleDurationVariability: cycleDurationVariability,
        cycleDurationDrift: cycleDurationDrift,
        phaseRelations: phaseRelations,
        phaseDispersion: phaseDispersion,
        temporalSymmetryDeviation: temporalSymmetryDeviation,
        comparisons: comparisons,
        explanatoryObservations: explanatoryObservations,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'start_s': startSeconds,
        'end_s': endSeconds,
        'video_start_s': startSeconds,
        'video_end_s': endSeconds,
        'duration_s': durationSeconds,
        'gait': gaitLabelToJson(gait),
        'riding_direction': ridingDirection.name.toUpperCase(),
        'valid': valid,
        'invalid_reasons': invalidReasons,
        'leg_summaries':
            legSummaries.map((key, value) => MapEntry(key, value.toJson())),
        'mean_cycle_duration': meanCycleDuration.toJson(),
        'cycle_frequency': cycleFrequency.toJson(),
        'cycle_duration_variability': cycleDurationVariability.toJson(),
        'cycle_duration_drift': cycleDurationDrift.toJson(),
        'phase_relations':
            phaseRelations.map((relation) => relation.toJson()).toList(),
        'phase_dispersion': phaseDispersion.toJson(),
        'temporal_symmetry_deviation': temporalSymmetryDeviation.toJson(),
        'comparisons':
            comparisons.map((comparison) => comparison.toJson()).toList(),
        'explanatory_observations': explanatoryObservations,
        'interpretation_limit':
            'descriptive temporal observations; no riding or medical score',
      };
}

class TaktParameterIssue {
  const TaktParameterIssue({
    required this.code,
    required this.observation,
    required this.uncertainty,
    required this.recommendation,
  });

  final String code;
  final String observation;
  final String uncertainty;
  final String recommendation;

  Map<String, Object> toJson() => {
        'code': code,
        'observation': observation,
        'uncertainty': uncertainty,
        'recommendation': recommendation,
      };
}

class TaktParameterResult {
  const TaktParameterResult({
    required this.status,
    required this.windows,
    required this.issues,
    required this.config,
    required this.assumptions,
  });

  final TaktParameterStatus status;
  final List<TaktAnalysisWindow> windows;
  final List<TaktParameterIssue> issues;
  final TaktParameterConfig config;
  final List<String> assumptions;

  List<TaktAnalysisWindow> get validWindows =>
      windows.where((window) => window.valid).toList();

  Map<String, Object> toJson() => {
        'status': switch (status) {
          TaktParameterStatus.accepted => 'TAKT_PARAMETERS_ACCEPTED',
          TaktParameterStatus.reviewRequired =>
            'TAKT_PARAMETERS_REVIEW_REQUIRED',
          TaktParameterStatus.notPossible => 'TAKT_PARAMETERS_NOT_POSSIBLE',
        },
        'time_unit': 's',
        'frequency_unit': 'Hz',
        'phase_unit': 'cycle_fraction',
        'variability_unit': 'percent',
        'config': config.toJson(),
        'assumptions': assumptions,
        'windows': windows.map((window) => window.toJson()).toList(),
        'valid_window_count': validWindows.length,
        'issues': issues.map((issue) => issue.toJson()).toList(),
      };
}
