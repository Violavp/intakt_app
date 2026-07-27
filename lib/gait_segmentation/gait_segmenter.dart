import 'dart:math' as math;

import '../imu_preprocessing/imu_preprocessing.dart';
import 'gait_segmentation_models.dart';

/// Offline segmentation of preprocessed four-leg IMU data.
///
/// A sliding window estimates movement RMS and the dominant vertical movement
/// frequency of each leg. Classification is deliberately separated from
/// preprocessing and does not modify any input or raw-source reference.
class GaitSegmenter {
  const GaitSegmenter({this.config = const GaitSegmentationConfig()});

  final GaitSegmentationConfig config;

  static const assumptions = [
    'analysis_time_s is the video-linked time produced by time reconstruction',
    'vertical movement acceleration is comparable after gravity alignment',
    'enabled movement gaits come from the documented recording protocol; '
        'disabled gaits are never inferred',
    'movement gaits are ordered by recording-internal signal-frequency '
        'clusters, not by physiological reference ranges',
    'gait remains frequency-based; AngleZ is used only for recording-calibrated '
        'line direction, signed bending rate and direction-change candidates',
    'positive AngleZ trend means left and negative trend means right for the '
        'confirmed test01 mounting; every new mounting requires validation',
    'confidence is a technical signal-quality score, not a probability of a '
        'medical or biomechanical diagnosis',
  ];

  GaitSegmentationResult segment(
    ImuPreprocessingResult input, {
    List<ManualSegmentCorrection> corrections = const [],
  }) {
    _validateConfig();
    _validateCorrections(corrections);
    final issues = <SegmentationIssue>[];
    if (!input.hasDataset || input.frames.isEmpty) {
      return _failed(
        issues,
        corrections,
        'missing_preprocessed_dataset',
        'Es liegt kein freigegebener Vorverarbeitungsdatensatz vor.',
      );
    }
    if (!input.gridSamplingRateHz.isFinite || input.gridSamplingRateHz <= 0) {
      return _failed(
        issues,
        corrections,
        'invalid_sampling_rate',
        'Die Raster-Abtastrate ist nicht endlich oder nicht positiv.',
      );
    }
    if (!_validTimes(input.frames)) {
      return _failed(
        issues,
        corrections,
        'invalid_frame_times',
        'Analysezeiten sind nicht endlich oder nicht streng steigend.',
      );
    }
    _validateCorrectionCoverage(corrections, input.frames);
    final labels = input.frames.first.values.keys.toSet();
    final missing = config.requiredLegLabels
        .where((label) => !labels.contains(label))
        .toList();
    if (missing.isNotEmpty) {
      return _failed(
        issues,
        corrections,
        'missing_required_leg_sensors',
        'Pflichtsensoren fehlen: ${missing.join(', ')}.',
      );
    }
    final labelsWithoutValues = config.requiredLegLabels
        .where(
          (label) => !input.frames.any((frame) => frame.values[label] != null),
        )
        .toList();
    if (labelsWithoutValues.isNotEmpty) {
      return _failed(
        issues,
        corrections,
        'missing_required_leg_signal',
        'Pflichtsensoren enthalten keine Werte: '
            '${labelsWithoutValues.join(', ')}.',
      );
    }
    if (!_finiteSignals(input.frames)) {
      return _failed(
        issues,
        corrections,
        'non_finite_signal',
        'Mindestens ein vorhandener Vorverarbeitungswert enthält NaN oder '
            'Infinity.',
      );
    }

    final duration = input.frames.last.analysisTimeSeconds -
        input.frames.first.analysisTimeSeconds;
    if (duration < config.windowSeconds) {
      return _failed(
        issues,
        corrections,
        'recording_too_short',
        'Die Aufnahme ist kürzer als das konfigurierte Analysefenster.',
      );
    }

    var reviewRequired = input.status == PreprocessingStatus.reviewRequired;
    if (reviewRequired) {
      issues.add(
        const SegmentationIssue(
          code: 'upstream_preprocessing_review_required',
          observation: 'Die Vorverarbeitung verlangt manuelle Prüfung.',
          uncertainty:
              'Zeit- oder Filterunsicherheit wirkt auf die Segmentgrenzen.',
          recommendation: 'Vorverarbeitungsbericht zusammen mit Video prüfen.',
        ),
      );
    }
    final missingAngles = config.requiredLegLabels
        .where(
          (label) => !input.frames.any(
            (frame) =>
                frame.values[label]?.raw.orientationAnglesDegrees != null,
          ),
        )
        .toList();
    if (missingAngles.isNotEmpty) {
      reviewRequired = true;
      issues.add(
        SegmentationIssue(
          code: 'leg_orientation_angles_missing',
          observation: 'AngleX/Y/Z fehlen für: ${missingAngles.join(', ')}.',
          uncertainty: 'Gangart bleibt frequenzbasiert bestimmbar; Richtung, '
              'Biegungsrate und Richtungswechsel bleiben ungültig.',
          recommendation: 'Vollständige AngleX/Y/Z-Kanäle der vier '
              'Beinsensoren bereitstellen.',
        ),
      );
    }

    final decisions = _classifyWindows(input);
    final gaitClusters = _assignMovementGaits(decisions);
    if (gaitClusters.isEmpty && config.enabledMovementGaits.isNotEmpty) {
      reviewRequired = true;
      issues.add(
        const SegmentationIssue(
          code: 'movement_gait_clusters_not_separable',
          observation:
              'Die erwarteten Bewegungsgruppen konnten in dieser Aufnahme '
              'nicht stabil getrennt werden.',
          uncertainty:
              'Eine Gangartzuordnung aus der aufnahmeinternen Frequenzstruktur '
              'ist nicht belastbar.',
          recommendation:
              'Bewegungsabschnitte im Video prüfen und keine fehlende '
              'Gangartgruppe erzwingen.',
        ),
      );
    }
    _applyTemporalGaitBlocks(decisions);
    _stabilizeGaits(decisions);
    _stabilizeDirections(decisions);
    _applyCorrections(decisions, corrections);
    _markTransitions(decisions);
    _markInterruptions(decisions);
    _markDirectionChanges(decisions);
    _applyCorrectionFlags(decisions, corrections);
    final segments = _merge(decisions);

    if (segments.any((segment) => segment.gait == GaitLabel.unknown)) {
      reviewRequired = true;
      issues.add(
        const SegmentationIssue(
          code: 'uncertain_gait_windows',
          observation: 'Mindestens ein Bewegungsfenster konnte keiner Gangart '
              'hinreichend sicher zugeordnet werden.',
          uncertainty: 'Frequenzband oder Periodizität war nicht eindeutig.',
          recommendation:
              'UNKNOWN-Abschnitte im Video prüfen und begründet korrigieren '
              'oder von der Analyse ausschließen.',
        ),
      );
    }
    if (corrections.isNotEmpty) {
      reviewRequired = true;
      issues.add(
        const SegmentationIssue(
          code: 'manual_corrections_applied',
          observation: 'Begründete manuelle Segmentkorrekturen sind aktiv.',
          uncertainty:
              'Die automatische Klassifikationsunsicherheit bleibt erhalten.',
          recommendation:
              'Korrekturintervalle und Begründungen im Video gegenprüfen.',
        ),
      );
    }
    if (!segments.any((segment) => segment.analyzable)) {
      reviewRequired = true;
      issues.add(
        const SegmentationIssue(
          code: 'no_analyzable_segments',
          observation:
              'Kein Abschnitt erfüllt alle technischen Auswahlkriterien.',
          uncertainty:
              'Eine nachgelagerte Ganganalyse wäre für diese Aufnahme nicht '
              'belastbar.',
          recommendation:
              'Video, Schwellenkonfiguration und Datenqualität prüfen; keine '
              'Ersatzabschnitte erzeugen.',
        ),
      );
    }

    return GaitSegmentationResult(
      status: reviewRequired
          ? SegmentationStatus.reviewRequired
          : SegmentationStatus.accepted,
      segments: segments,
      issues: issues,
      config: config,
      corrections: List.unmodifiable(corrections),
      gaitSignalClusters: gaitClusters,
      assumptions: assumptions,
    );
  }

  List<_WindowDecision> _classifyWindows(ImuPreprocessingResult input) {
    final frames = input.frames;
    final firstTime = frames.first.analysisTimeSeconds;
    final lastTime = frames.last.analysisTimeSeconds;
    final halfWindow = config.windowSeconds / 2;
    final directionHalfWindow = config.directionTrendWindowSeconds / 2;
    final halfStep = config.stepSeconds / 2;
    final output = <_WindowDecision>[];
    var previousMoving = false;
    for (var center = firstTime + halfWindow;
        center <= lastTime - halfWindow + 1e-9;
        center += config.stepSeconds) {
      final contextStart = center - halfWindow;
      final contextEnd = center + halfWindow;
      final window = frames
          .where(
            (frame) =>
                frame.analysisTimeSeconds >= contextStart &&
                frame.analysisTimeSeconds < contextEnd,
          )
          .toList();
      final decisionStart = math.max(firstTime, center - halfStep);
      final decisionEnd = math.min(lastTime, center + halfStep);
      final decisionFrames = frames
          .where(
            (frame) =>
                frame.analysisTimeSeconds >= decisionStart &&
                frame.analysisTimeSeconds < decisionEnd,
          )
          .toList();
      final expected = math.max(
        1,
        ((decisionEnd - decisionStart) * input.gridSamplingRateHz).round(),
      );
      final availableByLeg = <String, List<PreprocessedImuValue>>{
        for (final label in config.requiredLegLabels)
          label: [
            for (final frame in window)
              if (frame.values[label] != null) frame.values[label]!,
          ],
      };
      final decisionByLeg = <String, List<PreprocessedImuValue>>{
        for (final label in config.requiredLegLabels)
          label: [
            for (final frame in decisionFrames)
              if (frame.values[label] != null) frame.values[label]!,
          ],
      };
      final coverage = decisionByLeg.values
          .map((values) => values.length / expected)
          .reduce(math.min)
          .clamp(0.0, 1.0)
          .toDouble();
      final legRms = {
        for (final entry in decisionByLeg.entries)
          entry.key: _movementRms(entry.value),
      };
      final movementRms =
          legRms.values.reduce((left, right) => left + right) / legRms.length;
      final moving = coverage >= config.minimumWindowCoverage &&
          (previousMoving
              ? movementRms > config.movementOffRmsMps2
              : movementRms >= config.movementOnRmsMps2);
      previousMoving = moving;

      final spectrum = moving
          ? _dominantFrequency(availableByLeg, input.gridSamplingRateHz)
          : null;
      final diagonalSynchrony =
          moving ? _diagonalSynchrony(availableByLeg) : null;
      final gait = moving ? GaitLabel.unknown : GaitLabel.standing;
      final activityConfidence = _activityConfidence(movementRms, moving);
      final confidence =
          (coverage * (moving ? spectrum?.confidence ?? 0 : activityConfidence))
              .clamp(0.0, 1.0)
              .toDouble();
      final directionFrames = frames
          .where(
            (frame) =>
                frame.analysisTimeSeconds >= center - directionHalfWindow &&
                frame.analysisTimeSeconds < center + directionHalfWindow,
          )
          .toList();
      final direction = _directionEstimate(directionFrames);
      final sourceLines = <String, SourceLineRange>{};
      for (final label in labelsForTrace(input)) {
        final values = [
          for (final frame in window)
            if (frame.values[label] != null) frame.values[label]!,
        ];
        if (values.isEmpty) continue;
        sourceLines[label] = SourceLineRange(
          values.map((value) => value.raw.lowerSourceLine).reduce(math.min),
          values.map((value) => value.raw.upperSourceLine).reduce(math.max),
        );
      }
      output.add(
        _WindowDecision(
          startSeconds: output.isEmpty ? firstTime : decisionStart,
          endSeconds: decisionEnd,
          gait: gait,
          confidence: confidence,
          spectralConfidence: spectrum?.confidence ?? 0,
          dominantFrequencyHz: spectrum?.frequencyHz,
          diagonalSynchrony: diagonalSynchrony,
          movementRmsMps2: movementRms,
          coverage: coverage,
          turn: false,
          ridingDirection: direction.direction,
          frontAngleZTrendDegreesPerSecond: direction.frontSlope,
          hindAngleZTrendDegreesPerSecond: direction.hindSlope,
          meanAngleZTrendDegreesPerSecond: direction.meanSlope,
          directionConfidence: direction.confidence,
          sourceLines: sourceLines,
        ),
      );
    }
    if (output.isNotEmpty) output.last.endSeconds = lastTime;
    return output;
  }

  Iterable<String> labelsForTrace(ImuPreprocessingResult input) sync* {
    yield* config.requiredLegLabels;
  }

  _DirectionEstimate _directionEstimate(List<PreprocessedFrame> frames) {
    final slopes = <String, double>{};
    for (final label in config.requiredLegLabels) {
      final slope = _angleZTrend(frames, label);
      if (slope != null) slopes[label] = slope;
    }
    final front = _meanNullable([
      slopes['VL'],
      slopes['VR'],
    ]);
    final hind = _meanNullable([
      slopes['HL'],
      slopes['HR'],
    ]);
    final positive = slopes.values
        .where(
          (value) => value >= config.minimumDirectionSlopeDegreesPerSecond,
        )
        .toList();
    final negative = slopes.values
        .where(
          (value) => value <= -config.minimumDirectionSlopeDegreesPerSecond,
        )
        .toList();
    final supporting = positive.length >= negative.length ? positive : negative;
    final enough = supporting.length >= config.minimumDirectionAgreementSensors;
    final direction = !enough
        ? RidingDirection.unknown
        : positive.length >= negative.length
            ? config.positiveAngleZDirection
            : _oppositeDirection(config.positiveAngleZDirection);
    return _DirectionEstimate(
      direction: direction,
      frontSlope: front,
      hindSlope: hind,
      meanSlope: enough ? _mean(supporting) : null,
      confidence: slopes.isEmpty
          ? null
          : supporting.length / config.requiredLegLabels.length,
    );
  }

  double? _angleZTrend(List<PreprocessedFrame> frames, String label) {
    final points = <(double, double)>[];
    double? previousWrapped;
    var offset = 0.0;
    for (final frame in frames) {
      final wrapped = frame.values[label]?.raw.orientationAnglesDegrees?.z;
      if (wrapped == null || !wrapped.isFinite) continue;
      if (previousWrapped != null) {
        final difference = wrapped - previousWrapped;
        if (difference > 180) offset -= 360;
        if (difference < -180) offset += 360;
      }
      points.add((frame.analysisTimeSeconds, wrapped + offset));
      previousWrapped = wrapped;
    }
    if (points.length < 3) return null;
    final meanTime = _mean(points.map((point) => point.$1));
    final meanAngle = _mean(points.map((point) => point.$2));
    var numerator = 0.0;
    var denominator = 0.0;
    for (final point in points) {
      final deltaTime = point.$1 - meanTime;
      numerator += deltaTime * (point.$2 - meanAngle);
      denominator += deltaTime * deltaTime;
    }
    if (denominator == 0) return null;
    final slope = numerator / denominator;
    return slope.isFinite ? slope : null;
  }

  RidingDirection _oppositeDirection(RidingDirection direction) =>
      switch (direction) {
        RidingDirection.left => RidingDirection.right,
        RidingDirection.right => RidingDirection.left,
        RidingDirection.unknown => RidingDirection.unknown,
      };

  _SpectrumPeak? _dominantFrequency(
    Map<String, List<PreprocessedImuValue>> valuesByLeg,
    double samplingRateHz,
  ) {
    var bestFrequency = 0.0;
    var bestPower = 0.0;
    var totalPower = 0.0;
    var frequencyCount = 0;
    for (var frequency = config.minimumFrequencyHz;
        frequency <= config.maximumFrequencyHz + 1e-9;
        frequency += config.frequencyResolutionHz) {
      var power = 0.0;
      for (final values in valuesByLeg.values) {
        if (values.length < 3) continue;
        final mean = values
                .map((value) => value.movementAccelerationMps2.z)
                .reduce((left, right) => left + right) /
            values.length;
        var real = 0.0;
        var imaginary = 0.0;
        for (var index = 0; index < values.length; index++) {
          final centered = values[index].movementAccelerationMps2.z - mean;
          final angle = 2 * math.pi * frequency * index / samplingRateHz;
          real += centered * math.cos(angle);
          imaginary -= centered * math.sin(angle);
        }
        power += (real * real + imaginary * imaginary) /
            (values.length * values.length);
      }
      totalPower += power;
      frequencyCount++;
      if (power > bestPower) {
        bestPower = power;
        bestFrequency = frequency;
      }
    }
    if (totalPower <= 0 || !totalPower.isFinite || frequencyCount < 2) {
      return null;
    }
    final backgroundPower = (totalPower - bestPower) / (frequencyCount - 1);
    final contrastDenominator = bestPower + backgroundPower;
    final confidence = contrastDenominator == 0
        ? 0.0
        : (bestPower - backgroundPower) / contrastDenominator;
    return _SpectrumPeak(bestFrequency, confidence.clamp(0.0, 1.0).toDouble());
  }

  double _activityConfidence(double rms, bool moving) {
    final span = config.movementOnRmsMps2 - config.movementOffRmsMps2;
    if (moving) {
      return (0.5 + 0.5 * (rms - config.movementOnRmsMps2) / span)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    return (0.5 +
            0.5 * (config.movementOffRmsMps2 - rms) / config.movementOffRmsMps2)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  List<GaitSignalCluster> _assignMovementGaits(
    List<_WindowDecision> windows,
  ) {
    final candidates = windows
        .where(
          (window) =>
              window.gait == GaitLabel.unknown &&
              _clusterValue(window) != null &&
              (config.gaitClusteringFeature !=
                      GaitClusteringFeature.frequency ||
                  window.spectralConfidence >=
                      config.minimumSpectralConfidence),
        )
        .toList();
    final gaitCount = config.enabledMovementGaits.length;
    if (gaitCount == 0 || candidates.length < gaitCount) return const [];
    if (gaitCount == 1) {
      for (final window in candidates) {
        window.gait = config.enabledMovementGaits.first;
      }
      return [
        GaitSignalCluster(
          gait: config.enabledMovementGaits.first,
          feature: config.gaitClusteringFeature,
          centroid: _mean(candidates.map((window) => _clusterValue(window)!)),
          windowCount: candidates.length,
        ),
      ];
    }

    final sortedFrequencies =
        candidates.map((window) => _clusterValue(window)!).toList()..sort();
    var centers = [
      for (var index = 0; index < gaitCount; index++)
        sortedFrequencies[
            (((index + 0.5) / gaitCount) * (sortedFrequencies.length - 1))
                .round()],
    ];
    var assignments = List<int>.filled(candidates.length, 0);
    for (var iteration = 0; iteration < 30; iteration++) {
      assignments = [
        for (final window in candidates)
          _nearestCenter(_clusterValue(window)!, centers),
      ];
      final updated = [...centers];
      for (var cluster = 0; cluster < gaitCount; cluster++) {
        final values = [
          for (var index = 0; index < candidates.length; index++)
            if (assignments[index] == cluster)
              _clusterValue(candidates[index])!,
        ];
        if (values.isNotEmpty) updated[cluster] = _mean(values);
      }
      updated.sort();
      if (_maxCenterChange(centers, updated) < 1e-9) {
        centers = updated;
        break;
      }
      centers = updated;
    }
    assignments = [
      for (final window in candidates)
        _nearestCenter(_clusterValue(window)!, centers),
    ];
    final counts = [
      for (var cluster = 0; cluster < gaitCount; cluster++)
        assignments.where((value) => value == cluster).length,
    ];
    final separated = [
      for (var index = 1; index < centers.length; index++)
        centers[index] - centers[index - 1],
    ].every(
      (distance) => distance >= config.minimumClusterSeparation,
    );
    if (!separated ||
        counts.any((count) => count < config.minimumClusterWindows)) {
      return const [];
    }

    for (var index = 0; index < candidates.length; index++) {
      final window = candidates[index];
      final ownCluster = assignments[index];
      window.gait = config.enabledMovementGaits[ownCluster];
      final distances = [
        for (final center in centers) (_clusterValue(window)! - center).abs(),
      ]..sort();
      final margin = distances.length < 2
          ? 1.0
          : ((distances[1] - distances[0]) /
                  (distances[1] + distances[0] + 1e-12))
              .clamp(0.0, 1.0)
              .toDouble();
      final signalConfidence =
          config.gaitClusteringFeature == GaitClusteringFeature.frequency
              ? window.spectralConfidence
              : 1.0;
      window.confidence =
          (window.coverage * (0.6 * signalConfidence + 0.4 * margin))
              .clamp(0.0, 1.0)
              .toDouble();
    }
    return [
      for (var index = 0; index < gaitCount; index++)
        GaitSignalCluster(
          gait: config.enabledMovementGaits[index],
          feature: config.gaitClusteringFeature,
          centroid: centers[index],
          windowCount: counts[index],
        ),
    ];
  }

  double? _clusterValue(_WindowDecision window) {
    return switch (config.gaitClusteringFeature) {
      GaitClusteringFeature.diagonalSynchrony => window.diagonalSynchrony,
      GaitClusteringFeature.frequency => window.dominantFrequencyHz,
    };
  }

  void _applyTemporalGaitBlocks(List<_WindowDecision> windows) {
    _removeShortMovementBouts(windows);
    if (!config.enforceConfiguredGaitOrder) return;

    int? currentGaitIndex;
    var index = 0;
    while (index < windows.length) {
      final gait = windows[index].gait;
      var end = index + 1;
      while (end < windows.length && windows[end].gait == gait) {
        end++;
      }
      final duration =
          windows[end - 1].endSeconds - windows[index].startSeconds;
      if (gait == GaitLabel.standing) {
        if (duration >= config.gaitOrderResetStandingSeconds) {
          currentGaitIndex = null;
        }
        index = end;
        continue;
      }
      final gaitIndex = config.enabledMovementGaits.indexOf(gait);
      if (gaitIndex < 0) {
        index = end;
        continue;
      }
      final windowCount = end - index;
      if (currentGaitIndex == null) {
        if (windowCount >= config.minimumGaitAdvanceWindows) {
          currentGaitIndex = gaitIndex;
        } else {
          _markUnknown(windows, index, end);
        }
      } else if (gaitIndex < currentGaitIndex) {
        _markUnknown(windows, index, end);
      } else if (gaitIndex > currentGaitIndex) {
        if (windowCount >= config.minimumGaitAdvanceWindows) {
          currentGaitIndex = gaitIndex;
        } else {
          _markUnknown(windows, index, end);
        }
      }
      index = end;
    }
  }

  void _removeShortMovementBouts(List<_WindowDecision> windows) {
    var index = 0;
    while (index < windows.length) {
      if (windows[index].gait == GaitLabel.standing) {
        index++;
        continue;
      }
      var end = index + 1;
      while (end < windows.length && windows[end].gait != GaitLabel.standing) {
        end++;
      }
      final duration =
          windows[end - 1].endSeconds - windows[index].startSeconds;
      if (duration < config.minimumMovementBoutSeconds) {
        _markUnknown(windows, index, end);
      }
      index = end;
    }
  }

  void _markUnknown(
    List<_WindowDecision> windows,
    int start,
    int end,
  ) {
    for (var index = start; index < end; index++) {
      windows[index].gait = GaitLabel.unknown;
      windows[index].confidence = math.min(windows[index].confidence, 0.49);
    }
  }

  void _stabilizeGaits(List<_WindowDecision> windows) {
    if (config.minimumStableWindows <= 1 || windows.length < 3) return;
    var start = 0;
    while (start < windows.length) {
      var end = start + 1;
      while (end < windows.length && windows[end].gait == windows[start].gait) {
        end++;
      }
      final length = end - start;
      if (length < config.minimumStableWindows &&
          windows[start].gait != GaitLabel.standing &&
          start > 0 &&
          end < windows.length &&
          windows[start - 1].gait == windows[end].gait) {
        for (var index = start; index < end; index++) {
          windows[index].gait = windows[start - 1].gait;
          windows[index].confidence = math.min(windows[index].confidence, 0.5);
        }
      }
      start = end;
    }
  }

  void _stabilizeDirections(List<_WindowDecision> windows) {
    var start = 0;
    while (start < windows.length) {
      final direction = windows[start].ridingDirection;
      var end = start + 1;
      while (
          end < windows.length && windows[end].ridingDirection == direction) {
        end++;
      }
      if (direction != RidingDirection.unknown &&
          end - start < config.directionChangeConfirmationWindows) {
        for (var index = start; index < end; index++) {
          windows[index].ridingDirection = RidingDirection.unknown;
        }
      }
      start = end;
    }
  }

  void _applyCorrections(
    List<_WindowDecision> windows,
    List<ManualSegmentCorrection> corrections,
  ) {
    for (final correction in corrections) {
      for (final window in windows) {
        final midpoint = (window.startSeconds + window.endSeconds) / 2;
        if (midpoint < correction.startSeconds ||
            midpoint >= correction.endSeconds) {
          continue;
        }
        if (correction.gait != null) window.gait = correction.gait!;
        window.manualExclusion = correction.excludeFromAnalysis;
        window.correctionReasons.add(correction.reason);
      }
    }
  }

  void _applyCorrectionFlags(
    List<_WindowDecision> windows,
    List<ManualSegmentCorrection> corrections,
  ) {
    for (final correction in corrections) {
      for (final window in windows) {
        final midpoint = (window.startSeconds + window.endSeconds) / 2;
        if (midpoint < correction.startSeconds ||
            midpoint >= correction.endSeconds) {
          continue;
        }
        if (correction.transition != null) {
          window.transition = correction.transition!;
        }
        if (correction.turn != null) window.turn = correction.turn!;
        if (correction.interruption != null) {
          window.interruption = correction.interruption!;
        }
      }
    }
  }

  void _markTransitions(List<_WindowDecision> windows) {
    for (var index = 0; index < windows.length; index++) {
      final previous = index == 0 ? null : windows[index - 1].gait;
      final next = index == windows.length - 1 ? null : windows[index + 1].gait;
      windows[index].transition =
          (previous != null && previous != windows[index].gait) ||
              (next != null && next != windows[index].gait);
    }
  }

  void _markInterruptions(List<_WindowDecision> windows) {
    var start = 0;
    while (start < windows.length) {
      if (windows[start].gait != GaitLabel.standing) {
        start++;
        continue;
      }
      var end = start + 1;
      while (end < windows.length && windows[end].gait == GaitLabel.standing) {
        end++;
      }
      final duration =
          windows[end - 1].endSeconds - windows[start].startSeconds;
      final boundedByMovement = start > 0 &&
          end < windows.length &&
          _isMovement(windows[start - 1].gait) &&
          _isMovement(windows[end].gait);
      if (boundedByMovement && duration <= config.maximumInterruptionSeconds) {
        for (var index = start; index < end; index++) {
          windows[index].interruption = true;
        }
      }
      start = end;
    }
  }

  void _markDirectionChanges(List<_WindowDecision> windows) {
    RidingDirection? previous;
    int? previousIndex;
    for (var index = 0; index < windows.length; index++) {
      final current = windows[index].ridingDirection;
      if (current == RidingDirection.unknown) continue;
      if (previous != null && current != previous) {
        if (previousIndex != null) windows[previousIndex].turn = true;
        windows[index].turn = true;
      }
      previous = current;
      previousIndex = index;
    }
  }

  List<GaitSegment> _merge(List<_WindowDecision> windows) {
    if (windows.isEmpty) return const [];
    final groups = <List<_WindowDecision>>[];
    var current = <_WindowDecision>[windows.first];
    for (var index = 1; index < windows.length; index++) {
      if (_sameSegment(current.last, windows[index])) {
        current.add(windows[index]);
      } else {
        groups.add(current);
        current = <_WindowDecision>[windows[index]];
      }
    }
    groups.add(current);
    return [for (final group in groups) _segmentFromWindows(group)];
  }

  GaitSegment _segmentFromWindows(List<_WindowDecision> windows) {
    final duration = windows.last.endSeconds - windows.first.startSeconds;
    final gait = windows.first.gait;
    final confidence = _mean(windows.map((window) => window.confidence));
    final coverage = _mean(windows.map((window) => window.coverage));
    final turn = windows.first.turn;
    final transition = windows.first.transition;
    final interruption = windows.first.interruption;
    final manuallyExcluded = windows.any(
      (window) => window.manualExclusion == true,
    );
    final analyzable = _isMovement(gait) &&
        gait != GaitLabel.unknown &&
        duration >= config.minimumAnalyzableSeconds &&
        confidence >= config.minimumAnalyzableConfidence &&
        coverage >= config.minimumWindowCoverage &&
        !turn &&
        !transition &&
        !interruption &&
        !manuallyExcluded;
    final sourceLines = <String, SourceLineRange>{};
    for (final window in windows) {
      for (final entry in window.sourceLines.entries) {
        final existing = sourceLines[entry.key];
        sourceLines[entry.key] = existing == null
            ? entry.value
            : SourceLineRange(
                math.min(existing.first, entry.value.first),
                math.max(existing.last, entry.value.last),
              );
      }
    }
    return GaitSegment(
      startSeconds: windows.first.startSeconds,
      endSeconds: windows.last.endSeconds,
      gait: gait,
      confidence: confidence,
      uncertainty: 1 - confidence,
      dominantFrequencyHz: _meanNullable(
        windows.map((window) => window.dominantFrequencyHz),
      ),
      diagonalSynchrony: _meanNullable(
        windows.map((window) => window.diagonalSynchrony),
      ),
      movementRmsMps2: _mean(windows.map((window) => window.movementRmsMps2)),
      coverage: coverage,
      transition: transition,
      turn: turn,
      interruption: interruption,
      analyzable: analyzable,
      manuallyCorrected: windows.any(
        (window) => window.correctionReasons.isNotEmpty,
      ),
      correctionReasons:
          {for (final window in windows) ...window.correctionReasons}.toList(),
      sourceLines: sourceLines,
      ridingDirection: windows.first.ridingDirection,
      frontAngleZTrendDegreesPerSecond: _meanNullable(
        windows.map(
          (window) => window.frontAngleZTrendDegreesPerSecond,
        ),
      ),
      hindAngleZTrendDegreesPerSecond: _meanNullable(
        windows.map(
          (window) => window.hindAngleZTrendDegreesPerSecond,
        ),
      ),
      meanAngleZTrendDegreesPerSecond: _meanNullable(
        windows.map(
          (window) => window.meanAngleZTrendDegreesPerSecond,
        ),
      ),
      directionConfidence: _meanNullable(
        windows.map((window) => window.directionConfidence),
      ),
    );
  }

  bool _sameSegment(_WindowDecision left, _WindowDecision right) =>
      left.gait == right.gait &&
      left.transition == right.transition &&
      left.turn == right.turn &&
      left.ridingDirection == right.ridingDirection &&
      left.interruption == right.interruption &&
      left.manualExclusion == right.manualExclusion &&
      _listEquals(left.correctionReasons, right.correctionReasons);

  void _validateConfig() {
    final finitePositive = [
      config.windowSeconds,
      config.stepSeconds,
      config.movementOnRmsMps2,
      config.movementOffRmsMps2,
      config.minimumFrequencyHz,
      config.frequencyResolutionHz,
      config.maximumFrequencyHz,
      config.minimumAnalyzableSeconds,
      config.minimumDirectionSlopeDegreesPerSecond,
      config.directionTrendWindowSeconds,
      config.minimumClusterSeparation,
      config.minimumMovementBoutSeconds,
      config.gaitOrderResetStandingSeconds,
    ];
    final finiteNonNegative = [
      config.maximumInterruptionSeconds,
      config.minimumSpectralConfidence,
      config.minimumAnalyzableConfidence,
      config.minimumWindowCoverage,
    ];
    if (finitePositive.any((value) => !value.isFinite || value <= 0) ||
        finiteNonNegative.any((value) => !value.isFinite || value < 0) ||
        config.stepSeconds > config.windowSeconds ||
        config.movementOffRmsMps2 >= config.movementOnRmsMps2 ||
        config.minimumFrequencyHz >= config.maximumFrequencyHz ||
        config.minimumWindowCoverage <= 0 ||
        config.minimumWindowCoverage > 1 ||
        config.minimumSpectralConfidence < 0 ||
        config.minimumSpectralConfidence > 1 ||
        config.minimumAnalyzableConfidence < 0 ||
        config.minimumAnalyzableConfidence > 1 ||
        config.minimumClusterWindows < 1 ||
        config.minimumGaitAdvanceWindows < 1 ||
        config.minimumStableWindows < 1 ||
        config.minimumDirectionAgreementSensors < 2 ||
        config.minimumDirectionAgreementSensors >
            config.requiredLegLabels.length ||
        config.directionChangeConfirmationWindows < 1 ||
        config.enabledMovementGaits.isEmpty ||
        config.enabledMovementGaits.length > 3 ||
        config.enabledMovementGaits.toSet().length !=
            config.enabledMovementGaits.length ||
        config.enabledMovementGaits.any(
          (gait) => gait == GaitLabel.standing || gait == GaitLabel.unknown,
        ) ||
        !_gaitsInAscendingOrder(config.enabledMovementGaits) ||
        config.requiredLegLabels.length != 4 ||
        config.requiredLegLabels.toSet().length != 4) {
      throw ArgumentError('Ungültige Segmentierungskonfiguration.');
    }
  }

  void _validateCorrections(List<ManualSegmentCorrection> corrections) {
    final sorted = [...corrections]
      ..sort((left, right) => left.startSeconds.compareTo(right.startSeconds));
    for (var index = 0; index < sorted.length; index++) {
      final correction = sorted[index];
      if (!correction.startSeconds.isFinite ||
          !correction.endSeconds.isFinite ||
          correction.endSeconds <= correction.startSeconds ||
          (index > 0 &&
              correction.startSeconds < sorted[index - 1].endSeconds)) {
        throw ArgumentError(
          'Korrekturintervalle müssen endlich, vorwärts und überlappungsfrei '
          'sein.',
        );
      }
    }
  }

  void _validateCorrectionCoverage(
    List<ManualSegmentCorrection> corrections,
    List<PreprocessedFrame> frames,
  ) {
    for (final correction in corrections) {
      if (correction.endSeconds <= frames.first.analysisTimeSeconds ||
          correction.startSeconds >= frames.last.analysisTimeSeconds) {
        throw ArgumentError(
          'Korrekturintervall ${correction.startSeconds}–'
          '${correction.endSeconds} s liegt außerhalb der Aufnahme.',
        );
      }
    }
  }

  GaitSegmentationResult _failed(
    List<SegmentationIssue> issues,
    List<ManualSegmentCorrection> corrections,
    String code,
    String observation,
  ) {
    issues.add(
      SegmentationIssue(
        code: code,
        observation: observation,
        uncertainty: 'Keine belastbare Gangartsegmentierung möglich.',
        recommendation:
            'Eingabedaten und vorgelagerte Qualitätsberichte prüfen.',
      ),
    );
    return GaitSegmentationResult(
      status: SegmentationStatus.notPossible,
      segments: const [],
      issues: issues,
      config: config,
      corrections: List.unmodifiable(corrections),
      gaitSignalClusters: const [],
      assumptions: assumptions,
    );
  }
}

class _WindowDecision {
  _WindowDecision({
    required this.startSeconds,
    required this.endSeconds,
    required this.gait,
    required this.confidence,
    required this.spectralConfidence,
    required this.dominantFrequencyHz,
    required this.diagonalSynchrony,
    required this.movementRmsMps2,
    required this.coverage,
    required this.turn,
    required this.sourceLines,
    required this.ridingDirection,
    required this.frontAngleZTrendDegreesPerSecond,
    required this.hindAngleZTrendDegreesPerSecond,
    required this.meanAngleZTrendDegreesPerSecond,
    required this.directionConfidence,
  });

  final double startSeconds;
  double endSeconds;
  GaitLabel gait;
  double confidence;
  final double spectralConfidence;
  final double? dominantFrequencyHz;
  final double? diagonalSynchrony;
  final double movementRmsMps2;
  final double coverage;
  bool transition = false;
  bool turn;
  RidingDirection ridingDirection;
  final double? frontAngleZTrendDegreesPerSecond;
  final double? hindAngleZTrendDegreesPerSecond;
  final double? meanAngleZTrendDegreesPerSecond;
  final double? directionConfidence;
  bool interruption = false;
  bool? manualExclusion;
  final List<String> correctionReasons = [];
  final Map<String, SourceLineRange> sourceLines;
}

class _DirectionEstimate {
  const _DirectionEstimate({
    required this.direction,
    required this.frontSlope,
    required this.hindSlope,
    required this.meanSlope,
    required this.confidence,
  });

  final RidingDirection direction;
  final double? frontSlope;
  final double? hindSlope;
  final double? meanSlope;
  final double? confidence;
}

class _SpectrumPeak {
  const _SpectrumPeak(this.frequencyHz, this.confidence);

  final double frequencyHz;
  final double confidence;
}

double? _diagonalSynchrony(
  Map<String, List<PreprocessedImuValue>> valuesByLeg,
) {
  final vl = valuesByLeg['VL'];
  final vr = valuesByLeg['VR'];
  final hl = valuesByLeg['HL'];
  final hr = valuesByLeg['HR'];
  if (vl == null ||
      vr == null ||
      hl == null ||
      hr == null ||
      vl.length < 3 ||
      {vl.length, vr.length, hl.length, hr.length}.length != 1) {
    return null;
  }
  final vlHr = _pearson(
    vl.map((value) => value.movementAccelerationMps2.z).toList(),
    hr.map((value) => value.movementAccelerationMps2.z).toList(),
  );
  final vrHl = _pearson(
    vr.map((value) => value.movementAccelerationMps2.z).toList(),
    hl.map((value) => value.movementAccelerationMps2.z).toList(),
  );
  if (vlHr == null || vrHl == null) return null;
  return (vlHr + vrHl) / 2;
}

double? _pearson(List<double> left, List<double> right) {
  if (left.length != right.length || left.length < 3) return null;
  final leftMean = _mean(left);
  final rightMean = _mean(right);
  var numerator = 0.0;
  var leftSquared = 0.0;
  var rightSquared = 0.0;
  for (var index = 0; index < left.length; index++) {
    final a = left[index] - leftMean;
    final b = right[index] - rightMean;
    numerator += a * b;
    leftSquared += a * a;
    rightSquared += b * b;
  }
  final denominator = math.sqrt(leftSquared * rightSquared);
  return denominator == 0 ? null : numerator / denominator;
}

double _movementRms(List<PreprocessedImuValue> values) {
  if (values.isEmpty) return 0;
  return math.sqrt(
    values
            .map((value) => value.movementAccelerationMps2.magnitudeSquared)
            .reduce((left, right) => left + right) /
        values.length,
  );
}

double _mean(Iterable<double> input) {
  final values = input.toList();
  if (values.isEmpty) return 0;
  return values.reduce((left, right) => left + right) / values.length;
}

double? _meanNullable(Iterable<double?> input) {
  final values = input.whereType<double>().toList();
  return values.isEmpty ? null : _mean(values);
}

bool _validTimes(List<PreprocessedFrame> frames) {
  for (var index = 0; index < frames.length; index++) {
    final time = frames[index].analysisTimeSeconds;
    if (!time.isFinite ||
        (index > 0 && time <= frames[index - 1].analysisTimeSeconds)) {
      return false;
    }
  }
  return true;
}

bool _finiteSignals(List<PreprocessedFrame> frames) {
  for (final frame in frames) {
    for (final value in frame.values.values.whereType<PreprocessedImuValue>()) {
      final vectors = [
        value.movementAccelerationMps2,
        value.alignedAngularVelocityRadPerSecond,
      ];
      if (vectors.any(
        (vector) =>
            !vector.x.isFinite || !vector.y.isFinite || !vector.z.isFinite,
      )) {
        return false;
      }
    }
  }
  return true;
}

bool _isMovement(GaitLabel gait) =>
    gait == GaitLabel.walk ||
    gait == GaitLabel.trot ||
    gait == GaitLabel.gallop ||
    gait == GaitLabel.unknown;

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

int _nearestCenter(double value, List<double> centers) {
  var best = 0;
  var bestDistance = (value - centers.first).abs();
  for (var index = 1; index < centers.length; index++) {
    final distance = (value - centers[index]).abs();
    if (distance < bestDistance) {
      best = index;
      bestDistance = distance;
    }
  }
  return best;
}

double _maxCenterChange(List<double> before, List<double> after) {
  var maximum = 0.0;
  for (var index = 0; index < before.length; index++) {
    maximum = math.max(maximum, (before[index] - after[index]).abs());
  }
  return maximum;
}

bool _gaitsInAscendingOrder(List<GaitLabel> gaits) {
  const order = {
    GaitLabel.walk: 0,
    GaitLabel.trot: 1,
    GaitLabel.gallop: 2,
  };
  for (var index = 1; index < gaits.length; index++) {
    if (order[gaits[index]]! <= order[gaits[index - 1]]!) return false;
  }
  return true;
}
