import 'dart:convert';

import '../imu_import/imu_models.dart';
import '../imu_sync/index_time_reconstruction.dart';

enum PreprocessingStatus { accepted, reviewRequired, notPossible }

class ImuPreprocessingConfig {
  const ImuPreprocessingConfig({
    this.lowPassCutoffHz = 20,
    this.gravityCutoffHz = 0.5,
    this.butterworthOrder = 4,
    this.hampelHalfWindowSamples = 3,
    this.hampelThresholdMad = 4,
    this.maximumOutlierRunSamples = 1,
    this.minimumAccelerationMadMps2 = 0.02,
    this.minimumAngularVelocityMadRadPerSecond = 0.002,
    this.minimumSegmentSamples = 20,
    this.orientationWindowSeconds = 2,
    this.orientationMaximumGyroRmsRadPerSecond = 0.15,
    this.orientationMaximumGravityDeviationMps2 = 1.5,
    this.standardGravityMps2 = 9.80665,
    this.comparisonMovingAverageWindowSamples = 5,
    this.minimumEventPeakRetention = 0.75,
  });

  final double lowPassCutoffHz;
  final double gravityCutoffHz;

  /// Only order four is currently implemented as two documented biquads.
  final int butterworthOrder;
  final int hampelHalfWindowSamples;
  final double hampelThresholdMad;

  /// Longer candidate runs are retained because they may be real events.
  final int maximumOutlierRunSamples;
  final double minimumAccelerationMadMps2;
  final double minimumAngularVelocityMadRadPerSecond;
  final int minimumSegmentSamples;
  final double orientationWindowSeconds;
  final double orientationMaximumGyroRmsRadPerSecond;
  final double orientationMaximumGravityDeviationMps2;
  final double standardGravityMps2;
  final int comparisonMovingAverageWindowSamples;

  /// Technical event-preservation check, not a physiological threshold.
  final double minimumEventPeakRetention;

  factory ImuPreprocessingConfig.fromJsonString(String text) {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic>) {
      throw const FormatException(
        'Vorverarbeitungskonfiguration muss ein JSON-Objekt sein.',
      );
    }
    num number(String key, num fallback) {
      final value = root[key] ?? fallback;
      if (value is! num) {
        throw FormatException('"$key" muss eine Zahl sein.');
      }
      return value;
    }

    return ImuPreprocessingConfig(
      lowPassCutoffHz: number('low_pass_cutoff_hz', 20).toDouble(),
      gravityCutoffHz: number('gravity_cutoff_hz', 0.5).toDouble(),
      butterworthOrder: number('butterworth_order', 4).toInt(),
      hampelHalfWindowSamples: number('hampel_half_window_samples', 3).toInt(),
      hampelThresholdMad: number('hampel_threshold_mad', 4).toDouble(),
      maximumOutlierRunSamples:
          number('maximum_outlier_run_samples', 1).toInt(),
      minimumAccelerationMadMps2:
          number('minimum_acceleration_mad_mps2', 0.02).toDouble(),
      minimumAngularVelocityMadRadPerSecond:
          number('minimum_angular_velocity_mad_radps', 0.002).toDouble(),
      minimumSegmentSamples: number('minimum_segment_samples', 20).toInt(),
      orientationWindowSeconds:
          number('orientation_window_seconds', 2).toDouble(),
      orientationMaximumGyroRmsRadPerSecond:
          number('orientation_maximum_gyro_rms_radps', 0.15).toDouble(),
      orientationMaximumGravityDeviationMps2:
          number('orientation_maximum_gravity_deviation_mps2', 1.5).toDouble(),
      standardGravityMps2: number('standard_gravity_mps2', 9.80665).toDouble(),
      comparisonMovingAverageWindowSamples:
          number('comparison_moving_average_window_samples', 5).toInt(),
      minimumEventPeakRetention:
          number('minimum_event_peak_retention', 0.75).toDouble(),
    );
  }

  Map<String, Object> toJson() => {
        'low_pass': {
          'type': 'zero_phase_butterworth',
          'order_per_direction': butterworthOrder,
          'cutoff_hz': lowPassCutoffHz,
        },
        'gravity_low_pass': {
          'type': 'zero_phase_butterworth',
          'order_per_direction': butterworthOrder,
          'cutoff_hz': gravityCutoffHz,
        },
        'outliers': {
          'method': 'hampel_isolated_spikes',
          'half_window_samples': hampelHalfWindowSamples,
          'threshold_mad': hampelThresholdMad,
          'maximum_replaced_run_samples': maximumOutlierRunSamples,
          'minimum_acceleration_mad_mps2': minimumAccelerationMadMps2,
          'minimum_angular_velocity_mad_radps':
              minimumAngularVelocityMadRadPerSecond,
        },
        'minimum_segment_samples': minimumSegmentSamples,
        'orientation': {
          'method': 'stationary_gravity_roll_pitch_alignment',
          'window_seconds': orientationWindowSeconds,
          'maximum_gyro_rms_radps': orientationMaximumGyroRmsRadPerSecond,
          'maximum_gravity_deviation_mps2':
              orientationMaximumGravityDeviationMps2,
          'standard_gravity_mps2': standardGravityMps2,
          'yaw': 'unresolved',
        },
        'comparison_moving_average_window_samples':
            comparisonMovingAverageWindowSamples,
        'minimum_event_peak_retention': minimumEventPeakRetention,
      };
}

class PreprocessingIssue {
  const PreprocessingIssue({
    required this.code,
    required this.observation,
    required this.uncertainty,
    required this.recommendation,
    this.sensorLabel,
  });

  final String code;
  final String observation;
  final String uncertainty;
  final String recommendation;
  final String? sensorLabel;

  Map<String, Object?> toJson() => {
        'code': code,
        if (sensorLabel != null) 'sensor': sensorLabel,
        'observation': observation,
        'uncertainty': uncertainty,
        'recommendation': recommendation,
      };
}

class OrientationEstimate {
  const OrientationEstimate({
    required this.valid,
    required this.windowStartSeconds,
    required this.windowEndSeconds,
    required this.gravitySensorFrameMps2,
    required this.gravityMagnitudeMps2,
    required this.gyroRmsRadPerSecond,
    required this.gravityResidualMps2,
    required this.rotationSensorToGravityFrame,
    required this.invalidReason,
  });

  final bool valid;
  final double? windowStartSeconds;
  final double? windowEndSeconds;
  final Vector3? gravitySensorFrameMps2;
  final double? gravityMagnitudeMps2;
  final double? gyroRmsRadPerSecond;
  final double? gravityResidualMps2;

  /// Row-major rotation. It aligns measured gravity with +Z. Yaw is unchanged.
  final List<double>? rotationSensorToGravityFrame;
  final String? invalidReason;

  Map<String, Object?> toJson() => {
        'valid': valid,
        'window_start_s': windowStartSeconds,
        'window_end_s': windowEndSeconds,
        'gravity_sensor_frame_mps2': gravitySensorFrameMps2?.toJson(),
        'gravity_magnitude_mps2': gravityMagnitudeMps2,
        'gyro_rms_radps': gyroRmsRadPerSecond,
        'gravity_residual_mps2': gravityResidualMps2,
        'rotation_sensor_to_gravity_frame': rotationSensorToGravityFrame,
        'resolved_axes': ['vertical'],
        'unresolved_axes': ['anatomical_forward', 'anatomical_lateral'],
        if (invalidReason != null) 'invalid_reason': invalidReason,
      };
}

class FilterMethodMetrics {
  const FilterMethodMetrics({
    required this.method,
    required this.roughnessRmsMps2,
    required this.peakToPeakRetention,
    required this.strongestEventTimeShiftMilliseconds,
  });

  final String method;
  final double roughnessRmsMps2;
  final double peakToPeakRetention;
  final double strongestEventTimeShiftMilliseconds;

  Map<String, Object> toJson() => {
        'method': method,
        'roughness_rms_mps2': roughnessRmsMps2,
        'peak_to_peak_retention': peakToPeakRetention,
        'strongest_event_time_shift_ms': strongestEventTimeShiftMilliseconds,
      };
}

class SensorPreprocessingQuality {
  const SensorPreprocessingQuality({
    required this.sensorLabel,
    required this.inputSamples,
    required this.outputSamples,
    required this.gapSamples,
    required this.replacedOutlierSamples,
    required this.retainedCandidateOutlierSamples,
    required this.orientation,
    required this.filterComparisons,
    required this.qualityScore,
    required this.uncertainty,
  });

  final String sensorLabel;
  final int inputSamples;
  final int outputSamples;
  final int gapSamples;
  final int replacedOutlierSamples;
  final int retainedCandidateOutlierSamples;
  final OrientationEstimate orientation;
  final List<FilterMethodMetrics> filterComparisons;

  /// Technical completeness score in [0, 1], not a clinical score.
  final double qualityScore;
  final String uncertainty;

  Map<String, Object> toJson() => {
        'sensor': sensorLabel,
        'input_samples': inputSamples,
        'output_samples': outputSamples,
        'gap_samples': gapSamples,
        'replaced_outlier_samples': replacedOutlierSamples,
        'retained_candidate_outlier_samples': retainedCandidateOutlierSamples,
        'orientation': orientation.toJson(),
        'filter_comparison':
            filterComparisons.map((metrics) => metrics.toJson()).toList(),
        'quality_score': qualityScore,
        'quality_score_definition':
            'output coverage multiplied by orientation confidence; '
                'technical only',
        'uncertainty': uncertainty,
      };
}

class PreprocessedImuValue {
  const PreprocessedImuValue({
    required this.raw,
    required this.cleanedAccelerationMps2,
    required this.cleanedAngularVelocityRadPerSecond,
    required this.filteredAccelerationSensorFrameMps2,
    required this.filteredAngularVelocitySensorFrameRadPerSecond,
    required this.alignedAccelerationMps2,
    required this.alignedAngularVelocityRadPerSecond,
    required this.gravityMps2,
    required this.movementAccelerationMps2,
    required this.alignedMagneticFieldMicrotesla,
    required this.outlierReplaced,
    required this.processingTemporalResolutionMilliseconds,
  });

  /// Immutable reconstructed value with raw-source line traceability.
  final ResampledImuValue raw;
  final Vector3 cleanedAccelerationMps2;
  final Vector3 cleanedAngularVelocityRadPerSecond;
  final Vector3 filteredAccelerationSensorFrameMps2;
  final Vector3 filteredAngularVelocitySensorFrameRadPerSecond;
  final Vector3 alignedAccelerationMps2;
  final Vector3 alignedAngularVelocityRadPerSecond;
  final Vector3 gravityMps2;
  final Vector3 movementAccelerationMps2;
  final Vector3? alignedMagneticFieldMicrotesla;
  final bool outlierReplaced;

  /// Approximate half-period at the selected cutoff, not timestamp error.
  final double processingTemporalResolutionMilliseconds;
}

class PreprocessedFrame {
  const PreprocessedFrame({
    required this.analysisTimeSeconds,
    required this.values,
  });

  final double analysisTimeSeconds;
  final Map<String, PreprocessedImuValue?> values;
}

class ImuPreprocessingResult {
  const ImuPreprocessingResult({
    required this.status,
    required this.gridSamplingRateHz,
    required this.frames,
    required this.sensorQuality,
    required this.issues,
    required this.config,
    required this.assumptions,
  });

  final PreprocessingStatus status;
  final double gridSamplingRateHz;
  final List<PreprocessedFrame> frames;
  final Map<String, SensorPreprocessingQuality> sensorQuality;
  final List<PreprocessingIssue> issues;
  final ImuPreprocessingConfig config;
  final List<String> assumptions;

  bool get hasDataset =>
      status != PreprocessingStatus.notPossible && frames.isNotEmpty;

  Map<String, Object> toJson() => {
        'status': switch (status) {
          PreprocessingStatus.accepted => 'PREPROCESSING_ACCEPTED',
          PreprocessingStatus.reviewRequired => 'PREPROCESSING_REVIEW_REQUIRED',
          PreprocessingStatus.notPossible => 'PREPROCESSING_NOT_POSSIBLE',
        },
        'grid_sampling_rate_hz': gridSamplingRateHz,
        'frame_count': frames.length,
        'config': config.toJson(),
        'assumptions': assumptions,
        'sensors':
            sensorQuality.values.map((quality) => quality.toJson()).toList(),
        'issues': issues.map((issue) => issue.toJson()).toList(),
      };
}
