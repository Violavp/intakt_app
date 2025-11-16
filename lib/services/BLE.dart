import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'sensor_storage.dart';

/// Zuordnung deiner Sensoren (MAC-Suffix → Rolle)
const Map<String, String> sensorSuffixByRole = {
  "657910C7ECB7": "VL",
  "83FEC4707D1D": "VR",
  "1B9D88FD0E8C": "HL",
  "1792A254366C": "HR",
};

class BLEManager {
  static const String serviceUUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const String charUUID = "0000ffe1-0000-1000-8000-00805f9b34fb";

  final SensorStorage storage;

  /// Verbindung pro Sensorrolle
  final Map<String, bool> connected = {
    "VL": false,
    "VR": false,
    "HL": false,
    "HR": false,
  };

  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, StreamSubscription<List<int>>> _subs = {};

  BLEManager({required this.storage});

  void startScanAndConnect() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

    FlutterBluePlus.scanResults.listen((results) async {
      for (var r in results) {
        final name = r.device.name;
        if (name.isEmpty) continue;

        // prüfe MAC-Suffix
        for (final entry in sensorSuffixByRole.entries) {
          final suffix = entry.key;
          final role = entry.value;

          if (name.contains(suffix) && !_devices.containsKey(role)) {
            _devices[role] = r.device;
            await _connect(role, r.device);
          }
        }
      }
    });
  }

  Future<void> _connect(String role, BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      connected[role] = true;
    } catch (_) {}

    final services = await device.discoverServices();
    for (var s in services) {
      if (s.uuid.toString() == serviceUUID) {
        for (var c in s.characteristics) {
          if (c.uuid.toString() == charUUID) {
            await c.setNotifyValue(true);
            _listen(role, c);
            return;
          }
        }
      }
    }
  }

  void _listen(String role, BluetoothCharacteristic c) {
    _subs[role]?.cancel();

    _subs[role] = c.onValueReceived.listen((value) {
      if (value.length < 11 || value[0] != 0x55) return;

      switch (value[1]) {
        case 0x51:
          storage.add(role, "accel", _parseAccel(value));
          break;

        case 0x52:
          storage.add(role, "gyro", _parseGyro(value));
          break;

        case 0x53:
          storage.add(role, "angles", _parseAngles(value));
          break;
      }
    }, onDone: () {
      connected[role] = false;
    });
  }

  Map<String, double> _parseAccel(List<int> d) {
    int ax = _i16(d[2], d[3]);
    int ay = _i16(d[4], d[5]);
    int az = _i16(d[6], d[7]);

    return {
      "ax_g": ax / 32768 * 16,
      "ay_g": ay / 32768 * 16,
      "az_g": az / 32768 * 16,
    };
  }

  Map<String, double> _parseGyro(List<int> d) {
    int gx = _i16(d[2], d[3]);
    int gy = _i16(d[4], d[5]);
    int gz = _i16(d[6], d[7]);

    return {
      "gx_dps": gx / 32768 * 2000,
      "gy_dps": gy / 32768 * 2000,
      "gz_dps": gz / 32768 * 2000,
    };
  }

  Map<String, double> _parseAngles(List<int> d) {
    int roll = _i16(d[2], d[3]);
    int pitch = _i16(d[4], d[5]);
    int yaw = _i16(d[6], d[7]);

    return {
      "roll_deg": roll / 32768 * 180,
      "pitch_deg": pitch / 32768 * 180,
      "yaw_deg": yaw / 32768 * 180,
    };
  }

  int _i16(int lo, int hi) {
    int v = (hi << 8) | lo;
    if (v & 0x8000 != 0) v -= 65536;
    return v;
  }
}
