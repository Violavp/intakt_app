import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class RecordingForegroundService {
  static const MethodChannel _iosChannel =
      MethodChannel('intakt_app/recording_background');

  static Future<void> start() async {
    if (Platform.isIOS) {
      await _iosChannel.invokeMethod('startRecordingBackgroundTask');
      return;
    }
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'Aufnahme läuft',
      notificationText: 'Sensor-Daten werden aufgezeichnet.',
      callback: startCallback,
    );
  }

  static Future<void> stop() async {
    if (Platform.isIOS) {
      await _iosChannel.invokeMethod('stopRecordingBackgroundTask');
      return;
    }
    if (!Platform.isAndroid) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

class _RecordingTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}
