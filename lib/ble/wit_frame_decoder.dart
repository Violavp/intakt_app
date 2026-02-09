import 'dart:typed_data';

import '../models/sensor_sample.dart';
import 'wit_writer.dart';

class DecodedSample {
  final SensorSample sample;
  final Map<String, double> storageValues;

  DecodedSample({required this.sample, required this.storageValues});
}

/// Dekodiert 20-Byte-WIT-Frames in nutzbare Samples.
class WitFrameDecoder {
  WitFrameDecoder({required this.outputMode});

  final WitOutput outputMode;

  DecodedSample? decode(Uint8List frame, int sampleIndex, double timeSeconds) {
    if (frame.length < 20) return null;
    if (frame[0] != 0x55) return null;

    switch (frame[1]) {
      case 0x61:
        return outputMode == WitOutput.accGyroTimestamp
            ? _decodeAccGyroTimestamp(frame, sampleIndex, timeSeconds)
            : _decodeAccGyroAngle(frame, sampleIndex, timeSeconds);
      default:
        return null;
    }
  }

  DecodedSample _decodeAccGyroTimestamp(
      Uint8List d, int sampleIndex, double timeSeconds) {
    final ax = _i16(d[2], d[3]) / 32768.0 * 16.0;
    final ay = _i16(d[4], d[5]) / 32768.0 * 16.0;
    final az = _i16(d[6], d[7]) / 32768.0 * 16.0;
    final gx = _i16(d[8], d[9]) / 32768.0 * 2000.0;
    final gy = _i16(d[10], d[11]) / 32768.0 * 2000.0;
    final gz = _i16(d[12], d[13]) / 32768.0 * 2000.0;
    final tsMs = _u32(d[14], d[15], d[16], d[17]).toDouble();

    final sample = SensorSample(
      sampleIndex: sampleIndex,
      timeSeconds: timeSeconds,
      ax: ax,
      ay: ay,
      az: az,
      gx: gx,
      gy: gy,
      gz: gz,
      roll: 0,
      pitch: 0,
      yaw: 0,
      timestampMs: tsMs,
    );

    return DecodedSample(
      sample: sample,
      storageValues: {
        "accZ": az,
        "gyroZ": gz,
        "timestampMs": tsMs,
      },
    );
  }

  DecodedSample _decodeAccGyroAngle(
      Uint8List d, int sampleIndex, double timeSeconds) {
    final ax = _i16(d[2], d[3]) / 32768.0 * 16.0;
    final ay = _i16(d[4], d[5]) / 32768.0 * 16.0;
    final az = _i16(d[6], d[7]) / 32768.0 * 16.0;
    final gx = _i16(d[8], d[9]) / 32768.0 * 2000.0;
    final gy = _i16(d[10], d[11]) / 32768.0 * 2000.0;
    final gz = _i16(d[12], d[13]) / 32768.0 * 2000.0;
    final roll = _i16(d[14], d[15]) / 32768.0 * 180.0;
    final pitch = _i16(d[16], d[17]) / 32768.0 * 180.0;
    final yaw = _i16(d[18], d[19]) / 32768.0 * 180.0;

    final sample = SensorSample(
      sampleIndex: sampleIndex,
      timeSeconds: timeSeconds,
      ax: ax,
      ay: ay,
      az: az,
      gx: gx,
      gy: gy,
      gz: gz,
      roll: roll,
      pitch: pitch,
      yaw: yaw,
      timestampMs: null,
    );

    return DecodedSample(
      sample: sample,
      storageValues: {
        "accZ": az,
        "gyroZ": gz,
        "roll": roll,
        "pitch": pitch,
        "yaw": yaw,
      },
    );
  }

  int _i16(int lo, int hi) {
    int v = (hi << 8) | lo;
    if (v & 0x8000 != 0) v -= 65536;
    return v;
  }

  int _u32(int b0, int b1, int b2, int b3) {
    return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
  }
}
