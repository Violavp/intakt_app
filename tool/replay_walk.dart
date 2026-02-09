import 'dart:convert';
import 'dart:io';

import 'package:intakt_app/services/walk_metrics_engine.dart';
import 'package:intakt_app/services/walk_score_engine.dart';

class _Record {
  final double timeSeconds;
  final String leg;
  final double accZ;
  final double gyroZ;
  final double roll;
  final double pitch;

  _Record({
    required this.timeSeconds,
    required this.leg,
    required this.accZ,
    required this.gyroZ,
    required this.roll,
    required this.pitch,
  });
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/replay_walk.dart <csv_path>');
    exit(64);
  }

  final path = args.first;
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('File not found: $path');
    exit(66);
  }

  final records = <_Record>[];
  String? headerLine;

  await file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    if (headerLine == null) {
      headerLine = trimmed;
      return;
    }

    final parts = trimmed.split(',');
    if (parts.length < 7) return;

    final timeSeconds = double.tryParse(parts[1]) ?? 0.0;
    final leg = parts[2];
    final accZ = double.tryParse(parts[3]) ?? 0.0;
    final gyroZ = double.tryParse(parts[4]) ?? 0.0;
    final roll = double.tryParse(parts[5]) ?? 0.0;
    final pitch = double.tryParse(parts[6]) ?? 0.0;

    records.add(_Record(
      timeSeconds: timeSeconds,
      leg: leg,
      accZ: accZ,
      gyroZ: gyroZ,
      roll: roll,
      pitch: pitch,
    ));
  });

  if (records.isEmpty) {
    stderr.writeln('No records parsed from $path');
    exit(65);
  }

  records.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

  final walkScore = WalkScoreEngine();
  final walkMetrics = WalkMetricsEngine();
  const emitIntervalMs = 200.0;
  double lastEmitMs = 0.0;
  WalkScoreResult? lastScore;
  WalkLiveMetrics? lastMetrics;
  int emitCount = 0;
  int walkCount = 0;
  int stillCount = 0;
  double freqSum = 0.0;
  int freqCount = 0;

  stdout.writeln(
      't_sec,gait,walkScore,stability_pct,freq_spm,diag_deg,lat_deg,VL_ms,VR_ms,HL_ms,HR_ms');

  for (final r in records) {
    final tsMs = r.timeSeconds * 1000.0;
    walkScore.addSample(
      leg: r.leg,
      timestampMs: tsMs,
      accZ: r.accZ,
      gyroZ: r.gyroZ,
      roll: r.roll,
      pitch: r.pitch,
    );
    walkMetrics.addSample(
      leg: r.leg,
      timestampMs: tsMs,
      accZ: r.accZ,
      gyroZ: r.gyroZ,
      roll: r.roll,
      pitch: r.pitch,
    );

    if (lastEmitMs == 0.0 || tsMs - lastEmitMs >= emitIntervalMs) {
      lastEmitMs = tsMs;
      final score = walkScore.poll();
      if (score != null) lastScore = score;
      final metrics = walkMetrics.poll();
      if (metrics != null) lastMetrics = metrics;

      final walkOk = (lastScore?.isWalk == true) && !walkMetrics.isStill;
      final gait = walkOk ? 'schritt' : 'stehen';
      final freq = walkOk ? (lastMetrics?.freqHoofbeatsPerMin ?? 0.0) : 0.0;
      emitCount++;
      if (walkMetrics.isStill) stillCount++;
      if (walkOk) {
        walkCount++;
        if (freq > 0) {
          freqSum += freq;
          freqCount++;
        }
      }

      stdout.writeln([
        r.timeSeconds.toStringAsFixed(3),
        gait,
        (lastScore?.score ?? double.nan).toStringAsFixed(3),
        (lastMetrics?.taktStabilityPct ?? double.nan).toStringAsFixed(1),
        freq.toStringAsFixed(1),
        (lastMetrics?.diagPhaseDeg ?? double.nan).toStringAsFixed(0),
        (lastMetrics?.latPhaseDeg ?? double.nan).toStringAsFixed(0),
        (lastMetrics?.legDevMs["VL"] ?? double.nan).toStringAsFixed(0),
        (lastMetrics?.legDevMs["VR"] ?? double.nan).toStringAsFixed(0),
        (lastMetrics?.legDevMs["HL"] ?? double.nan).toStringAsFixed(0),
        (lastMetrics?.legDevMs["HR"] ?? double.nan).toStringAsFixed(0),
      ].join(','));
    }
  }

  if (emitCount > 0) {
    final walkPct = (walkCount / emitCount) * 100.0;
    final stillPct = (stillCount / emitCount) * 100.0;
    final avgFreq = freqCount > 0 ? (freqSum / freqCount) : 0.0;
    stderr.writeln(
      'Summary: emits=$emitCount, schritt=$walkCount (${walkPct.toStringAsFixed(1)}%), '
      'still=$stillCount (${stillPct.toStringAsFixed(1)}%), avg_freq_spm=${avgFreq.toStringAsFixed(1)}',
    );
  }
}
