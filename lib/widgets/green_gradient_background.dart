import 'package:flutter/material.dart';

class GreenGradientBackground extends StatelessWidget {
  final Widget child;

  const GreenGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E3D30),
            Color(0xFF2A3D38),
            Color(0xFF353535),
          ],
        ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.1, -0.4),
            radius: 1.2,
            colors: [
              Color(0x663D5A4A),
              Colors.transparent,
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}
