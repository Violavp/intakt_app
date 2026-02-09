import 'dart:convert';
import 'dart:io';

import 'package:intakt_app/services/takt_engine.dart';
import 'package:intakt_app/services/takt_models.dart';

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
    stderr.writeln('Usage: dart run tool/replay_gait.dart <csv_path>');
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

  final engine = TaktEngine();
  final states = <TaktUiState>[];
  final sub = engine.stream.listen(states.add);

  for (final r in records) {
    engine.addSample(
      leg: r.leg,
      timestampMs: r.timeSeconds * 1000.0,
      accZ: r.accZ,
      gyroZ: r.gyroZ,
      roll: r.roll,
      pitch: r.pitch,
    );
  }

  await Future<void>.delayed(const Duration(milliseconds: 50));
  await sub.cancel();

  if (states.isEmpty) {
    stderr.writeln('No gait states produced.');
    exit(65);
  }

  final counts = <Gait, int>{
    Gait.stehen: 0,
    Gait.schritt: 0,
    Gait.trab: 0,
    Gait.galopp: 0,
  };
  for (final s in states) {
    counts[s.gait] = (counts[s.gait] ?? 0) + 1;
  }

  final total = states.length;
  stdout.writeln(
    'Summary: total=$total, '
    'stehen=${counts[Gait.stehen]}, '
    'schritt=${counts[Gait.schritt]}, '
    'trab=${counts[Gait.trab]}, '
    'galopp=${counts[Gait.galopp]}',
  );

  final trotPct = (counts[Gait.trab]! / total) * 100.0;
  stdout.writeln('Trab-Anteil: ${trotPct.toStringAsFixed(1)}%');

  final segments = <String>[];
  Gait current = states.first.gait;
  double segStart = states.first.timestampMs / 1000.0;
  for (int i = 1; i < states.length; i++) {
    final s = states[i];
    if (s.gait != current) {
      final end = s.timestampMs / 1000.0;
      segments.add(
        '${_gaitLabel(current)}: ${segStart.toStringAsFixed(2)}–${end.toStringAsFixed(2)}s',
      );
      current = s.gait;
      segStart = end;
    }
  }
  final lastEnd = states.last.timestampMs / 1000.0;
  segments.add(
    '${_gaitLabel(current)}: ${segStart.toStringAsFixed(2)}–${lastEnd.toStringAsFixed(2)}s',
  );

  stdout.writeln('Segments:');
  for (final seg in segments) {
    stdout.writeln('  $seg');
  }
}

String _gaitLabel(Gait gait) {
  switch (gait) {
    case Gait.stehen:
      return 'stehen';
    case Gait.schritt:
      return 'schritt';
    case Gait.trab:
      return 'trab';
    case Gait.galopp:
      return 'galopp';
  }
}
