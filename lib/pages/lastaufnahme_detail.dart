import 'package:flutter/material.dart';

class LastaufnahmeDetailPage extends StatelessWidget {
  const LastaufnahmeDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1612),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Lastaufnahme"),
      ),
      body: const Center(
        child: Text(
          "Lastaufnahme-Visualisierung kommt später rein.",
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
