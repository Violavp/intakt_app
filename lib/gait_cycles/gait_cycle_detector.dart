import 'dart:math' as math;

import '../gait_segmentation/gait_segmentation.dart';
import '../imu_preprocessing/imu_preprocessing.dart';
import 'gait_cycle_models.dart';

/// Detects recording-internal movement events and touchdown-to-touchdown cycles.
///
/// The state transition is deliberately separated from gait segmentation and
/// interpretation. Right-leg device axes are canonicalized because the sensors
/// are mounted as mirror images. User-confirmed signed AsY and AccX windows
/// define separate touchdown and liftoff patterns for each gait, leg and
/// riding direction.
class GaitCycleDetector {
  const GaitCycleDetector({
    this.config = const GaitCycleDetectionConfig(),
  });

  final GaitCycleDetectionConfig config;

  static const assumptions = [
    'analysis_time_s is the reconstructed video-linked time basis',
    'right leg device axes are mirrored relative to left leg device axes',
    'signed AsY and AccX event patterns are learned separately for gait, leg '
        'and riding direction from user-confirmed events',
    'neither AsY nor AccX defines the gait or riding direction',
    'touchdown and liftoff names are user-confirmed signal interpretations; '
        'they are not force-plate validation',
    'quality is technical repeatability and completeness, not a medical score',
    'cycle bounds were calibrated on this recording and are not physiological '
        'reference ranges',
  ];

  GaitCycleDetectionResult detect(
    ImuPreprocessingResult input,
    GaitSegmentationResult segmentation, {
    List<ManualGaitEventCorrection> corrections = const [],
  }) {
    _validate();
    final issues = <CycleDetectionIssue>[];
    if (!input.hasDataset || input.frames.isEmpty) {
      return _failed(
        issues,
        'missing_preprocessed_dataset',
        'Es liegt kein Vorverarbeitungsdatensatz vor.',
      );
    }
    if (segmentation.status == SegmentationStatus.notPossible ||
        segmentation.segments.isEmpty) {
      return _failed(
        issues,
        'missing_gait_segments',
        'Es liegen keine Gangartsegmente vor.',
      );
    }
    final labels = input.frames.first.values.keys.toSet();
    final missing =
        config.requiredLegLabels.where((label) => !labels.contains(label));
    if (missing.isNotEmpty) {
      return _failed(
        issues,
        'missing_required_leg_signal',
        'Pflichtsensoren fehlen: ${missing.join(', ')}.',
      );
    }
    _validateCorrections(corrections, input);

    final supported = segmentation.segments
        .where(
          (segment) =>
              segment.gait == GaitLabel.walk || segment.gait == GaitLabel.trot,
        )
        .toList();
    if (supported.isEmpty) {
      return _failed(
        issues,
        'missing_supported_gait_segments',
        'Keine Schritt- oder Trabsegmente stehen zur Verfügung.',
      );
    }

    final calibrations = _buildEventPatternCalibrations(
      input,
      supported,
      corrections,
    );
    final automatic = <DetectedGaitEvent>[];
    var uncalibratedSegmentSensors = 0;
    for (final segment in supported) {
      for (final sensor in config.requiredLegLabels) {
        final calibration = calibrations[
            _CalibrationKey(sensor, segment.gait, segment.ridingDirection)];
        if (calibration == null) uncalibratedSegmentSensors++;
        automatic.addAll(
          _detectSegment(
            input,
            segment,
            sensor,
            automatic.length,
            calibration,
          ),
        );
      }
    }
    final events = _applyCorrections(input, supported, automatic, corrections);
    final cycles = _formCycles(input, events, supported);

    if (calibrations.isNotEmpty) {
      issues.add(
        CycleDetectionIssue(
          code: 'direction_specific_event_patterns_calibrated',
          observation:
              '${calibrations.length} AsY-/AccX-Ereignismuster wurden getrennt '
              'nach Gangart, Bein und Reitrichtung aus bestätigten '
              'Ereignissen gelernt.',
          uncertainty:
              'Die Regeln gelten als aufnahmespezifische Signalkalibrierung, '
              'nicht als externe Hufkontaktvalidierung.',
          recommendation:
              'Automatische Ergebnisse außerhalb der bestätigten Ausschnitte '
              'vor einem Roll-out stichprobenartig prüfen.',
        ),
      );
    }
    if (uncalibratedSegmentSensors > 0) {
      issues.add(
        CycleDetectionIssue(
          code: 'event_pattern_not_calibrated_for_all_segments',
          observation:
              '$uncalibratedSegmentSensors Segment-Bein-Kombinationen besitzen '
              'kein passendes bestätigtes Ereignismuster.',
          uncertainty:
              'Dort bleibt nur die bisherige AsY-Schwellenregel aktiv und die '
              'automatische Qualität wird ausdrücklich reduziert.',
          recommendation:
              'Diese Bereiche nicht freigeben, sondern im Diagramm bestätigen '
              'oder korrigieren.',
        ),
      );
    }

    final reviewedSegments = supported.where((segment) => !segment.analyzable);
    if (reviewedSegments.isNotEmpty) {
      issues.add(
        const CycleDetectionIssue(
          code: 'upstream_segments_require_review',
          observation:
              'Mindestens ein verwendeter Gangabschnitt ist vorgelagert nicht '
              'als analysierbar freigegeben.',
          uncertainty: 'Automatische Ereignisse in diesen Abschnitten bleiben '
              'Prüfkandidaten; Nutzerkorrekturen bleiben rückverfolgbar.',
          recommendation:
              'Segmentqualität separat prüfen und keine medizinische '
              'Interpretation ausgeben.',
        ),
      );
    }
    if (corrections.isNotEmpty) {
      issues.add(
        const CycleDetectionIssue(
          code: 'user_event_corrections_applied',
          observation:
              'Manuell bestätigte Ereigniszeitpunkte wurden angewendet.',
          uncertainty:
              'Die Bestätigung ersetzt in diesem Entwicklungsschritt die '
              'Videoannotation, nicht eine Kraftmessung.',
          recommendation:
              'Korrekturen unverändert mit Aufnahme und Algorithmusversion '
              'archivieren.',
        ),
      );
    }
    if (cycles.isEmpty) {
      return GaitCycleDetectionResult(
        status: GaitCycleDetectionStatus.notPossible,
        events: events,
        cycles: const [],
        issues: [
          ...issues,
          const CycleDetectionIssue(
            code: 'no_complete_cycles',
            observation:
                'Es wurden keine vollständigen Auftreten–Abheben–Auftreten-'
                'Folgen erkannt.',
            uncertainty: 'Ereignisfolge oder Segmentlänge reicht nicht aus.',
            recommendation: 'Ereignisgrafik und Gangartgrenzen kontrollieren.',
          ),
        ],
        config: config,
        assumptions: assumptions,
      );
    }
    final requiresReview = issues.isNotEmpty ||
        cycles.any((cycle) => !cycle.plausible) ||
        input.status != PreprocessingStatus.accepted ||
        segmentation.status != SegmentationStatus.accepted;
    return GaitCycleDetectionResult(
      status: requiresReview
          ? GaitCycleDetectionStatus.reviewRequired
          : GaitCycleDetectionStatus.accepted,
      events: List.unmodifiable(events),
      cycles: List.unmodifiable(cycles),
      issues: List.unmodifiable(issues),
      config: config,
      assumptions: assumptions,
    );
  }

  List<DetectedGaitEvent> _detectSegment(
    ImuPreprocessingResult input,
    GaitSegment segment,
    String sensor,
    int idOffset,
    _EventPatternCalibration? calibration,
  ) {
    final points = <_Point>[];
    final sign = sensor.endsWith('R') ? -1.0 : 1.0;
    for (final frame in input.frames) {
      if (frame.analysisTimeSeconds < segment.startSeconds ||
          frame.analysisTimeSeconds > segment.endSeconds) {
        continue;
      }
      final value = frame.values[sensor];
      if (value == null) continue;
      points.add(
        _Point(
          time: frame.analysisTimeSeconds,
          gyro: sign * value.filteredAngularVelocitySensorFrameRadPerSecond.y,
          acceleration: sign * value.filteredAccelerationSensorFrameMps2.x,
          raw: value,
        ),
      );
    }
    if (points.length < 10) return const [];
    if (calibration != null) {
      return _detectPatternEvents(
        points,
        segment,
        sensor,
        idOffset,
        calibration,
      );
    }
    final radius = math.max(
        1, (config.smoothingSeconds * input.gridSamplingRateHz / 2).round());
    final activity = _smooth(
      points.map((point) => point.gyro.abs()).toList(),
      radius,
    );
    final sorted = [...activity]..sort();
    final low = _quantile(sorted, 0.35);
    final high = _quantile(sorted, 0.70);
    if (high <= low + 1e-9) return const [];
    final enter = low + 0.60 * (high - low);
    final exit = low + 0.35 * (high - low);
    final minimumSamples = math.max(
        2, (config.minimumPhaseSeconds * input.gridSamplingRateHz).round());
    final provisional = <(GaitEventKind, int, double)>[];
    var isHigh = activity.first >= enter;
    var lastTransition = 0;
    for (var index = 1; index < points.length - 1; index++) {
      if (!isHigh &&
          activity[index] >= enter &&
          index - lastTransition >= minimumSamples) {
        provisional.add((GaitEventKind.liftoff, index, 1));
        isHigh = true;
        lastTransition = index;
      } else if (isHigh &&
          activity[index] <= exit &&
          index - lastTransition >= minimumSamples) {
        provisional.add((GaitEventKind.touchdown, index, -1));
        isHigh = false;
        lastTransition = index;
      }
    }
    final refineRadius = math.max(
        1, (config.refinementSeconds * input.gridSamplingRateHz).round());
    final output = <DetectedGaitEvent>[];
    for (final candidate in provisional) {
      final kind = candidate.$1;
      var bestIndex = candidate.$2;
      var bestScore = double.negativeInfinity;
      for (var index = math.max(1, candidate.$2 - refineRadius);
          index <= math.min(points.length - 2, candidate.$2 + refineRadius);
          index++) {
        final derivative = activity[index + 1] - activity[index - 1];
        final transition = candidate.$3 * derivative;
        final impact = points[index].acceleration.abs() / 9.80665;
        final score = transition / (high - low) + 0.15 * impact;
        if (score > bestScore) {
          bestScore = score;
          bestIndex = index;
        }
      }
      final point = points[bestIndex];
      final contrast =
          ((activity[bestIndex] - low).abs() / (high - low)).clamp(0.0, 1.0);
      final quality = ((0.55 * contrast + 0.45 * bestScore.clamp(0.0, 1.0)) *
              config.uncalibratedQualityFactor)
          .clamp(0.0, 1.0);
      output.add(
        _event(
          id: 'auto-${idOffset + output.length + 1}',
          sensor: sensor,
          gait: segment.gait,
          kind: kind,
          point: point,
          quality: quality,
          source: GaitEventSource.automatic,
          ridingDirection: segment.ridingDirection,
          patternCalibration: 'UNCALIBRATED_DEFAULT',
          patternSupportCount: 0,
          patternAgreement: null,
        ),
      );
    }
    return output;
  }

  Map<_CalibrationKey, _EventPatternCalibration> _buildEventPatternCalibrations(
    ImuPreprocessingResult input,
    List<GaitSegment> segments,
    List<ManualGaitEventCorrection> corrections,
  ) {
    final referencesByKey =
        <_CalibrationKey, List<ManualGaitEventCorrection>>{};
    for (final correction in corrections) {
      final direction = _correctionDirection(correction, segments);
      if (direction == RidingDirection.unknown) continue;
      final key = _CalibrationKey(
        correction.sensorLabel,
        correction.gait,
        direction,
      );
      referencesByKey
          .putIfAbsent(key, () => <ManualGaitEventCorrection>[])
          .add(correction);
    }

    final calibrations = <_CalibrationKey, _EventPatternCalibration>{};
    for (final entry in referencesByKey.entries) {
      final references = entry.value
        ..sort((left, right) => left.timeSeconds.compareTo(right.timeSeconds));
      final stanceDurations = _referencePhaseDurations(
        references,
        GaitEventKind.touchdown,
        GaitEventKind.liftoff,
      );
      final swingDurations = _referencePhaseDurations(
        references,
        GaitEventKind.liftoff,
        GaitEventKind.touchdown,
      );
      final cycleDurations = _referenceSameEventDurations(
        references,
        GaitEventKind.touchdown,
      );
      if (stanceDurations.isEmpty ||
          swingDurations.isEmpty ||
          cycleDurations.isEmpty) {
        continue;
      }
      final points = _pointsForSensor(input, entry.key.sensor);
      final radius = math.max(
        2,
        (config.patternHalfWindowSeconds * input.gridSamplingRateHz).round(),
      );
      final touchdownExamples = <List<double>>[];
      final liftoffExamples = <List<double>>[];
      for (final reference in references) {
        final index = _nearestPointIndex(points, reference.timeSeconds);
        final pattern = _normalizedPattern(points, index, radius);
        if (pattern == null) continue;
        (reference.kind == GaitEventKind.touchdown
                ? touchdownExamples
                : liftoffExamples)
            .add(pattern);
      }
      if (touchdownExamples.length < config.minimumPatternExamplesPerKind ||
          liftoffExamples.length < config.minimumPatternExamplesPerKind) {
        continue;
      }
      final touchdownPattern = _meanPattern(touchdownExamples);
      final liftoffPattern = _meanPattern(liftoffExamples);
      final similarities = [
        for (final example in touchdownExamples)
          (_dot(example, touchdownPattern) + 1) / 2,
        for (final example in liftoffExamples)
          (_dot(example, liftoffPattern) + 1) / 2,
      ];
      calibrations[entry.key] = _EventPatternCalibration(
        touchdownPattern: touchdownPattern,
        liftoffPattern: liftoffPattern,
        supportCount: references.length,
        agreement: _mean(similarities).clamp(0.0, 1.0),
        medianStanceSeconds: _median(stanceDurations),
        medianSwingSeconds: _median(swingDurations),
        medianCycleSeconds: _median(cycleDurations),
        radiusSamples: radius,
      );
    }
    return calibrations;
  }

  List<double> _referencePhaseDurations(
    List<ManualGaitEventCorrection> references,
    GaitEventKind start,
    GaitEventKind end,
  ) {
    final durations = <double>[];
    for (var index = 0; index + 1 < references.length; index++) {
      if (references[index].kind != start) continue;
      for (var next = index + 1; next < references.length; next++) {
        if (references[next].kind == start) break;
        if (references[next].kind == end) {
          final duration =
              references[next].timeSeconds - references[index].timeSeconds;
          if (duration >= config.minimumPhaseSeconds) durations.add(duration);
          break;
        }
      }
    }
    return durations;
  }

  List<double> _referenceSameEventDurations(
    List<ManualGaitEventCorrection> references,
    GaitEventKind kind,
  ) {
    final times = references
        .where((reference) => reference.kind == kind)
        .map((reference) => reference.timeSeconds)
        .toList();
    return [
      for (var index = 0; index + 1 < times.length; index++)
        if (times[index + 1] - times[index] >= config.minimumPhaseSeconds)
          times[index + 1] - times[index],
    ];
  }

  List<DetectedGaitEvent> _detectPatternEvents(
    List<_Point> points,
    GaitSegment segment,
    String sensor,
    int idOffset,
    _EventPatternCalibration calibration,
  ) {
    final touchdownScores = List<double>.filled(
      points.length,
      double.negativeInfinity,
    );
    final liftoffScores = List<double>.filled(
      points.length,
      double.negativeInfinity,
    );
    for (var index = calibration.radiusSamples;
        index + calibration.radiusSamples < points.length;
        index++) {
      final pattern =
          _normalizedPattern(points, index, calibration.radiusSamples);
      if (pattern == null) continue;
      touchdownScores[index] = _dot(pattern, calibration.touchdownPattern);
      liftoffScores[index] = _dot(pattern, calibration.liftoffPattern);
    }
    final touchdownCandidates = _localPatternCandidates(
      points,
      touchdownScores,
      GaitEventKind.touchdown,
    );
    final liftoffCandidates = _localPatternCandidates(
      points,
      liftoffScores,
      GaitEventKind.liftoff,
    );
    final touchdowns = _selectSpacedPatternCandidates(
      touchdownCandidates,
      calibration.medianCycleSeconds * config.sameEventSpacingFraction,
    )..sort((left, right) => left.time.compareTo(right.time));

    final selected = <_PatternCandidate>[];
    for (var index = 0; index < touchdowns.length; index++) {
      final touchdown = touchdowns[index];
      selected.add(touchdown);
      if (index + 1 >= touchdowns.length) continue;
      final nextTouchdown = touchdowns[index + 1];
      final expected = touchdown.time + calibration.medianStanceSeconds;
      final tolerance = math.max(
        config.minimumPhaseSeconds,
        calibration.medianStanceSeconds * config.phaseSearchToleranceFraction,
      );
      _PatternCandidate? best;
      var bestRank = double.negativeInfinity;
      for (final candidate in liftoffCandidates) {
        if (candidate.time <= touchdown.time ||
            candidate.time >= nextTouchdown.time ||
            (candidate.time - expected).abs() > tolerance) {
          continue;
        }
        final timingPenalty = (candidate.time - expected).abs() / tolerance;
        final rank = candidate.score - 0.25 * timingPenalty;
        if (rank > bestRank) {
          best = candidate;
          bestRank = rank;
        }
      }
      if (best != null) selected.add(best);
    }
    selected.sort((left, right) => left.time.compareTo(right.time));

    final events = <DetectedGaitEvent>[];
    for (final candidate in selected) {
      final quality =
          (((candidate.score + 1) / 2) * calibration.agreement).clamp(0.0, 1.0);
      events.add(
        _event(
          id: 'auto-${idOffset + events.length + 1}',
          sensor: sensor,
          gait: segment.gait,
          kind: candidate.kind,
          point: points[candidate.index],
          quality: quality,
          source: GaitEventSource.automatic,
          ridingDirection: segment.ridingDirection,
          patternCalibration: 'DIRECTION_PATTERN_CALIBRATED',
          patternSupportCount: calibration.supportCount,
          patternAgreement: calibration.agreement,
        ),
      );
    }
    return events;
  }

  List<_Point> _pointsForSensor(
    ImuPreprocessingResult input,
    String sensor,
  ) {
    final sign = sensor.endsWith('R') ? -1.0 : 1.0;
    final points = <_Point>[];
    for (final frame in input.frames) {
      final value = frame.values[sensor];
      if (value == null) continue;
      points.add(
        _Point(
          time: frame.analysisTimeSeconds,
          gyro: sign * value.filteredAngularVelocitySensorFrameRadPerSecond.y,
          acceleration: sign * value.filteredAccelerationSensorFrameMps2.x,
          raw: value,
        ),
      );
    }
    return points;
  }

  int _nearestPointIndex(List<_Point> points, double time) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < points.length; index++) {
      final distance = (points[index].time - time).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  List<double>? _normalizedPattern(
    List<_Point> points,
    int center,
    int radius,
  ) {
    if (center - radius < 0 || center + radius >= points.length) return null;
    final window = points.sublist(center - radius, center + radius + 1);
    final expectedStep =
        (window.last.time - window.first.time) / (window.length - 1);
    if (!expectedStep.isFinite || expectedStep <= 0) return null;
    for (var index = 0; index + 1 < window.length; index++) {
      if (window[index + 1].time - window[index].time > expectedStep * 2.5) {
        return null;
      }
    }
    final gyro = window.map((point) => point.gyro).toList();
    final acceleration = window.map((point) => point.acceleration).toList();
    final feature = <double>[
      ..._standardize(gyro),
      ..._standardize(acceleration),
    ];
    final norm =
        math.sqrt(feature.fold(0.0, (sum, value) => sum + value * value));
    if (norm <= 1e-12) return null;
    return [for (final value in feature) value / norm];
  }

  List<double> _standardize(List<double> values) {
    final mean = _mean(values);
    final scale = math.sqrt(
      values.fold(0.0, (sum, value) => sum + math.pow(value - mean, 2)) /
          values.length,
    );
    if (scale <= 1e-12) return List<double>.filled(values.length, 0);
    return [for (final value in values) (value - mean) / scale];
  }

  List<double> _meanPattern(List<List<double>> examples) {
    final mean = List<double>.filled(examples.first.length, 0);
    for (final example in examples) {
      for (var index = 0; index < mean.length; index++) {
        mean[index] += example[index] / examples.length;
      }
    }
    final norm = math.sqrt(mean.fold(0.0, (sum, value) => sum + value * value));
    return [for (final value in mean) value / norm];
  }

  List<_PatternCandidate> _localPatternCandidates(
    List<_Point> points,
    List<double> scores,
    GaitEventKind kind,
  ) {
    final candidates = <_PatternCandidate>[];
    for (var index = 1; index + 1 < scores.length; index++) {
      final score = scores[index];
      if (score < config.minimumPatternCorrelation ||
          score < scores[index - 1] ||
          score < scores[index + 1]) {
        continue;
      }
      candidates.add(
        _PatternCandidate(
          index: index,
          time: points[index].time,
          kind: kind,
          score: score,
        ),
      );
    }
    return candidates;
  }

  List<_PatternCandidate> _selectSpacedPatternCandidates(
    List<_PatternCandidate> candidates,
    double minimumSpacingSeconds,
  ) {
    final ranked = [...candidates]
      ..sort((left, right) => right.score.compareTo(left.score));
    final selected = <_PatternCandidate>[];
    for (final candidate in ranked) {
      if (selected.every(
        (other) => (candidate.time - other.time).abs() >= minimumSpacingSeconds,
      )) {
        selected.add(candidate);
      }
    }
    return selected;
  }

  RidingDirection _correctionDirection(
    ManualGaitEventCorrection correction,
    List<GaitSegment> segments,
  ) {
    if (correction.ridingDirection != null) {
      return correction.ridingDirection!;
    }
    for (final segment in segments) {
      if (segment.gait == correction.gait &&
          correction.timeSeconds >= segment.startSeconds &&
          correction.timeSeconds <= segment.endSeconds) {
        return segment.ridingDirection;
      }
    }
    return RidingDirection.unknown;
  }

  bool _cycleWithinOneGaitContext(
    DetectedGaitEvent start,
    DetectedGaitEvent end,
    GaitLabel gait,
    List<GaitSegment> segments,
  ) {
    if (start.ridingDirection == RidingDirection.unknown ||
        end.ridingDirection != start.ridingDirection) {
      return false;
    }
    final overlapping = segments
        .where(
          (segment) =>
              segment.endSeconds >= start.timeSeconds &&
              segment.startSeconds <= end.timeSeconds,
        )
        .toList()
      ..sort((left, right) => left.startSeconds.compareTo(right.startSeconds));
    var coveredUntil = start.timeSeconds;
    const tolerance = 0.03;
    for (final segment in overlapping) {
      if (segment.startSeconds > coveredUntil + tolerance ||
          segment.gait != gait ||
          segment.ridingDirection != start.ridingDirection ||
          segment.turn ||
          segment.interruption) {
        return false;
      }
      coveredUntil = math.max(coveredUntil, segment.endSeconds);
      if (coveredUntil >= end.timeSeconds - tolerance) return true;
    }
    return false;
  }

  List<DetectedGaitEvent> _applyCorrections(
    ImuPreprocessingResult input,
    List<GaitSegment> segments,
    List<DetectedGaitEvent> automatic,
    List<ManualGaitEventCorrection> corrections,
  ) {
    final output = [...automatic];
    for (var correctionIndex = 0;
        correctionIndex < corrections.length;
        correctionIndex++) {
      final correction = corrections[correctionIndex];
      var bestIndex = -1;
      var bestDistance = double.infinity;
      for (var index = 0; index < output.length; index++) {
        final event = output[index];
        if (event.sensorLabel != correction.sensorLabel ||
            event.gait != correction.gait ||
            event.source == GaitEventSource.userCorrection) {
          continue;
        }
        final distance = (event.timeSeconds - correction.timeSeconds).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = index;
        }
      }
      final point = _nearestPoint(
        input,
        correction.sensorLabel,
        correction.timeSeconds,
      );
      final direction = _correctionDirection(correction, segments);
      final corrected = _event(
        id: 'user-${correctionIndex + 1}',
        sensor: correction.sensorLabel,
        gait: correction.gait,
        kind: correction.kind,
        point: point,
        quality: 1,
        source: GaitEventSource.userCorrection,
        ridingDirection: direction,
        patternCalibration: 'USER_CONFIRMED',
        patternSupportCount: 1,
        patternAgreement: 1,
      );
      if (bestIndex >= 0 &&
          bestDistance <= config.manualMatchToleranceSeconds) {
        output[bestIndex] = corrected;
      } else {
        output.add(corrected);
      }
    }
    output.sort((left, right) {
      final sensor = left.sensorLabel.compareTo(right.sensorLabel);
      if (sensor != 0) return sensor;
      return left.timeSeconds.compareTo(right.timeSeconds);
    });
    return output;
  }

  List<GaitCycle> _formCycles(
    ImuPreprocessingResult input,
    List<DetectedGaitEvent> events,
    List<GaitSegment> segments,
  ) {
    final cycles = <GaitCycle>[];
    for (final sensor in config.requiredLegLabels) {
      for (final gait in const [GaitLabel.walk, GaitLabel.trot]) {
        final selected = events
            .where((event) => event.sensorLabel == sensor && event.gait == gait)
            .toList()
          ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
        final bounds = gait == GaitLabel.walk
            ? (config.walkMinimumCycleSeconds, config.walkMaximumCycleSeconds)
            : (config.trotMinimumCycleSeconds, config.trotMaximumCycleSeconds);
        final touchdowns = _separateTouchdowns(
          selected
              .where((event) => event.kind == GaitEventKind.touchdown)
              .toList(),
          bounds.$1,
        );
        final durations = <double>[];
        for (var index = 0; index + 1 < touchdowns.length; index++) {
          final duration =
              touchdowns[index + 1].timeSeconds - touchdowns[index].timeSeconds;
          if (duration >= bounds.$1 && duration <= bounds.$2) {
            durations.add(duration);
          }
        }
        final median = _median(durations);
        for (var index = 0; index + 1 < touchdowns.length; index++) {
          final start = touchdowns[index];
          final end = touchdowns[index + 1];
          final liftoffs = selected
              .where(
                (event) =>
                    event.kind == GaitEventKind.liftoff &&
                    event.timeSeconds > start.timeSeconds &&
                    event.timeSeconds < end.timeSeconds,
              )
              .toList();
          if (liftoffs.isEmpty) continue;
          liftoffs.sort((left, right) {
            final source = right.source.index.compareTo(left.source.index);
            return source != 0 ? source : right.quality.compareTo(left.quality);
          });
          final liftoff = liftoffs.first;
          final duration = end.timeSeconds - start.timeSeconds;
          final deviation =
              median == 0 ? 0.0 : (duration - median).abs() / median;
          final available = input.frames
              .where(
                (frame) =>
                    frame.analysisTimeSeconds >= start.timeSeconds &&
                    frame.analysisTimeSeconds <= end.timeSeconds &&
                    frame.values[sensor] != null,
              )
              .length;
          final expected =
              math.max(1, (duration * input.gridSamplingRateHz).round() + 1);
          final coverage = (available / expected).clamp(0.0, 1.0);
          final reasons = <String>[];
          if (duration < bounds.$1 || duration > bounds.$2) {
            reasons.add('cycle_duration_outside_recording_calibration');
          }
          if (coverage < config.minimumCoverage) {
            reasons.add('insufficient_sample_coverage');
          }
          final orderingValid = liftoff.timeSeconds > start.timeSeconds &&
              liftoff.timeSeconds < end.timeSeconds;
          if (!orderingValid) reasons.add('invalid_event_order');
          if (!_cycleWithinOneGaitContext(start, end, gait, segments)) {
            reasons.add('cycle_crosses_gait_or_direction_boundary');
          }
          final quality =
              ((start.quality + liftoff.quality + end.quality) / 3 * coverage)
                  .clamp(0.0, 1.0);
          if (quality < config.minimumCycleQuality) {
            reasons.add('quality_below_threshold');
          }
          final userConfirmed =
              start.source == GaitEventSource.userCorrection &&
                  liftoff.source == GaitEventSource.userCorrection &&
                  end.source == GaitEventSource.userCorrection;
          cycles.add(
            GaitCycle(
              id: 'cycle-${cycles.length + 1}',
              sensorLabel: sensor,
              gait: gait,
              startEventId: start.id,
              liftoffEventId: liftoff.id,
              endEventId: end.id,
              startSeconds: start.timeSeconds,
              endSeconds: end.timeSeconds,
              liftoffSeconds: liftoff.timeSeconds,
              durationUncertaintyMilliseconds: math.sqrt(
                math.pow(start.sourceUncertaintyMilliseconds, 2) +
                    math.pow(end.sourceUncertaintyMilliseconds, 2),
              ),
              stanceUncertaintyMilliseconds: math.sqrt(
                math.pow(start.sourceUncertaintyMilliseconds, 2) +
                    math.pow(liftoff.sourceUncertaintyMilliseconds, 2),
              ),
              swingUncertaintyMilliseconds: math.sqrt(
                math.pow(liftoff.sourceUncertaintyMilliseconds, 2) +
                    math.pow(end.sourceUncertaintyMilliseconds, 2),
              ),
              quality: quality,
              plausible: reasons.isEmpty,
              exclusionReasons: List.unmodifiable(reasons),
              sampleCoverage: coverage,
              durationDeviationFraction: deviation,
              userConfirmed: userConfirmed,
            ),
          );
        }
      }
    }
    cycles.sort((left, right) {
      final time = left.startSeconds.compareTo(right.startSeconds);
      return time != 0 ? time : left.sensorLabel.compareTo(right.sensorLabel);
    });
    return cycles;
  }

  List<DetectedGaitEvent> _separateTouchdowns(
    List<DetectedGaitEvent> candidates,
    double minimumCycleSeconds,
  ) {
    if (candidates.isEmpty) return const [];
    candidates.sort(
      (left, right) => left.timeSeconds.compareTo(right.timeSeconds),
    );
    final selected = <DetectedGaitEvent>[];
    for (final candidate in candidates) {
      if (selected.isEmpty ||
          candidate.timeSeconds - selected.last.timeSeconds >=
              minimumCycleSeconds) {
        selected.add(candidate);
        continue;
      }
      final previous = selected.last;
      final candidateManual =
          candidate.source == GaitEventSource.userCorrection;
      final previousManual = previous.source == GaitEventSource.userCorrection;
      if (candidateManual && !previousManual) {
        selected[selected.length - 1] = candidate;
      } else if (!previousManual &&
          !candidateManual &&
          candidate.quality > previous.quality) {
        selected[selected.length - 1] = candidate;
      }
    }
    return selected;
  }

  DetectedGaitEvent _event({
    required String id,
    required String sensor,
    required GaitLabel gait,
    required GaitEventKind kind,
    required _Point point,
    required double quality,
    required GaitEventSource source,
    required RidingDirection ridingDirection,
    required String patternCalibration,
    required int patternSupportCount,
    required double? patternAgreement,
  }) =>
      DetectedGaitEvent(
        id: id,
        sensorLabel: sensor,
        gait: gait,
        kind: kind,
        timeSeconds: point.time,
        quality: quality,
        source: source,
        canonicalGyroYRadPerSecond: point.gyro,
        canonicalAccelerationXMps2: point.acceleration,
        sourceName: point.raw.raw.lowerSourceName,
        sourceLine: point.raw.raw.lowerSourceLine,
        sourceUncertaintyMilliseconds: point.raw.raw.uncertaintyMilliseconds,
        ridingDirection: ridingDirection,
        patternCalibration: patternCalibration,
        patternSupportCount: patternSupportCount,
        patternAgreement: patternAgreement,
      );

  _Point _nearestPoint(
    ImuPreprocessingResult input,
    String sensor,
    double time,
  ) {
    final sign = sensor.endsWith('R') ? -1.0 : 1.0;
    PreprocessedFrame? bestFrame;
    var bestDistance = double.infinity;
    for (final frame in input.frames) {
      if (frame.values[sensor] == null) continue;
      final distance = (frame.analysisTimeSeconds - time).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestFrame = frame;
      }
    }
    if (bestFrame == null) {
      throw ArgumentError(
          'Keine Daten für Nutzerkorrektur $sensor bei $time s.');
    }
    final value = bestFrame.values[sensor]!;
    return _Point(
      time: bestFrame.analysisTimeSeconds,
      gyro: sign * value.filteredAngularVelocitySensorFrameRadPerSecond.y,
      acceleration: sign * value.filteredAccelerationSensorFrameMps2.x,
      raw: value,
    );
  }

  void _validateCorrections(
    List<ManualGaitEventCorrection> corrections,
    ImuPreprocessingResult input,
  ) {
    final first = input.frames.first.analysisTimeSeconds;
    final last = input.frames.last.analysisTimeSeconds;
    for (final correction in corrections) {
      if (!config.requiredLegLabels.contains(correction.sensorLabel)) {
        throw FormatException(
          'Unbekannter Beinsensor "${correction.sensorLabel}".',
        );
      }
      if (correction.gait != GaitLabel.walk &&
          correction.gait != GaitLabel.trot) {
        throw const FormatException(
          'Ereigniskorrekturen sind nur für WALK und TROT zulässig.',
        );
      }
      if (!correction.timeSeconds.isFinite ||
          correction.timeSeconds < first ||
          correction.timeSeconds > last) {
        throw FormatException(
          'Ereigniskorrektur ${correction.timeSeconds} s liegt außerhalb '
          'der Aufnahme.',
        );
      }
    }
  }

  void _validate() {
    if (config.smoothingSeconds <= 0 ||
        config.minimumPhaseSeconds <= 0 ||
        config.refinementSeconds <= 0 ||
        config.walkMinimumCycleSeconds <= 0 ||
        config.walkMaximumCycleSeconds <= config.walkMinimumCycleSeconds ||
        config.trotMinimumCycleSeconds <= 0 ||
        config.trotMaximumCycleSeconds <= config.trotMinimumCycleSeconds ||
        config.minimumCoverage <= 0 ||
        config.minimumCoverage > 1 ||
        config.minimumCycleQuality < 0 ||
        config.minimumCycleQuality > 1 ||
        config.patternHalfWindowSeconds <= 0 ||
        config.minimumPatternExamplesPerKind < 1 ||
        config.minimumPatternCorrelation < -1 ||
        config.minimumPatternCorrelation > 1 ||
        config.sameEventSpacingFraction <= 0 ||
        config.sameEventSpacingFraction > 1 ||
        config.phaseSearchToleranceFraction <= 0 ||
        config.phaseSearchToleranceFraction > 1 ||
        config.uncalibratedQualityFactor <= 0 ||
        config.uncalibratedQualityFactor > 1) {
      throw ArgumentError('Ungültige Gangzykluskonfiguration.');
    }
  }

  GaitCycleDetectionResult _failed(
    List<CycleDetectionIssue> issues,
    String code,
    String observation,
  ) =>
      GaitCycleDetectionResult(
        status: GaitCycleDetectionStatus.notPossible,
        events: const [],
        cycles: const [],
        issues: [
          ...issues,
          CycleDetectionIssue(
            code: code,
            observation: observation,
            uncertainty:
                'Das Goal kann für diese Eingabe nicht berechnet werden.',
            recommendation: 'Vorgelagerte Daten und Konfiguration prüfen.',
          ),
        ],
        config: config,
        assumptions: assumptions,
      );
}

class _Point {
  const _Point({
    required this.time,
    required this.gyro,
    required this.acceleration,
    required this.raw,
  });

  final double time;
  final double gyro;
  final double acceleration;
  final PreprocessedImuValue raw;
}

class _CalibrationKey {
  const _CalibrationKey(this.sensor, this.gait, this.direction);

  final String sensor;
  final GaitLabel gait;
  final RidingDirection direction;

  @override
  bool operator ==(Object other) =>
      other is _CalibrationKey &&
      other.sensor == sensor &&
      other.gait == gait &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(sensor, gait, direction);
}

class _EventPatternCalibration {
  const _EventPatternCalibration({
    required this.touchdownPattern,
    required this.liftoffPattern,
    required this.supportCount,
    required this.agreement,
    required this.medianStanceSeconds,
    required this.medianSwingSeconds,
    required this.medianCycleSeconds,
    required this.radiusSamples,
  });

  final List<double> touchdownPattern;
  final List<double> liftoffPattern;
  final int supportCount;
  final double agreement;
  final double medianStanceSeconds;
  final double medianSwingSeconds;
  final double medianCycleSeconds;
  final int radiusSamples;
}

class _PatternCandidate {
  const _PatternCandidate({
    required this.index,
    required this.time,
    required this.kind,
    required this.score,
  });

  final int index;
  final double time;
  final GaitEventKind kind;
  final double score;
}

List<double> _smooth(List<double> values, int radius) => [
      for (var index = 0; index < values.length; index++)
        _mean(
          values.sublist(
            math.max(0, index - radius),
            math.min(values.length, index + radius + 1),
          ),
        ),
    ];

double _mean(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double _dot(List<double> left, List<double> right) {
  var value = 0.0;
  for (var index = 0; index < left.length; index++) {
    value += left[index] * right[index];
  }
  return value;
}

double _quantile(List<double> sorted, double quantile) {
  if (sorted.isEmpty) return 0;
  final position = (sorted.length - 1) * quantile;
  final low = position.floor();
  final high = position.ceil();
  if (low == high) return sorted[low];
  return sorted[low] * (high - position) + sorted[high] * (position - low);
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
