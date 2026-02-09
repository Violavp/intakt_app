import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'pages/main_page.dart';
import 'pages/takt_detail.dart';
import 'pages/symmetrie_detail.dart';
import 'pages/lastaufnahme_detail.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'recording_channel',
      channelName: 'Aufnahme',
      channelDescription: 'Hält die Sensor-Aufnahme im Hintergrund aktiv.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      iconData: const NotificationIconData(
        resType: ResourceType.mipmap,
        resPrefix: ResourcePrefix.ic,
        name: 'launcher',
      ),
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: const ForegroundTaskOptions(
      interval: 5000,
      isOnceEvent: false,
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
  runApp(const InTaktApp());
}

class InTaktApp extends StatelessWidget {
  const InTaktApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: "InTakt – Live Training",
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF0D1612),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: Colors.white),
          ),
        ),
        routes: {
          "/": (context) => const MainPage(),
          "/takt": (context) => const TaktDetailPage(),
          "/symmetrie": (context) => const SymmetrieDetailPage(),
          "/last": (context) => const LastaufnahmeDetailPage(),
        },
      ),
    );
  }
}
