import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SensorStorage {
  static const List<String> _columns = [
    "sampleIndex",
    "timeSeconds",
    "sensor",
    "aNorm",
    "gNorm",
    "roll",
    "pitch",
    "yaw",
  ];

  final List<Map<String, dynamic>> _data = [];
  bool _recording = false;
  final List<VoidCallback> _resetListeners = [];
  final List<VoidCallback> _startListeners = [];
  final List<VoidCallback> _stopListeners = [];
  IOSink? _sink;
  File? _file;
  bool _opening = false;
  final List<String> _pendingLines = [];
  static const int _flushLineCount = 600;

  bool get isRecording => _recording;

  /// Startet eine neue Aufzeichnung (vorherige Daten werden verworfen).
  Future<void> startRecording() async {
    _data.clear();
    _pendingLines.clear();
    await _closeSink();
    _recording = true;
    await _openSink();
    for (final cb in _resetListeners) {
      cb();
    }
    for (final cb in _startListeners) {
      cb();
    }
  }

  /// Stoppt die Aufzeichnung und schließt die Datei.
  Future<void> stopRecording() async {
    _recording = false;
    await _flushPending(force: true);
    await _closeSink();
    for (final cb in _stopListeners) {
      cb();
    }
  }

  void add(
    String role,
    Map<String, double> values, {
    required int sampleIndex,
    required double timeSeconds,
    double? sensorTimestampMs,
  }) {
    if (!_recording) return;
    if (_sink == null && !_opening) {
      _openSink();
    }

    final row = _columns.map((col) {
      switch (col) {
        case "sampleIndex":
          return sampleIndex.toString();
        case "timeSeconds":
          return timeSeconds.toStringAsFixed(6);
        case "sensor":
          return role;
        default:
          final v = values[col];
          if (v == null) return "";
          return v.toStringAsFixed(6);
      }
    }).join(",");
    _pendingLines.add(row);
    if (_pendingLines.length >= _flushLineCount) {
      _writePending();
    }
  }

  List<Map<String, dynamic>> get all => List.unmodifiable(_data);

  void clear() {
    _data.clear();
    _pendingLines.clear();
  }

  void registerResetListener(VoidCallback cb) {
    _resetListeners.add(cb);
  }

  void registerStartListener(VoidCallback cb) {
    _startListeners.add(cb);
  }

  void registerStopListener(VoidCallback cb) {
    _stopListeners.add(cb);
  }

  /// Exportiert die aktuellen Daten als CSV-Datei und gibt die Datei zurück.
  Future<File> exportCsv() async {
    if (_file == null) {
      throw Exception("Keine Daten zum Exportieren");
    }
    await _flushPending(force: true);
    return _file!;
  }

  String _timestampedFileName() {
    final now = DateTime.now().toLocal();
    String two(int n) => n.toString().padLeft(2, "0");
    final date =
        "${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}";
    return "intakt_$date.csv";
  }

  Future<void> _openSink() async {
    if (_sink != null || _opening) return;
    _opening = true;
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final dir = Directory("${baseDir.path}/intakt");
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final fileName = _timestampedFileName();
      _file = File("${dir.path}/$fileName");
      _sink = _file!.openWrite(mode: FileMode.write);
      _sink!.writeln(_columns.join(","));
      if (_pendingLines.isNotEmpty) {
        _writePending();
      }
    } finally {
      _opening = false;
    }
  }

  void _writePending() {
    if (_sink == null || _pendingLines.isEmpty) return;
    _sink!.write(_pendingLines.join("\n"));
    _sink!.write("\n");
    _pendingLines.clear();
  }

  Future<void> _flushPending({required bool force}) async {
    _writePending();
    if (force && _sink != null) {
      await _sink!.flush();
    }
  }

  Future<void> _closeSink() async {
    if (_sink != null) {
      await _sink!.flush();
      await _sink!.close();
      _sink = null;
    }
    _opening = false;
  }
}
