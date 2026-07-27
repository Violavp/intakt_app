import 'dart:convert';

import '../gait_segmentation/gait_segmentation_models.dart';

enum GaitEventKind { touchdown, liftoff }

enum GaitEventSource { automatic, userCorrection }

enum GaitCycleDetectionStatus { accepted, reviewRequired, notPossible }

class GaitCycleDetectionConfig {
  const GaitCycleDetectionConfig({
    this.smoothingSeconds = 0.05,
    this.minimumPhaseSeconds = 0.12,
    this.refinementSeconds = 0.10,
    this.walkMinimumCycleSeconds = 0.9,
    this.walkMaximumCycleSeconds = 1.6,
    this.trotMinimumCycleSeconds = 0.55,
    this.trotMaximumCycleSeconds = 1.1,
    this.minimumCoverage = 0.9,
    this.minimumCycleQuality = 0.55,
    this.manualMatchToleranceSeconds = 0.20,
    this.patternHalfWindowSeconds = 0.12,
    this.minimumPatternExamplesPerKind = 2,
    this.minimumPatternCorrelation = 0.45,
    this.sameEventSpacingFraction = 0.65,
    this.phaseSearchToleranceFraction = 0.45,
    this.uncalibratedQualityFactor = 0.65,
    this.requiredLegLabels = const ['VL', 'VR', 'HL', 'HR'],
  });

  final double smoothingSeconds;
  final double minimumPhaseSeconds;
  final double refinementSeconds;

  /// Recording-calibration bounds, not physiological reference ranges.
  final double walkMinimumCycleSeconds;
  final double walkMaximumCycleSeconds;
  final double trotMinimumCycleSeconds;
  final double trotMaximumCycleSeconds;
  final double minimumCoverage;
  final double minimumCycleQuality;
  final double manualMatchToleranceSeconds;
  final double patternHalfWindowSeconds;
  final int minimumPatternExamplesPerKind;
  final double minimumPatternCorrelation;
  final double sameEventSpacingFraction;
  final double phaseSearchToleranceFraction;
  final double uncalibratedQualityFactor;
  final List<String> requiredLegLabels;

  factory GaitCycleDetectionConfig.fromJsonString(String text) {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic>) {
      throw const FormatException(
        'Gangzykluskonfiguration muss ein JSON-Objekt sein.',
      );
    }
    double number(String key, double fallback) {
      final value = root[key] ?? fallback;
      if (value is! num) throw FormatException('"$key" muss eine Zahl sein.');
      return value.toDouble();
    }

    final labels = root['required_leg_labels'];
    if (labels != null &&
        (labels is! List || labels.any((value) => value is! String))) {
      throw const FormatException(
        '"required_leg_labels" muss eine Liste von Sensorkürzeln sein.',
      );
    }
    return GaitCycleDetectionConfig(
      smoothingSeconds: number('smoothing_seconds', 0.05),
      minimumPhaseSeconds: number('minimum_phase_seconds', 0.12),
      refinementSeconds: number('refinement_seconds', 0.10),
      walkMinimumCycleSeconds: number('walk_minimum_cycle_seconds', 0.9),
      walkMaximumCycleSeconds: number('walk_maximum_cycle_seconds', 1.6),
      trotMinimumCycleSeconds: number('trot_minimum_cycle_seconds', 0.55),
      trotMaximumCycleSeconds: number('trot_maximum_cycle_seconds', 1.1),
      minimumCoverage: number('minimum_coverage', 0.9),
      minimumCycleQuality: number('minimum_cycle_quality', 0.55),
      manualMatchToleranceSeconds:
          number('manual_match_tolerance_seconds', 0.20),
      patternHalfWindowSeconds: number('pattern_half_window_seconds', 0.12),
      minimumPatternExamplesPerKind:
          number('minimum_pattern_examples_per_kind', 2).toInt(),
      minimumPatternCorrelation: number('minimum_pattern_correlation', 0.45),
      sameEventSpacingFraction: number('same_event_spacing_fraction', 0.65),
      phaseSearchToleranceFraction:
          number('phase_search_tolerance_fraction', 0.45),
      uncalibratedQualityFactor: number('uncalibrated_quality_factor', 0.65),
      requiredLegLabels: labels == null
          ? const ['VL', 'VR', 'HL', 'HR']
          : labels.cast<String>(),
    );
  }

  Map<String, Object?> toJson() => {
        'signal_selection': {
          'event_pattern':
              'normalized signed canonical filtered gyro_y and acc_x window',
          'uncalibrated_fallback':
              'abs(canonical filtered device-axis gyro_y) hysteresis',
          'right_mounting_orientation_sign': -1,
          'left_mounting_orientation_sign': 1,
        },
        'smoothing_seconds': smoothingSeconds,
        'minimum_phase_seconds': minimumPhaseSeconds,
        'refinement_seconds': refinementSeconds,
        'walk_cycle_bounds_s': [
          walkMinimumCycleSeconds,
          walkMaximumCycleSeconds,
        ],
        'trot_cycle_bounds_s': [
          trotMinimumCycleSeconds,
          trotMaximumCycleSeconds,
        ],
        'minimum_coverage': minimumCoverage,
        'minimum_cycle_quality': minimumCycleQuality,
        'manual_match_tolerance_seconds': manualMatchToleranceSeconds,
        'pattern_half_window_seconds': patternHalfWindowSeconds,
        'minimum_pattern_examples_per_kind': minimumPatternExamplesPerKind,
        'minimum_pattern_correlation': minimumPatternCorrelation,
        'same_event_spacing_fraction': sameEventSpacingFraction,
        'phase_search_tolerance_fraction': phaseSearchToleranceFraction,
        'uncalibrated_quality_factor': uncalibratedQualityFactor,
        'required_leg_labels': requiredLegLabels,
        'threshold_interpretation':
            'recording calibration, not a medical reference range',
      };
}

class ManualGaitEventCorrection {
  const ManualGaitEventCorrection({
    required this.sensorLabel,
    required this.gait,
    required this.kind,
    required this.timeSeconds,
    required this.source,
    this.ridingDirection,
  });

  final String sensorLabel;
  final GaitLabel gait;
  final GaitEventKind kind;
  final double timeSeconds;
  final String source;
  final RidingDirection? ridingDirection;

  factory ManualGaitEventCorrection.fromJson(Map<String, dynamic> json) {
    final sensor = json['sensor'] ?? json['bein'];
    final time = json['time_s'] ?? json['zeit_s'];
    final gait = json['gait'];
    final event = json['event'] ?? json['ereignis'];
    final source = json['source'] ?? json['quelle'] ?? 'user_confirmation';
    final direction = json['direction'] ?? json['riding_direction'];
    if (sensor is! String ||
        time is! num ||
        gait is! String ||
        event is! String ||
        source is! String) {
      throw const FormatException(
        'Nutzerkorrektur benötigt sensor/bein, gait, event/ereignis und '
        'time_s/zeit_s.',
      );
    }
    if (direction != null &&
        direction != 'LEFT' &&
        direction != 'RIGHT' &&
        direction != 'UNKNOWN') {
      throw FormatException('Unbekannte Reitrichtung "$direction".');
    }
    return ManualGaitEventCorrection(
      sensorLabel: sensor,
      gait: gaitLabelFromJson(gait),
      kind: switch (event.toLowerCase()) {
        'auftreten' || 'touchdown' => GaitEventKind.touchdown,
        'abheben' || 'liftoff' => GaitEventKind.liftoff,
        _ => throw FormatException('Unbekanntes Ereignis "$event".'),
      },
      timeSeconds: time.toDouble(),
      source: source,
      ridingDirection: switch (direction) {
        'LEFT' => RidingDirection.left,
        'RIGHT' => RidingDirection.right,
        'UNKNOWN' => RidingDirection.unknown,
        _ => null,
      },
    );
  }

  Map<String, Object> toJson() => {
        'sensor': sensorLabel,
        'gait': gaitLabelToJson(gait),
        'event': kind.name,
        'time_s': timeSeconds,
        'source': source,
        if (ridingDirection != null)
          'direction': ridingDirection!.name.toUpperCase(),
      };
}

class DetectedGaitEvent {
  const DetectedGaitEvent({
    required this.id,
    required this.sensorLabel,
    required this.gait,
    required this.kind,
    required this.timeSeconds,
    required this.quality,
    required this.source,
    required this.canonicalGyroYRadPerSecond,
    required this.canonicalAccelerationXMps2,
    required this.sourceName,
    required this.sourceLine,
    required this.sourceUncertaintyMilliseconds,
    this.ridingDirection = RidingDirection.unknown,
    this.patternCalibration = 'UNCALIBRATED_DEFAULT',
    this.patternSupportCount = 0,
    this.patternAgreement,
  });

  final String id;
  final String sensorLabel;
  final GaitLabel gait;
  final GaitEventKind kind;
  final double timeSeconds;
  final double quality;
  final GaitEventSource source;
  final double canonicalGyroYRadPerSecond;
  final double canonicalAccelerationXMps2;
  final String sourceName;
  final int sourceLine;
  final double sourceUncertaintyMilliseconds;
  final RidingDirection ridingDirection;

  /// `USER_CONFIRMED`, `DIRECTION_PATTERN_CALIBRATED` or
  /// `UNCALIBRATED_DEFAULT`.
  final String patternCalibration;
  final int patternSupportCount;
  final double? patternAgreement;

  Map<String, Object?> toJson() => {
        'id': id,
        'sensor': sensorLabel,
        'gait': gaitLabelToJson(gait),
        'event': kind == GaitEventKind.touchdown ? 'TOUCHDOWN' : 'LIFTOFF',
        'time_s': timeSeconds,
        'video_time_s': timeSeconds,
        'quality': quality,
        'quality_definition':
            'technical transition contrast and sample completeness',
        'source': source.name,
        'canonical_gyro_y_radps': canonicalGyroYRadPerSecond,
        'canonical_acc_x_mps2': canonicalAccelerationXMps2,
        'raw_source': sourceName,
        'raw_source_line': sourceLine,
        'source_uncertainty_ms': sourceUncertaintyMilliseconds,
        'riding_direction': ridingDirection.name.toUpperCase(),
        'pattern_calibration': patternCalibration,
        'pattern_support_count': patternSupportCount,
        'pattern_agreement': patternAgreement,
      };
}

class GaitCycle {
  const GaitCycle({
    required this.id,
    required this.sensorLabel,
    required this.gait,
    required this.startEventId,
    required this.liftoffEventId,
    required this.endEventId,
    required this.startSeconds,
    required this.endSeconds,
    required this.liftoffSeconds,
    required this.durationUncertaintyMilliseconds,
    required this.stanceUncertaintyMilliseconds,
    required this.swingUncertaintyMilliseconds,
    required this.quality,
    required this.plausible,
    required this.exclusionReasons,
    required this.sampleCoverage,
    required this.durationDeviationFraction,
    required this.userConfirmed,
  });

  final String id;
  final String sensorLabel;
  final GaitLabel gait;
  final String startEventId;
  final String liftoffEventId;
  final String endEventId;
  final double startSeconds;
  final double endSeconds;
  final double liftoffSeconds;
  final double durationUncertaintyMilliseconds;
  final double stanceUncertaintyMilliseconds;
  final double swingUncertaintyMilliseconds;
  final double quality;
  final bool plausible;
  final List<String> exclusionReasons;
  final double sampleCoverage;
  final double durationDeviationFraction;
  final bool userConfirmed;

  double get durationSeconds => endSeconds - startSeconds;
  double get stanceSeconds => liftoffSeconds - startSeconds;
  double get swingSeconds => endSeconds - liftoffSeconds;

  Map<String, Object> toJson() => {
        'id': id,
        'sensor': sensorLabel,
        'gait': gaitLabelToJson(gait),
        'start_event_id': startEventId,
        'liftoff_event_id': liftoffEventId,
        'end_event_id': endEventId,
        'start_s': startSeconds,
        'end_s': endSeconds,
        'video_start_s': startSeconds,
        'video_end_s': endSeconds,
        'liftoff_s': liftoffSeconds,
        'duration_s': durationSeconds,
        'stance_s': stanceSeconds,
        'swing_s': swingSeconds,
        'duration_uncertainty_ms': durationUncertaintyMilliseconds,
        'stance_uncertainty_ms': stanceUncertaintyMilliseconds,
        'swing_uncertainty_ms': swingUncertaintyMilliseconds,
        'quality': quality,
        'uncertainty': 1 - quality,
        'plausible': plausible,
        'exclusion_reasons': exclusionReasons,
        'sample_coverage': sampleCoverage,
        'duration_deviation_fraction': durationDeviationFraction,
        'user_confirmed': userConfirmed,
      };
}

class CycleDetectionIssue {
  const CycleDetectionIssue({
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

class GaitCycleDetectionResult {
  const GaitCycleDetectionResult({
    required this.status,
    required this.events,
    required this.cycles,
    required this.issues,
    required this.config,
    required this.assumptions,
  });

  final GaitCycleDetectionStatus status;
  final List<DetectedGaitEvent> events;
  final List<GaitCycle> cycles;
  final List<CycleDetectionIssue> issues;
  final GaitCycleDetectionConfig config;
  final List<String> assumptions;

  List<GaitCycle> get plausibleCycles =>
      cycles.where((cycle) => cycle.plausible).toList();

  Map<String, Object> toJson() => {
        'status': switch (status) {
          GaitCycleDetectionStatus.accepted => 'CYCLE_DETECTION_ACCEPTED',
          GaitCycleDetectionStatus.reviewRequired =>
            'CYCLE_DETECTION_REVIEW_REQUIRED',
          GaitCycleDetectionStatus.notPossible =>
            'CYCLE_DETECTION_NOT_POSSIBLE',
        },
        'time_unit': 's',
        'events': events.map((event) => event.toJson()).toList(),
        'cycles': cycles.map((cycle) => cycle.toJson()).toList(),
        'plausible_cycle_count': plausibleCycles.length,
        'config': config.toJson(),
        'assumptions': assumptions,
        'issues': issues.map((issue) => issue.toJson()).toList(),
      };
}
