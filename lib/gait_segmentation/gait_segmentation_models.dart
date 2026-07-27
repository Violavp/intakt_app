import 'dart:convert';

enum GaitLabel { standing, walk, trot, gallop, unknown }

enum SegmentationStatus { accepted, reviewRequired, notPossible }

enum GaitClusteringFeature { diagonalSynchrony, frequency }

enum RidingDirection { left, right, unknown }

class GaitSegmentationConfig {
  const GaitSegmentationConfig({
    this.windowSeconds = 4,
    this.stepSeconds = 0.5,
    this.minimumWindowCoverage = 0.9,
    this.movementOnRmsMps2 = 0.45,
    this.movementOffRmsMps2 = 0.30,
    this.minimumFrequencyHz = 0.5,
    this.maximumFrequencyHz = 4.5,
    this.frequencyResolutionHz = 0.05,
    this.minimumSpectralConfidence = 0.35,
    this.minimumClusterWindows = 6,
    this.minimumClusterSeparation = 0.4,
    this.gaitClusteringFeature = GaitClusteringFeature.frequency,
    this.enabledMovementGaits = const [GaitLabel.walk, GaitLabel.trot],
    this.minimumMovementBoutSeconds = 3,
    this.gaitOrderResetStandingSeconds = 5,
    this.minimumGaitAdvanceWindows = 6,
    this.enforceConfiguredGaitOrder = true,
    this.minimumDirectionSlopeDegreesPerSecond = 2,
    this.directionTrendWindowSeconds = 12,
    this.minimumDirectionAgreementSensors = 4,
    this.directionChangeConfirmationWindows = 2,
    this.positiveAngleZDirection = RidingDirection.left,
    this.maximumInterruptionSeconds = 2,
    this.minimumAnalyzableSeconds = 3,
    this.minimumAnalyzableConfidence = 0.55,
    this.minimumStableWindows = 2,
    this.requiredLegLabels = const ['VL', 'VR', 'HL', 'HR'],
  });

  final double windowSeconds;
  final double stepSeconds;
  final double minimumWindowCoverage;
  final double movementOnRmsMps2;
  final double movementOffRmsMps2;
  final double minimumFrequencyHz;
  final double maximumFrequencyHz;
  final double frequencyResolutionHz;
  final double minimumSpectralConfidence;
  final int minimumClusterWindows;
  final double minimumClusterSeparation;
  final GaitClusteringFeature gaitClusteringFeature;
  final List<GaitLabel> enabledMovementGaits;
  final double minimumMovementBoutSeconds;
  final double gaitOrderResetStandingSeconds;
  final int minimumGaitAdvanceWindows;
  final bool enforceConfiguredGaitOrder;
  final double minimumDirectionSlopeDegreesPerSecond;
  final double directionTrendWindowSeconds;
  final int minimumDirectionAgreementSensors;
  final int directionChangeConfirmationWindows;
  final RidingDirection positiveAngleZDirection;
  final double maximumInterruptionSeconds;
  final double minimumAnalyzableSeconds;
  final double minimumAnalyzableConfidence;
  final int minimumStableWindows;
  final List<String> requiredLegLabels;

  factory GaitSegmentationConfig.fromJsonString(String text) {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic>) {
      throw const FormatException(
        'Segmentierungskonfiguration muss ein JSON-Objekt sein.',
      );
    }
    num number(String key, num fallback) {
      final value = root[key] ?? fallback;
      if (value is! num) {
        throw FormatException('"$key" muss eine Zahl sein.');
      }
      return value;
    }

    bool boolean(String key, bool fallback) {
      final value = root[key] ?? fallback;
      if (value is! bool) {
        throw FormatException('"$key" muss boolesch sein.');
      }
      return value;
    }

    final labels = root['required_leg_labels'];
    if (labels != null &&
        (labels is! List ||
            labels.length != 4 ||
            labels.any((value) => value is! String))) {
      throw const FormatException(
        '"required_leg_labels" muss vier Sensorkürzel enthalten.',
      );
    }
    final gaitValues = root['enabled_movement_gaits'];
    if (gaitValues != null && gaitValues is! List) {
      throw const FormatException(
        '"enabled_movement_gaits" muss eine Liste sein.',
      );
    }
    final enabledGaits = gaitValues == null
        ? const [GaitLabel.walk, GaitLabel.trot]
        : [
            for (final value in gaitValues) gaitLabelFromJson(value),
          ];
    final featureValue = root['gait_clustering_feature'] ?? 'frequency';
    if (featureValue is! String) {
      throw const FormatException(
        '"gait_clustering_feature" muss eine Zeichenkette sein.',
      );
    }
    final clusteringFeature = switch (featureValue) {
      'diagonal_synchrony' => GaitClusteringFeature.diagonalSynchrony,
      'frequency' => GaitClusteringFeature.frequency,
      _ => throw FormatException(
          'Unbekanntes gait_clustering_feature "$featureValue".',
        ),
    };
    final positiveDirectionValue = root['positive_angle_z_direction'] ?? 'LEFT';
    if (positiveDirectionValue is! String) {
      throw const FormatException(
        '"positive_angle_z_direction" muss LEFT oder RIGHT sein.',
      );
    }
    final positiveDirection = switch (positiveDirectionValue.toUpperCase()) {
      'LEFT' => RidingDirection.left,
      'RIGHT' => RidingDirection.right,
      _ => throw const FormatException(
          '"positive_angle_z_direction" muss LEFT oder RIGHT sein.',
        ),
    };
    return GaitSegmentationConfig(
      windowSeconds: number('window_seconds', 4).toDouble(),
      stepSeconds: number('step_seconds', 0.5).toDouble(),
      minimumWindowCoverage: number('minimum_window_coverage', 0.9).toDouble(),
      movementOnRmsMps2: number('movement_on_rms_mps2', 0.45).toDouble(),
      movementOffRmsMps2: number('movement_off_rms_mps2', 0.30).toDouble(),
      minimumFrequencyHz: number('minimum_frequency_hz', 0.5).toDouble(),
      maximumFrequencyHz: number('maximum_frequency_hz', 4.5).toDouble(),
      frequencyResolutionHz: number('frequency_resolution_hz', 0.05).toDouble(),
      minimumSpectralConfidence:
          number('minimum_spectral_confidence', 0.35).toDouble(),
      minimumClusterWindows: number('minimum_cluster_windows', 6).toInt(),
      minimumClusterSeparation:
          number('minimum_cluster_separation', 0.4).toDouble(),
      gaitClusteringFeature: clusteringFeature,
      enabledMovementGaits: enabledGaits,
      minimumMovementBoutSeconds:
          number('minimum_movement_bout_seconds', 3).toDouble(),
      gaitOrderResetStandingSeconds:
          number('gait_order_reset_standing_seconds', 5).toDouble(),
      minimumGaitAdvanceWindows:
          number('minimum_gait_advance_windows', 6).toInt(),
      enforceConfiguredGaitOrder:
          boolean('enforce_configured_gait_order', true),
      minimumDirectionSlopeDegreesPerSecond:
          number('minimum_direction_slope_degps', 2).toDouble(),
      directionTrendWindowSeconds:
          number('direction_trend_window_seconds', 12).toDouble(),
      minimumDirectionAgreementSensors:
          number('minimum_direction_agreement_sensors', 4).toInt(),
      directionChangeConfirmationWindows:
          number('direction_change_confirmation_windows', 2).toInt(),
      positiveAngleZDirection: positiveDirection,
      maximumInterruptionSeconds:
          number('maximum_interruption_seconds', 2).toDouble(),
      minimumAnalyzableSeconds:
          number('minimum_analyzable_seconds', 3).toDouble(),
      minimumAnalyzableConfidence:
          number('minimum_analyzable_confidence', 0.55).toDouble(),
      minimumStableWindows: number('minimum_stable_windows', 2).toInt(),
      requiredLegLabels: labels == null
          ? const ['VL', 'VR', 'HL', 'HR']
          : labels.cast<String>(),
    );
  }

  Map<String, Object> toJson() => {
        'window_seconds': windowSeconds,
        'step_seconds': stepSeconds,
        'minimum_window_coverage': minimumWindowCoverage,
        'movement_on_rms_mps2': movementOnRmsMps2,
        'movement_off_rms_mps2': movementOffRmsMps2,
        'minimum_frequency_hz': minimumFrequencyHz,
        'maximum_frequency_hz': maximumFrequencyHz,
        'frequency_resolution_hz': frequencyResolutionHz,
        'minimum_spectral_confidence': minimumSpectralConfidence,
        'minimum_cluster_windows': minimumClusterWindows,
        'minimum_cluster_separation': minimumClusterSeparation,
        'gait_clustering_feature': switch (gaitClusteringFeature) {
          GaitClusteringFeature.diagonalSynchrony => 'diagonal_synchrony',
          GaitClusteringFeature.frequency => 'frequency',
        },
        'enabled_movement_gaits':
            enabledMovementGaits.map(gaitLabelToJson).toList(),
        'minimum_movement_bout_seconds': minimumMovementBoutSeconds,
        'gait_order_reset_standing_seconds': gaitOrderResetStandingSeconds,
        'minimum_gait_advance_windows': minimumGaitAdvanceWindows,
        'enforce_configured_gait_order': enforceConfiguredGaitOrder,
        'minimum_direction_slope_degps': minimumDirectionSlopeDegreesPerSecond,
        'direction_trend_window_seconds': directionTrendWindowSeconds,
        'minimum_direction_agreement_sensors': minimumDirectionAgreementSensors,
        'direction_change_confirmation_windows':
            directionChangeConfirmationWindows,
        'positive_angle_z_direction':
            positiveAngleZDirection.name.toUpperCase(),
        'maximum_interruption_seconds': maximumInterruptionSeconds,
        'minimum_analyzable_seconds': minimumAnalyzableSeconds,
        'minimum_analyzable_confidence': minimumAnalyzableConfidence,
        'minimum_stable_windows': minimumStableWindows,
        'required_leg_labels': requiredLegLabels,
      };
}

class ManualSegmentCorrection {
  const ManualSegmentCorrection({
    required this.startSeconds,
    required this.endSeconds,
    required this.reason,
    this.gait,
    this.excludeFromAnalysis,
    this.transition,
    this.turn,
    this.interruption,
  });

  final double startSeconds;
  final double endSeconds;
  final String reason;
  final GaitLabel? gait;
  final bool? excludeFromAnalysis;
  final bool? transition;
  final bool? turn;
  final bool? interruption;

  factory ManualSegmentCorrection.fromJson(Map<String, dynamic> json) {
    final start = json['start_s'];
    final end = json['end_s'];
    final reason = json['reason'];
    if (start is! num || end is! num || reason is! String || reason.isEmpty) {
      throw const FormatException(
        'Korrektur benötigt start_s, end_s und eine Begründung.',
      );
    }
    final gaitText = json['gait'];
    return ManualSegmentCorrection(
      startSeconds: start.toDouble(),
      endSeconds: end.toDouble(),
      reason: reason,
      gait: gaitText == null ? null : gaitLabelFromJson(gaitText),
      excludeFromAnalysis: _optionalBool(json, 'exclude_from_analysis'),
      transition: _optionalBool(json, 'transition'),
      turn: _optionalBool(json, 'turn'),
      interruption: _optionalBool(json, 'interruption'),
    );
  }

  Map<String, Object?> toJson() => {
        'start_s': startSeconds,
        'end_s': endSeconds,
        if (gait != null) 'gait': gaitLabelToJson(gait!),
        if (excludeFromAnalysis != null)
          'exclude_from_analysis': excludeFromAnalysis,
        if (transition != null) 'transition': transition,
        if (turn != null) 'turn': turn,
        if (interruption != null) 'interruption': interruption,
        'reason': reason,
      };
}

class SegmentationIssue {
  const SegmentationIssue({
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

class SourceLineRange {
  const SourceLineRange(this.first, this.last);

  final int first;
  final int last;

  Map<String, int> toJson() => {'first': first, 'last': last};
}

class GaitSignalCluster {
  const GaitSignalCluster({
    required this.gait,
    required this.feature,
    required this.centroid,
    required this.windowCount,
  });

  final GaitLabel gait;
  final GaitClusteringFeature feature;
  final double centroid;
  final int windowCount;

  Map<String, Object> toJson() => {
        'gait': gaitLabelToJson(gait),
        'feature': switch (feature) {
          GaitClusteringFeature.diagonalSynchrony => 'diagonal_synchrony',
          GaitClusteringFeature.frequency => 'frequency',
        },
        'centroid': centroid,
        'unit': switch (feature) {
          GaitClusteringFeature.diagonalSynchrony => 'correlation',
          GaitClusteringFeature.frequency => 'Hz',
        },
        'window_count': windowCount,
      };
}

class GaitSegment {
  const GaitSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.gait,
    required this.confidence,
    required this.uncertainty,
    required this.dominantFrequencyHz,
    required this.diagonalSynchrony,
    required this.movementRmsMps2,
    required this.coverage,
    required this.transition,
    required this.turn,
    required this.interruption,
    required this.analyzable,
    required this.manuallyCorrected,
    required this.correctionReasons,
    required this.sourceLines,
    this.ridingDirection = RidingDirection.unknown,
    this.frontAngleZTrendDegreesPerSecond,
    this.hindAngleZTrendDegreesPerSecond,
    this.meanAngleZTrendDegreesPerSecond,
    this.directionConfidence,
  });

  final double startSeconds;
  final double endSeconds;
  final GaitLabel gait;

  /// Technical classifier confidence in [0, 1], not a clinical probability.
  final double confidence;

  /// Complement of confidence in [0, 1].
  final double uncertainty;
  final double? dominantFrequencyHz;
  final double? diagonalSynchrony;
  final double movementRmsMps2;
  final double coverage;
  final bool transition;
  final bool turn;
  final bool interruption;
  final bool analyzable;
  final bool manuallyCorrected;
  final List<String> correctionReasons;
  final Map<String, SourceLineRange> sourceLines;
  final RidingDirection ridingDirection;
  final double? frontAngleZTrendDegreesPerSecond;
  final double? hindAngleZTrendDegreesPerSecond;
  final double? meanAngleZTrendDegreesPerSecond;

  /// Fraction of required leg sensors supporting the reported trend sign.
  final double? directionConfidence;

  double get durationSeconds => endSeconds - startSeconds;

  Map<String, Object?> toJson() => {
        'start_s': startSeconds,
        'end_s': endSeconds,
        'video_start_s': startSeconds,
        'video_end_s': endSeconds,
        'duration_s': durationSeconds,
        'gait': gaitLabelToJson(gait),
        'confidence': confidence,
        'uncertainty': uncertainty,
        'uncertainty_definition': '1 - technical classifier confidence',
        'dominant_leg_frequency_hz': dominantFrequencyHz,
        'diagonal_synchrony': diagonalSynchrony,
        'movement_rms_mps2': movementRmsMps2,
        'coverage': coverage,
        'transition': transition,
        'turn_candidate': turn,
        'riding_direction': ridingDirection.name.toUpperCase(),
        'direction_valid': ridingDirection != RidingDirection.unknown &&
            meanAngleZTrendDegreesPerSecond != null,
        if (ridingDirection == RidingDirection.unknown ||
            meanAngleZTrendDegreesPerSecond == null)
          'direction_invalid_reason':
              'four_leg_angle_z_consensus_not_reached_or_signal_missing',
        'front_angle_z_trend_degps': frontAngleZTrendDegreesPerSecond,
        'hind_angle_z_trend_degps': hindAngleZTrendDegreesPerSecond,
        'mean_angle_z_trend_degps': meanAngleZTrendDegreesPerSecond,
        'line_bending_rate_degps': meanAngleZTrendDegreesPerSecond,
        'direction_confidence': directionConfidence,
        'direction_interpretation':
            'recording-calibrated line direction and signed bending rate; '
                'not gait classification or geometric curvature',
        'interruption': interruption,
        'analyzable': analyzable,
        'manually_corrected': manuallyCorrected,
        'correction_reasons': correctionReasons,
        'source_lines': sourceLines.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };
}

class GaitSegmentationResult {
  const GaitSegmentationResult({
    required this.status,
    required this.segments,
    required this.issues,
    required this.config,
    required this.corrections,
    required this.gaitSignalClusters,
    required this.assumptions,
  });

  final SegmentationStatus status;
  final List<GaitSegment> segments;
  final List<SegmentationIssue> issues;
  final GaitSegmentationConfig config;
  final List<ManualSegmentCorrection> corrections;
  final List<GaitSignalCluster> gaitSignalClusters;
  final List<String> assumptions;

  bool get hasSegments =>
      status != SegmentationStatus.notPossible && segments.isNotEmpty;

  List<GaitSegment> get analyzableSegments =>
      segments.where((segment) => segment.analyzable).toList();

  Map<String, Object> toJson() => {
        'status': switch (status) {
          SegmentationStatus.accepted => 'SEGMENTATION_ACCEPTED',
          SegmentationStatus.reviewRequired => 'SEGMENTATION_REVIEW_REQUIRED',
          SegmentationStatus.notPossible => 'SEGMENTATION_NOT_POSSIBLE',
        },
        'time_unit': 's',
        'frequency_unit': 'Hz',
        'acceleration_unit': 'm/s²',
        'orientation_angle_unit': 'degree',
        'angle_z_trend_unit': 'degree/s',
        'config': config.toJson(),
        'assumptions': assumptions,
        'manual_corrections':
            corrections.map((correction) => correction.toJson()).toList(),
        'gait_signal_clusters':
            gaitSignalClusters.map((cluster) => cluster.toJson()).toList(),
        'segments': segments.map((segment) => segment.toJson()).toList(),
        'analyzable_segment_count': analyzableSegments.length,
        'issues': issues.map((issue) => issue.toJson()).toList(),
      };
}

String gaitLabelToJson(GaitLabel gait) => switch (gait) {
      GaitLabel.standing => 'STANDING',
      GaitLabel.walk => 'WALK',
      GaitLabel.trot => 'TROT',
      GaitLabel.gallop => 'GALLOP',
      GaitLabel.unknown => 'UNKNOWN',
    };

GaitLabel gaitLabelFromJson(Object? value) {
  if (value is! String) {
    throw const FormatException('"gait" muss eine Zeichenkette sein.');
  }
  return switch (value.toUpperCase()) {
    'STANDING' => GaitLabel.standing,
    'WALK' => GaitLabel.walk,
    'TROT' => GaitLabel.trot,
    'GALLOP' => GaitLabel.gallop,
    'UNKNOWN' => GaitLabel.unknown,
    _ => throw FormatException('Unbekannte Gangart "$value".'),
  };
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! bool) {
    throw FormatException('"$key" muss boolesch sein.');
  }
  return value as bool?;
}
