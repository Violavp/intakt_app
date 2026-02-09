import 'dart:async';
import 'dart:math';

import '../ble/wit_writer.dart';
import '../models/sensor_sample.dart';

enum CalibState { idle, collecting, readyToCalibrate, calibrating, done, failed }

class AutoCalibrator {
  final BleDeviceWriter writer;
  final Duration windowLength;
  final double accelStdThreshold;
  final double gyroStdThreshold;
  final Duration minStillDuration;
  final Duration waitAfterConfig;

  CalibState state = CalibState.idle;

  final List<SensorSample> _buffer = [];
  double? _stillSince;

  AutoCalibrator({
    required this.writer,
    this.windowLength = const Duration(seconds: 2),
    this.accelStdThreshold = 0.005, // g
    this.gyroStdThreshold = 0.5, // deg/s
    this.minStillDuration = const Duration(seconds: 1),
    this.waitAfterConfig = const Duration(milliseconds: 200),
  });

  void addSample(SensorSample sample) {
    if (state == CalibState.idle) {
      state = CalibState.collecting;
    }
    if (state != CalibState.collecting) return;

    _buffer.add(sample);
    _trimBuffer(sample.timeSeconds);

    if (_buffer.length < 10) return;

    final stats = _computeStats();
    final now = sample.timeSeconds;

    final isStill =
        stats.accelStd < accelStdThreshold && stats.gyroStd < gyroStdThreshold;

    if (isStill) {
      _stillSince ??= now;
      final stillDuration = now - _stillSince!;
      if (stillDuration >= minStillDuration.inSeconds) {
        state = CalibState.readyToCalibrate;
      }
    } else {
      _stillSince = null;
    }
  }

  /// Führt die Kalibrierung aus. Gibt true zurück bei Erfolg, false sonst.
  Future<bool> runCalibration() async {
    if (state != CalibState.readyToCalibrate &&
        state != CalibState.collecting) {
      state = CalibState.calibrating;
    } else {
      state = CalibState.calibrating;
    }

    try {
      // Burst on, 100Hz setzen, speichern und kurz warten
      await _applyBurstAndRate100();
      await Future.delayed(waitAfterConfig);

      await writer.write([0xFF, 0xAA, 0x69, 0x88, 0xB5]); // Unlock
      await writer.write([0xFF, 0xAA, 0x01, 0x01, 0x00]); // Accel calib
      await Future.delayed(const Duration(milliseconds: 500));

      await writer.write([0xFF, 0xAA, 0x00, 0x00, 0x00]); // Save

      state = CalibState.done;
      return true;
    } catch (_) {
      state = CalibState.failed;
      return false;
    }
  }

  void _trimBuffer(double latestSeconds) {
    final cutoff = latestSeconds - windowLength.inMilliseconds / 1000.0;
    _buffer.removeWhere((s) => s.timeSeconds < cutoff);
  }

  _Stats _computeStats() {
    final accelMag = <double>[];
    final gyroMag = <double>[];

    for (final s in _buffer) {
      accelMag.add(_mag(s.ax, s.ay, s.az));
      gyroMag.add(_mag(s.gx, s.gy, s.gz));
    }

    return _Stats(
      accelStd: _std(accelMag),
      gyroStd: _std(gyroMag),
    );
  }

  double _mag(double x, double y, double z) => sqrt(x * x + y * y + z * z);

  double _std(List<double> values) {
    if (values.isEmpty) return double.nan;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final varSum =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
    return sqrt(varSum / values.length);
  }

  Future<void> _applyBurstAndRate100() async {
    await writer.write([0xFF, 0xAA, 0x69, 0x88, 0xB5]); // Unlock
    await Future.delayed(const Duration(milliseconds: 150));
    await writer.write([0xFF, 0xAA, 0x03, 0x09, 0x00]); // 100 Hz (ID)
    await Future.delayed(const Duration(milliseconds: 150));
    await writer.write([0xFF, 0xAA, 0x96, 0x02, 0x00]); // acc+gyro+timestamp
    await Future.delayed(const Duration(milliseconds: 150));
    await writer.write([0xFF, 0xAA, 0x00, 0x00, 0x00]); // Save
  }
}

class _Stats {
  final double accelStd;
  final double gyroStd;

  _Stats({required this.accelStd, required this.gyroStd});
}
