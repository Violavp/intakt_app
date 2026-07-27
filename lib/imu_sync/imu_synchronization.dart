import 'dart:math' as math;

import '../imu_import/imu_models.dart';

enum SynchronizationStatus {
  accepted,
  reviewRequired,
  notSynchronized,
}

class ImuSynchronizationConfig {
  const ImuSynchronizationConfig({
    this.targetSamplingRateHz = 100,
    this.referenceSensorLabel,
    this.maximumLag = const Duration(milliseconds: 250),
    this.lagStep = const Duration(milliseconds: 2),
    this.correlationWindow = const Duration(seconds: 2),
    this.correlationWindowStep = const Duration(seconds: 1),
    this.minimumSamplesPerSensor = 20,
    this.minimumCorrelationSamples = 20,
    this.minimumWindowCorrelation = 0.5,
    this.maximumLagResidual = const Duration(milliseconds: 12),
    this.minimumCoverage = 0.95,
    this.maximumInterpolationGapFactor = 3,
  });

  /// Common output grid. Unit: Hz.
  final double targetSamplingRateHz;

  /// Defaults to the first configured required sensor.
  final String? referenceSensorLabel;

  /// Symmetric search range around timestamp alignment.
  final Duration maximumLag;
  final Duration lagStep;
  final Duration correlationWindow;
  final Duration correlationWindowStep;
  final int minimumSamplesPerSensor;
  final int minimumCorrelationSamples;

  /// Technical acceptance threshold in [-1, 1], not a physiological range.
  final double minimumWindowCorrelation;

  /// Technical residual threshold after affine offset/drift fitting.
  final Duration maximumLagResidual;
  final double minimumCoverage;

  /// Interpolation never bridges a source interval larger than this factor
  /// times the sensor's median sampling interval.
  final double maximumInterpolationGapFactor;
}

class SynchronizationIssue {
  const SynchronizationIssue({
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

class LagEstimate {
  const LagEstimate({
    required this.windowCenterSeconds,
    required this.lagMilliseconds,
    required this.correlation,
    required this.pairedSamples,
  });

  /// Seconds from the common model origin.
  final double windowCenterSeconds;
  final double lagMilliseconds;
  final double correlation;
  final int pairedSamples;

  Map<String, Object> toJson() => {
        'window_center_s': windowCenterSeconds,
        'lag_ms': lagMilliseconds,
        'correlation': correlation,
        'paired_samples': pairedSamples,
      };
}

class SensorSynchronizationQuality {
  const SensorSynchronizationQuality({
    required this.sensorLabel,
    required this.valid,
    required this.rawStartOffsetMilliseconds,
    required this.estimatedSignalOffsetMilliseconds,
    required this.estimatedDriftPpm,
    required this.lagResidualRmseMilliseconds,
    required this.maximumAbsoluteLagResidualMilliseconds,
    required this.meanWindowCorrelation,
    required this.sourceSamplingRateHz,
    required this.outputCoverage,
    required this.uncertaintyMilliseconds,
    required this.lagEstimates,
    required this.invalidReason,
  });

  final String sensorLabel;
  final bool valid;

  /// Raw first-timestamp difference relative to the reference. Unit: ms.
  final double rawStartOffsetMilliseconds;

  /// Intercept of lag(t) = offset + drift * t. Unit: ms.
  final double? estimatedSignalOffsetMilliseconds;

  /// Slope of the affine lag model. Unit: microseconds per second (ppm).
  final double? estimatedDriftPpm;
  final double? lagResidualRmseMilliseconds;
  final double? maximumAbsoluteLagResidualMilliseconds;
  final double? meanWindowCorrelation;
  final double? sourceSamplingRateHz;
  final double outputCoverage;

  /// Combined lag-fit, lag-grid and half-output-period uncertainty. Unit: ms.
  final double? uncertaintyMilliseconds;
  final List<LagEstimate> lagEstimates;
  final String? invalidReason;

  Map<String, Object?> toJson() => {
        'sensor': sensorLabel,
        'valid': valid,
        'raw_start_offset_ms': rawStartOffsetMilliseconds,
        'estimated_signal_offset_ms': estimatedSignalOffsetMilliseconds,
        'estimated_drift_ppm': estimatedDriftPpm,
        'lag_residual_rmse_ms': lagResidualRmseMilliseconds,
        'maximum_absolute_lag_residual_ms':
            maximumAbsoluteLagResidualMilliseconds,
        'mean_window_correlation': meanWindowCorrelation,
        'source_sampling_rate_hz': sourceSamplingRateHz,
        'output_coverage': outputCoverage,
        'uncertainty_ms': uncertaintyMilliseconds,
        'lag_estimates':
            lagEstimates.map((estimate) => estimate.toJson()).toList(),
        if (invalidReason != null) 'invalid_reason': invalidReason,
      };
}

class SynchronizedImuValue {
  const SynchronizedImuValue({
    required this.accelerationMps2,
    required this.angularVelocityRadPerSecond,
    required this.magneticFieldMicrotesla,
    required this.lowerSourceName,
    required this.lowerSourceLine,
    required this.upperSourceName,
    required this.upperSourceLine,
    this.orientationAnglesDegrees,
  });

  final Vector3 accelerationMps2;
  final Vector3 angularVelocityRadPerSecond;
  final Vector3? magneticFieldMicrotesla;
  final Vector3? orientationAnglesDegrees;

  /// Traceability for the two raw rows used by linear interpolation.
  final String lowerSourceName;
  final int lowerSourceLine;
  final String upperSourceName;
  final int upperSourceLine;
}

class SynchronizedFrame {
  const SynchronizedFrame({
    required this.timestamp,
    required this.elapsedSeconds,
    required this.values,
  });

  final DateTime timestamp;
  final double elapsedSeconds;

  /// Every frame has the same sensor keys. A null value marks a gap that was
  /// deliberately not interpolated.
  final Map<String, SynchronizedImuValue?> values;
}

class ImuSynchronizationResult {
  const ImuSynchronizationResult({
    required this.status,
    required this.referenceSensorLabel,
    required this.gridSamplingRateHz,
    required this.gridPeriodMicroseconds,
    required this.commonStart,
    required this.commonEnd,
    required this.frames,
    required this.sensorQuality,
    required this.issues,
    required this.assumptions,
  });

  final SynchronizationStatus status;
  final String referenceSensorLabel;
  final double gridSamplingRateHz;
  final int gridPeriodMicroseconds;
  final DateTime? commonStart;
  final DateTime? commonEnd;
  final List<SynchronizedFrame> frames;
  final Map<String, SensorSynchronizationQuality> sensorQuality;
  final List<SynchronizationIssue> issues;
  final List<String> assumptions;

  bool get hasSynchronizedDataset =>
      status != SynchronizationStatus.notSynchronized && frames.isNotEmpty;

  Map<String, Object?> toJson() => {
        'status': switch (status) {
          SynchronizationStatus.accepted => 'SYNCHRONIZATION_ACCEPTED',
          SynchronizationStatus.reviewRequired =>
            'SYNCHRONIZATION_REVIEW_REQUIRED',
          SynchronizationStatus.notSynchronized =>
            'SYNCHRONIZATION_NOT_POSSIBLE',
        },
        'reference_sensor': referenceSensorLabel,
        'time_basis': 'UTC microseconds since Unix epoch',
        'grid_sampling_rate_hz': gridSamplingRateHz,
        'grid_period_us': gridPeriodMicroseconds,
        'common_start': commonStart?.toIso8601String(),
        'common_end': commonEnd?.toIso8601String(),
        'frame_count': frames.length,
        'assumptions': assumptions,
        'sensors':
            sensorQuality.values.map((quality) => quality.toJson()).toList(),
        'issues': issues.map((issue) => issue.toJson()).toList(),
      };
}

/// Signal-based affine synchronization of one IMU recording set.
///
/// Acceleration magnitudes are cross-correlated in moving windows. Per-sensor
/// lags are fitted as `lag(t) = offset + drift * t`, then all channels are
/// linearly interpolated onto one UTC grid. Raw samples remain unchanged.
class ImuSynchronizer {
  const ImuSynchronizer({
    this.config = const ImuSynchronizationConfig(),
  });

  final ImuSynchronizationConfig config;

  ImuSynchronizationResult synchronize(ImuImportResult input) {
    _validateConfig();
    final requiredLabels =
        input.catalog.requiredSensors.map((sensor) => sensor.label).toList();
    final referenceLabel = config.referenceSensorLabel ??
        (requiredLabels.isEmpty ? '' : requiredLabels.first);
    final issues = <SynchronizationIssue>[];

    if (referenceLabel.isEmpty || !requiredLabels.contains(referenceLabel)) {
      return _failed(
        referenceLabel,
        issues,
        'invalid_reference_sensor',
        'Der Referenzsensor "$referenceLabel" ist kein konfigurierter '
            'Pflichtsensor.',
      );
    }
    for (final label in requiredLabels) {
      if (!input.recordings.containsKey(label)) {
        issues.add(
          SynchronizationIssue(
            code: 'missing_required_sensor',
            sensorLabel: label,
            observation: 'Pflichtsensor $label fehlt.',
            uncertainty: 'Eine gemeinsame Vier-Sensor-Zeitbasis ist unmöglich.',
            recommendation: 'Dateiauswahl und Sensorzuordnung prüfen.',
          ),
        );
      }
    }
    if (issues.isNotEmpty) {
      return _failedResult(referenceLabel, issues);
    }

    final recordings = <String, SensorRecording>{
      for (final label in requiredLabels) label: input.recordings[label]!,
    };
    for (final entry in recordings.entries) {
      final reason = _invalidRecordingReason(entry.value);
      if (reason != null) {
        issues.add(
          SynchronizationIssue(
            code: 'invalid_sensor_time_series',
            sensorLabel: entry.key,
            observation: reason,
            uncertainty:
                'Offset und Drift können damit nicht belastbar geschätzt werden.',
            recommendation:
                'Zeitstempel und Pflichtwerte im unveränderten Export prüfen.',
          ),
        );
      }
    }
    if (issues.isNotEmpty) {
      return _failedResult(referenceLabel, issues);
    }

    final reference = recordings[referenceLabel]!;
    final originMicros =
        reference.samples.first.timestamp.microsecondsSinceEpoch;
    final rawOverlapStart = recordings.values
        .map((recording) =>
            recording.samples.first.timestamp.microsecondsSinceEpoch)
        .reduce(math.max);
    final rawOverlapEnd = recordings.values
        .map((recording) =>
            recording.samples.last.timestamp.microsecondsSinceEpoch)
        .reduce(math.min);
    final windowMicros = config.correlationWindow.inMicroseconds;
    if (rawOverlapEnd - rawOverlapStart < windowMicros) {
      return _failed(
        referenceLabel,
        issues,
        'insufficient_overlap',
        'Die gemeinsame Rohzeit-Überlappung ist kürzer als das '
            '${config.correlationWindow.inMilliseconds} ms lange '
            'Korrelationsfenster.',
      );
    }

    final models = <String, _ClockModel>{};
    final qualities = <String, SensorSynchronizationQuality>{};
    final referenceRate = _samplingRate(reference);
    models[referenceLabel] = const _ClockModel(offsetSeconds: 0, drift: 0);
    qualities[referenceLabel] = SensorSynchronizationQuality(
      sensorLabel: referenceLabel,
      valid: true,
      rawStartOffsetMilliseconds: 0,
      estimatedSignalOffsetMilliseconds: 0,
      estimatedDriftPpm: 0,
      lagResidualRmseMilliseconds: 0,
      maximumAbsoluteLagResidualMilliseconds: 0,
      meanWindowCorrelation: 1,
      sourceSamplingRateHz: referenceRate,
      outputCoverage: 1,
      uncertaintyMilliseconds: 0,
      lagEstimates: const [],
      invalidReason: null,
    );

    for (final entry in recordings.entries) {
      if (entry.key == referenceLabel) continue;
      final estimates = _estimateWindowLags(
        reference,
        entry.value,
        originMicros,
        rawOverlapStart,
        rawOverlapEnd,
      );
      if (estimates.length < 2) {
        final reason = 'Weniger als zwei Korrelationsfenster überschreiten die '
            'Mindestkorrelation ${config.minimumWindowCorrelation}.';
        qualities[entry.key] = SensorSynchronizationQuality(
          sensorLabel: entry.key,
          valid: false,
          rawStartOffsetMilliseconds: _startOffsetMs(entry.value, reference),
          estimatedSignalOffsetMilliseconds: null,
          estimatedDriftPpm: null,
          lagResidualRmseMilliseconds: null,
          maximumAbsoluteLagResidualMilliseconds: null,
          meanWindowCorrelation: estimates.isEmpty
              ? null
              : estimates
                      .map((estimate) => estimate.correlation)
                      .reduce((a, b) => a + b) /
                  estimates.length,
          sourceSamplingRateHz: _samplingRate(entry.value),
          outputCoverage: 0,
          uncertaintyMilliseconds: null,
          lagEstimates: estimates,
          invalidReason: reason,
        );
        issues.add(
          SynchronizationIssue(
            code: 'insufficient_signal_alignment',
            sensorLabel: entry.key,
            observation: reason,
            uncertainty:
                'Das Beschleunigungssignal ist möglicherweise zu konstant, '
                'zu kurz oder nicht eindeutig.',
            recommendation:
                'Gemeinsames Synchronisationsereignis aufzeichnen oder '
                'Fenster grafisch prüfen.',
          ),
        );
        continue;
      }
      final fit = _fitLag(estimates);
      final valid = fit.rmseMilliseconds <=
          config.maximumLagResidual.inMicroseconds / 1000;
      final reason = valid
          ? null
          : 'Lag-Residualfehler ${fit.rmseMilliseconds.toStringAsFixed(3)} ms '
              'überschreitet ${config.maximumLagResidual.inMicroseconds / 1000} ms.';
      models[entry.key] =
          _ClockModel(offsetSeconds: fit.offsetSeconds, drift: fit.drift);
      qualities[entry.key] = SensorSynchronizationQuality(
        sensorLabel: entry.key,
        valid: valid,
        rawStartOffsetMilliseconds: _startOffsetMs(entry.value, reference),
        estimatedSignalOffsetMilliseconds: fit.offsetSeconds * 1000,
        estimatedDriftPpm: fit.drift * 1000000,
        lagResidualRmseMilliseconds: fit.rmseMilliseconds,
        maximumAbsoluteLagResidualMilliseconds:
            fit.maximumAbsoluteResidualMilliseconds,
        meanWindowCorrelation: fit.meanCorrelation,
        sourceSamplingRateHz: _samplingRate(entry.value),
        outputCoverage: 0,
        uncertaintyMilliseconds: _uncertaintyMs(fit.rmseMilliseconds),
        lagEstimates: estimates,
        invalidReason: reason,
      );
      if (!valid) {
        issues.add(
          SynchronizationIssue(
            code: 'excessive_lag_residual',
            sensorLabel: entry.key,
            observation: reason!,
            uncertainty:
                'Ein einzelnes affines Clock-Modell beschreibt den Verlauf '
                'nicht ausreichend.',
            recommendation:
                'Fensterlags grafisch prüfen; Aufnahme nicht automatisch nutzen.',
          ),
        );
      }
    }
    if (qualities.values.any((quality) => !quality.valid)) {
      return _failedResult(
        referenceLabel,
        issues,
        sensorQuality: qualities,
      );
    }

    final correctedStart = recordings.entries
        .map((entry) => _correctedMicros(
              entry.value.samples.first.timestamp.microsecondsSinceEpoch,
              originMicros,
              models[entry.key]!,
            ))
        .reduce(math.max);
    final correctedEnd = recordings.entries
        .map((entry) => _correctedMicros(
              entry.value.samples.last.timestamp.microsecondsSinceEpoch,
              originMicros,
              models[entry.key]!,
            ))
        .reduce(math.min);
    final periodMicros = (1000000 / config.targetSamplingRateHz).round();
    final gridStart = ((correctedStart / periodMicros).ceil()) * periodMicros;
    final gridEnd = ((correctedEnd / periodMicros).floor()) * periodMicros;
    if (gridEnd < gridStart) {
      return _failed(
        referenceLabel,
        issues,
        'empty_common_grid',
        'Nach Clock-Korrektur bleibt kein gemeinsamer Rasterpunkt.',
        sensorQuality: qualities,
      );
    }

    final maximumGaps = <String, double>{
      for (final entry in recordings.entries)
        entry.key: _medianIntervalMicros(entry.value) *
            config.maximumInterpolationGapFactor,
    };
    final frames = <SynchronizedFrame>[];
    final available = <String, int>{
      for (final label in requiredLabels) label: 0
    };
    for (var gridMicros = gridStart;
        gridMicros <= gridEnd;
        gridMicros += periodMicros) {
      final values = <String, SynchronizedImuValue?>{};
      for (final entry in recordings.entries) {
        final rawMicros = _rawMicrosForCorrected(
            gridMicros, originMicros, models[entry.key]!);
        final value =
            _interpolate(entry.value, rawMicros, maximumGaps[entry.key]!);
        values[entry.key] = value;
        if (value != null) available[entry.key] = available[entry.key]! + 1;
      }
      frames.add(
        SynchronizedFrame(
          timestamp:
              DateTime.fromMicrosecondsSinceEpoch(gridMicros, isUtc: true),
          elapsedSeconds: (gridMicros - gridStart) / 1000000,
          values: values,
        ),
      );
    }

    var reviewRequired = false;
    for (final label in requiredLabels) {
      final old = qualities[label]!;
      final coverage = available[label]! / frames.length;
      final validCoverage = coverage >= config.minimumCoverage;
      if (!validCoverage) {
        reviewRequired = true;
        issues.add(
          SynchronizationIssue(
            code: 'insufficient_output_coverage',
            sensorLabel: label,
            observation:
                'Nur ${(coverage * 100).toStringAsFixed(2)} % des gemeinsamen '
                'Rasters sind belegt.',
            uncertainty:
                'Große Quelllücken werden absichtlich nicht interpoliert.',
            recommendation:
                'Markierte Lücken prüfen und betroffene Abschnitte ausschließen.',
          ),
        );
      }
      qualities[label] = SensorSynchronizationQuality(
        sensorLabel: old.sensorLabel,
        valid: old.valid && validCoverage,
        rawStartOffsetMilliseconds: old.rawStartOffsetMilliseconds,
        estimatedSignalOffsetMilliseconds:
            old.estimatedSignalOffsetMilliseconds,
        estimatedDriftPpm: old.estimatedDriftPpm,
        lagResidualRmseMilliseconds: old.lagResidualRmseMilliseconds,
        maximumAbsoluteLagResidualMilliseconds:
            old.maximumAbsoluteLagResidualMilliseconds,
        meanWindowCorrelation: old.meanWindowCorrelation,
        sourceSamplingRateHz: old.sourceSamplingRateHz,
        outputCoverage: coverage,
        uncertaintyMilliseconds: label == referenceLabel
            ? periodMicros / 2000
            : old.uncertaintyMilliseconds,
        lagEstimates: old.lagEstimates,
        invalidReason: validCoverage
            ? old.invalidReason
            : 'Rasterabdeckung unterschreitet ${config.minimumCoverage}.',
      );
    }

    return ImuSynchronizationResult(
      status: reviewRequired
          ? SynchronizationStatus.reviewRequired
          : SynchronizationStatus.accepted,
      referenceSensorLabel: referenceLabel,
      gridSamplingRateHz: 1000000 / periodMicros,
      gridPeriodMicroseconds: periodMicros,
      commonStart: DateTime.fromMicrosecondsSinceEpoch(gridStart, isUtc: true),
      commonEnd: DateTime.fromMicrosecondsSinceEpoch(gridEnd, isUtc: true),
      frames: frames,
      sensorQuality: qualities,
      issues: issues,
      assumptions: _assumptions(periodMicros),
    );
  }

  List<LagEstimate> _estimateWindowLags(
    SensorRecording reference,
    SensorRecording target,
    int originMicros,
    int overlapStart,
    int overlapEnd,
  ) {
    final halfWindow = config.correlationWindow.inMicroseconds ~/ 2;
    final estimates = <LagEstimate>[];
    for (var center = overlapStart + halfWindow;
        center <= overlapEnd - halfWindow;
        center += config.correlationWindowStep.inMicroseconds) {
      LagEstimate? best;
      final from = center - halfWindow;
      final to = center + halfWindow;
      final referenceWindow = reference.samples.where((sample) {
        final micros = sample.timestamp.microsecondsSinceEpoch;
        return micros >= from && micros <= to;
      }).toList(growable: false);
      for (var lag = -config.maximumLag.inMicroseconds;
          lag <= config.maximumLag.inMicroseconds;
          lag += config.lagStep.inMicroseconds) {
        final pairs = <(double, double)>[];
        for (final sample in referenceWindow) {
          final micros = sample.timestamp.microsecondsSinceEpoch;
          final targetMagnitude =
              _interpolatedAccelerationMagnitude(target, micros + lag);
          if (targetMagnitude != null) {
            pairs.add((
              math.sqrt(sample.accelerationMps2.magnitudeSquared),
              targetMagnitude,
            ));
          }
        }
        if (pairs.length < config.minimumCorrelationSamples) continue;
        final correlation = _correlation(pairs);
        if (correlation.isFinite &&
            (best == null || correlation > best.correlation)) {
          best = LagEstimate(
            windowCenterSeconds: (center - originMicros) / 1000000,
            lagMilliseconds: lag / 1000,
            correlation: correlation,
            pairedSamples: pairs.length,
          );
        }
      }
      if (best != null && best.correlation >= config.minimumWindowCorrelation) {
        estimates.add(best);
      }
    }
    return estimates;
  }

  _LagFit _fitLag(List<LagEstimate> estimates) {
    final meanX = estimates
            .map((estimate) => estimate.windowCenterSeconds)
            .reduce((a, b) => a + b) /
        estimates.length;
    final meanY = estimates
            .map((estimate) => estimate.lagMilliseconds / 1000)
            .reduce((a, b) => a + b) /
        estimates.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (final estimate in estimates) {
      final dx = estimate.windowCenterSeconds - meanX;
      numerator += dx * (estimate.lagMilliseconds / 1000 - meanY);
      denominator += dx * dx;
    }
    final drift = denominator == 0 ? 0.0 : numerator / denominator;
    final offset = meanY - drift * meanX;
    final residuals = estimates
        .map((estimate) =>
            estimate.lagMilliseconds -
            (offset + drift * estimate.windowCenterSeconds) * 1000)
        .toList();
    final rmse = math.sqrt(
        residuals.map((value) => value * value).reduce((a, b) => a + b) /
            residuals.length);
    return _LagFit(
      offsetSeconds: offset,
      drift: drift,
      rmseMilliseconds: rmse,
      maximumAbsoluteResidualMilliseconds:
          residuals.map((value) => value.abs()).reduce(math.max),
      meanCorrelation: estimates
              .map((estimate) => estimate.correlation)
              .reduce((a, b) => a + b) /
          estimates.length,
    );
  }

  String? _invalidRecordingReason(SensorRecording recording) {
    if (recording.samples.length < config.minimumSamplesPerSensor) {
      return '${recording.identity.label} enthält nur '
          '${recording.samples.length} Messwerte; erforderlich sind '
          '${config.minimumSamplesPerSensor}.';
    }
    for (var index = 0; index < recording.samples.length; index++) {
      final sample = recording.samples[index];
      if (!_finiteVector(sample.accelerationMps2) ||
          !_finiteVector(sample.angularVelocityRadPerSecond) ||
          (sample.magneticFieldMicrotesla != null &&
              !_finiteVector(sample.magneticFieldMicrotesla!)) ||
          (sample.orientationAnglesDegrees != null &&
              !_finiteVector(sample.orientationAnglesDegrees!))) {
        return '${recording.identity.label} enthält NaN oder Infinity in '
            'Quellzeile ${sample.sourceLine}.';
      }
      if (index > 0 &&
          !sample.timestamp.isAfter(recording.samples[index - 1].timestamp)) {
        return '${recording.identity.label} besitzt nicht streng steigende '
            'Zeitstempel bei Quellzeile ${sample.sourceLine}.';
      }
    }
    return null;
  }

  void _validateConfig() {
    if (!config.targetSamplingRateHz.isFinite ||
        config.targetSamplingRateHz <= 0 ||
        config.maximumLag <= Duration.zero ||
        config.lagStep <= Duration.zero ||
        config.correlationWindow <= Duration.zero ||
        config.correlationWindowStep <= Duration.zero ||
        config.minimumSamplesPerSensor < 2 ||
        config.minimumCorrelationSamples < 3 ||
        config.minimumWindowCorrelation < -1 ||
        config.minimumWindowCorrelation > 1 ||
        config.maximumLagResidual.isNegative ||
        !config.minimumCoverage.isFinite ||
        config.minimumCoverage < 0 ||
        config.minimumCoverage > 1 ||
        !config.maximumInterpolationGapFactor.isFinite ||
        config.maximumInterpolationGapFactor < 1) {
      throw ArgumentError('Ungültige Synchronisationskonfiguration.');
    }
  }

  ImuSynchronizationResult _failed(
    String referenceLabel,
    List<SynchronizationIssue> issues,
    String code,
    String observation, {
    Map<String, SensorSynchronizationQuality> sensorQuality = const {},
  }) {
    issues.add(
      SynchronizationIssue(
        code: code,
        observation: observation,
        uncertainty: 'Es wird kein synchronisierter Datensatz erzeugt.',
        recommendation:
            'Eingangsdaten und Synchronisationskonfiguration prüfen.',
      ),
    );
    return _failedResult(
      referenceLabel,
      issues,
      sensorQuality: sensorQuality,
    );
  }

  ImuSynchronizationResult _failedResult(
    String referenceLabel,
    List<SynchronizationIssue> issues, {
    Map<String, SensorSynchronizationQuality> sensorQuality = const {},
  }) =>
      ImuSynchronizationResult(
        status: SynchronizationStatus.notSynchronized,
        referenceSensorLabel: referenceLabel,
        gridSamplingRateHz: config.targetSamplingRateHz,
        gridPeriodMicroseconds: config.targetSamplingRateHz > 0 &&
                config.targetSamplingRateHz.isFinite
            ? (1000000 / config.targetSamplingRateHz).round()
            : 0,
        commonStart: null,
        commonEnd: null,
        frames: const [],
        sensorQuality: sensorQuality,
        issues: List.unmodifiable(issues),
        assumptions: const [
          'Ungültige Synchronisation erzeugt ausdrücklich keinen Ersatzdatensatz.',
        ],
      );

  List<String> _assumptions(int periodMicros) => [
        'Alle gemeinsamen Zeitstempel sind UTC-Mikrosekunden seit Unix-Epoch.',
        'Beschleunigungsbetrag [m/s²] dient ausschließlich der technischen '
            'Lag-Schätzung; andere Kanäle werden mit derselben Clock-Korrektur '
            'interpoliert.',
        'Clock-Modell: lag(t) = offset + drift × t; korrigierte Zeit = '
            'Quellzeit − lag(t).',
        'Das Raster hat $periodMicros µs Periodendauer '
            '(${(1000000 / periodMicros).toStringAsFixed(6)} Hz).',
        'Lineare Interpolation überbrückt höchstens '
            '${config.maximumInterpolationGapFactor} mediane Quellintervalle.',
        'Unsicherheit kombiniert Lag-Residual-RMSE, halbe Lag-Suchschrittweite '
            'und halbe Rasterperiode quadratisch.',
        'Grenzen für Korrelation, Residual und Abdeckung sind technische '
            'Akzeptanzregeln, keine physiologischen Referenzbereiche.',
        'Ohne externen Trigger oder Videoannotation ist die absolute '
            'Synchronisationsrichtigkeit nicht fachlich validiert.',
      ];

  double _uncertaintyMs(double rmseMs) {
    final halfStep = config.lagStep.inMicroseconds / 2000;
    final halfGrid = (1000000 / config.targetSamplingRateHz) / 2000;
    return math
        .sqrt(rmseMs * rmseMs + halfStep * halfStep + halfGrid * halfGrid);
  }
}

class _ClockModel {
  const _ClockModel({required this.offsetSeconds, required this.drift});

  final double offsetSeconds;
  final double drift;
}

class _LagFit {
  const _LagFit({
    required this.offsetSeconds,
    required this.drift,
    required this.rmseMilliseconds,
    required this.maximumAbsoluteResidualMilliseconds,
    required this.meanCorrelation,
  });

  final double offsetSeconds;
  final double drift;
  final double rmseMilliseconds;
  final double maximumAbsoluteResidualMilliseconds;
  final double meanCorrelation;
}

bool _finiteVector(Vector3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;

double _startOffsetMs(
  SensorRecording target,
  SensorRecording reference,
) =>
    target.samples.first.timestamp
        .difference(reference.samples.first.timestamp)
        .inMicroseconds /
    1000;

double _samplingRate(SensorRecording recording) =>
    1000000 / _medianIntervalMicros(recording);

double _medianIntervalMicros(SensorRecording recording) {
  final intervals = <int>[];
  for (var index = 1; index < recording.samples.length; index++) {
    intervals.add(
      recording.samples[index].timestamp
          .difference(recording.samples[index - 1].timestamp)
          .inMicroseconds,
    );
  }
  intervals.sort();
  final middle = intervals.length ~/ 2;
  return intervals.length.isOdd
      ? intervals[middle].toDouble()
      : (intervals[middle - 1] + intervals[middle]) / 2;
}

int _correctedMicros(int rawMicros, int originMicros, _ClockModel model) {
  final rawRelativeSeconds = (rawMicros - originMicros) / 1000000;
  final correctedRelative = rawRelativeSeconds -
      model.offsetSeconds -
      model.drift * rawRelativeSeconds;
  return originMicros + (correctedRelative * 1000000).round();
}

double _rawMicrosForCorrected(
  int correctedMicros,
  int originMicros,
  _ClockModel model,
) {
  final correctedRelative = (correctedMicros - originMicros) / 1000000;
  final rawRelative =
      (correctedRelative + model.offsetSeconds) / (1 - model.drift);
  return originMicros + rawRelative * 1000000;
}

double? _interpolatedAccelerationMagnitude(
  SensorRecording recording,
  num rawMicros,
) {
  final bracket = _bracket(recording.samples, rawMicros);
  if (bracket == null) return null;
  final lower = recording.samples[bracket.$1];
  final upper = recording.samples[bracket.$2];
  if (bracket.$1 == bracket.$2) {
    return math.sqrt(lower.accelerationMps2.magnitudeSquared);
  }
  final fraction = (rawMicros - lower.timestamp.microsecondsSinceEpoch) /
      (upper.timestamp.microsecondsSinceEpoch -
          lower.timestamp.microsecondsSinceEpoch);
  final vector = _lerpVector(
      lower.accelerationMps2, upper.accelerationMps2, fraction.toDouble());
  return math.sqrt(vector.magnitudeSquared);
}

SynchronizedImuValue? _interpolate(
  SensorRecording recording,
  double rawMicros,
  double maximumGapMicros,
) {
  final bracket = _bracket(recording.samples, rawMicros);
  if (bracket == null) return null;
  final lower = recording.samples[bracket.$1];
  final upper = recording.samples[bracket.$2];
  final gap = upper.timestamp.difference(lower.timestamp).inMicroseconds.abs();
  if (gap > maximumGapMicros) return null;
  final fraction = bracket.$1 == bracket.$2
      ? 0.0
      : (rawMicros - lower.timestamp.microsecondsSinceEpoch) / gap;
  return SynchronizedImuValue(
    accelerationMps2:
        _lerpVector(lower.accelerationMps2, upper.accelerationMps2, fraction),
    angularVelocityRadPerSecond: _lerpVector(
      lower.angularVelocityRadPerSecond,
      upper.angularVelocityRadPerSecond,
      fraction,
    ),
    magneticFieldMicrotesla: lower.magneticFieldMicrotesla != null &&
            upper.magneticFieldMicrotesla != null
        ? _lerpVector(
            lower.magneticFieldMicrotesla!,
            upper.magneticFieldMicrotesla!,
            fraction,
          )
        : null,
    orientationAnglesDegrees: lower.orientationAnglesDegrees != null &&
            upper.orientationAnglesDegrees != null
        ? _lerpCircularDegrees(
            lower.orientationAnglesDegrees!,
            upper.orientationAnglesDegrees!,
            fraction,
          )
        : null,
    lowerSourceName: lower.sourceName,
    lowerSourceLine: lower.sourceLine,
    upperSourceName: upper.sourceName,
    upperSourceLine: upper.sourceLine,
  );
}

(int, int)? _bracket(List<ImuSample> samples, num rawMicros) {
  if (rawMicros < samples.first.timestamp.microsecondsSinceEpoch ||
      rawMicros > samples.last.timestamp.microsecondsSinceEpoch) {
    return null;
  }
  var low = 0;
  var high = samples.length - 1;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    final value = samples[middle].timestamp.microsecondsSinceEpoch;
    if (value == rawMicros) return (middle, middle);
    if (value < rawMicros) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return (high, low);
}

Vector3 _lerpVector(Vector3 lower, Vector3 upper, double fraction) => Vector3(
      lower.x + (upper.x - lower.x) * fraction,
      lower.y + (upper.y - lower.y) * fraction,
      lower.z + (upper.z - lower.z) * fraction,
    );

Vector3 _lerpCircularDegrees(
  Vector3 lower,
  Vector3 upper,
  double fraction,
) =>
    Vector3(
      _lerpCircularDegree(lower.x, upper.x, fraction),
      _lerpCircularDegree(lower.y, upper.y, fraction),
      _lerpCircularDegree(lower.z, upper.z, fraction),
    );

double _lerpCircularDegree(double lower, double upper, double fraction) {
  var difference = upper - lower;
  if (difference > 180) difference -= 360;
  if (difference < -180) difference += 360;
  var value = lower + difference * fraction;
  if (value > 180) value -= 360;
  if (value < -180) value += 360;
  return value;
}

double _correlation(List<(double, double)> pairs) {
  final meanX =
      pairs.map((pair) => pair.$1).reduce((a, b) => a + b) / pairs.length;
  final meanY =
      pairs.map((pair) => pair.$2).reduce((a, b) => a + b) / pairs.length;
  var covariance = 0.0;
  var varianceX = 0.0;
  var varianceY = 0.0;
  for (final pair in pairs) {
    final x = pair.$1 - meanX;
    final y = pair.$2 - meanY;
    covariance += x * y;
    varianceX += x * x;
    varianceY += y * y;
  }
  if (varianceX == 0 || varianceY == 0) return double.nan;
  return covariance / math.sqrt(varianceX * varianceY);
}
