import '../models/sensor_sample.dart';

class ParsedSample {
  final Map<String, double> values;
  final SensorSample sample;

  ParsedSample({required this.values, required this.sample});
}

class WitParser {
  final Map<String, List<int>> _cache = {};

  List<ParsedSample> parse(String role, List<int> data) {
    final buffer = <int>[...?_cache[role], ...data];
    final results = <ParsedSample>[];

    int headerIndex = _findHeader(buffer);
    if (headerIndex == -1) {
      _cache[role] = [];
      return results;
    }
    if (headerIndex > 0) {
      buffer.removeRange(0, headerIndex);
    }
    if (buffer.length < 14) {
      _cache[role] = buffer;
      return results;
    }

    while (buffer.length >= 14 && buffer[0] == 0x55 && buffer[1] == 0x61) {
      final frames = (buffer.length - 2) ~/ 12;
      if (frames <= 0) break;

      for (int i = 0; i < frames; i++) {
        final base = 2 + i * 12;
        if (base + 11 >= buffer.length) break;
        int ax = _i16(buffer[base], buffer[base + 1]);
        int ay = _i16(buffer[base + 2], buffer[base + 3]);
        int az = _i16(buffer[base + 4], buffer[base + 5]);
        int gx = _i16(buffer[base + 6], buffer[base + 7]);
        int gy = _i16(buffer[base + 8], buffer[base + 9]);
        int gz = _i16(buffer[base + 10], buffer[base + 11]);

        final map = <String, double>{
          "accX": ax / 32768.0 * 16.0,
          "accY": ay / 32768.0 * 16.0,
          "accZ": az / 32768.0 * 16.0,
          "gyroX": gx / 32768.0 * 2000.0,
          "gyroY": gy / 32768.0 * 2000.0,
          "gyroZ": gz / 32768.0 * 2000.0,
          "roll": 0,
          "pitch": 0,
          "yaw": 0,
        };
        results.add(ParsedSample(
          values: map,
          sample: SensorSample(
            sampleIndex: 0,
            timeSeconds: 0,
            ax: map["accX"]!,
            ay: map["accY"]!,
            az: map["accZ"]!,
            gx: map["gyroX"]!,
            gy: map["gyroY"]!,
            gz: map["gyroZ"]!,
            roll: 0,
            pitch: 0,
            yaw: 0,
          ),
        ));
      }

      final consumed = 2 + frames * 12;
      if (buffer.length > consumed) {
        _cache[role] = buffer.sublist(consumed);
      } else {
        _cache[role] = [];
      }
      break;
    }

    return results;
  }

  int _findHeader(List<int> buf) {
    for (int i = 0; i + 1 < buf.length; i++) {
      if (buf[i] == 0x55 && buf[i + 1] == 0x61) {
        return i;
      }
    }
    return -1;
  }

  int _i16(int lo, int hi) {
    int v = (hi << 8) | lo;
    if (v & 0x8000 != 0) v -= 65536;
    return v;
  }
}
