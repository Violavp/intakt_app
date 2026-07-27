import 'dart:math' as math;

import '../imu_import/imu_models.dart';

enum TimeReconstructionStatus { accepted, reviewRequired, notPossible }

enum LossDetermination { notObserved, suspected, notDeterminable }

class IndexTimeReconstructionConfig {
  const IndexTimeReconstructionConfig({
    this.defaultNominalSamplingRateHz = 100,
    this.nominalSamplingRatesHz = const {},
    this.targetSamplingRateHz = 100,
    this.maximumInterpolationGapFactor = 3,
    this.suspectedPacketGapFactor = 2.5,
    this.receptionTimestampResolution = const Duration(milliseconds: 1),
    this.defaultAnchorUncertainty = const Duration(milliseconds: 20),
    this.maximumAnchorResidual = const Duration(milliseconds: 100),
    this.minimumSamplesPerSensor = 2,
  });

  /// Configured sensor rate, not inferred from reception timestamps. Unit: Hz.
  final double defaultNominalSamplingRateHz;
  final Map<String, double> nominalSamplingRatesHz;

  /// Common reconstructed output grid. Unit: Hz.
  final double targetSamplingRateHz;

  /// Interpolation does not bridge a reconstructed source interval larger
  /// than this factor times the nominal interval.
  final double maximumInterpolationGapFactor;

  /// Reception gaps above this factor are reported as suspected transport
  /// gaps. They are never silently converted to missing samples.
  final double suspectedPacketGapFactor;
  final Duration receptionTimestampResolution;
  final Duration defaultAnchorUncertainty;
  final Duration maximumAnchorResidual;
  final int minimumSamplesPerSensor;
}

/// A manually or externally assigned event linking video time to one raw row.
class VideoImuAnchor {
  const VideoImuAnchor({
    required this.id,
    required this.sensorLabel,
    required this.videoTimeSeconds,
    required this.rawSourceLine,
    this.rawSourceName,
    this.uncertaintyMilliseconds,
    this.assignment,
  });

  final String id;
  final String sensorLabel;
  final double videoTimeSeconds;
  final int rawSourceLine;
  final String? rawSourceName;
  final double? uncertaintyMilliseconds;
  final String? assignment;

  Map<String, Object?> toJson() => {
        'id': id,
        'sensor': sensorLabel,
        'video_time_s': videoTimeSeconds,
        'raw_source_name': rawSourceName,
        'raw_source_line': rawSourceLine,
        'uncertainty_ms': uncertaintyMilliseconds,
        'assignment': assignment,
      };
}

class BleReceptionPacket {
  const BleReceptionPacket({
    required this.packetIndex,
    required this.receptionTimestamp,
    required this.rawTimestamp,
    required this.firstSampleIndex,
    required this.lastSampleIndex,
    required this.firstSourceLine,
    required this.lastSourceLine,
  });

  final int packetIndex;
  final DateTime receptionTimestamp;
  final String rawTimestamp;
  final int firstSampleIndex;
  final int lastSampleIndex;
  final int firstSourceLine;
  final int lastSourceLine;

  int get sampleCount => lastSampleIndex - firstSampleIndex + 1;

  Map<String, Object> toJson() => {
        'packet_index': packetIndex,
        'reception_timestamp': receptionTimestamp.toIso8601String(),
        'raw_timestamp': rawTimestamp,
        'first_sample_index': firstSampleIndex,
        'last_sample_index': lastSampleIndex,
        'sample_count': sampleCount,
        'first_source_line': firstSourceLine,
        'last_source_line': lastSourceLine,
      };
}

class SuspectedTransportGap {
  const SuspectedTransportGap({
    required this.afterPacketIndex,
    required this.beforePacketIndex,
    required this.receptionGapMilliseconds,
    required this.expectedCoveredMilliseconds,
    required this.possibleMissingSamples,
  });

  final int afterPacketIndex;
  final int beforePacketIndex;
  final double receptionGapMilliseconds;
  final double expectedCoveredMilliseconds;

  /// Reception-time indication only; never inserted into the sample index.
  final int possibleMissingSamples;

  Map<String, Object> toJson() => {
        'after_packet_index': afterPacketIndex,
        'before_packet_index': beforePacketIndex,
        'reception_gap_ms': receptionGapMilliseconds,
        'expected_covered_ms': expectedCoveredMilliseconds,
        'possible_missing_samples': possibleMissingSamples,
        'classification': 'SUSPECTED_NOT_PROVEN',
      };
}

class ReconstructedSample {
  const ReconstructedSample({
    required this.sampleIndex,
    required this.packetIndex,
    required this.indexTimeSeconds,
    required this.analysisTimeSeconds,
    required this.uncertaintyMilliseconds,
    required this.rawSample,
  });

  final int sampleIndex;
  final int packetIndex;
  final double indexTimeSeconds;
  final double analysisTimeSeconds;
  final double uncertaintyMilliseconds;

  /// Original immutable imported object; order and timestamps are unchanged.
  final ImuSample rawSample;
}

class ResampledImuValue {
  const ResampledImuValue({
    required this.accelerationMps2,
    required this.angularVelocityRadPerSecond,
    required this.magneticFieldMicrotesla,
    required this.lowerSampleIndex,
    required this.upperSampleIndex,
    required this.lowerSourceName,
    required this.lowerSourceLine,
    required this.upperSourceName,
    required this.upperSourceLine,
    required this.uncertaintyMilliseconds,
    this.orientationAnglesDegrees,
  });

  final Vector3 accelerationMps2;
  final Vector3 angularVelocityRadPerSecond;
  final Vector3? magneticFieldMicrotesla;
  final Vector3? orientationAnglesDegrees;
  final int lowerSampleIndex;
  final int upperSampleIndex;
  final String lowerSourceName;
  final int lowerSourceLine;
  final String upperSourceName;
  final int upperSourceLine;
  final double uncertaintyMilliseconds;
}

class ReconstructedTimeFrame {
  const ReconstructedTimeFrame({
    required this.analysisTimeSeconds,
    required this.values,
  });

  final double analysisTimeSeconds;
  final Map<String, ResampledImuValue?> values;
}

class AnchorFitEvidence {
  const AnchorFitEvidence({
    required this.anchor,
    required this.sampleIndex,
    required this.indexTimeSeconds,
    required this.fittedAnalysisTimeSeconds,
    required this.residualMilliseconds,
  });

  final VideoImuAnchor anchor;
  final int sampleIndex;
  final double indexTimeSeconds;
  final double fittedAnalysisTimeSeconds;
  final double residualMilliseconds;

  Map<String, Object?> toJson() => {
        ...anchor.toJson(),
        'sample_index': sampleIndex,
        'index_time_s': indexTimeSeconds,
        'fitted_analysis_time_s': fittedAnalysisTimeSeconds,
        'fit_residual_ms': residualMilliseconds,
      };
}

class SensorTimeReconstruction {
  const SensorTimeReconstruction({
    required this.sensorLabel,
    required this.valid,
    required this.nominalSamplingRateHz,
    required this.effectiveSamplingRateHz,
    required this.packetCount,
    required this.duplicateReceptionTimestampSamples,
    required this.offsetSeconds,
    required this.timeGradient,
    required this.estimatedDriftPpm,
    required this.anchorResidualRmseMilliseconds,
    required this.maximumAbsoluteAnchorResidualMilliseconds,
    required this.baseUncertaintyMilliseconds,
    required this.lossDetermination,
    required this.lossReason,
    required this.packets,
    required this.suspectedTransportGaps,
    required this.anchorEvidence,
    required this.samples,
    required this.invalidReason,
  });

  final String sensorLabel;
  final bool valid;
  final double nominalSamplingRateHz;
  final double? effectiveSamplingRateHz;
  final int packetCount;
  final int duplicateReceptionTimestampSamples;

  /// analysis_time_s = offset_s + time_gradient * index_time_s.
  final double? offsetSeconds;
  final double? timeGradient;
  final double? estimatedDriftPpm;
  final double? anchorResidualRmseMilliseconds;
  final double? maximumAbsoluteAnchorResidualMilliseconds;
  final double? baseUncertaintyMilliseconds;
  final LossDetermination lossDetermination;
  final String lossReason;
  final List<BleReceptionPacket> packets;
  final List<SuspectedTransportGap> suspectedTransportGaps;
  final List<AnchorFitEvidence> anchorEvidence;
  final List<ReconstructedSample> samples;
  final String? invalidReason;

  Map<String, Object?> toJson() => {
        'sensor': sensorLabel,
        'valid': valid,
        'time_basis': 'RECONSTRUCTED_INDEX_TIME',
        'nominal_sampling_rate_hz': nominalSamplingRateHz,
        'effective_sampling_rate_hz': effectiveSamplingRateHz,
        'sample_count': samples.length,
        'packet_count': packetCount,
        'duplicate_reception_timestamp_samples':
            duplicateReceptionTimestampSamples,
        'offset_s': offsetSeconds,
        'time_gradient': timeGradient,
        'estimated_drift_ppm': estimatedDriftPpm,
        'anchor_residual_rmse_ms': anchorResidualRmseMilliseconds,
        'maximum_absolute_anchor_residual_ms':
            maximumAbsoluteAnchorResidualMilliseconds,
        'base_uncertainty_ms': baseUncertaintyMilliseconds,
        if (samples.isNotEmpty)
          'sample_uncertainty_ms': {
            'minimum': samples
                .map((sample) => sample.uncertaintyMilliseconds)
                .reduce(math.min),
            'maximum': samples
                .map((sample) => sample.uncertaintyMilliseconds)
                .reduce(math.max),
          },
        'loss_determination': lossDetermination.name,
        'loss_reason': lossReason,
        'packet_size_distribution': {
          for (final size
              in packets.map((packet) => packet.sampleCount).toSet())
            '$size':
                packets.where((packet) => packet.sampleCount == size).length,
        },
        'suspected_transport_gaps':
            suspectedTransportGaps.map((gap) => gap.toJson()).toList(),
        'anchors': anchorEvidence.map((anchor) => anchor.toJson()).toList(),
        if (invalidReason != null) 'invalid_reason': invalidReason,
      };
}

class IndexTimeReconstructionIssue {
  const IndexTimeReconstructionIssue({
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

class IndexTimeReconstructionResult {
  const IndexTimeReconstructionResult({
    required this.status,
    required this.gridSamplingRateHz,
    required this.gridPeriodMicroseconds,
    required this.commonStartSeconds,
    required this.commonEndSeconds,
    required this.sensors,
    required this.frames,
    required this.issues,
    required this.assumptions,
  });

  final TimeReconstructionStatus status;
  final double gridSamplingRateHz;
  final int gridPeriodMicroseconds;
  final double? commonStartSeconds;
  final double? commonEndSeconds;
  final Map<String, SensorTimeReconstruction> sensors;
  final List<ReconstructedTimeFrame> frames;
  final List<IndexTimeReconstructionIssue> issues;
  final List<String> assumptions;

  bool get hasReconstructedDataset =>
      status != TimeReconstructionStatus.notPossible && frames.isNotEmpty;

  Map<String, Object?> toJson() => {
        'status': switch (status) {
          TimeReconstructionStatus.accepted => 'TIME_RECONSTRUCTION_ACCEPTED',
          TimeReconstructionStatus.reviewRequired =>
            'TIME_RECONSTRUCTION_REVIEW_REQUIRED',
          TimeReconstructionStatus.notPossible =>
            'TIME_RECONSTRUCTION_NOT_POSSIBLE',
        },
        'time_basis': 'RECONSTRUCTED_INDEX_TIME',
        'time_basis_notice':
            'Analysezeiten sind rekonstruiert und keine Sensorzeitstempel.',
        'grid_sampling_rate_hz': gridSamplingRateHz,
        'grid_period_us': gridPeriodMicroseconds,
        'common_start_s': commonStartSeconds,
        'common_end_s': commonEndSeconds,
        'frame_count': frames.length,
        'assumptions': assumptions,
        'sensors': sensors.values.map((sensor) => sensor.toJson()).toList(),
        'issues': issues.map((issue) => issue.toJson()).toList(),
      };
}

/// Reconstructs sample times without modifying or sorting imported samples.
///
/// `index_time = sample_index / nominal_rate`
/// `analysis_time = offset + gradient * index_time`
class IndexTimeReconstructor {
  const IndexTimeReconstructor({
    this.config = const IndexTimeReconstructionConfig(),
  });

  final IndexTimeReconstructionConfig config;

  IndexTimeReconstructionResult reconstruct(
    ImuImportResult input,
    List<VideoImuAnchor> anchors,
  ) {
    _validateConfig();
    final requiredLabels =
        input.catalog.requiredSensors.map((sensor) => sensor.label).toList();
    final labels = [
      ...requiredLabels,
      for (final label in input.recordings.keys)
        if (!requiredLabels.contains(label) &&
            anchors.any((anchor) => anchor.sensorLabel == label))
          label,
    ];
    final issues = <IndexTimeReconstructionIssue>[];
    final sensors = <String, SensorTimeReconstruction>{};

    for (final label in labels) {
      final recording = input.recordings[label];
      if (recording == null && requiredLabels.contains(label)) {
        issues.add(
          IndexTimeReconstructionIssue(
            code: 'missing_required_sensor',
            sensorLabel: label,
            observation: 'Pflichtsensor $label fehlt.',
            uncertainty: 'Ein gemeinsames Raster ist nicht bestimmbar.',
            recommendation: 'Import und Sensorzuordnung prüfen.',
          ),
        );
        continue;
      }
      if (recording == null) continue;
      final nominalRate = config.nominalSamplingRatesHz[label] ??
          config.defaultNominalSamplingRateHz;
      final sensorAnchors =
          anchors.where((anchor) => anchor.sensorLabel == label).toList();
      sensors[label] =
          _reconstructSensor(recording, nominalRate, sensorAnchors, issues);
    }

    if (sensors.length != labels.length ||
        sensors.values.any((sensor) => !sensor.valid)) {
      return _emptyResult(
        status: TimeReconstructionStatus.notPossible,
        sensors: sensors,
        issues: issues,
      );
    }

    final start = sensors.values
        .map((sensor) => sensor.samples.first.analysisTimeSeconds)
        .reduce(math.max);
    final end = sensors.values
        .map((sensor) => sensor.samples.last.analysisTimeSeconds)
        .reduce(math.min);
    final periodMicros = (1000000 / config.targetSamplingRateHz).round();
    final startMicros =
        ((start * 1000000 / periodMicros).ceil()) * periodMicros;
    final endMicros = ((end * 1000000 / periodMicros).floor()) * periodMicros;
    if (endMicros < startMicros) {
      issues.add(
        const IndexTimeReconstructionIssue(
          code: 'empty_common_grid',
          observation:
              'Die rekonstruierten Sensorzeiträume überlappen sich nicht.',
          uncertainty: 'Ein gemeinsamer Datensatz kann nicht erzeugt werden.',
          recommendation: 'Videoanker und Sensorzuordnung prüfen.',
        ),
      );
      return _emptyResult(
        status: TimeReconstructionStatus.notPossible,
        sensors: sensors,
        issues: issues,
      );
    }

    final frames = <ReconstructedTimeFrame>[];
    for (var micros = startMicros;
        micros <= endMicros;
        micros += periodMicros) {
      final time = micros / 1000000;
      frames.add(
        ReconstructedTimeFrame(
          analysisTimeSeconds: time,
          values: {
            for (final entry in sensors.entries)
              entry.key: _interpolate(entry.value, time),
          },
        ),
      );
    }
    final review = sensors.values.any(
      (sensor) =>
          sensor.anchorEvidence.length < 2 ||
          sensor.lossDetermination != LossDetermination.notObserved,
    );
    return IndexTimeReconstructionResult(
      status: review
          ? TimeReconstructionStatus.reviewRequired
          : TimeReconstructionStatus.accepted,
      gridSamplingRateHz: config.targetSamplingRateHz,
      gridPeriodMicroseconds: periodMicros,
      commonStartSeconds: startMicros / 1000000,
      commonEndSeconds: endMicros / 1000000,
      sensors: sensors,
      frames: frames,
      issues: issues,
      assumptions: _assumptions,
    );
  }

  SensorTimeReconstruction _reconstructSensor(
    SensorRecording recording,
    double nominalRate,
    List<VideoImuAnchor> anchors,
    List<IndexTimeReconstructionIssue> issues,
  ) {
    final label = recording.identity.label;
    final samples = recording.samples;
    if (samples.length < config.minimumSamplesPerSensor) {
      return _invalidSensor(
        label,
        nominalRate,
        'Weniger als ${config.minimumSamplesPerSensor} Samples.',
      );
    }
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      if (!_finiteVector(sample.accelerationMps2) ||
          !_finiteVector(sample.angularVelocityRadPerSecond) ||
          (sample.magneticFieldMicrotesla != null &&
              !_finiteVector(sample.magneticFieldMicrotesla!)) ||
          (sample.orientationAnglesDegrees != null &&
              !_finiteVector(sample.orientationAnglesDegrees!))) {
        return _invalidSensor(
          label,
          nominalRate,
          'Nicht endlicher Messwert an Sampleindex $index.',
        );
      }
      if (index > 0 &&
          sample.timestamp.isBefore(samples[index - 1].timestamp)) {
        return _invalidSensor(
          label,
          nominalRate,
          'Rückwärts laufender Empfangszeitstempel an Sampleindex $index.',
        );
      }
    }

    final packets = _packets(samples);
    final effectiveRate = _effectiveRate(samples);
    final gaps = _suspectedGaps(packets, nominalRate);
    final duplicateSamples =
        packets.fold<int>(0, (sum, packet) => sum + packet.sampleCount - 1);
    final matched = <(VideoImuAnchor, int)>[];
    for (final anchor in anchors) {
      if (!anchor.videoTimeSeconds.isFinite ||
          anchor.videoTimeSeconds < 0 ||
          anchor.uncertaintyMilliseconds != null &&
              (!anchor.uncertaintyMilliseconds!.isFinite ||
                  anchor.uncertaintyMilliseconds! < 0)) {
        return _invalidSensor(label, nominalRate, 'Ungültiger Videoanker.');
      }
      final index = samples.indexWhere(
        (sample) =>
            sample.sourceLine == anchor.rawSourceLine &&
            (anchor.rawSourceName == null ||
                sample.sourceName == anchor.rawSourceName),
      );
      if (index < 0) {
        return _invalidSensor(
          label,
          nominalRate,
          'Videoanker ${anchor.id} verweist nicht auf eine Rohdatenzeile '
          'dieses Sensors.',
        );
      }
      matched.add((anchor, index));
    }
    if (matched.isEmpty) {
      issues.add(
        IndexTimeReconstructionIssue(
          code: 'missing_video_anchor',
          sensorLabel: label,
          observation: 'Kein Videoanker ist Sensor $label zugeordnet.',
          uncertainty: 'Der Offset zur gemeinsamen Videozeit ist unbekannt.',
          recommendation: 'Mindestens ein Ereignis bis zur Rohzeile zuordnen.',
        ),
      );
      return _invalidSensor(label, nominalRate, 'Kein Videoanker.');
    }

    final fit = _fit(matched, nominalRate, effectiveRate);
    final anchorEvidence = <AnchorFitEvidence>[
      for (final item in matched)
        AnchorFitEvidence(
          anchor: item.$1,
          sampleIndex: item.$2,
          indexTimeSeconds: item.$2 / nominalRate,
          fittedAnalysisTimeSeconds:
              fit.offsetSeconds + fit.gradient * item.$2 / nominalRate,
          residualMilliseconds: (item.$1.videoTimeSeconds -
                  (fit.offsetSeconds + fit.gradient * item.$2 / nominalRate)) *
              1000,
        ),
    ];
    final residuals = anchorEvidence
        .map((evidence) => evidence.residualMilliseconds)
        .toList();
    final rmse = math.sqrt(
      residuals.fold<double>(0, (sum, value) => sum + value * value) /
          residuals.length,
    );
    final maximumResidual =
        residuals.map((value) => value.abs()).reduce(math.max);
    if (maximumResidual > config.maximumAnchorResidual.inMicroseconds / 1000) {
      return _invalidSensor(
        label,
        nominalRate,
        'Videoanker-Residual ${maximumResidual.toStringAsFixed(3)} ms '
        'überschreitet die technische Grenze.',
      );
    }

    final packetHalfSpanMs = packets
            .map((packet) => (packet.sampleCount - 1) / nominalRate * 500)
            .reduce(math.max) +
        config.receptionTimestampResolution.inMicroseconds / 2000;
    final anchorUncertaintyMs = math.sqrt(
      matched
              .map((item) =>
                  item.$1.uncertaintyMilliseconds ??
                  config.defaultAnchorUncertainty.inMicroseconds / 1000)
              .map((value) => value * value)
              .reduce((a, b) => a + b) /
          matched.length,
    );
    final baseUncertainty = math.sqrt(rmse * rmse +
        anchorUncertaintyMs * anchorUncertaintyMs +
        packetHalfSpanMs * packetHalfSpanMs);
    final packetIndices = List<int>.filled(samples.length, 0);
    for (final packet in packets) {
      for (var index = packet.firstSampleIndex;
          index <= packet.lastSampleIndex;
          index++) {
        packetIndices[index] = packet.packetIndex;
      }
    }
    final reconstructed = <ReconstructedSample>[
      for (var index = 0; index < samples.length; index++)
        ReconstructedSample(
          sampleIndex: index,
          packetIndex: packetIndices[index],
          indexTimeSeconds: index / nominalRate,
          analysisTimeSeconds:
              fit.offsetSeconds + fit.gradient * index / nominalRate,
          uncertaintyMilliseconds: _sampleUncertainty(
            index: index,
            anchors: matched,
            nominalRate: nominalRate,
            gradient: fit.gradient,
            effectiveRate: effectiveRate,
            baseUncertaintyMilliseconds: baseUncertainty,
          ),
          rawSample: samples[index],
        ),
    ];
    final lossDetermination = gaps.isEmpty
        ? LossDetermination.notDeterminable
        : LossDetermination.suspected;
    final lossReason = gaps.isEmpty
        ? 'Ohne Sensor-Sequenznummer oder monotone Sensorzeit sind einzelne '
            'Paket- und Sampleverluste trotz unauffälliger Empfangsabstände '
            'nicht beweisbar.'
        : 'Auffällige BLE-Empfangsabstände sprechen für mögliche Verluste; '
            'Anzahl und Position bleiben ohne Sequenznummer unbestimmt.';
    if (anchors.length < 2) {
      issues.add(
        IndexTimeReconstructionIssue(
          code: 'single_anchor_rate_assumption',
          sensorLabel: label,
          observation:
              'Nur ein Videoanker liegt vor; der Gradient stammt aus der '
              'effektiven Empfangsrate.',
          uncertainty:
              'Clock-Drift und BLE-Paketierung sind damit nicht trennbar.',
          recommendation:
              'Je Sensor ein Ereignis am Anfang und Ende annotieren.',
        ),
      );
    }
    if (gaps.isNotEmpty) {
      issues.add(
        IndexTimeReconstructionIssue(
          code: 'suspected_transport_gap',
          sensorLabel: label,
          observation:
              '${gaps.length} auffällige BLE-Empfangslücke(n) erkannt.',
          uncertainty: lossReason,
          recommendation:
              'Künftige Exporte um Sensor-Sequenznummern und Sensorzeit ergänzen.',
        ),
      );
    }
    return SensorTimeReconstruction(
      sensorLabel: label,
      valid: true,
      nominalSamplingRateHz: nominalRate,
      effectiveSamplingRateHz: effectiveRate,
      packetCount: packets.length,
      duplicateReceptionTimestampSamples: duplicateSamples,
      offsetSeconds: fit.offsetSeconds,
      timeGradient: fit.gradient,
      estimatedDriftPpm: (fit.gradient - 1) * 1000000,
      anchorResidualRmseMilliseconds: rmse,
      maximumAbsoluteAnchorResidualMilliseconds: maximumResidual,
      baseUncertaintyMilliseconds: baseUncertainty,
      lossDetermination: lossDetermination,
      lossReason: lossReason,
      packets: packets,
      suspectedTransportGaps: gaps,
      anchorEvidence: anchorEvidence,
      samples: reconstructed,
      invalidReason: null,
    );
  }

  _TimeFit _fit(
    List<(VideoImuAnchor, int)> anchors,
    double nominalRate,
    double? effectiveRate,
  ) {
    if (anchors.length == 1) {
      final gradient =
          effectiveRate == null ? 1.0 : nominalRate / effectiveRate;
      return _TimeFit(
        offsetSeconds: anchors.first.$1.videoTimeSeconds -
            gradient * anchors.first.$2 / nominalRate,
        gradient: gradient,
      );
    }
    final xs = anchors.map((item) => item.$2 / nominalRate).toList();
    final ys = anchors.map((item) => item.$1.videoTimeSeconds).toList();
    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;
    var covariance = 0.0;
    var variance = 0.0;
    for (var index = 0; index < xs.length; index++) {
      covariance += (xs[index] - meanX) * (ys[index] - meanY);
      variance += math.pow(xs[index] - meanX, 2);
    }
    if (variance == 0) {
      throw ArgumentError(
          'Videoanker müssen verschiedene Sampleindizes haben.');
    }
    final gradient = covariance / variance;
    if (!gradient.isFinite || gradient <= 0) {
      throw ArgumentError(
          'Videoanker ergeben keinen positiven Zeitgradienten.');
    }
    return _TimeFit(
      offsetSeconds: meanY - gradient * meanX,
      gradient: gradient,
    );
  }

  List<BleReceptionPacket> _packets(List<ImuSample> samples) {
    final packets = <BleReceptionPacket>[];
    var first = 0;
    for (var index = 1; index <= samples.length; index++) {
      if (index < samples.length &&
          samples[index].timestamp == samples[first].timestamp) {
        continue;
      }
      packets.add(
        BleReceptionPacket(
          packetIndex: packets.length,
          receptionTimestamp: samples[first].timestamp,
          rawTimestamp: samples[first].rawTimestamp,
          firstSampleIndex: first,
          lastSampleIndex: index - 1,
          firstSourceLine: samples[first].sourceLine,
          lastSourceLine: samples[index - 1].sourceLine,
        ),
      );
      first = index;
    }
    return packets;
  }

  List<SuspectedTransportGap> _suspectedGaps(
    List<BleReceptionPacket> packets,
    double nominalRate,
  ) {
    final gaps = <SuspectedTransportGap>[];
    for (var index = 1; index < packets.length; index++) {
      final previous = packets[index - 1];
      final current = packets[index];
      final receptionGapMs = current.receptionTimestamp
              .difference(previous.receptionTimestamp)
              .inMicroseconds /
          1000;
      // A reception timestamp can describe a batch delivered since the
      // previous callback. At recording boundaries either adjacent packet can
      // be partial, so the larger batch is the conservative expectation.
      final expectedCoveredMs =
          math.max(previous.sampleCount, current.sampleCount) /
              nominalRate *
              1000;
      if (receptionGapMs >
          expectedCoveredMs * config.suspectedPacketGapFactor) {
        gaps.add(
          SuspectedTransportGap(
            afterPacketIndex: previous.packetIndex,
            beforePacketIndex: current.packetIndex,
            receptionGapMilliseconds: receptionGapMs,
            expectedCoveredMilliseconds: expectedCoveredMs,
            possibleMissingSamples: math.max(
                0,
                (receptionGapMs / 1000 * nominalRate).round() -
                    current.sampleCount),
          ),
        );
      }
    }
    return gaps;
  }

  ResampledImuValue? _interpolate(
    SensorTimeReconstruction sensor,
    double time,
  ) {
    final samples = sensor.samples;
    if (time < samples.first.analysisTimeSeconds ||
        time > samples.last.analysisTimeSeconds) {
      return null;
    }
    var low = 0;
    var high = samples.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final value = samples[middle].analysisTimeSeconds;
      if ((value - time).abs() < 1e-12) {
        low = middle;
        high = middle;
        break;
      }
      if (value < time) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    final lowerIndex = low == high ? low : high;
    final upperIndex = low == high ? low : low;
    if (lowerIndex < 0 || upperIndex >= samples.length) return null;
    final lower = samples[lowerIndex];
    final upper = samples[upperIndex];
    final gapSeconds = upper.analysisTimeSeconds - lower.analysisTimeSeconds;
    if (gapSeconds >
        config.maximumInterpolationGapFactor / sensor.nominalSamplingRateHz) {
      return null;
    }
    final fraction =
        gapSeconds == 0 ? 0.0 : (time - lower.analysisTimeSeconds) / gapSeconds;
    final lowerRaw = lower.rawSample;
    final upperRaw = upper.rawSample;
    return ResampledImuValue(
      accelerationMps2:
          _lerp(lowerRaw.accelerationMps2, upperRaw.accelerationMps2, fraction),
      angularVelocityRadPerSecond: _lerp(
        lowerRaw.angularVelocityRadPerSecond,
        upperRaw.angularVelocityRadPerSecond,
        fraction,
      ),
      magneticFieldMicrotesla: lowerRaw.magneticFieldMicrotesla != null &&
              upperRaw.magneticFieldMicrotesla != null
          ? _lerp(
              lowerRaw.magneticFieldMicrotesla!,
              upperRaw.magneticFieldMicrotesla!,
              fraction,
            )
          : null,
      orientationAnglesDegrees: lowerRaw.orientationAnglesDegrees != null &&
              upperRaw.orientationAnglesDegrees != null
          ? _lerpCircularDegrees(
              lowerRaw.orientationAnglesDegrees!,
              upperRaw.orientationAnglesDegrees!,
              fraction,
            )
          : null,
      lowerSampleIndex: lower.sampleIndex,
      upperSampleIndex: upper.sampleIndex,
      lowerSourceName: lowerRaw.sourceName,
      lowerSourceLine: lowerRaw.sourceLine,
      upperSourceName: upperRaw.sourceName,
      upperSourceLine: upperRaw.sourceLine,
      uncertaintyMilliseconds: math.max(
        lower.uncertaintyMilliseconds,
        upper.uncertaintyMilliseconds,
      ),
    );
  }

  double _sampleUncertainty({
    required int index,
    required List<(VideoImuAnchor, int)> anchors,
    required double nominalRate,
    required double gradient,
    required double? effectiveRate,
    required double baseUncertaintyMilliseconds,
  }) {
    final nearestDistance =
        anchors.map((anchor) => (anchor.$2 - index).abs()).reduce(math.min);
    final rateDisagreement = anchors.length == 1
        ? (gradient - 1).abs()
        : effectiveRate == null
            ? 0.0
            : (gradient - nominalRate / effectiveRate).abs();
    final extrapolationMs =
        nearestDistance / nominalRate * rateDisagreement * 1000;
    return math.sqrt(baseUncertaintyMilliseconds * baseUncertaintyMilliseconds +
        extrapolationMs * extrapolationMs);
  }

  double? _effectiveRate(List<ImuSample> samples) {
    final duration = samples.last.timestamp
            .difference(samples.first.timestamp)
            .inMicroseconds /
        1000000;
    return duration <= 0 ? null : (samples.length - 1) / duration;
  }

  SensorTimeReconstruction _invalidSensor(
    String label,
    double nominalRate,
    String reason,
  ) =>
      SensorTimeReconstruction(
        sensorLabel: label,
        valid: false,
        nominalSamplingRateHz: nominalRate,
        effectiveSamplingRateHz: null,
        packetCount: 0,
        duplicateReceptionTimestampSamples: 0,
        offsetSeconds: null,
        timeGradient: null,
        estimatedDriftPpm: null,
        anchorResidualRmseMilliseconds: null,
        maximumAbsoluteAnchorResidualMilliseconds: null,
        baseUncertaintyMilliseconds: null,
        lossDetermination: LossDetermination.notDeterminable,
        lossReason: 'Zeitreihe ungültig; Verlustprüfung nicht bestimmbar.',
        packets: const [],
        suspectedTransportGaps: const [],
        anchorEvidence: const [],
        samples: const [],
        invalidReason: reason,
      );

  IndexTimeReconstructionResult _emptyResult({
    required TimeReconstructionStatus status,
    required Map<String, SensorTimeReconstruction> sensors,
    required List<IndexTimeReconstructionIssue> issues,
  }) =>
      IndexTimeReconstructionResult(
        status: status,
        gridSamplingRateHz: config.targetSamplingRateHz,
        gridPeriodMicroseconds: (1000000 / config.targetSamplingRateHz).round(),
        commonStartSeconds: null,
        commonEndSeconds: null,
        sensors: sensors,
        frames: const [],
        issues: issues,
        assumptions: _assumptions,
      );

  List<String> get _assumptions => const [
        'Sampleindex und Originalreihenfolge werden unverändert aus dem Import '
            'übernommen; Index 0 bezeichnet die erste Sensorzeile.',
        'Identische aufeinanderfolgende Empfangszeitstempel desselben Sensors '
            'bilden ein BLE-Empfangspaket.',
        'Die nominale Rate ist Konfiguration; die effektive Rate wird nur aus '
            'Samplezahl und erstem/letztem Empfangszeitstempel geschätzt.',
        'Ohne Sequenznummer oder Sensorzeit sind einzelne Paket- und '
            'Sampleverluste nicht sicher bestimmbar.',
        'Analysezeiten sind affine, indexbasierte Rekonstruktionen und keine '
            'gemessenen Samplezeitstempel.',
        'Grenzen und Unsicherheiten sind technische Angaben, keine '
            'medizinischen Referenzbereiche.',
      ];

  void _validateConfig() {
    final rates = [
      config.defaultNominalSamplingRateHz,
      config.targetSamplingRateHz,
      ...config.nominalSamplingRatesHz.values,
    ];
    if (rates.any((rate) => !rate.isFinite || rate <= 0) ||
        !config.maximumInterpolationGapFactor.isFinite ||
        config.maximumInterpolationGapFactor <= 0 ||
        !config.suspectedPacketGapFactor.isFinite ||
        config.suspectedPacketGapFactor <= 1 ||
        config.minimumSamplesPerSensor < 2 ||
        config.receptionTimestampResolution.isNegative ||
        config.defaultAnchorUncertainty.isNegative ||
        config.maximumAnchorResidual.isNegative) {
      throw ArgumentError('Ungültige Indexzeit-Rekonstruktionskonfiguration.');
    }
  }
}

class _TimeFit {
  const _TimeFit({
    required this.offsetSeconds,
    required this.gradient,
  });

  final double offsetSeconds;
  final double gradient;
}

bool _finiteVector(Vector3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;

Vector3 _lerp(Vector3 lower, Vector3 upper, double fraction) => Vector3(
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
