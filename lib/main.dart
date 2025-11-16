import 'package:flutter/material.dart';
import 'pages/main_page.dart';
import 'pages/takt_detail.dart';
import 'pages/symmetrie_detail.dart';
import 'pages/lastaufnahme_detail.dart';

void main() {
  runApp(const InTaktApp());
}

class InTaktApp extends StatelessWidget {
  const InTaktApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    );
  }
}
