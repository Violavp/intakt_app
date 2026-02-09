import 'dart:math';

import 'package:flutter/material.dart';

import '../widgets/green_gradient_background.dart';

class SymmetrieDetailPage extends StatelessWidget {
  const SymmetrieDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    const leftLoad = 45.0;
    const rightLoad = 55.0;
    const shoulderRotation = -8.0;
    const hipRotation = 6.0;

    final totalLoad = leftLoad + rightLoad;
    final sideDifference = (leftLoad - rightLoad).abs();
    final straightnessIndex =
        (100 - (sideDifference / totalLoad) * 100).round();
    final cogOffset = ((rightLoad - leftLoad) / totalLoad) * 50.0;

    final rotationalMisalignment =
        (shoulderRotation - hipRotation).abs();
    final hasRotation = rotationalMisalignment > 2.0;

    final status = _statusFor(straightnessIndex, hasRotation, rotationalMisalignment);
    final colors = _statusColors(status);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GreenGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              children: [
                _Header(
                  title: "Geraderichtung",
                  subtitle: "Koerperachsen-Analyse",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: _HorseVisualization(
                    cogOffset: cogOffset,
                    shoulderRotation: shoulderRotation,
                    hipRotation: hipRotation,
                    hasRotation: hasRotation,
                    colors: colors,
                    rotationalMisalignment: rotationalMisalignment,
                  ),
                ),
                const SizedBox(height: 10),
                _MetricsGrid(
                  straightnessIndex: straightnessIndex,
                  rotationalMisalignment: rotationalMisalignment,
                  shoulderRotation: shoulderRotation,
                  hipRotation: hipRotation,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.chevron_left, color: Color(0xE6FFFFFF)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Color(0xF2FFFFFF),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0x80FFFFFF),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }
}

class _HorseVisualization extends StatelessWidget {
  final double cogOffset;
  final double shoulderRotation;
  final double hipRotation;
  final bool hasRotation;
  final _StatusColors colors;
  final double rotationalMisalignment;

  const _HorseVisualization({
    required this.cogOffset,
    required this.shoulderRotation,
    required this.hipRotation,
    required this.hasRotation,
    required this.colors,
    required this.rotationalMisalignment,
  });

  @override
  Widget build(BuildContext context) {
    final leftOpacity =
        cogOffset < -2 ? min(cogOffset.abs() / 15.0, 0.6) : 0.0;
    final rightOpacity =
        cogOffset > 2 ? min(cogOffset / 15.0, 0.6) : 0.0;

    return Center(
      child: SizedBox(
        width: 340,
        height: 480,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 0.7,
                child: Opacity(
                  opacity: leftOpacity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(32),
                      ),
                      gradient: RadialGradient(
                        center: Alignment.centerRight,
                        radius: 1.0,
                        colors: [
                          colors.glow,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 0.7,
                child: Opacity(
                  opacity: rightOpacity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(32),
                      ),
                      gradient: RadialGradient(
                        center: Alignment.centerLeft,
                        radius: 1.0,
                        colors: [
                          colors.glow,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 40,
                height: 420,
                child: CustomPaint(
                  painter: _SpinePainter(
                    hasRotation: hasRotation,
                    shoulderRotation: shoulderRotation,
                    hipRotation: hipRotation,
                    color: colors.color,
                  ),
                ),
              ),
            ),
            _AxisLine(
              top: 0.31,
              width: 180,
              rotationDeg: shoulderRotation,
              hasRotation: hasRotation,
              colors: colors,
            ),
            _AxisLine(
              top: 0.69,
              width: 170,
              rotationDeg: hipRotation,
              hasRotation: hasRotation,
              colors: colors,
            ),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 160,
                height: 224,
                child: CustomPaint(
                  painter: _HorseSilhouettePainter(),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 0.31 * 480 - 10,
              child: const Text(
                "Schulter",
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: Color(0xB38BA18C),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 0.69 * 480 - 10,
              child: const Text(
                "Becken",
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: Color(0xB38BA18C),
                ),
              ),
            ),
            if (hasRotation)
              Positioned(
                left: 6,
                top: 240 - 24,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.color.withOpacity(0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Rotation",
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                      Text(
                        "${rotationalMisalignment.toStringAsFixed(1)}°",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AxisLine extends StatelessWidget {
  final double top;
  final double width;
  final double rotationDeg;
  final bool hasRotation;
  final _StatusColors colors;

  const _AxisLine({
    required this.top,
    required this.width,
    required this.rotationDeg,
    required this.hasRotation,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top * 480,
      left: (340 - width) / 2,
      child: Transform.rotate(
        angle: rotationDeg * pi / 180,
        child: Stack(
          children: [
            Container(
              width: width,
              height: 2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: hasRotation
                      ? [
                          colors.color.withOpacity(0.25),
                          colors.color,
                          colors.color.withOpacity(0.25),
                        ]
                      : const [
                          Color(0x4D8BA18C),
                          Color(0x998BA18C),
                          Color(0x4D8BA18C),
                        ],
                ),
                boxShadow: hasRotation
                    ? [
                        BoxShadow(
                          color: colors.glow,
                          blurRadius: 12,
                        )
                      ]
                    : null,
              ),
            ),
            Positioned(
              left: width * 0.1 - 5,
              top: -4,
              child: const _AxisMarker(),
            ),
            Positioned(
              right: width * 0.1 - 5,
              top: -4,
              child: const _AxisMarker(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AxisMarker extends StatelessWidget {
  const _AxisMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xCC8BA18C),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _HorseSilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC9B896).withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final scaleX = size.width / 200;
    final scaleY = size.height / 280;
    canvas.scale(scaleX, scaleY);

    canvas.drawOval(Rect.fromCenter(center: const Offset(100, 30), width: 24, height: 32), paint);
    canvas.drawLine(const Offset(100, 14), const Offset(100, 8), paint);
    canvas.drawLine(const Offset(95, 20), const Offset(92, 18), paint);
    canvas.drawLine(const Offset(105, 20), const Offset(108, 18), paint);

    canvas.drawPath(
      Path()
        ..moveTo(88, 42)
        ..quadraticBezierTo(85, 55, 82, 70)
        ..moveTo(112, 42)
        ..quadraticBezierTo(115, 55, 118, 70),
      paint..strokeCap = StrokeCap.round,
    );

    canvas.drawOval(Rect.fromCenter(center: const Offset(100, 140), width: 76, height: 150), paint);
    canvas.drawOval(Rect.fromCenter(center: const Offset(100, 85), width: 70, height: 40), paint);
    canvas.drawOval(Rect.fromCenter(center: const Offset(100, 200), width: 64, height: 36), paint);

    canvas.drawOval(Rect.fromCenter(center: const Offset(75, 85), width: 16, height: 20), paint);
    canvas.drawOval(Rect.fromCenter(center: const Offset(125, 85), width: 16, height: 20), paint);
    canvas.drawOval(Rect.fromCenter(center: const Offset(75, 200), width: 16, height: 20), paint);
    canvas.drawOval(Rect.fromCenter(center: const Offset(125, 200), width: 16, height: 20), paint);

    canvas.drawPath(
      Path()
        ..moveTo(100, 215)
        ..quadraticBezierTo(100, 235, 98, 250),
      paint..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SpinePainter extends CustomPainter {
  final bool hasRotation;
  final double shoulderRotation;
  final double hipRotation;
  final Color color;

  _SpinePainter({
    required this.hasRotation,
    required this.shoulderRotation,
    required this.hipRotation,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.0),
        color.withOpacity(0.85),
        color.withOpacity(0.85),
        color.withOpacity(0.0),
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    if (hasRotation) {
      paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    }

    final path = Path();
    final centerX = size.width / 2;
    if (hasRotation) {
      path.moveTo(centerX, 0);
      path.quadraticBezierTo(
        centerX - shoulderRotation * 0.8,
        size.height * 0.3,
        centerX,
        size.height * 0.5,
      );
      path.quadraticBezierTo(
        centerX + hipRotation * 0.8,
        size.height * 0.7,
        centerX,
        size.height,
      );
    } else {
      path.moveTo(centerX, 0);
      path.lineTo(centerX, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpinePainter oldDelegate) {
    return oldDelegate.hasRotation != hasRotation ||
        oldDelegate.shoulderRotation != shoulderRotation ||
        oldDelegate.hipRotation != hipRotation ||
        oldDelegate.color != color;
  }
}

class _MetricsGrid extends StatelessWidget {
  final int straightnessIndex;
  final double rotationalMisalignment;
  final double shoulderRotation;
  final double hipRotation;

  const _MetricsGrid({
    required this.straightnessIndex,
    required this.rotationalMisalignment,
    required this.shoulderRotation,
    required this.hipRotation,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: "Geraderichtungsindex",
                value: "$straightnessIndex%",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: "Rotation",
                value: "${rotationalMisalignment.toStringAsFixed(1)}°",
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: "Schulterachse",
                value: "${shoulderRotation.toStringAsFixed(0)}°",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: "Beckenachse",
                value:
                    "${hipRotation >= 0 ? '+' : ''}${hipRotation.toStringAsFixed(0)}°",
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const _MetricCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.0,
                      color: Color(0x80FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xE6FFFFFF),
                    ),
                  ),
                ],
              ),
    );
  }
}

enum _SymmetryStatus { harmonious, caution, alert }

class _StatusColors {
  final Color color;
  final Color glow;
  final Color text;

  const _StatusColors({
    required this.color,
    required this.glow,
    required this.text,
  });
}

_SymmetryStatus _statusFor(int straightnessIndex, bool hasRotation, double misalignment) {
  if (straightnessIndex >= 90 && !hasRotation) {
    return _SymmetryStatus.harmonious;
  }
  if (straightnessIndex >= 80 && misalignment < 8) {
    return _SymmetryStatus.caution;
  }
  return _SymmetryStatus.alert;
}

_StatusColors _statusColors(_SymmetryStatus status) {
  switch (status) {
    case _SymmetryStatus.harmonious:
      return const _StatusColors(
        color: Color(0xFF10B981),
        glow: Color(0x9910B981),
        text: Color(0xFF6EE7B7),
      );
    case _SymmetryStatus.caution:
      return const _StatusColors(
        color: Color(0xFFF59E0B),
        glow: Color(0x99F59E0B),
        text: Color(0xFFFBBF24),
      );
    case _SymmetryStatus.alert:
      return const _StatusColors(
        color: Color(0xFFEF4444),
        glow: Color(0x99EF4444),
        text: Color(0xFFF87171),
      );
  }
}
