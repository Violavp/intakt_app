import 'package:flutter/material.dart';

class SymmetrieDetailPage extends StatelessWidget {
  const SymmetrieDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1612),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Geraderichtung"),
      ),
      body: const Center(
        child: Text(
          "Geraderichtung-Analyse folgt.",
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
