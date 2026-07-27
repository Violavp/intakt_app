import 'dart:math' as math;

import '../imu_import/imu_models.dart';
import '../imu_sync/index_time_reconstruction.dart';
import 'preprocessing_models.dart';

/// Reproducible preprocessing of an already reconstructed common IMU grid.
///
/// Processing order per continuous sensor segment:
/// 1. isolated-spike Hampel replacement,
/// 2. fourth-order zero-phase Butterworth low-pass,
/// 3. stationary-gravity roll/pitch alignment,
/// 4. gravity low-pass and movement = acceleration - gravity.
///
/// Input values and their raw-source references are never modified.
class ImuPreprocessor {
  const ImuPreprocessor({
    this.config = const ImuPreprocessingConfig(),
  });

  final ImuPreprocessingConfig config;

  ImuPreprocessingResult process(IndexTimeReconstructionResult input) {
    _validateConfig(input.gridSamplingRateHz);
    final issues = <PreprocessingIssue>[];
    if (!input.hasReconstructedDataset || input.frames.isEmpty) {
      return _failed(
        input.gridSamplingRateHz,
        issues,
        'missing_reconstructed_dataset',
        'Es liegt kein freigegebener rekonstruierter Eingangsdatensatz vor.',
      );
    }
    if (!_validFrameTimes(input.frames)) {
      return _failed(
        input.gridSamplingRateHz,
        issues,
        'invalid_frame_times',
        'Analysezeiten sind nicht endlich oder nicht streng steigend.',
      );
    }

    final labels = input.frames.first.values.keys.toList();
    if (labels.isEmpty ||
        input.frames.any(
          (frame) => !frame.values.keys.toSet().containsAll(labels),
        )) {
      return _failed(
        input.gridSamplingRateHz,
        issues,
        'inconsistent_sensor_keys',
        'Sensorbelegung des gemeinsamen Rasters ist inkonsistent.',
      );
    }

    final processedBySensor = <String, List<PreprocessedImuValue?>>{};
    final qualities = <String, SensorPreprocessingQuality>{};
    var reviewRequired =
        input.status == TimeReconstructionStatus.reviewRequired;
    if (reviewRequired) {
      issues.add(
        const PreprocessingIssue(
          code: 'upstream_time_review_required',
          observation:
              'Die vorgelagerte Zeitrekonstruktion verlangt manuelle Prüfung.',
          uncertainty:
              'Die rekonstruierten Analysezeiten sind keine gemessenen '
              'Sensorabtastzeitpunkte.',
          recommendation:
              'Zeitrekonstruktionsbericht und Videoanker gemeinsam prüfen.',
        ),
      );
    }

    for (final label in labels) {
      final sensorResult = _processSensor(
        label,
        input.frames,
        input.gridSamplingRateHz,
        issues,
      );
      processedBySensor[label] = sensorResult.values;
      qualities[label] = sensorResult.quality;
      reviewRequired = reviewRequired || sensorResult.reviewRequired;
    }

    final frames = <PreprocessedFrame>[
      for (var index = 0; index < input.frames.length; index++)
        PreprocessedFrame(
          analysisTimeSeconds: input.frames[index].analysisTimeSeconds,
          values: {
            for (final label in labels) label: processedBySensor[label]![index],
          },
        ),
    ];
    if (qualities.values.every((quality) => quality.outputSamples == 0)) {
      return _failed(
        input.gridSamplingRateHz,
        issues,
        'no_processable_segments',
        'Kein Sensor enthält ein ausreichend langes zusammenhängendes Segment.',
        qualities: qualities,
      );
    }
    final sensorsWithoutOutput = qualities.values
        .where((quality) => quality.outputSamples == 0)
        .map((quality) => quality.sensorLabel)
        .toList();
    if (sensorsWithoutOutput.isNotEmpty) {
      return _failed(
        input.gridSamplingRateHz,
        issues,
        'sensor_without_output',
        'Für ${sensorsWithoutOutput.join(', ')} konnte kein '
            'Vorverarbeitungssignal erzeugt werden.',
        qualities: qualities,
      );
    }
    return ImuPreprocessingResult(
      status: reviewRequired
          ? PreprocessingStatus.reviewRequired
          : PreprocessingStatus.accepted,
      gridSamplingRateHz: input.gridSamplingRateHz,
      frames: frames,
      sensorQuality: qualities,
      issues: issues,
      config: config,
      assumptions: _assumptions,
    );
  }

  _SensorResult _processSensor(
    String label,
    List<ReconstructedTimeFrame> frames,
    double samplingRateHz,
    List<PreprocessingIssue> issues,
  ) {
    final source = <ResampledImuValue?>[
      for (final frame in frames) frame.values[label],
    ];
    final output = List<PreprocessedImuValue?>.filled(source.length, null);
    final segments = _continuousSegments(source);
    var replaced = 0;
    var retained = 0;
    var outputSamples = 0;
    var shortSegmentSamples = 0;
    final cleanedAcceleration = List<Vector3?>.filled(source.length, null);
    final cleanedGyro = List<Vector3?>.filled(source.length, null);
    final filteredAcceleration = List<Vector3?>.filled(source.length, null);
    final filteredGyro = List<Vector3?>.filled(source.length, null);
    final filteredMag = List<Vector3?>.filled(source.length, null);
    final replacedAt = List<bool>.filled(source.length, false);

    for (final segment in segments) {
      if (segment.length < config.minimumSegmentSamples) {
        shortSegmentSamples += segment.length;
        continue;
      }
      final acceleration = [
        for (var i = segment.start; i < segment.end; i++)
          source[i]!.accelerationMps2,
      ];
      final gyro = [
        for (var i = segment.start; i < segment.end; i++)
          source[i]!.angularVelocityRadPerSecond,
      ];
      final cleanAcceleration = _hampelVectors(
        acceleration,
        config.minimumAccelerationMadMps2,
      );
      final cleanGyro = _hampelVectors(
        gyro,
        config.minimumAngularVelocityMadRadPerSecond,
      );
      final accelerationFiltered = _filterVectors(
        cleanAcceleration.values,
        config.lowPassCutoffHz,
        samplingRateHz,
      );
      final gyroFiltered = _filterVectors(
        cleanGyro.values,
        config.lowPassCutoffHz,
        samplingRateHz,
      );
      final magnetic = [
        for (var i = segment.start; i < segment.end; i++)
          source[i]!.magneticFieldMicrotesla,
      ];
      final hasCompleteMagnetic = magnetic.every((value) => value != null);
      final magneticFiltered = hasCompleteMagnetic
          ? _filterVectors(
              magnetic.cast<Vector3>(),
              config.lowPassCutoffHz,
              samplingRateHz,
            )
          : null;
      for (var local = 0; local < segment.length; local++) {
        final global = segment.start + local;
        cleanedAcceleration[global] = cleanAcceleration.values[local];
        cleanedGyro[global] = cleanGyro.values[local];
        filteredAcceleration[global] = accelerationFiltered[local];
        filteredGyro[global] = gyroFiltered[local];
        filteredMag[global] = magneticFiltered?[local];
        replacedAt[global] =
            cleanAcceleration.replacedAt[local] || cleanGyro.replacedAt[local];
        if (replacedAt[global]) replaced++;
        if (cleanAcceleration.retainedAt[local] ||
            cleanGyro.retainedAt[local]) {
          retained++;
        }
      }
    }

    if (shortSegmentSamples > 0) {
      issues.add(
        PreprocessingIssue(
          code: 'short_segment_not_filtered',
          sensorLabel: label,
          observation: '$shortSegmentSamples Samples liegen in Segmenten unter '
              '${config.minimumSegmentSamples} Samples und bleiben als Lücke.',
          uncertainty:
              'Rand- und Filterzustände wären für diese Abschnitte instabil.',
          recommendation: 'Datenlücken und Aufnahmelänge prüfen.',
        ),
      );
    }

    final orientation = _estimateOrientation(
      frames,
      filteredAcceleration,
      filteredGyro,
      samplingRateHz,
    );
    var reviewRequired = !orientation.valid || shortSegmentSamples > 0;
    final rotation = orientation.rotationSensorToGravityFrame;
    if (!orientation.valid) {
      issues.add(
        PreprocessingIssue(
          code: 'orientation_not_resolved',
          sensorLabel: label,
          observation:
              orientation.invalidReason ?? 'Keine stabile Lage gefunden.',
          uncertainty:
              'Roll/Pitch und damit vertikale/horizontale Komponenten bleiben '
              'im lokalen Sensorrahmen.',
          recommendation:
              'Eine dokumentierte ruhige Kalibrierphase vor der Bewegung '
              'aufzeichnen.',
        ),
      );
    }

    final alignedAcceleration = [
      for (final value in filteredAcceleration)
        value == null
            ? null
            : rotation == null
                ? value
                : _rotate(value, rotation),
    ];
    final alignedGyro = [
      for (final value in filteredGyro)
        value == null
            ? null
            : rotation == null
                ? value
                : _rotate(value, rotation),
    ];
    final alignedMag = [
      for (final value in filteredMag)
        value == null
            ? null
            : rotation == null
                ? value
                : _rotate(value, rotation),
    ];
    final gravity = List<Vector3?>.filled(source.length, null);
    for (final segment in _continuousVectorSegments(alignedAcceleration)) {
      if (segment.length < config.minimumSegmentSamples) continue;
      final values = [
        for (var i = segment.start; i < segment.end; i++)
          alignedAcceleration[i]!,
      ];
      final filtered = _filterVectors(
        values,
        config.gravityCutoffHz,
        samplingRateHz,
      );
      for (var local = 0; local < segment.length; local++) {
        gravity[segment.start + local] = filtered[local];
      }
    }

    for (var index = 0; index < source.length; index++) {
      final raw = source[index];
      final cleanAcc = cleanedAcceleration[index];
      final cleanGyro = cleanedGyro[index];
      final filteredAcc = filteredAcceleration[index];
      final filteredAngular = filteredGyro[index];
      final alignedAcc = alignedAcceleration[index];
      final alignedAngular = alignedGyro[index];
      final gravityValue = gravity[index];
      if (raw == null ||
          cleanAcc == null ||
          cleanGyro == null ||
          filteredAcc == null ||
          filteredAngular == null ||
          alignedAcc == null ||
          alignedAngular == null ||
          gravityValue == null) {
        continue;
      }
      output[index] = PreprocessedImuValue(
        raw: raw,
        cleanedAccelerationMps2: cleanAcc,
        cleanedAngularVelocityRadPerSecond: cleanGyro,
        filteredAccelerationSensorFrameMps2: filteredAcc,
        filteredAngularVelocitySensorFrameRadPerSecond: filteredAngular,
        alignedAccelerationMps2: alignedAcc,
        alignedAngularVelocityRadPerSecond: alignedAngular,
        gravityMps2: gravityValue,
        movementAccelerationMps2: _subtract(alignedAcc, gravityValue),
        alignedMagneticFieldMicrotesla: alignedMag[index],
        outlierReplaced: replacedAt[index],
        processingTemporalResolutionMilliseconds:
            1000 / (2 * config.lowPassCutoffHz),
      );
      outputSamples++;
    }

    final comparisons = _compareFilters(
      cleanedAcceleration,
      filteredAcceleration,
      samplingRateHz,
    );
    final butterworth = comparisons.firstWhere(
      (metrics) => metrics.method == 'zero_phase_butterworth',
      orElse: () => const FilterMethodMetrics(
        method: 'zero_phase_butterworth',
        roughnessRmsMps2: double.nan,
        peakToPeakRetention: double.nan,
        strongestEventTimeShiftMilliseconds: double.nan,
      ),
    );
    if (butterworth.peakToPeakRetention.isFinite &&
        butterworth.peakToPeakRetention < config.minimumEventPeakRetention) {
      reviewRequired = true;
      issues.add(
        PreprocessingIssue(
          code: 'event_peak_attenuation',
          sensorLabel: label,
          observation: 'Die Peak-to-Peak-Erhaltung beträgt '
              '${butterworth.peakToPeakRetention.toStringAsFixed(3)}.',
          uncertainty:
              'Starke Einzelspitzen können technische Artefakte oder reale '
              'kurze Ereignisse sein.',
          recommendation:
              'Roh-/Filteroverlay und Videoereignisse manuell prüfen.',
        ),
      );
    }

    final inputSamples = source.whereType<ResampledImuValue>().length;
    final coverage = inputSamples == 0 ? 0.0 : outputSamples / inputSamples;
    final orientationConfidence = orientation.valid
        ? (1 -
                orientation.gravityResidualMps2! /
                    config.orientationMaximumGravityDeviationMps2)
            .clamp(0.0, 1.0)
        : 0.5;
    final qualityScore = (coverage * orientationConfidence).clamp(0.0, 1.0);
    return _SensorResult(
      values: output,
      reviewRequired: reviewRequired,
      quality: SensorPreprocessingQuality(
        sensorLabel: label,
        inputSamples: inputSamples,
        outputSamples: outputSamples,
        gapSamples: source.length - inputSamples,
        replacedOutlierSamples: replaced,
        retainedCandidateOutlierSamples: retained,
        orientation: orientation,
        filterComparisons: comparisons,
        qualityScore: qualityScore,
        uncertainty: orientation.valid
            ? 'Vertikale Achse aus dem stabilsten technischen Ruhefenster; '
                'Yaw und anatomische Horizontalzeichen bleiben unbestimmt.'
            : 'Keine belastbare Schwerkraftausrichtung; Werte verbleiben im '
                'lokalen Sensorrahmen.',
      ),
    );
  }

  OrientationEstimate _estimateOrientation(
    List<ReconstructedTimeFrame> frames,
    List<Vector3?> acceleration,
    List<Vector3?> gyro,
    double samplingRateHz,
  ) {
    final window = math.max(
      config.minimumSegmentSamples,
      (config.orientationWindowSeconds * samplingRateHz).round(),
    );
    _OrientationCandidate? best;
    for (var start = 0; start + window <= acceleration.length; start++) {
      final accWindow = acceleration.sublist(start, start + window);
      final gyroWindow = gyro.sublist(start, start + window);
      if (accWindow.any((value) => value == null) ||
          gyroWindow.any((value) => value == null)) {
        continue;
      }
      final mean = _meanVector(accWindow.cast<Vector3>());
      final magnitude = _magnitude(mean);
      final residual = (magnitude - config.standardGravityMps2).abs();
      final gyroRms = math.sqrt(
        gyroWindow
                .cast<Vector3>()
                .map((value) => value.magnitudeSquared)
                .reduce((a, b) => a + b) /
            window,
      );
      final score = residual / config.orientationMaximumGravityDeviationMps2 +
          gyroRms / config.orientationMaximumGyroRmsRadPerSecond;
      if (best == null || score < best.score) {
        best = _OrientationCandidate(
          start: start,
          end: start + window,
          gravity: mean,
          magnitude: magnitude,
          residual: residual,
          gyroRms: gyroRms,
          score: score,
        );
      }
    }
    if (best == null) {
      return const OrientationEstimate(
        valid: false,
        windowStartSeconds: null,
        windowEndSeconds: null,
        gravitySensorFrameMps2: null,
        gravityMagnitudeMps2: null,
        gyroRmsRadPerSecond: null,
        gravityResidualMps2: null,
        rotationSensorToGravityFrame: null,
        invalidReason:
            'Kein lückenloses, ausreichend langes Kalibrierfenster vorhanden.',
      );
    }
    final valid =
        best.gyroRms <= config.orientationMaximumGyroRmsRadPerSecond &&
            best.residual <= config.orientationMaximumGravityDeviationMps2 &&
            best.magnitude > 0;
    return OrientationEstimate(
      valid: valid,
      windowStartSeconds: frames[best.start].analysisTimeSeconds,
      windowEndSeconds: frames[best.end - 1].analysisTimeSeconds,
      gravitySensorFrameMps2: best.gravity,
      gravityMagnitudeMps2: best.magnitude,
      gyroRmsRadPerSecond: best.gyroRms,
      gravityResidualMps2: best.residual,
      rotationSensorToGravityFrame:
          valid ? _rotationToPositiveZ(best.gravity) : null,
      invalidReason: valid
          ? null
          : 'Bestes Fenster überschreitet Ruhe-/Gravitationskriterien '
              '(Gyro-RMS ${best.gyroRms.toStringAsFixed(4)} rad/s, '
              'Gravitationsresiduum ${best.residual.toStringAsFixed(4)} '
              'm/s²).',
    );
  }

  List<FilterMethodMetrics> _compareFilters(
    List<Vector3?> cleaned,
    List<Vector3?> butterworth,
    double samplingRateHz,
  ) {
    final rawValues = <double>[];
    final butterworthValues = <double>[];
    for (var index = 0; index < cleaned.length; index++) {
      if (cleaned[index] != null && butterworth[index] != null) {
        rawValues.add(_magnitude(cleaned[index]!));
        butterworthValues.add(_magnitude(butterworth[index]!));
      }
    }
    if (rawValues.length < config.minimumSegmentSamples) return const [];
    final movingAverage = _movingAverage(
      rawValues,
      config.comparisonMovingAverageWindowSamples,
    );
    return [
      _metrics(
        'zero_phase_butterworth',
        rawValues,
        butterworthValues,
        samplingRateHz,
      ),
      _metrics(
        'centered_moving_average',
        rawValues,
        movingAverage,
        samplingRateHz,
      ),
    ];
  }

  FilterMethodMetrics _metrics(
    String method,
    List<double> raw,
    List<double> filtered,
    double samplingRateHz,
  ) {
    final rawRange = _range(raw);
    final filteredRange = _range(filtered);
    final rawMedian = _median(raw);
    final filteredMedian = _median(filtered);
    final rawEventIndex = _maximumDeviationIndex(raw, rawMedian);
    final filteredEventIndex = _maximumDeviationIndex(filtered, filteredMedian);
    return FilterMethodMetrics(
      method: method,
      roughnessRmsMps2: _differenceRms(filtered),
      peakToPeakRetention: rawRange == 0 ? 1 : filteredRange / rawRange,
      strongestEventTimeShiftMilliseconds:
          (filteredEventIndex - rawEventIndex).abs() / samplingRateHz * 1000,
    );
  }

  _HampelResult _hampelVectors(List<Vector3> values, double minimumMad) {
    final axes = [
      [for (final value in values) value.x],
      [for (final value in values) value.y],
      [for (final value in values) value.z],
    ];
    final results = [
      for (final axis in axes) _hampel(axis, minimumMad),
    ];
    return _HampelResult(
      values: [
        for (var index = 0; index < values.length; index++)
          Vector3(
            results[0].values[index],
            results[1].values[index],
            results[2].values[index],
          ),
      ],
      replacedAt: [
        for (var index = 0; index < values.length; index++)
          results.any((result) => result.replacedAt[index]),
      ],
      retainedAt: [
        for (var index = 0; index < values.length; index++)
          results.any((result) => result.retainedAt[index]),
      ],
    );
  }

  _ScalarHampelResult _hampel(List<double> values, double minimumMad) {
    final candidates = List<bool>.filled(values.length, false);
    final medians = List<double>.filled(values.length, 0);
    for (var index = 0; index < values.length; index++) {
      final start = math.max(0, index - config.hampelHalfWindowSamples);
      final end =
          math.min(values.length, index + config.hampelHalfWindowSamples + 1);
      final window = values.sublist(start, end);
      final median = _median(window);
      final mad = _median([
        for (final value in window) (value - median).abs(),
      ]);
      medians[index] = median;
      final robustScale = math.max(1.4826 * mad, minimumMad);
      candidates[index] = (values[index] - median).abs() >
          config.hampelThresholdMad * robustScale;
    }
    final output = values.toList();
    final replacedAt = List<bool>.filled(values.length, false);
    final retainedAt = List<bool>.filled(values.length, false);
    var start = 0;
    while (start < candidates.length) {
      if (!candidates[start]) {
        start++;
        continue;
      }
      var end = start + 1;
      while (end < candidates.length && candidates[end]) {
        end++;
      }
      final length = end - start;
      if (length <= config.maximumOutlierRunSamples) {
        for (var index = start; index < end; index++) {
          output[index] = medians[index];
          replacedAt[index] = true;
        }
      } else {
        for (var index = start; index < end; index++) {
          retainedAt[index] = true;
        }
      }
      start = end;
    }
    return _ScalarHampelResult(
      values: output,
      replacedAt: replacedAt,
      retainedAt: retainedAt,
    );
  }

  List<Vector3> _filterVectors(
    List<Vector3> values,
    double cutoffHz,
    double samplingRateHz,
  ) {
    final x = _zeroPhaseButterworth(
      [for (final value in values) value.x],
      cutoffHz,
      samplingRateHz,
    );
    final y = _zeroPhaseButterworth(
      [for (final value in values) value.y],
      cutoffHz,
      samplingRateHz,
    );
    final z = _zeroPhaseButterworth(
      [for (final value in values) value.z],
      cutoffHz,
      samplingRateHz,
    );
    return [
      for (var index = 0; index < values.length; index++)
        Vector3(x[index], y[index], z[index]),
    ];
  }

  List<double> _zeroPhaseButterworth(
    List<double> values,
    double cutoffHz,
    double samplingRateHz,
  ) {
    // Q values are the two pole pairs of a normalized fourth-order
    // Butterworth response. Forward/backward application removes phase lag.
    const qValues = [0.541196100146197, 1.306562964876377];
    final padding = math.min(12, values.length - 1);
    var working = <double>[
      for (var i = 0; i < padding; i++) values.first,
      ...values,
      for (var i = 0; i < padding; i++) values.last,
    ];
    for (final q in qValues) {
      working = _biquadLowPass(working, cutoffHz, samplingRateHz, q);
    }
    working = working.reversed.toList();
    for (final q in qValues) {
      working = _biquadLowPass(working, cutoffHz, samplingRateHz, q);
    }
    working = working.reversed.toList();
    return working.sublist(padding, padding + values.length);
  }

  List<double> _biquadLowPass(
    List<double> input,
    double cutoffHz,
    double samplingRateHz,
    double q,
  ) {
    final omega = 2 * math.pi * cutoffHz / samplingRateHz;
    final cosine = math.cos(omega);
    final alpha = math.sin(omega) / (2 * q);
    final a0 = 1 + alpha;
    final b0 = (1 - cosine) / 2 / a0;
    final b1 = (1 - cosine) / a0;
    final b2 = b0;
    final a1 = -2 * cosine / a0;
    final a2 = (1 - alpha) / a0;
    var x1 = input.first;
    var x2 = input.first;
    var y1 = input.first;
    var y2 = input.first;
    final output = <double>[];
    for (final x0 in input) {
      final y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      output.add(y0);
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
    }
    return output;
  }

  void _validateConfig(double samplingRateHz) {
    final nyquist = samplingRateHz / 2;
    final finitePositive = [
      samplingRateHz,
      config.lowPassCutoffHz,
      config.gravityCutoffHz,
      config.hampelThresholdMad,
      config.minimumAccelerationMadMps2,
      config.minimumAngularVelocityMadRadPerSecond,
      config.orientationWindowSeconds,
      config.orientationMaximumGyroRmsRadPerSecond,
      config.orientationMaximumGravityDeviationMps2,
      config.standardGravityMps2,
    ];
    if (finitePositive.any((value) => !value.isFinite || value <= 0) ||
        config.lowPassCutoffHz >= nyquist ||
        config.gravityCutoffHz >= config.lowPassCutoffHz ||
        config.butterworthOrder != 4 ||
        config.hampelHalfWindowSamples < 1 ||
        config.maximumOutlierRunSamples < 1 ||
        config.minimumSegmentSamples < 4 ||
        config.comparisonMovingAverageWindowSamples < 1 ||
        config.comparisonMovingAverageWindowSamples.isEven ||
        !config.minimumEventPeakRetention.isFinite ||
        config.minimumEventPeakRetention < 0 ||
        config.minimumEventPeakRetention > 1) {
      throw ArgumentError('Ungültige IMU-Vorverarbeitungskonfiguration.');
    }
  }

  bool _validFrameTimes(List<ReconstructedTimeFrame> frames) {
    for (var index = 0; index < frames.length; index++) {
      final time = frames[index].analysisTimeSeconds;
      if (!time.isFinite ||
          index > 0 && time <= frames[index - 1].analysisTimeSeconds) {
        return false;
      }
      for (final value in frames[index].values.values) {
        if (value != null &&
            (!_finiteVector(value.accelerationMps2) ||
                !_finiteVector(value.angularVelocityRadPerSecond) ||
                value.magneticFieldMicrotesla != null &&
                    !_finiteVector(value.magneticFieldMicrotesla!))) {
          return false;
        }
      }
    }
    return true;
  }

  ImuPreprocessingResult _failed(
    double samplingRateHz,
    List<PreprocessingIssue> issues,
    String code,
    String observation, {
    Map<String, SensorPreprocessingQuality> qualities = const {},
  }) {
    issues.add(
      PreprocessingIssue(
        code: code,
        observation: observation,
        uncertainty: 'Vorverarbeitungsergebnisse wären nicht belastbar.',
        recommendation: 'Vorgelagerte Daten- und Zeitbasisprüfung korrigieren.',
      ),
    );
    return ImuPreprocessingResult(
      status: PreprocessingStatus.notPossible,
      gridSamplingRateHz: samplingRateHz,
      frames: const [],
      sensorQuality: qualities,
      issues: issues,
      config: config,
      assumptions: _assumptions,
    );
  }

  List<String> get _assumptions => const [
        'Die Eingabe ist das unveränderte Ergebnis der separaten '
            'indexbasierten Zeitrekonstruktion.',
        'Filter werden nur innerhalb lückenloser Segmente und niemals über '
            'fehlende Werte hinweg angewendet.',
        'Der Hampel-Schritt ersetzt ausschließlich kurze statistische '
            'Spitzenkandidaten; längere Ereignisse bleiben erhalten.',
        'Vorwärts-/Rückwärtsfilterung ist nullphasig, aber nicht kausal und '
            'daher für Offline-Analyse bestimmt.',
        'Die Schwerkraftausrichtung bestimmt Roll und Pitch. Yaw sowie '
            'anatomische Vorwärts-/Seitwärtszeichen bleiben ohne gerichtete '
            'Kalibrierung unbestimmt.',
        'Gravitations- und Bewegungsanteil sind filterbasierte technische '
            'Schätzungen, keine direkt getrennt gemessenen Größen.',
        'Qualitätswerte und Schwellen sind technische Prüfgrößen und keine '
            'medizinischen oder physiologischen Referenzbereiche.',
      ];
}

class _SensorResult {
  const _SensorResult({
    required this.values,
    required this.quality,
    required this.reviewRequired,
  });

  final List<PreprocessedImuValue?> values;
  final SensorPreprocessingQuality quality;
  final bool reviewRequired;
}

class _Segment {
  const _Segment(this.start, this.end);

  final int start;
  final int end;
  int get length => end - start;
}

class _HampelResult {
  const _HampelResult({
    required this.values,
    required this.replacedAt,
    required this.retainedAt,
  });

  final List<Vector3> values;
  final List<bool> replacedAt;
  final List<bool> retainedAt;
}

class _ScalarHampelResult {
  const _ScalarHampelResult({
    required this.values,
    required this.replacedAt,
    required this.retainedAt,
  });

  final List<double> values;
  final List<bool> replacedAt;
  final List<bool> retainedAt;
}

class _OrientationCandidate {
  const _OrientationCandidate({
    required this.start,
    required this.end,
    required this.gravity,
    required this.magnitude,
    required this.residual,
    required this.gyroRms,
    required this.score,
  });

  final int start;
  final int end;
  final Vector3 gravity;
  final double magnitude;
  final double residual;
  final double gyroRms;
  final double score;
}

List<_Segment> _continuousSegments(List<ResampledImuValue?> values) {
  final segments = <_Segment>[];
  var start = 0;
  while (start < values.length) {
    while (start < values.length && values[start] == null) {
      start++;
    }
    if (start >= values.length) break;
    var end = start + 1;
    while (end < values.length && values[end] != null) {
      end++;
    }
    segments.add(_Segment(start, end));
    start = end;
  }
  return segments;
}

List<_Segment> _continuousVectorSegments(List<Vector3?> values) {
  final segments = <_Segment>[];
  var start = 0;
  while (start < values.length) {
    while (start < values.length && values[start] == null) {
      start++;
    }
    if (start >= values.length) break;
    var end = start + 1;
    while (end < values.length && values[end] != null) {
      end++;
    }
    segments.add(_Segment(start, end));
    start = end;
  }
  return segments;
}

double _median(List<double> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _magnitude(Vector3 value) => math.sqrt(value.magnitudeSquared);

Vector3 _meanVector(List<Vector3> values) => Vector3(
      values.map((value) => value.x).reduce((a, b) => a + b) / values.length,
      values.map((value) => value.y).reduce((a, b) => a + b) / values.length,
      values.map((value) => value.z).reduce((a, b) => a + b) / values.length,
    );

Vector3 _subtract(Vector3 a, Vector3 b) =>
    Vector3(a.x - b.x, a.y - b.y, a.z - b.z);

bool _finiteVector(Vector3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;

List<double> _rotationToPositiveZ(Vector3 gravity) {
  final magnitude = _magnitude(gravity);
  final x = gravity.x / magnitude;
  final y = gravity.y / magnitude;
  final z = gravity.z / magnitude;
  if (z > 1 - 1e-12) {
    return const [1, 0, 0, 0, 1, 0, 0, 0, 1];
  }
  if (z < -1 + 1e-12) {
    return const [1, 0, 0, 0, -1, 0, 0, 0, -1];
  }
  // Rodrigues rotation from unit g=(x,y,z) to k=(0,0,1).
  final vx = y;
  final vy = -x;
  final c = z;
  final factor = 1 / (1 + c);
  return [
    c + vx * vx * factor,
    vx * vy * factor,
    vy,
    vy * vx * factor,
    c + vy * vy * factor,
    -vx,
    -vy,
    vx,
    c,
  ];
}

Vector3 _rotate(Vector3 value, List<double> r) => Vector3(
      r[0] * value.x + r[1] * value.y + r[2] * value.z,
      r[3] * value.x + r[4] * value.y + r[5] * value.z,
      r[6] * value.x + r[7] * value.y + r[8] * value.z,
    );

List<double> _movingAverage(List<double> values, int window) {
  final half = window ~/ 2;
  return [
    for (var index = 0; index < values.length; index++)
      (() {
        final start = math.max(0, index - half);
        final end = math.min(values.length, index + half + 1);
        return values.sublist(start, end).reduce((a, b) => a + b) /
            (end - start);
      })(),
  ];
}

double _range(List<double> values) =>
    values.reduce(math.max) - values.reduce(math.min);

double _differenceRms(List<double> values) {
  if (values.length < 2) return 0;
  var sum = 0.0;
  for (var index = 1; index < values.length; index++) {
    final difference = values[index] - values[index - 1];
    sum += difference * difference;
  }
  return math.sqrt(sum / (values.length - 1));
}

int _maximumDeviationIndex(List<double> values, double center) {
  var bestIndex = 0;
  var best = -1.0;
  for (var index = 0; index < values.length; index++) {
    final deviation = (values[index] - center).abs();
    if (deviation > best) {
      best = deviation;
      bestIndex = index;
    }
  }
  return bestIndex;
}
