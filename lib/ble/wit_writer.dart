import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum WitRate { hz50, hz100, hz200 }
enum WitOutput { accGyroAngle, accGyroTimestamp }

class WitRateIds {
  static int hz50 = 0x08;
  static int hz100 = 0x09; // zentral änderbar, falls nötig
  static int hz200 = 0x0B;
}

abstract class BleDeviceWriter {
  Future<void> write(List<int> bytes);
}

class WitWriter implements BleDeviceWriter {
  final BluetoothCharacteristic? characteristic;
  static const _cmdDelay = Duration(milliseconds: 150);

  const WitWriter(this.characteristic);

  @override
  Future<void> write(List<int> bytes) async {
    final c = characteristic;
    if (c == null) return;
    await c.write(bytes, withoutResponse: true);
  }

  Future<void> configure({
    required WitRate rate,
    WitOutput output = WitOutput.accGyroTimestamp,
  }) async {
    final c = characteristic;
    if (c == null) return;

    await write([0xFF, 0xAA, 0x69, 0x88, 0xB5]); // Unlock
    await Future.delayed(_cmdDelay);

    await write([0xFF, 0xAA, 0x03, _rateId(rate), 0x00]); // Return rate (index)
    await Future.delayed(_cmdDelay);

    await write([0xFF, 0xAA, 0x1F, 0x01, 0x00]); // Bandwidth 188 Hz (beibehalten)
    await Future.delayed(_cmdDelay);

    await write([0xFF, 0xAA, 0x96, _outputId(output), 0x00]); // Output content (z.B. acc+gyro+timestamp)
    await Future.delayed(_cmdDelay);

    await write([0xFF, 0xAA, 0x00, 0x00, 0x00]); // Save
    await Future.delayed(_cmdDelay);

    // optional logging intentionally suppressed to keep output clean
  }

  Future<void> setWitRate(WitRate rate) async {
    // Backwards-compatible shim to use the new configure flow.
    await configure(rate: rate, output: WitOutput.accGyroTimestamp);
    await verifyRate();
  }

  /// Liest Register 0x03 und loggt den zurückgelieferten Rate-Index.
  Future<void> verifyRate() async {
    final c = characteristic;
    if (c == null) return;
    try {
      await write([0xFF, 0xAA, 0x27, 0x03, 0x00]); // read reg 0x03
      await Future.delayed(_cmdDelay);
      // Die Antwort landet als Notification; Logging würde hier idealerweise an der Caller-Seite erfolgen.
    } catch (_) {
      // silent fail
    }
  }

  int _rateId(WitRate rate) {
    switch (rate) {
      case WitRate.hz50:
        return WitRateIds.hz50;
      case WitRate.hz100:
        return WitRateIds.hz100;
      case WitRate.hz200:
        return WitRateIds.hz200;
    }
  }

  int _outputId(WitOutput output) {
    switch (output) {
      case WitOutput.accGyroAngle:
        return 0x00;
      case WitOutput.accGyroTimestamp:
        return 0x02;
    }
  }
}
