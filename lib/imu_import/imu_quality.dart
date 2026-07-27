import 'dart:math' as math;

import 'imu_models.dart';

enum QualitySeverity { info, warning, error }

enum SensorQualityStatus { usable, reviewRequired, unusable }

class QualityIssue {
  const QualityIssue({
    required this.code,
    required this.severity,
    required this.observation,
    required this.uncertainty,
    required this.recommendation,
    this.sensorLabel,
  });

  final String code;
  final QualitySeverity severity;
  final String observation;
  final String uncertainty;
  final String recommendation;
  final String? sensorLabel;

  Map<String, Object?> toJson() => {
        'code': code,
        'severity': severity.name,
        if (sensorLabel != null) 'sensor': sensorLabel,
        'observation': observation,
        'uncertainty': uncertainty,
        'recommendation': recommendation,
      };
}

/// A suspicious interval between two unchanged source rows.
class IntervalMarker {
  const IntervalMarker({
    required this.previousTimestamp,
    required this.currentTimestamp,
    required this.previousSourceName,
    required this.currentSourceName,
    required this.previousSourceLine,
    required this.currentSourceLine,
    required this.intervalMs,
    this.estimatedMissingRows,
  });

  final DateTime previousTimestamp;
  final DateTime currentTimestamp;
  final String previousSourceName;
  final String currentSourceName;
  final int previousSourceLine;
  final int currentSourceLine;
  final double intervalMs;

  /// Technical estimate based on the median positive reception interval.
  /// It is not an assertion about the sensor's true sampling instants.
  final int? estimatedMissingRows;

  Map<String, Object?> toJson() => {
        'previous_timestamp': previousTimestamp.toIso8601String(),
        'current_timestamp': currentTimestamp.toIso8601String(),
        'previous_source_file': previousSourceName,
        'current_source_file': currentSourceName,
        'previous_source_line': previousSourceLine,
        'current_source_line': currentSourceLine,
        'interval_ms': intervalMs,
        if (estimatedMissingRows != null)
          'estimated_missing_rows': estimatedMissingRows,
      };
}

/// A source-preserving marker for a frozen run or statistical outlier.
class ValueMarker {
  const ValueMarker({
    required this.kind,
    required this.channel,
    required this.unit,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.sourceName,
    required this.startSourceLine,
    required this.endSourceLine,
    required this.sampleCount,
    this.value,
  });

  final String kind;
  final String channel;
  final String unit;
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final String sourceName;
  final int startSourceLine;
  final int endSourceLine;
  final int sampleCount;
  final double? value;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'channel': channel,
        'unit': unit,
        'start_timestamp': startTimestamp.toIso8601String(),
        'end_timestamp': endTimestamp.toIso8601String(),
        'source_file': sourceName,
        'start_source_line': startSourceLine,
        'end_source_line': endSourceLine,
        'sample_count': sampleCount,
        if (value != null) 'value': value,
      };
}

class SensorQualityMetrics {
  const SensorQualityMetrics({
    required this.label,
    required this.hardwareId,
    required this.status,
    required this.rows,
    required this.uniqueTimestamps,
    required this.duplicateTimestampRows,
    required this.backwardTimestampRows,
    required this.durationSeconds,
    required this.rowRateHz,
    required this.uniqueTimestampRateHz,
    required this.medianPositiveIntervalMs,
    required this.maxPositiveIntervalMs,
    required this.adaptiveGapThresholdMs,
    required this.gapLocations,
    required this.irregularIntervalLocations,
    required this.magnetometerRows,
    required this.frozenSegments,
    required this.extremeOutliers,
  });

  final String label;
  final String hardwareId;
  final SensorQualityStatus status;
  final int rows;
  final int uniqueTimestamps;
  final int duplicateTimestampRows;
  final int backwardTimestampRows;
  final double? durationSeconds;
  final double? rowRateHz;
  final double? uniqueTimestampRateHz;
  final double? medianPositiveIntervalMs;
  final double? maxPositiveIntervalMs;
  final double? adaptiveGapThresholdMs;
  final List<IntervalMarker> gapLocations;
  final List<IntervalMarker> irregularIntervalLocations;
  final int magnetometerRows;
  final List<ValueMarker> frozenSegments;
  final List<ValueMarker> extremeOutliers;

  int get gaps => gapLocations.length;

  /// Kept as a compact channel summary for existing report consumers.
  List<String> get constantChannels =>
      frozenSegments.map((marker) => marker.channel).toSet().toList()..sort();

  Map<String, Object?> toJson() => {
        'label': label,
        'hardware_id': hardwareId,
        'quality_status': _statusName(status),
        'rows': rows,
        'unique_timestamps': uniqueTimestamps,
        'duplicate_timestamp_rows': duplicateTimestampRows,
        'backward_timestamp_rows': backwardTimestampRows,
        'duration_s': durationSeconds,
        'row_rate_hz': rowRateHz,
        'unique_timestamp_rate_hz': uniqueTimestampRateHz,
        'median_positive_interval_ms': medianPositiveIntervalMs,
        'max_positive_interval_ms': maxPositiveIntervalMs,
        'adaptive_gap_threshold_ms': adaptiveGapThresholdMs,
        'gaps_over_adaptive_threshold': gaps,
        'gap_locations':
            gapLocations.map((location) => location.toJson()).toList(),
        'irregular_interval_locations': irregularIntervalLocations
            .map((location) => location.toJson())
            .toList(),
        'magnetometer_rows': magnetometerRows,
        'constant_channels': constantChannels,
        'frozen_segments':
            frozenSegments.map((marker) => marker.toJson()).toList(),
        'extreme_outliers':
            extremeOutliers.map((marker) => marker.toJson()).toList(),
      };
}

class ImuQualityReport {
  const ImuQualityReport({
    required this.metrics,
    required this.issues,
    required this.rowCountsDiffer,
    required this.samplingRatesDiffer,
    required this.readyForFurtherAnalysis,
    required this.assumptions,
  });

  final Map<String, SensorQualityMetrics> metrics;
  final List<QualityIssue> issues;
  final bool rowCountsDiffer;
  final bool samplingRatesDiffer;
  final bool readyForFurtherAnalysis;
  final List<String> assumptions;

  Map<String, Object> toJson() => {
        'status': readyForFurtherAnalysis
            ? 'QUALITY_ACCEPTED'
            : metrics.values.any(
                (metric) => metric.status == SensorQualityStatus.unusable,
              )
                ? 'QUALITY_NOT_SUFFICIENT'
                : 'QUALITY_REVIEW_REQUIRED',
        'ready_for_further_analysis': readyForFurtherAnalysis,
        'row_counts_differ': rowCountsDiffer,
        'sampling_rates_differ': samplingRatesDiffer,
        'assumptions': assumptions,
        'sensors': metrics.values.map((metric) => metric.toJson()).toList(),
        'issues': issues.map((issue) => issue.toJson()).toList(),
      };
}

/// Quality assessment only. It never changes, interpolates or drops samples.
class ImuQualityAnalyzer {
  const ImuQualityAnalyzer({
    this.unexpectedlyShortDuration = const Duration(seconds: 2),
    this.irregularIntervalRelativeTolerance = 0.2,
    this.irregularIntervalAbsoluteTolerance = const Duration(milliseconds: 1),
    this.frozenRunMinSamples = 10,
    this.extremeOutlierIqrMultiplier = 3,
    this.extremeOutlierMinSamples = 8,
  })  : assert(irregularIntervalRelativeTolerance >= 0),
        assert(frozenRunMinSamples >= 2),
        assert(extremeOutlierIqrMultiplier > 0),
        assert(extremeOutlierMinSamples >= 4);

  /// Technical QA threshold, not a physiological reference.
  final Duration unexpectedlyShortDuration;

  /// Positive intervals differing by more than both tolerances are marked.
  final double irregularIntervalRelativeTolerance;
  final Duration irregularIntervalAbsoluteTolerance;

  /// Exact consecutive equality is only marked at or above this run length.
  final int frozenRunMinSamples;

  /// Statistical extreme fence: Q1/Q3 plus/minus this many IQRs.
  final double extremeOutlierIqrMultiplier;
  final int extremeOutlierMinSamples;

  ImuQualityReport analyze(ImuImportResult result) {
    final issues = <QualityIssue>[];
    final metrics = <String, SensorQualityMetrics>{};

    for (final identity in result.catalog.requiredSensors) {
      final recording = result.recordings[identity.label];
      if (recording == null) {
        metrics[identity.label] = _missingSensorMetrics(identity);
        issues.add(
          QualityIssue(
            code: 'missing_required_sensor',
            severity: QualitySeverity.error,
            sensorLabel: identity.label,
            observation:
                'Pflichtsensor ${identity.label} (${identity.hardwareId}) fehlt.',
            uncertainty:
                'Die vier Beinpositionen sind dadurch nicht vollständig belegt.',
            recommendation:
                'Hardware-ID, Dateiauswahl und Exportvollständigkeit prüfen.',
          ),
        );
      }
    }

    for (final recording in result.recordings.values) {
      final draft = _analyzeSensor(recording);
      var status = SensorQualityStatus.usable;

      if (draft.rows < 2 ||
          draft.durationSeconds == null ||
          draft.durationSeconds! <
              unexpectedlyShortDuration.inMicroseconds / 1000000) {
        status = SensorQualityStatus.unusable;
        issues.add(
          QualityIssue(
            code: 'unexpectedly_short_recording',
            severity: QualitySeverity.error,
            sensorLabel: draft.label,
            observation: '${draft.label} enthält ${draft.rows} Zeilen über '
                '${_format(draft.durationSeconds)} s.',
            uncertainty: 'Die technische Mindestdauer von '
                '${unexpectedlyShortDuration.inMilliseconds / 1000} s ist '
                'konfigurierbar und kein physiologischer Referenzbereich.',
            recommendation: 'Aufnahmestart, -ende und Export prüfen; diese '
                'Aufnahme nicht automatisch weiterverarbeiten.',
          ),
        );
      }
      if (draft.backwardTimestampRows > 0) {
        status = SensorQualityStatus.unusable;
        issues.add(
          QualityIssue(
            code: 'backward_timestamps',
            severity: QualitySeverity.error,
            sensorLabel: draft.label,
            observation:
                '${draft.backwardTimestampRows} Zeitstempel gehen gegenüber '
                'der vorherigen Quellzeile rückwärts.',
            uncertainty: 'Reihenfolge oder Uhrzeitbasis der Quelle ist unklar.',
            recommendation:
                'Originalexport prüfen; Zeilen nicht automatisch sortieren.',
          ),
        );
      }
      if (draft.duplicateTimestampRows > 0) {
        status = _atLeastReview(status);
        issues.add(
          QualityIssue(
            code: 'duplicate_reception_timestamps',
            severity: QualitySeverity.warning,
            sensorLabel: draft.label,
            observation:
                '${draft.duplicateTimestampRows} Zeilen teilen sich einen '
                'Zeitstempel mit ihrer Vorgängerzeile.',
            uncertainty:
                'Der Export kann Empfangs-/Batchzeiten abbilden; exakte '
                'Einzelabtastzeiten sind nicht belegt.',
            recommendation:
                'Quellreihenfolge bewahren und keine Einzelzeiten erfinden.',
          ),
        );
      }
      if (draft.gaps > 0) {
        status = _atLeastReview(status);
        issues.add(
          QualityIssue(
            code: 'reception_gaps',
            severity: QualitySeverity.warning,
            sensorLabel: draft.label,
            observation: '${draft.gaps} mögliche Datenlücken sind mit '
                'Zeitstempeln und Quellzeilen lokalisiert.',
            uncertainty: 'Die angegebene Zahl fehlender Zeilen ist eine '
                'Schätzung aus dem medianen Empfangsintervall.',
            recommendation:
                'Markierte Abschnitte prüfen und nicht stillschweigend '
                'interpolieren.',
          ),
        );
      }
      if (draft.irregularIntervalLocations.isNotEmpty) {
        status = _atLeastReview(status);
        issues.add(
          QualityIssue(
            code: 'irregular_sampling_intervals',
            severity: QualitySeverity.warning,
            sensorLabel: draft.label,
            observation: '${draft.irregularIntervalLocations.length} positive '
                'Abtastintervalle weichen von der medianen Empfangsperiode ab.',
            uncertainty:
                'Batch-Zeitstempel können die Abweichung mitverursachen.',
            recommendation:
                'Markierte Intervalle vor einer Zeitachsenbildung prüfen.',
          ),
        );
      }
      if (draft.magnetometerRows != 0 && draft.magnetometerRows != draft.rows) {
        status = _atLeastReview(status);
        issues.add(
          QualityIssue(
            code: 'incomplete_optional_magnetometer',
            severity: QualitySeverity.warning,
            sensorLabel: draft.label,
            observation:
                'Magnetometerwerte liegen in ${draft.magnetometerRows} von '
                '${draft.rows} Zeilen vor.',
            uncertainty: 'Fehlende optionale Werte wurden als fehlend bewahrt.',
            recommendation:
                'Magnetometer nur in vollständig belegten Abschnitten nutzen.',
          ),
        );
      }
      if (draft.frozenSegments.isNotEmpty) {
        status = _atLeastReview(status);
        issues.add(
          QualityIssue(
            code: 'frozen_signal_segments',
            severity: QualitySeverity.warning,
            sensorLabel: draft.label,
            observation: '${draft.frozenSegments.length} exakt konstante '
                'Kanalabschnitte sind zeilen- und zeitbezogen markiert.',
            uncertainty: 'Konstanz kann Ruhe, geringe Exportauflösung oder ein '
                'eingefrorenes Signal bedeuten.',
            recommendation:
                'Markierte Signalabschnitte und Sensormontage prüfen.',
          ),
        );
      }
      if (draft.extremeOutliers.isNotEmpty) {
        status = _atLeastReview(status);
        issues.add(
          QualityIssue(
            code: 'extreme_statistical_outliers',
            severity: QualitySeverity.warning,
            sensorLabel: draft.label,
            observation: '${draft.extremeOutliers.length} Werte liegen '
                'außerhalb der technischen $extremeOutlierIqrMultiplier×IQR-'
                'Fences und sind einzeln markiert.',
            uncertainty: 'Die Markierung ist rein statistisch und verwendet '
                'keinen erfundenen Sensor- oder Referenzbereich.',
            recommendation:
                'Quellwerte prüfen; nicht automatisch löschen oder ersetzen.',
          ),
        );
      }
      metrics[draft.label] = draft.withStatus(status);
    }

    final presentMetrics =
        metrics.values.where((metric) => metric.rows > 0).toList();
    final rowCounts = presentMetrics.map((metric) => metric.rows).toSet();
    final rowCountsDiffer = rowCounts.length > 1;
    if (rowCountsDiffer) {
      issues.add(
        QualityIssue(
          code: 'different_file_lengths',
          severity: QualitySeverity.warning,
          observation: 'Sensorzeilenzahlen unterscheiden sich: '
              '${presentMetrics.map((m) => '${m.label}=${m.rows}').join(', ')}.',
          uncertainty:
              'Mögliche Ursachen sind Start-/Endversatz oder Datenverlust.',
          recommendation:
              'Zeitliche Überlappung vor gemeinsamer Verarbeitung bestimmen.',
        ),
      );
      _promotePresentMetrics(metrics);
    }

    final rates = presentMetrics
        .map((metric) => metric.rowRateHz)
        .whereType<double>()
        .toList();
    final samplingRatesDiffer = rates.length > 1 &&
        rates.reduce(math.max) - rates.reduce(math.min) >
            math.max(0.5, rates.reduce(math.min) * 0.01);
    if (samplingRatesDiffer) {
      issues.add(
        const QualityIssue(
          code: 'different_sampling_rates',
          severity: QualitySeverity.warning,
          observation:
              'Geschätzte Zeilenraten weichen um mehr als 1 % oder 0,5 Hz ab.',
          uncertainty:
              'Batch-Zeitstempel begrenzen die Aussagekraft der Schätzung.',
          recommendation:
              'Raten vor gemeinsamer Zeitachsenbildung separat behandeln.',
        ),
      );
      _promotePresentMetrics(metrics);
    }

    final missingSourceRows = result.messages
        .where((message) => message.code == 'blank_line')
        .toList();
    if (missingSourceRows.isNotEmpty) {
      issues.add(
        QualityIssue(
          code: 'missing_source_rows',
          severity: QualitySeverity.warning,
          observation: '${missingSourceRows.length} leere Quellzeilen wurden '
              'als mögliche fehlende Datenpunkte lokalisiert: '
              '${missingSourceRows.map((message) => '${message.sourceName ?? 'unbekannte Datei'}:${message.line ?? 'unbekannte Zeile'}').join(', ')}.',
          uncertainty: 'Eine leere Zeile enthält keine Sensor-ID; der '
              'betroffene Sensor kann daher nicht sicher zugeordnet werden.',
          recommendation:
              'Markierte Quellzeilen im unveränderten Export prüfen.',
        ),
      );
      _promotePresentMetrics(metrics);
    }

    final readyForFurtherAnalysis = metrics.isNotEmpty &&
        metrics.values.every(
          (metric) => metric.status == SensorQualityStatus.usable,
        );
    return ImuQualityReport(
      metrics: metrics,
      issues: issues,
      rowCountsDiffer: rowCountsDiffer,
      samplingRatesDiffer: samplingRatesDiffer,
      readyForFurtherAnalysis: readyForFurtherAnalysis,
      assumptions: [
        'Qualitätsprüfung verändert, sortiert, interpoliert oder verwirft '
            'keine Rohdaten.',
        'Messdauer [s] ist die Differenz zwischen erstem und letztem '
            'Quellzeitstempel; bei Rücksprüngen ist der Sensor unbrauchbar.',
        'Eine mögliche Datenlücke ist ein positives Empfangsintervall größer '
            'als max(100 ms, 5 × medianes positives Intervall).',
        'Unregelmäßig bedeutet eine Abweichung vom Median größer als sowohl '
            '${irregularIntervalAbsoluteTolerance.inMicroseconds / 1000} ms '
            'als auch ${irregularIntervalRelativeTolerance * 100} %.',
        'Freeze-Markierungen verlangen mindestens $frozenRunMinSamples exakt '
            'gleiche aufeinanderfolgende Werte desselben Kanals.',
        'Extreme Ausreißer werden erst ab $extremeOutlierMinSamples Werten '
            'außerhalb von Q1/Q3 ± $extremeOutlierIqrMultiplier × IQR markiert.',
        'Schätzungen fehlender Zeilen basieren auf Empfangszeitstempeln und '
            'sind wegen möglicher Batch-Zeitstempel unsicher.',
        'QUALITY_REVIEW_REQUIRED und QUALITY_NOT_SUFFICIENT sperren die '
            'automatische Weiterverarbeitung.',
      ],
    );
  }

  SensorQualityMetrics _analyzeSensor(SensorRecording recording) {
    final samples = recording.samples;
    var duplicates = 0;
    var backwards = 0;
    final positiveIntervals = <_IndexedInterval>[];
    for (var index = 1; index < samples.length; index++) {
      final deltaUs = samples[index]
          .timestamp
          .difference(samples[index - 1].timestamp)
          .inMicroseconds;
      if (deltaUs == 0) {
        duplicates++;
      } else if (deltaUs < 0) {
        backwards++;
      } else {
        positiveIntervals.add(_IndexedInterval(index, deltaUs / 1000));
      }
    }
    final sortedIntervals = positiveIntervals
        .map((interval) => interval.intervalMs)
        .toList()
      ..sort();
    final median = _median(sortedIntervals);
    final gapThreshold = median == null ? null : math.max(100.0, median * 5);
    final irregularTolerance = median == null
        ? null
        : math.max(
            irregularIntervalAbsoluteTolerance.inMicroseconds / 1000,
            median * irregularIntervalRelativeTolerance,
          );

    IntervalMarker marker(_IndexedInterval interval, {bool gap = false}) {
      final previous = samples[interval.currentIndex - 1];
      final current = samples[interval.currentIndex];
      return IntervalMarker(
        previousTimestamp: previous.timestamp,
        currentTimestamp: current.timestamp,
        previousSourceName: previous.sourceName,
        currentSourceName: current.sourceName,
        previousSourceLine: previous.sourceLine,
        currentSourceLine: current.sourceLine,
        intervalMs: interval.intervalMs,
        estimatedMissingRows: gap && median != null
            ? math.max(1, (interval.intervalMs / median).round() - 1)
            : null,
      );
    }

    final gapLocations = gapThreshold == null
        ? <IntervalMarker>[]
        : [
            for (final interval in positiveIntervals)
              if (interval.intervalMs > gapThreshold)
                marker(interval, gap: true),
          ];
    final irregularLocations = irregularTolerance == null || median == null
        ? <IntervalMarker>[]
        : [
            for (final interval in positiveIntervals)
              if ((interval.intervalMs - median).abs() > irregularTolerance)
                marker(interval),
          ];
    final durationSeconds = samples.length < 2 || backwards > 0
        ? null
        : samples.last.timestamp
                .difference(samples.first.timestamp)
                .inMicroseconds /
            1000000;
    final uniqueTimestamps =
        samples.map((sample) => sample.timestamp).toSet().length;
    final rowRate = durationSeconds == null || durationSeconds <= 0
        ? null
        : (samples.length - 1) / durationSeconds;
    final uniqueRate = durationSeconds == null || durationSeconds <= 0
        ? null
        : (uniqueTimestamps - 1) / durationSeconds;

    return SensorQualityMetrics(
      label: recording.identity.label,
      hardwareId: recording.identity.hardwareId,
      status: SensorQualityStatus.usable,
      rows: samples.length,
      uniqueTimestamps: uniqueTimestamps,
      duplicateTimestampRows: duplicates,
      backwardTimestampRows: backwards,
      durationSeconds: durationSeconds,
      rowRateHz: rowRate,
      uniqueTimestampRateHz: uniqueRate,
      medianPositiveIntervalMs: median,
      maxPositiveIntervalMs:
          sortedIntervals.isEmpty ? null : sortedIntervals.last,
      adaptiveGapThresholdMs: gapThreshold,
      gapLocations: gapLocations,
      irregularIntervalLocations: irregularLocations,
      magnetometerRows: samples
          .where((sample) => sample.magneticFieldMicrotesla != null)
          .length,
      frozenSegments: _frozenSegments(samples),
      extremeOutliers: _extremeOutliers(samples),
    );
  }

  List<ValueMarker> _frozenSegments(List<ImuSample> samples) {
    final markers = <ValueMarker>[];
    for (final channel in _channels(samples)) {
      var start = 0;
      for (var index = 1; index <= samples.length; index++) {
        final continues = index < samples.length &&
            channel.value(samples[index]) == channel.value(samples[index - 1]);
        if (continues) continue;
        final count = index - start;
        if (count >= frozenRunMinSamples) {
          final first = samples[start];
          final last = samples[index - 1];
          markers.add(
            ValueMarker(
              kind: 'frozen_segment',
              channel: channel.name,
              unit: channel.unit,
              startTimestamp: first.timestamp,
              endTimestamp: last.timestamp,
              sourceName: first.sourceName,
              startSourceLine: first.sourceLine,
              endSourceLine: last.sourceLine,
              sampleCount: count,
              value: channel.value(first),
            ),
          );
        }
        start = index;
      }
    }
    return markers;
  }

  List<ValueMarker> _extremeOutliers(List<ImuSample> samples) {
    if (samples.length < extremeOutlierMinSamples) return const [];
    final markers = <ValueMarker>[];
    for (final channel in _channels(samples)) {
      final values = samples.map(channel.value).toList()..sort();
      final q1 = _quantile(values, 0.25);
      final q3 = _quantile(values, 0.75);
      final iqr = q3 - q1;
      if (iqr <= 0) continue;
      final lower = q1 - extremeOutlierIqrMultiplier * iqr;
      final upper = q3 + extremeOutlierIqrMultiplier * iqr;
      for (var index = 0; index < samples.length; index++) {
        final value = channel.value(samples[index]);
        if (value >= lower && value <= upper) continue;
        final sample = samples[index];
        markers.add(
          ValueMarker(
            kind: 'extreme_statistical_outlier',
            channel: channel.name,
            unit: channel.unit,
            startTimestamp: sample.timestamp,
            endTimestamp: sample.timestamp,
            sourceName: sample.sourceName,
            startSourceLine: sample.sourceLine,
            endSourceLine: sample.sourceLine,
            sampleCount: 1,
            value: value,
          ),
        );
      }
    }
    return markers;
  }
}

class _IndexedInterval {
  const _IndexedInterval(this.currentIndex, this.intervalMs);

  final int currentIndex;
  final double intervalMs;
}

class _Channel {
  const _Channel(this.name, this.unit, this.value);

  final String name;
  final String unit;
  final double Function(ImuSample) value;
}

List<_Channel> _channels(List<ImuSample> samples) {
  final channels = <_Channel>[
    _Channel('acc_x', 'm/s^2', (sample) => sample.accelerationMps2.x),
    _Channel('acc_y', 'm/s^2', (sample) => sample.accelerationMps2.y),
    _Channel('acc_z', 'm/s^2', (sample) => sample.accelerationMps2.z),
    _Channel(
      'gyro_x',
      'rad/s',
      (sample) => sample.angularVelocityRadPerSecond.x,
    ),
    _Channel(
      'gyro_y',
      'rad/s',
      (sample) => sample.angularVelocityRadPerSecond.y,
    ),
    _Channel(
      'gyro_z',
      'rad/s',
      (sample) => sample.angularVelocityRadPerSecond.z,
    ),
  ];
  if (samples.isNotEmpty &&
      samples.every((sample) => sample.magneticFieldMicrotesla != null)) {
    channels.addAll([
      _Channel(
        'mag_x',
        'uT',
        (sample) => sample.magneticFieldMicrotesla!.x,
      ),
      _Channel(
        'mag_y',
        'uT',
        (sample) => sample.magneticFieldMicrotesla!.y,
      ),
      _Channel(
        'mag_z',
        'uT',
        (sample) => sample.magneticFieldMicrotesla!.z,
      ),
    ]);
  }
  return channels;
}

SensorQualityMetrics _missingSensorMetrics(SensorIdentity identity) {
  return SensorQualityMetrics(
    label: identity.label,
    hardwareId: identity.hardwareId,
    status: SensorQualityStatus.unusable,
    rows: 0,
    uniqueTimestamps: 0,
    duplicateTimestampRows: 0,
    backwardTimestampRows: 0,
    durationSeconds: null,
    rowRateHz: null,
    uniqueTimestampRateHz: null,
    medianPositiveIntervalMs: null,
    maxPositiveIntervalMs: null,
    adaptiveGapThresholdMs: null,
    gapLocations: const [],
    irregularIntervalLocations: const [],
    magnetometerRows: 0,
    frozenSegments: const [],
    extremeOutliers: const [],
  );
}

SensorQualityStatus _atLeastReview(SensorQualityStatus status) =>
    status == SensorQualityStatus.usable
        ? SensorQualityStatus.reviewRequired
        : status;

void _promotePresentMetrics(Map<String, SensorQualityMetrics> metrics) {
  for (final entry in metrics.entries.toList()) {
    if (entry.value.rows > 0) {
      metrics[entry.key] =
          entry.value.withStatus(_atLeastReview(entry.value.status));
    }
  }
}

extension on SensorQualityMetrics {
  SensorQualityMetrics withStatus(SensorQualityStatus value) {
    return SensorQualityMetrics(
      label: label,
      hardwareId: hardwareId,
      status: value,
      rows: rows,
      uniqueTimestamps: uniqueTimestamps,
      duplicateTimestampRows: duplicateTimestampRows,
      backwardTimestampRows: backwardTimestampRows,
      durationSeconds: durationSeconds,
      rowRateHz: rowRateHz,
      uniqueTimestampRateHz: uniqueTimestampRateHz,
      medianPositiveIntervalMs: medianPositiveIntervalMs,
      maxPositiveIntervalMs: maxPositiveIntervalMs,
      adaptiveGapThresholdMs: adaptiveGapThresholdMs,
      gapLocations: gapLocations,
      irregularIntervalLocations: irregularIntervalLocations,
      magnetometerRows: magnetometerRows,
      frozenSegments: frozenSegments,
      extremeOutliers: extremeOutliers,
    );
  }
}

double? _median(List<double> sorted) {
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double _quantile(List<double> sorted, double probability) {
  final position = (sorted.length - 1) * probability;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final weight = position - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

String _statusName(SensorQualityStatus status) => switch (status) {
      SensorQualityStatus.usable => 'USABLE',
      SensorQualityStatus.reviewRequired => 'REVIEW_REQUIRED',
      SensorQualityStatus.unusable => 'UNUSABLE',
    };

String _format(double? value) =>
    value == null ? 'nicht bestimmbar' : value.toStringAsFixed(3);
