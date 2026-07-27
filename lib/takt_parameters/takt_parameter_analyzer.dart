import 'dart:math' as math;

import '../gait_cycles/gait_cycles.dart';
import '../gait_segmentation/gait_segmentation.dart';
import 'takt_parameter_models.dart';

/// Descriptive temporal Takt parameters calculated after event detection.
///
/// This stage does not detect events, classify gait, score riding quality or
/// infer a medical condition. Invalid windows remain explicit and carry null
/// metrics instead of replacement values.
class TaktParameterAnalyzer {
  const TaktParameterAnalyzer({
    this.config = const TaktParameterConfig(),
  });

  final TaktParameterConfig config;

  static const assumptions = [
    'cycle start events are recording-calibrated signal hypotheses and not '
        'force-plate-validated hoof contacts',
    'gait is supplied by the frequency-based segmentation stage and is not '
        'changed by Takt parameters',
    'AngleZ direction is used only to keep left and right riding-line windows '
        'separate',
    'smaller variability, absolute drift, phase dispersion and temporal '
        'symmetry deviation mean greater temporal stability, not medical '
        'soundness or a riding score',
    'improvement and worsening are personal within-recording comparisons of '
        'disjoint windows and require a change larger than technical '
        'uncertainty',
  ];

  TaktParameterResult analyze(
    GaitCycleDetectionResult cycleDetection,
    GaitSegmentationResult segmentation,
  ) {
    _validateConfig();
    final issues = <TaktParameterIssue>[];
    if (cycleDetection.cycles.isEmpty) {
      return _failed(
        issues,
        'missing_gait_cycles',
        'Es liegen keine Gangzyklen für die Taktparameter vor.',
      );
    }
    if (segmentation.segments.isEmpty ||
        segmentation.status == SegmentationStatus.notPossible) {
      return _failed(
        issues,
        'missing_gait_segments',
        'Es liegen keine verwendbaren Gangartsegmente vor.',
      );
    }

    if (cycleDetection.status != GaitCycleDetectionStatus.accepted) {
      issues.add(
        const TaktParameterIssue(
          code: 'upstream_cycle_detection_review_required',
          observation:
              'Die verwendete Gangereignis- und Zykluserkennung ist nicht '
              'abschließend validiert.',
          uncertainty:
              'Alle zeitlichen Taktparameter erben die Ereignisunsicherheit.',
          recommendation:
              'Ereignisse gegen eine unabhängige Referenz validieren.',
        ),
      );
    }
    if (segmentation.status != SegmentationStatus.accepted) {
      issues.add(
        const TaktParameterIssue(
          code: 'upstream_segmentation_review_required',
          observation: 'Die Gangsegmentierung verlangt weiterhin Prüfung.',
          uncertainty:
              'Gangart- und Abschnittsgrenzen können die Fensterauswahl '
              'beeinflussen.',
          recommendation:
              'Taktfenster zusammen mit Segment- und Videobericht prüfen.',
        ),
      );
    }

    final eventById = {
      for (final event in cycleDetection.events) event.id: event,
    };
    final windows = <TaktAnalysisWindow>[];
    for (final segment in segmentation.segments.where(
      (segment) =>
          segment.gait == GaitLabel.walk || segment.gait == GaitLabel.trot,
    )) {
      windows.addAll(
        _analyzeSegment(
          segment,
          cycleDetection.cycles,
          eventById,
          windows.length,
        ),
      );
    }
    final compared = _addComparisons(windows);
    final invalidCount = compared.where((window) => !window.valid).length;
    if (invalidCount > 0) {
      issues.add(
        TaktParameterIssue(
          code: 'invalid_takt_windows_present',
          observation: '$invalidCount Taktfenster erfüllen die technischen '
              'Berechnungsbedingungen nicht.',
          uncertainty: 'Ungültige Fenster enthalten ausdrücklich null statt '
              'Ersatzwerten.',
          recommendation:
              'Ausschlussgründe und Zahl gültiger Zyklen je Bein prüfen.',
        ),
      );
    }
    final validCount = compared.where((window) => window.valid).length;
    if (validCount == 0) {
      issues.add(
        const TaktParameterIssue(
          code: 'no_valid_takt_windows',
          observation:
              'Kein Fenster enthält genug gültige Zyklen aller vier Beine.',
          uncertainty:
              'Mittelwert, Verlauf und Vergleich sind nicht bestimmbar.',
          recommendation:
              'Längeren stabilen Gangabschnitt oder validierte Ereignisse '
              'bereitstellen; keine Werte ergänzen.',
        ),
      );
    }
    return TaktParameterResult(
      status: validCount == 0
          ? TaktParameterStatus.notPossible
          : issues.isEmpty
              ? TaktParameterStatus.accepted
              : TaktParameterStatus.reviewRequired,
      windows: List.unmodifiable(compared),
      issues: List.unmodifiable(issues),
      config: config,
      assumptions: assumptions,
    );
  }

  List<TaktAnalysisWindow> _analyzeSegment(
    GaitSegment segment,
    List<GaitCycle> allCycles,
    Map<String, DetectedGaitEvent> eventById,
    int idOffset,
  ) {
    final duration = segment.durationSeconds;
    if (duration < config.minimumWindowSeconds) {
      return [
        _invalidWindow(
          id: 'takt-window-${idOffset + 1}',
          start: segment.startSeconds,
          end: segment.endSeconds,
          segment: segment,
          reasons: const ['stable_segment_shorter_than_window'],
        ),
      ];
    }
    final output = <TaktAnalysisWindow>[];
    for (var end = segment.startSeconds + config.minimumWindowSeconds;
        end <= segment.endSeconds + 1e-9;
        end += config.stepSeconds) {
      final segmentReasons = <String>[];
      if (!segment.analyzable) {
        segmentReasons.add('upstream_segment_not_analyzable');
      }
      if (segment.transition) segmentReasons.add('transition_window');
      if (segment.turn) segmentReasons.add('direction_change_window');
      if (segment.interruption) segmentReasons.add('interruption_window');

      Map<String, List<GaitCycle>>? selectedByLeg;
      double? selectedStart;
      var candidateDuration = config.minimumWindowSeconds;
      while (candidateDuration <= config.maximumWindowSeconds + 1e-9) {
        final candidateStart = end - candidateDuration;
        if (candidateStart < segment.startSeconds - 1e-9) break;
        final candidateByLeg = _cyclesByLeg(
          allCycles,
          segment.gait,
          candidateStart,
          end,
        );
        if (config.requiredLegLabels.every(
          (label) =>
              candidateByLeg[label]!.length >= config.minimumValidCyclesPerLeg,
        )) {
          selectedStart = candidateStart;
          selectedByLeg = candidateByLeg;
          break;
        }
        candidateDuration += config.stepSeconds;
      }

      if (selectedByLeg == null || segmentReasons.isNotEmpty) {
        final fallbackStart = math.max(
          segment.startSeconds,
          end - config.maximumWindowSeconds,
        );
        final fallbackByLeg = _cyclesByLeg(
          allCycles,
          segment.gait,
          fallbackStart,
          end,
        );
        final reasons = [...segmentReasons];
        for (final label in config.requiredLegLabels) {
          if (fallbackByLeg[label]!.length < config.minimumValidCyclesPerLeg) {
            reasons.add('insufficient_valid_cycles_$label');
          }
        }
        output.add(
          _invalidWindow(
            id: 'takt-window-${idOffset + output.length + 1}',
            start: fallbackStart,
            end: end,
            segment: segment,
            reasons: reasons,
            cyclesByLeg: fallbackByLeg,
          ),
        );
        continue;
      }
      output.add(
        _validWindow(
          id: 'takt-window-${idOffset + output.length + 1}',
          start: selectedStart!,
          end: end,
          segment: segment,
          cyclesByLeg: selectedByLeg,
          eventById: eventById,
        ),
      );
    }
    return output;
  }

  Map<String, List<GaitCycle>> _cyclesByLeg(
    List<GaitCycle> allCycles,
    GaitLabel gait,
    double start,
    double end,
  ) =>
      {
        for (final label in config.requiredLegLabels)
          label: allCycles
              .where(
                (cycle) =>
                    cycle.sensorLabel == label &&
                    cycle.gait == gait &&
                    cycle.plausible &&
                    cycle.startSeconds >= start - 1e-9 &&
                    cycle.endSeconds <= end + 1e-9,
              )
              .toList()
            ..sort(
              (left, right) => left.startSeconds.compareTo(right.startSeconds),
            ),
      };

  TaktAnalysisWindow _validWindow({
    required String id,
    required double start,
    required double end,
    required GaitSegment segment,
    required Map<String, List<GaitCycle>> cyclesByLeg,
    required Map<String, DetectedGaitEvent> eventById,
  }) {
    final legSummaries = <String, LegTaktSummary>{};
    for (final entry in cyclesByLeg.entries) {
      legSummaries[entry.key] = _legSummary(entry.key, entry.value);
    }
    final meanDuration = _averageMetric(
      legSummaries.values.map((summary) => summary.meanCycleDuration).toList(),
      's',
      'leg_cycle_duration_unavailable',
    );
    final frequency = _reciprocalMetric(meanDuration, 'Hz');
    final variability = _averageMetric(
      legSummaries.values
          .map(
            (summary) => summary.cycleDurationCoefficientOfVariation,
          )
          .toList(),
      'percent',
      'leg_cycle_variability_unavailable',
    );
    final drift = _averageMetric(
      cyclesByLeg.values.map(_driftMetric).toList(),
      's/s',
      'leg_cycle_drift_unavailable',
    );
    final relations = _phaseRelations(
      segment.gait,
      cyclesByLeg,
      eventById,
    );
    final phaseDispersion = _averageMetric(
      relations.map((relation) => relation.circularStandardDeviation).toList(),
      'cycle_fraction',
      'phase_relations_unavailable',
    );
    final symmetry = _symmetryMetric(relations);
    return TaktAnalysisWindow(
      id: id,
      startSeconds: start,
      endSeconds: end,
      gait: segment.gait,
      ridingDirection: segment.ridingDirection,
      valid: true,
      invalidReasons: const [],
      legSummaries: Map.unmodifiable(legSummaries),
      meanCycleDuration: meanDuration,
      cycleFrequency: frequency,
      cycleDurationVariability: variability,
      cycleDurationDrift: drift,
      phaseRelations: List.unmodifiable(relations),
      phaseDispersion: phaseDispersion,
      temporalSymmetryDeviation: symmetry,
      comparisons: const [],
      explanatoryObservations: const ['comparison_window_not_yet_available'],
    );
  }

  LegTaktSummary _legSummary(String label, List<GaitCycle> cycles) {
    final durations = cycles.map((cycle) => cycle.durationSeconds).toList();
    final uncertainties = cycles
        .map((cycle) => cycle.durationUncertaintyMilliseconds / 1000)
        .toList();
    final mean = _meanMetric(durations, uncertainties, 's');
    return LegTaktSummary(
      sensorLabel: label,
      validCycleCount: cycles.length,
      cycleIds: cycles.map((cycle) => cycle.id).toList(),
      meanCycleDuration: mean,
      cycleDurationStandardDeviation:
          _standardDeviationMetric(durations, uncertainties, 's'),
      cycleDurationCoefficientOfVariation:
          _coefficientOfVariationMetric(durations, uncertainties),
      cycleFrequency: _reciprocalMetric(mean, 'Hz'),
    );
  }

  List<TaktPhaseRelation> _phaseRelations(
    GaitLabel gait,
    Map<String, List<GaitCycle>> cyclesByLeg,
    Map<String, DetectedGaitEvent> eventById,
  ) {
    final specifications = <(String, String, double?)>[
      ('VL', 'VR', 0.5),
      ('HL', 'HR', 0.5),
      ('VL', 'HR', gait == GaitLabel.trot ? 0.0 : null),
      ('VR', 'HL', gait == GaitLabel.trot ? 0.0 : null),
    ];
    return [
      for (final specification in specifications)
        _phaseRelation(
          specification.$1,
          specification.$2,
          specification.$3,
          cyclesByLeg,
          eventById,
        ),
    ];
  }

  TaktPhaseRelation _phaseRelation(
    String referenceLabel,
    String targetLabel,
    double? expectedPhase,
    Map<String, List<GaitCycle>> cyclesByLeg,
    Map<String, DetectedGaitEvent> eventById,
  ) {
    final references = cyclesByLeg[referenceLabel] ?? const [];
    final targets = cyclesByLeg[targetLabel] ?? const [];
    final phases = <double>[];
    final phaseUncertainties = <double>[];
    final sourceIds = <String>[];
    for (final reference in references) {
      GaitCycle? target;
      var bestDistance = double.infinity;
      for (final candidate in targets) {
        final rawPhase = (candidate.startSeconds - reference.startSeconds) /
            reference.durationSeconds;
        if (rawPhase.abs() > 0.75) continue;
        final phaseDistance = expectedPhase == null
            ? _circularDistance(_fraction(rawPhase), 0)
            : _circularDistance(_fraction(rawPhase), expectedPhase);
        final timeDistance =
            phaseDistance * reference.durationSeconds + rawPhase.abs() * 1e-9;
        if (timeDistance < bestDistance) {
          bestDistance = timeDistance;
          target = candidate;
        }
      }
      if (target == null || bestDistance > reference.durationSeconds * 0.35) {
        continue;
      }
      final phase = _fraction(
        (target.startSeconds - reference.startSeconds) /
            reference.durationSeconds,
      );
      final referenceEvent = eventById[reference.startEventId];
      final targetEvent = eventById[target.startEventId];
      if (referenceEvent == null || targetEvent == null) continue;
      final phaseUncertainty = math.sqrt(
            math.pow(referenceEvent.sourceUncertaintyMilliseconds, 2) +
                math.pow(targetEvent.sourceUncertaintyMilliseconds, 2),
          ) /
          1000 /
          reference.durationSeconds;
      phases.add(phase);
      phaseUncertainties.add(phaseUncertainty);
      sourceIds.add('${reference.id}|${target.id}');
    }
    if (phases.length < 2) {
      const reason = 'insufficient_phase_pairs';
      return TaktPhaseRelation(
        referenceSensor: referenceLabel,
        targetSensor: targetLabel,
        sampleCount: phases.length,
        meanPhase: const TaktMetric.invalid(
          unit: 'cycle_fraction',
          invalidReason: reason,
        ),
        circularStandardDeviation: const TaktMetric.invalid(
          unit: 'cycle_fraction',
          invalidReason: reason,
        ),
        expectedPhase: expectedPhase,
        absoluteExpectedPhaseDeviation: const TaktMetric.invalid(
          unit: 'cycle_fraction',
          invalidReason: reason,
        ),
        sourceCycleIds: sourceIds,
      );
    }
    final meanPhaseValue = _circularMean(phases);
    final dispersionValue = _circularStandardDeviation(phases);
    final meanPhaseUncertainty = math.sqrt(
      math.pow(dispersionValue / math.sqrt(phases.length), 2) +
          math.pow(
            math.sqrt(
                  phaseUncertainties
                      .map((value) => value * value)
                      .reduce((left, right) => left + right),
                ) /
                phases.length,
            2,
          ),
    );
    final dispersionUncertainty = _jackknifeStandardError(
      phases,
      _circularStandardDeviation,
    );
    final meanMetric = _metric(
      meanPhaseValue,
      meanPhaseUncertainty,
      'cycle_fraction',
    );
    final dispersionMetric = _metric(
      dispersionValue,
      dispersionUncertainty,
      'cycle_fraction',
    );
    final expectedDeviation = expectedPhase == null
        ? const TaktMetric.invalid(
            unit: 'cycle_fraction',
            invalidReason: 'no_fixed_expected_phase_for_this_relation',
          )
        : _metric(
            _circularDistance(meanPhaseValue, expectedPhase),
            meanPhaseUncertainty,
            'cycle_fraction',
          );
    return TaktPhaseRelation(
      referenceSensor: referenceLabel,
      targetSensor: targetLabel,
      sampleCount: phases.length,
      meanPhase: meanMetric,
      circularStandardDeviation: dispersionMetric,
      expectedPhase: expectedPhase,
      absoluteExpectedPhaseDeviation: expectedDeviation,
      sourceCycleIds: sourceIds,
    );
  }

  TaktMetric _symmetryMetric(List<TaktPhaseRelation> relations) {
    final contralateral = relations.where(
      (relation) =>
          (relation.referenceSensor == 'VL' && relation.targetSensor == 'VR') ||
          (relation.referenceSensor == 'HL' && relation.targetSensor == 'HR'),
    );
    final deviations = contralateral
        .map((relation) => relation.absoluteExpectedPhaseDeviation)
        .where((metric) => metric.valid)
        .toList();
    if (deviations.length != 2) {
      return const TaktMetric.invalid(
        unit: 'percent_cycle',
        invalidReason: 'contralateral_phase_relations_unavailable',
      );
    }
    final value =
        deviations.map((metric) => metric.value!).reduce((a, b) => a + b) /
            deviations.length *
            100;
    final uncertainty = math.sqrt(
          deviations
              .map(
                (metric) => math.pow(metric.standardUncertainty! * 100, 2),
              )
              .reduce((a, b) => a + b),
        ) /
        deviations.length;
    return _metric(value, uncertainty, 'percent_cycle');
  }

  TaktMetric _driftMetric(List<GaitCycle> cycles) {
    if (cycles.length < 3) {
      return const TaktMetric.invalid(
        unit: 's/s',
        invalidReason: 'insufficient_cycles_for_drift',
      );
    }
    final times = cycles
        .map((cycle) => (cycle.startSeconds + cycle.endSeconds) / 2)
        .toList();
    final durations = cycles.map((cycle) => cycle.durationSeconds).toList();
    final meanTime = _mean(times);
    final meanDuration = _mean(durations);
    var denominator = 0.0;
    var numerator = 0.0;
    for (var index = 0; index < cycles.length; index++) {
      final deltaTime = times[index] - meanTime;
      denominator += deltaTime * deltaTime;
      numerator += deltaTime * (durations[index] - meanDuration);
    }
    if (denominator <= 0) {
      return const TaktMetric.invalid(
        unit: 's/s',
        invalidReason: 'zero_time_span_for_drift',
      );
    }
    final slope = numerator / denominator;
    var residualSquares = 0.0;
    for (var index = 0; index < cycles.length; index++) {
      final fitted = meanDuration + slope * (times[index] - meanTime);
      residualSquares += math.pow(durations[index] - fitted, 2);
    }
    final residualVariance = residualSquares / math.max(1, cycles.length - 2);
    final regressionUncertainty = math.sqrt(residualVariance / denominator);
    final measurementUncertainty = math.sqrt(
          cycles
              .map(
                (cycle) => math.pow(
                  cycle.durationUncertaintyMilliseconds / 1000,
                  2,
                ),
              )
              .reduce((a, b) => a + b),
        ) /
        cycles.length /
        math.sqrt(denominator / cycles.length);
    return _metric(
      slope,
      math.sqrt(
        regressionUncertainty * regressionUncertainty +
            measurementUncertainty * measurementUncertainty,
      ),
      's/s',
    );
  }

  List<TaktAnalysisWindow> _addComparisons(
    List<TaktAnalysisWindow> windows,
  ) {
    final output = <TaktAnalysisWindow>[];
    for (final current in windows) {
      if (!current.valid) {
        output.add(current);
        continue;
      }
      TaktAnalysisWindow? comparison;
      for (final candidate in output.where(
        (window) =>
            window.valid &&
            window.gait == current.gait &&
            window.ridingDirection == current.ridingDirection &&
            window.endSeconds <= current.startSeconds + 1e-9,
      )) {
        if (comparison == null ||
            candidate.endSeconds > comparison.endSeconds) {
          comparison = candidate;
        }
      }
      if (comparison == null ||
          current.startSeconds - comparison.endSeconds >
              config.stepSeconds * 1.01) {
        output.add(current);
        continue;
      }
      final comparisons = [
        _compare(
          'cycle_duration_variability',
          current.cycleDurationVariability,
          comparison.cycleDurationVariability,
          comparison.id,
          lowerIsMoreStable: true,
        ),
        _compare(
          'cycle_duration_drift',
          current.cycleDurationDrift,
          comparison.cycleDurationDrift,
          comparison.id,
          lowerIsMoreStable: true,
          compareAbsoluteValues: true,
        ),
        _compare(
          'phase_dispersion',
          current.phaseDispersion,
          comparison.phaseDispersion,
          comparison.id,
          lowerIsMoreStable: true,
        ),
        _compare(
          'temporal_symmetry_deviation',
          current.temporalSymmetryDeviation,
          comparison.temporalSymmetryDeviation,
          comparison.id,
          lowerIsMoreStable: true,
        ),
        _compare(
          'cycle_frequency',
          current.cycleFrequency,
          comparison.cycleFrequency,
          comparison.id,
          lowerIsMoreStable: false,
        ),
      ];
      final observations = <String>[];
      for (final value in comparisons) {
        switch (value.assessment) {
          case TaktChangeAssessment.improved:
            observations.add('${value.component}_improved');
          case TaktChangeAssessment.worsened:
            observations.add('${value.component}_worsened');
          case TaktChangeAssessment.changedWithoutValence:
            observations.add('${value.component}_changed');
          case TaktChangeAssessment.stableWithinUncertainty:
            observations.add('${value.component}_stable_within_uncertainty');
          case TaktChangeAssessment.comparisonUnavailable:
            observations.add('${value.component}_comparison_unavailable');
        }
      }
      output.add(
        current.withComparison(
          comparisons: List.unmodifiable(comparisons),
          explanatoryObservations: List.unmodifiable(observations),
        ),
      );
    }
    return output;
  }

  TaktMetricComparison _compare(
    String component,
    TaktMetric current,
    TaktMetric comparison,
    String comparisonWindowId, {
    required bool lowerIsMoreStable,
    bool compareAbsoluteValues = false,
  }) {
    if (!current.valid || !comparison.valid) {
      return TaktMetricComparison(
        component: component,
        assessment: TaktChangeAssessment.comparisonUnavailable,
        currentValue: current.value,
        comparisonValue: comparison.value,
        delta: null,
        combinedStandardUncertainty: null,
        comparisonWindowId: comparisonWindowId,
      );
    }
    final currentValue =
        compareAbsoluteValues ? current.value!.abs() : current.value!;
    final comparisonValue =
        compareAbsoluteValues ? comparison.value!.abs() : comparison.value!;
    final delta = currentValue - comparisonValue;
    final uncertainty = math.sqrt(
      math.pow(current.standardUncertainty!, 2) +
          math.pow(comparison.standardUncertainty!, 2),
    );
    final significant =
        delta.abs() > config.confidenceIntervalMultiplier * uncertainty;
    final assessment = !significant
        ? TaktChangeAssessment.stableWithinUncertainty
        : !lowerIsMoreStable
            ? TaktChangeAssessment.changedWithoutValence
            : delta < 0
                ? TaktChangeAssessment.improved
                : TaktChangeAssessment.worsened;
    return TaktMetricComparison(
      component: component,
      assessment: assessment,
      currentValue: currentValue,
      comparisonValue: comparisonValue,
      delta: delta,
      combinedStandardUncertainty: uncertainty,
      comparisonWindowId: comparisonWindowId,
    );
  }

  TaktAnalysisWindow _invalidWindow({
    required String id,
    required double start,
    required double end,
    required GaitSegment segment,
    required List<String> reasons,
    Map<String, List<GaitCycle>> cyclesByLeg = const {},
  }) {
    final reason = reasons.join('|');
    final summaries = <String, LegTaktSummary>{};
    for (final label in config.requiredLegLabels) {
      final cycles = cyclesByLeg[label] ?? const [];
      final invalidSeconds = TaktMetric.invalid(
        unit: 's',
        invalidReason: reason,
      );
      final invalidPercent = TaktMetric.invalid(
        unit: 'percent',
        invalidReason: reason,
      );
      summaries[label] = LegTaktSummary(
        sensorLabel: label,
        validCycleCount: cycles.length,
        cycleIds: cycles.map((cycle) => cycle.id).toList(),
        meanCycleDuration: invalidSeconds,
        cycleDurationStandardDeviation: invalidSeconds,
        cycleDurationCoefficientOfVariation: invalidPercent,
        cycleFrequency: TaktMetric.invalid(
          unit: 'Hz',
          invalidReason: reason,
        ),
      );
    }
    return TaktAnalysisWindow(
      id: id,
      startSeconds: start,
      endSeconds: end,
      gait: segment.gait,
      ridingDirection: segment.ridingDirection,
      valid: false,
      invalidReasons: List.unmodifiable(reasons),
      legSummaries: Map.unmodifiable(summaries),
      meanCycleDuration: TaktMetric.invalid(unit: 's', invalidReason: reason),
      cycleFrequency: TaktMetric.invalid(unit: 'Hz', invalidReason: reason),
      cycleDurationVariability:
          TaktMetric.invalid(unit: 'percent', invalidReason: reason),
      cycleDurationDrift:
          TaktMetric.invalid(unit: 's/s', invalidReason: reason),
      phaseRelations: const [],
      phaseDispersion: TaktMetric.invalid(
        unit: 'cycle_fraction',
        invalidReason: reason,
      ),
      temporalSymmetryDeviation: TaktMetric.invalid(
        unit: 'percent_cycle',
        invalidReason: reason,
      ),
      comparisons: const [],
      explanatoryObservations: const [],
    );
  }

  TaktMetric _meanMetric(
    List<double> values,
    List<double> measurementUncertainties,
    String unit,
  ) {
    if (values.isEmpty || values.length != measurementUncertainties.length) {
      return TaktMetric.invalid(
        unit: unit,
        invalidReason: 'missing_values_or_uncertainties',
      );
    }
    final value = _mean(values);
    final sampleDeviation = _sampleStandardDeviation(values);
    final sampleUncertainty =
        values.length > 1 ? sampleDeviation / math.sqrt(values.length) : 0.0;
    final measurementUncertainty = math.sqrt(
          measurementUncertainties
              .map((uncertainty) => uncertainty * uncertainty)
              .reduce((a, b) => a + b),
        ) /
        values.length;
    return _metric(
      value,
      math.sqrt(
        sampleUncertainty * sampleUncertainty +
            measurementUncertainty * measurementUncertainty,
      ),
      unit,
    );
  }

  TaktMetric _standardDeviationMetric(
    List<double> values,
    List<double> measurementUncertainties,
    String unit,
  ) {
    if (values.length < 2) {
      return TaktMetric.invalid(
        unit: unit,
        invalidReason: 'insufficient_values_for_standard_deviation',
      );
    }
    final value = _sampleStandardDeviation(values);
    final jackknife = _jackknifeStandardError(
      values,
      _sampleStandardDeviation,
    );
    final measurement = math.sqrt(
          measurementUncertainties
              .map((uncertainty) => uncertainty * uncertainty)
              .reduce((a, b) => a + b),
        ) /
        values.length;
    return _metric(
      value,
      math.sqrt(jackknife * jackknife + measurement * measurement),
      unit,
    );
  }

  TaktMetric _coefficientOfVariationMetric(
    List<double> values,
    List<double> measurementUncertainties,
  ) {
    if (values.length < 2 || _mean(values) == 0) {
      return const TaktMetric.invalid(
        unit: 'percent',
        invalidReason: 'insufficient_values_for_variability',
      );
    }
    double coefficient(List<double> sample) =>
        100 * _sampleStandardDeviation(sample) / _mean(sample);
    final value = coefficient(values);
    final jackknife = _jackknifeStandardError(values, coefficient);
    final measurement = 100 *
        math.sqrt(
          measurementUncertainties
              .map((uncertainty) => uncertainty * uncertainty)
              .reduce((a, b) => a + b),
        ) /
        values.length /
        _mean(values);
    return _metric(
      value,
      math.sqrt(jackknife * jackknife + measurement * measurement),
      'percent',
    );
  }

  TaktMetric _reciprocalMetric(TaktMetric source, String unit) {
    if (!source.valid || source.value == 0) {
      return TaktMetric.invalid(
        unit: unit,
        invalidReason: source.invalidReason ?? 'zero_source_value',
      );
    }
    final value = 1 / source.value!;
    final uncertainty =
        source.standardUncertainty! / math.pow(source.value!, 2);
    return _metric(value, uncertainty, unit);
  }

  TaktMetric _averageMetric(
    List<TaktMetric> metrics,
    String unit,
    String invalidReason,
  ) {
    final valid = metrics.where((metric) => metric.valid).toList();
    if (valid.isEmpty) {
      return TaktMetric.invalid(unit: unit, invalidReason: invalidReason);
    }
    final value = _mean(valid.map((metric) => metric.value!).toList());
    final propagatedUncertainty = math.sqrt(
          valid
              .map(
                (metric) => math.pow(metric.standardUncertainty!, 2),
              )
              .reduce((a, b) => a + b),
        ) /
        valid.length;
    final betweenLegUncertainty = valid.length < 2
        ? 0.0
        : _sampleStandardDeviation(
              valid.map((metric) => metric.value!).toList(),
            ) /
            math.sqrt(valid.length);
    return _metric(
      value,
      math.sqrt(
        propagatedUncertainty * propagatedUncertainty +
            betweenLegUncertainty * betweenLegUncertainty,
      ),
      unit,
    );
  }

  TaktMetric _metric(double value, double uncertainty, String unit) {
    final safeUncertainty =
        uncertainty.isFinite && uncertainty >= 0 ? uncertainty : 0.0;
    final margin = config.confidenceIntervalMultiplier * safeUncertainty;
    return TaktMetric.valid(
      value: value,
      unit: unit,
      standardUncertainty: safeUncertainty,
      confidenceIntervalLower: value - margin,
      confidenceIntervalUpper: value + margin,
    );
  }

  void _validateConfig() {
    if (!config.minimumWindowSeconds.isFinite ||
        config.minimumWindowSeconds <= 0 ||
        !config.maximumWindowSeconds.isFinite ||
        config.maximumWindowSeconds < config.minimumWindowSeconds ||
        !config.stepSeconds.isFinite ||
        config.stepSeconds <= 0 ||
        config.minimumValidCyclesPerLeg < 2 ||
        !config.confidenceIntervalMultiplier.isFinite ||
        config.confidenceIntervalMultiplier <= 0 ||
        config.requiredLegLabels.toSet().length !=
            config.requiredLegLabels.length ||
        !const {'VL', 'VR', 'HL', 'HR'}.containsAll(config.requiredLegLabels)) {
      throw ArgumentError('Ungültige Taktparameterkonfiguration.');
    }
  }

  TaktParameterResult _failed(
    List<TaktParameterIssue> issues,
    String code,
    String observation,
  ) =>
      TaktParameterResult(
        status: TaktParameterStatus.notPossible,
        windows: const [],
        issues: [
          ...issues,
          TaktParameterIssue(
            code: code,
            observation: observation,
            uncertainty: 'Taktparameter können nicht berechnet werden.',
            recommendation: 'Vorgelagerte Stufen und Eingaben prüfen.',
          ),
        ],
        config: config,
        assumptions: assumptions,
      );
}

double _mean(List<double> values) =>
    values.reduce((left, right) => left + right) / values.length;

double _sampleStandardDeviation(List<double> values) {
  if (values.length < 2) return 0;
  final mean = _mean(values);
  return math.sqrt(
    values
            .map((value) => math.pow(value - mean, 2))
            .reduce((left, right) => left + right) /
        (values.length - 1),
  );
}

double _jackknifeStandardError(
  List<double> values,
  double Function(List<double>) estimator,
) {
  if (values.length < 3) return 0;
  final estimates = <double>[];
  for (var excluded = 0; excluded < values.length; excluded++) {
    estimates.add(
      estimator([
        for (var index = 0; index < values.length; index++)
          if (index != excluded) values[index],
      ]),
    );
  }
  final mean = _mean(estimates);
  return math.sqrt(
    (estimates.length - 1) /
        estimates.length *
        estimates
            .map((value) => math.pow(value - mean, 2))
            .reduce((left, right) => left + right),
  );
}

double _fraction(double value) {
  final result = value - value.floorToDouble();
  return result >= 1 ? 0 : result;
}

double _circularDistance(double left, double right) {
  final difference = (left - right).abs();
  return math.min(difference, 1 - difference);
}

double _circularMean(List<double> phases) {
  final x = phases
          .map((phase) => math.cos(2 * math.pi * phase))
          .reduce((a, b) => a + b) /
      phases.length;
  final y = phases
          .map((phase) => math.sin(2 * math.pi * phase))
          .reduce((a, b) => a + b) /
      phases.length;
  final angle = math.atan2(y, x) / (2 * math.pi);
  return angle < 0 ? angle + 1 : angle;
}

double _circularStandardDeviation(List<double> phases) {
  if (phases.length < 2) return 0;
  final x = phases
          .map((phase) => math.cos(2 * math.pi * phase))
          .reduce((a, b) => a + b) /
      phases.length;
  final y = phases
          .map((phase) => math.sin(2 * math.pi * phase))
          .reduce((a, b) => a + b) /
      phases.length;
  final resultant = math.sqrt(x * x + y * y).clamp(1e-12, 1.0);
  return math.sqrt(-2 * math.log(resultant)) / (2 * math.pi);
}
