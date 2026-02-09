import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../ble/wit_writer.dart';
import '../calibration/wit_calibrator.dart';
import 'sensor_pipeline.dart';
import 'takt_engine.dart';
import 'sensor_storage.dart';

/// Zuordnung deiner Sensoren (ID-Suffix → Rolle)
/// IDs aus deinen Logs:
/// VL: 11B85F0D-DFB2-4C02-546C-657910C7ECB7
/// VR: 6FB95EEE-A2D9-7A4C-75EC-83FEC4707D1D
/// HL: 56BCA306-26D0-9EA8-3056-1B9D88FD0E8C
/// HR: 1D1877C5-E41B-ED8D-43DA-1792A254366C
const Map<String, String> sensorSuffixByRole = {
  "657910C7ECB7": "VL",
  "83FEC4707D1D": "VR",
  "1B9D88FD0E8C": "HL",
  "1792A254366C": "HR",
};

/// Fallback-Reihenfolge, falls keine Suffixe matchen
const List<String> rolesOrder = ["VL", "VR", "HL", "HR"];

class BLEManager {
  // WT901BLE67 sendet je nach Firmware:
  // - FFF0 / FFF4 (notify)
  // - FFE5 / FFE4 (notify)
  // - gelegentlich 0000 / 0011 / 0022 (legacy)
  static const String primaryServiceUUID = "0000fff0-0000-1000-8000-00805f9b34fb";
  static const String primaryCharUUID = "0000fff4-0000-1000-8000-00805f9b34fb";
  static const String serviceFFE5 = "0000ffe5-0000-1000-8000-00805f9a34fb";
  static const String charFFE4 = "0000ffe4-0000-1000-8000-00805f9a34fb";
  static const String charFFE9 = "0000ffe9-0000-1000-8000-00805f9a34fb"; // write
  static const String altServiceUUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const String altCharUUID = "0000ffe1-0000-1000-8000-00805f9b34fb";
  static const String legacyServiceUUID = "00000000-0000-1000-8000-00805f9b34fb";
  static const String legacyCharUUID1 = "00000011-0000-1000-8000-00805f9b34fb";
  static const String legacyCharUUID2 = "00000022-0000-1000-8000-00805f9b34fb";

  final SensorStorage storage;
  final TaktEngine? gaitEngine;

  /// Verbindung pro Sensorrolle
  final Map<String, bool> connected = {
    "VL": false,
    "VR": false,
    "HL": false,
    "HR": false,
  };

  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, StreamSubscription<BluetoothConnectionState>> _connSubs = {};
  Timer? _rescanTimer;
  final Set<String> _seenDevices = {};
  final Map<String, AutoCalibrator> _calibrators = {};
  final Map<String, WitWriter> _writers = {};
  final Map<String, SensorPipeline> _pipelines = {};
  static const bool _enableLogs = true;
  static const WitOutput _outputMode = WitOutput.accGyroTimestamp;

  void _log(String message) {
    if (_enableLogs) debugPrint(message);
  }

  BLEManager({required this.storage, this.gaitEngine}) {
    // Log-Level reduzieren, damit die Konsole nicht überläuft.
    FlutterBluePlus.setLogLevel(LogLevel.warning);
  }

  Future<void> startScanAndConnect() async {
    // Warte auf einen gültigen Adapter-Status und stelle sicher, dass BT an ist
    final state = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown);
    if (state != BluetoothAdapterState.on) {
      _log("Bluetooth nicht aktiv: $state");
      return;
    }

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

    FlutterBluePlus.scanResults.listen((results) async {
      for (var r in results) {
        final name = r.device.name;
        final id = r.device.remoteId.str;
        if (name.isEmpty) continue;

        // Verhindere, dass ein Gerät mehreren Rollen zugeordnet wird.
        if (_devices.values.any((d) => d.remoteId.str == id)) continue;

        // Nur unsere bekannten Sensoren verarbeiten.
        final matchesSuffix =
            sensorSuffixByRole.keys.any((s) => name.contains(s) || id.contains(s));
        final isWT = name.startsWith("WT901");
        if (!matchesSuffix && !isWT) continue;

        if (_seenDevices.add(id)) {
          _log("Gefunden: $name ($id)");
        }

        bool matched = false;

        // prüfe Suffix im Namen oder in der ID
        for (final entry in sensorSuffixByRole.entries) {
          final suffix = entry.key;
          final role = entry.value;

          if (!_devices.containsKey(role) &&
              (name.contains(suffix) || id.contains(suffix))) {
            _devices[role] = r.device;
            matched = true;
            _log("Match für $role → $id, verbinde...");
            await _connect(role, r.device);
            break;
          }
        }

        // falls kein Match, verteile in Reihenfolge der Rollen
        if (!matched) {
          for (final role in rolesOrder) {
            if (!_devices.containsKey(role)) {
              _devices[role] = r.device;
              _log("Fallback-Rolle $role → $id, verbinde...");
              await _connect(role, r.device);
              break;
            }
          }
        }
      }
    });

    // Wiederkehrender Scan, um abgehängte Sensoren erneut zu verbinden.
    _rescanTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      _scanMissing();
    });
  }

  Future<void> _connect(String role, BluetoothDevice device) async {
    await _pipelines[role]?.stop();
    connected[role] = false; // erst grün, wenn Notifications aktiv
    try {
      await device.connect(autoConnect: false);
      _log("Verbunden mit $role (${device.remoteId}) – prüfe Services");
    } catch (e) {
      _log("Verbindung zu $role fehlgeschlagen: $e");
      return;
    }

    List<BluetoothService> services = [];
    try {
      services = await device.discoverServices();
    } catch (e) {
      _log("discoverServices für $role fehlgeschlagen: $e");
      return;
    }
    if (services.isEmpty) {
      _log("Keine Services gefunden für $role");
    }
    BluetoothCharacteristic? writeChar;
    BluetoothCharacteristic? notifyChar;
    for (var s in services) {
      final sid = s.uuid.toString().toLowerCase();
      _log("Service $sid für $role");
      for (var c in s.characteristics) {
        _log(
            "  Char ${c.uuid.toString().toLowerCase()} props: notify=${c.properties.notify} read=${c.properties.read} write=${c.properties.write}");
        if (c.uuid.toString().toLowerCase() == charFFE9) {
          writeChar = c;
        }
        final cid = c.uuid.toString().toLowerCase();
        if ((cid == primaryCharUUID ||
                cid == charFFE4 ||
                cid == altCharUUID ||
                cid == legacyCharUUID1 ||
                cid == legacyCharUUID2) &&
            c.properties.notify) {
          notifyChar = c;
        }
      }
    }
    _connSubs[role]?.cancel();
    _connSubs[role] = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnected(role, "connectionState");
      }
    });
    if (notifyChar != null && writeChar != null) {
      final writer = WitWriter(writeChar);
      _writers[role] = writer;
      final calibrator = AutoCalibrator(writer: writer);
      _calibrators[role] = calibrator;
      final pipeline = SensorPipeline(
        role: role,
        storage: storage,
        writer: writer,
        calibrator: calibrator,
        outputMode: _outputMode,
        logEnabled: _enableLogs,
        gaitEngine: gaitEngine,
        onConnectionLost: () => _handleDisconnected(role, "notifyStream"),
      );
      _pipelines[role] = pipeline;

      await pipeline.start(notifyChar);
      await pipeline.applyRateWithVerify();

      // Rate-Register auslesen und loggen
      try {
        await writer.verifyRate();
      } catch (_) {}

      connected[role] = true;
      _log("Notifications aktiv für $role");
      return;
    }
    _log("Gesuchter Service/Char nicht gefunden für $role");
  }

  void _handleDisconnected(String role, String source) {
    _log("Verbindung beendet für $role ($source)");
    connected[role] = false;
    _pipelines[role]?.stop();
    _pipelines.remove(role);
    _devices.remove(role);
    _connSubs[role]?.cancel();
    _connSubs.remove(role);
    _scanMissing();
  }

  void _scanMissing() {
    final missing = connected.entries
        .where((e) => e.value == false)
        .map((e) => e.key)
        .toList();
    if (missing.isEmpty) return;
    _log("Fehlende Rollen: $missing → Rescan");
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
  }

  /// Kalibriert alle Sensoren, die bereit sind. Gibt true zurück, wenn alle Versuche erfolgreich.
  Future<bool> calibrateAll() async {
    bool allOk = true;
    for (final entry in _calibrators.entries) {
      final cal = entry.value;
      if (cal.state == CalibState.readyToCalibrate ||
          cal.state == CalibState.collecting) {
        final ok = await cal.runCalibration();
        if (!ok) allOk = false;
      }
    }
    return allOk;
  }

  /// Setzt Samplingrate/Burst/Save auf allen verfügbaren Write-Characteristics.
  Future<void> setWitRate(WitRate rate) async {
    for (final entry in _writers.entries) {
      final role = entry.key;
      final writer = entry.value;
      try {
        await writer.setWitRate(rate);
      } catch (e) {
        _log("Rate-Set für $role fehlgeschlagen: $e");
      }
    }
  }

  /// Aktuelle "effektive" Frames pro Sekunde pro Rolle (aus der Pipeline gemessen).
  /// 0 bedeutet: keine Daten / nicht verbunden / noch keine Samples.
  Map<String, int> framesPerSecondByRole() {
    final out = <String, int>{};
    for (final role in connected.keys) {
      out[role] = _pipelines[role]?.framesPerSecond ?? 0;
    }
    return out;
  }

  /// Anzahl der verworfenen Frames (Queue übergelaufen) pro Rolle.
  Map<String, int> droppedFramesByRole() {
    final out = <String, int>{};
    for (final role in connected.keys) {
      out[role] = _pipelines[role]?.droppedFrames ?? 0;
    }
    return out;
  }
}
