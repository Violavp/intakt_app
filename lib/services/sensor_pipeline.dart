import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/command_queue.dart';
import '../ble/frame_assembler.dart';
import '../ble/wit_frame_decoder.dart';
import '../ble/wit_writer.dart';
import '../calibration/wit_calibrator.dart';
import '../models/sensor_sample.dart';
import 'sensor_storage.dart';
import 'takt_engine.dart';

class SensorPipeline {
  SensorPipeline({
    required this.role,
    required this.storage,
    required this.writer,
    required this.calibrator,
    required this.outputMode,
    this.gaitEngine,
    CommandQueue? commandQueue,
    this.logEnabled = false,
    this.onConnectionLost,
  })  : _assembler = FrameAssembler(acceptedTypes: const {0x61}),
        _decoder = WitFrameDecoder(outputMode: outputMode),
        _commandQueue = commandQueue ?? CommandQueue() {
    storage.registerResetListener(resetSampleIndex);
    storage.registerStartListener(_handleStart);
    storage.registerStopListener(_handleStop);
  }

  final String role;
  final SensorStorage storage;
  final WitWriter writer;
  final AutoCalibrator calibrator;
  final WitOutput outputMode;
  final bool logEnabled;
  final VoidCallback? onConnectionLost;
  final TaktEngine? gaitEngine;

  final FrameAssembler _assembler;
  final WitFrameDecoder _decoder;
  final CommandQueue _commandQueue;

  final ListQueue<_QueuedEntry> _storageQueue = ListQueue();
  final List<int> _fpsWindowMs = <int>[];
  static const double _sampleIntervalSeconds = 0.01;
  final List<double> _verifyTimestampsMs = [];

  StreamSubscription<List<int>>? _sub;
  Timer? _flushTimer;
  final StreamController<SensorSample> _uiController =
      StreamController.broadcast();

  SensorSample? latestSample;
  int droppedFrames = 0;
  int _sampleIndex = 0;
  bool _recordingActive = false;
  bool _collectVerify = false;
  int _notifyCount = 0;

  Future<void> start(BluetoothCharacteristic notifyChar) async {
    await notifyChar.setNotifyValue(true);
    _sub = notifyChar.onValueReceived.listen(
      _onChunk,
      onDone: _handleDone,
      onError: _handleError,
    );
    _flushTimer ??=
        Timer.periodic(const Duration(milliseconds: 200), (_) => _flush());
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _uiController.close();
  }

  Future<void> applyRateWithVerify({
    int targetHz = 100,
    int fallbackHz = 50,
    Duration verifyDuration = const Duration(seconds: 3),
    double threshold = 0.8,
    bool enableFallback = true,
  }) async {
    await _commandQueue.enqueue(() async {
      final desiredRate = _rateFromHz(targetHz);
      final needsTempTimestamp = outputMode != WitOutput.accGyroTimestamp;

      // Für die Verifikation ggf. temporär auf Timestamp-Output umschalten.
      if (needsTempTimestamp) {
        _log("Temporär Timestamp-Output für Verify bei $role");
        await writer.configure(
          rate: desiredRate,
          output: WitOutput.accGyroTimestamp,
        );
      } else {
        await writer.configure(rate: desiredRate, output: outputMode);
      }
      _fpsWindowMs.clear();
      _verifyTimestampsMs.clear();
      _sampleIndex = 0;
      final notifyStart = _notifyCount;
      _collectVerify = true;

      await Future.delayed(verifyDuration);

      _collectVerify = false;
      final notifyDelta = _notifyCount - notifyStart;
      final durationSec = verifyDuration.inMilliseconds / 1000.0;
      final fpsNotifications =
          durationSec > 0 ? notifyDelta / durationSec : 0.0;

      double medianDtMs = double.nan;
      double minDtMs = double.nan;
      double maxDtMs = double.nan;
      double samplesPerSecond = 0.0;

      if (_verifyTimestampsMs.length >= 2) {
        final ts = List<double>.from(_verifyTimestampsMs)..sort();
        final dts = <double>[];
        for (int i = 1; i < ts.length; i++) {
          final dt = ts[i] - ts[i - 1];
          if (dt > 0) dts.add(dt);
        }
        if (dts.isNotEmpty) {
          dts.sort();
          medianDtMs = dts[dts.length ~/ 2];
          minDtMs = dts.first;
          maxDtMs = dts.last;
          final totalMs = ts.last - ts.first;
          samplesPerSecond =
              totalMs > 0 ? (ts.length - 1) / (totalMs / 1000.0) : 0.0;
        }
      }

      _log(
          "Verify $role: fpsNotify=${fpsNotifications.toStringAsFixed(1)}, samplesPerSec=${samplesPerSecond.toStringAsFixed(1)}, medianDtMs=${medianDtMs.toStringAsFixed(2)}, minDtMs=${minDtMs.toStringAsFixed(2)}, maxDtMs=${maxDtMs.toStringAsFixed(2)}");

      final fail = medianDtMs.isNaN ? false : medianDtMs >= 18.0;
      if (enableFallback && fail) {
        _log("Fallback auf $fallbackHz Hz für $role (medianDtMs=$medianDtMs)");
        await writer.configure(
          rate: _rateFromHz(fallbackHz),
          output: outputMode,
        );
      }

      // Nach Verifikation ggf. zurück auf den gewünschten Output schalten.
      if (needsTempTimestamp) {
        await writer.configure(rate: desiredRate, output: outputMode);
      }
    });
  }

  int get framesPerSecond {
    final now = DateTime.now().millisecondsSinceEpoch;
    _fpsWindowMs.removeWhere((t) => now - t > 1000);
    return _fpsWindowMs.length;
  }

  int get bufferSize => _storageQueue.length;

  String _toHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, "0"));
      buffer.write(" ");
    }
    return buffer.toString().trim();
  }

  void _onChunk(List<int> chunk) {
    if (!_recordingActive && !_collectVerify && gaitEngine == null) return;
    final frames = _assembler.add(Uint8List.fromList(chunk));
    _notifyCount += 1;
    for (final frame in frames) {
      if (frame.length >= 4 && frame[0] == 0x55 && frame[1] == 0x27) {
        _log("Readback-Response $role: ${_toHex(frame)}");
        continue;
      }
      final idx = _sampleIndex++;
      final timeSeconds = idx * _sampleIntervalSeconds;
      final decoder =
          _collectVerify ? WitFrameDecoder(outputMode: WitOutput.accGyroTimestamp) : _decoder;
      final decoded = decoder.decode(frame, idx, timeSeconds);
      if (decoded == null) continue;
      // FPS immer messen (auch ohne Recording), damit wir die Sampling-Qualität live sehen können.
      _fpsWindowMs.add(DateTime.now().millisecondsSinceEpoch);
      final ax = decoded.sample.ax;
      final ay = decoded.sample.ay;
      final az = decoded.sample.az;
      final gx = decoded.sample.gx;
      final gy = decoded.sample.gy;
      final gz = decoded.sample.gz;
      final aNorm = sqrt(ax * ax + ay * ay + az * az);
      final gNorm = sqrt(gx * gx + gy * gy + gz * gz);

      // Gait-Engine immer füttern (auch ohne Recording), Zeitbasis: bevorzugt Sensor-Timestamp, sonst Synthese.
      if (gaitEngine != null) {
        final tsMs = decoded.sample.timestampMs ?? (timeSeconds * 1000.0);
        gaitEngine!.addSample(
          leg: role,
          timestampMs: tsMs,
          accZ: az,
          gyroZ: gz,
          roll: decoded.sample.roll,
          pitch: decoded.sample.pitch,
          accX: ax,
          accY: ay,
          gyroX: gx,
          gyroY: gy,
        );
      }

      if (_collectVerify && decoded.sample.timestampMs != null) {
        _verifyTimestampsMs.add(decoded.sample.timestampMs!);
      }

      if (_recordingActive) {
        latestSample = decoded.sample;
        calibrator.addSample(decoded.sample);

        final storageValues = <String, double>{
          "aNorm": aNorm,
          "gNorm": gNorm,
          "roll": decoded.sample.roll,
          "pitch": decoded.sample.pitch,
          "yaw": decoded.sample.yaw,
        };
        _storageQueue.add(_QueuedEntry(
            idx, timeSeconds, decoded.sample.timestampMs, storageValues));
        if (_storageQueue.length > 2000) {
          _storageQueue.removeFirst();
          droppedFrames++;
        }
      }
    }
  }

  void _flush() {
    while (_storageQueue.isNotEmpty) {
      final entry = _storageQueue.removeFirst();
      storage.add(
        role,
        entry.values,
        sampleIndex: entry.sampleIndex,
        timeSeconds: entry.timeSeconds,
        sensorTimestampMs: entry.sensorTimestampMs,
      );
    }
    if (latestSample != null && !_uiController.isClosed) {
      _uiController.add(latestSample!);
    }
  }

  WitRate _rateFromHz(int hz) {
    if (hz >= 180) return WitRate.hz200;
    if (hz >= 75) return WitRate.hz100;
    return WitRate.hz50;
  }

  void _handleDone() {
    _log("Notify-Stream beendet für $role");
    onConnectionLost?.call();
  }

  void _handleError(Object e) {
    _log("Notify-Fehler für $role: $e");
    onConnectionLost?.call();
  }

  void _log(String msg) {
    if (logEnabled) debugPrint(msg);
  }

  Stream<SensorSample> get uiStream => _uiController.stream;

  void resetSampleIndex() {
    _sampleIndex = 0;
    _storageQueue.clear();
  }

  void _handleStart() {
    _recordingActive = true;
    resetSampleIndex();
  }

  void _handleStop() {
    _recordingActive = false;
  }

}

class _QueuedEntry {
  final int sampleIndex;
  final double timeSeconds;
  final double? sensorTimestampMs;
  final Map<String, double> values;

  _QueuedEntry(
      this.sampleIndex,
      this.timeSeconds,
      this.sensorTimestampMs,
      this.values);
}
