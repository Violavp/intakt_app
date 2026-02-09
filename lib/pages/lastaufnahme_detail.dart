import 'dart:math';

import 'package:flutter/material.dart';

import '../widgets/green_gradient_background.dart';

class LastaufnahmeDetailPage extends StatelessWidget {
  const LastaufnahmeDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    const legData = [
      LegData(label: "VL", fullName: "Vorne Links", load: 48, position: "VL"),
      LegData(label: "VR", fullName: "Vorne Rechts", load: 52, position: "VR"),
      LegData(label: "HL", fullName: "Hinten Links", load: 58, position: "HL"),
      LegData(label: "HR", fullName: "Hinten Rechts", load: 62, position: "HR"),
    ];

    final vl = legData.firstWhere((l) => l.label == "VL").load;
    final vr = legData.firstWhere((l) => l.label == "VR").load;
    final hl = legData.firstWhere((l) => l.label == "HL").load;
    final hr = legData.firstWhere((l) => l.label == "HR").load;

    final frontTotal = vl + vr;
    final hindTotal = hl + hr;
    final totalLoad = frontTotal + hindTotal;
    final loadDistributionIndex =
        ((hindTotal / totalLoad) * 100).round();
    final pitch = ((hindTotal - frontTotal) / totalLoad) * 10.0;
    final frontHindRatio = ((frontTotal / hindTotal) * 100).round();
    final mostActiveLeg = legData.reduce(
      (prev, current) => prev.load > current.load ? prev : current,
    );
    final centerOfGravity = (hindTotal - frontTotal) / totalLoad;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GreenGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              children: [
                _Header(
                  title: "Lastaufnahme",
                  subtitle: "Gewichtsverteilung",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _HorseLoadVisualization(
                    legData: legData,
                    totalLoad: totalLoad,
                    centerOfGravity: centerOfGravity,
                  ),
                ),
                const SizedBox(height: 12),
                _MetricsGrid(
                  loadDistributionIndex: loadDistributionIndex,
                  pitch: pitch,
                  frontHindRatio: frontHindRatio,
                  mostActiveLeg: mostActiveLeg.label,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LegData {
  final String label;
  final String fullName;
  final double load;
  final String position;

  const LegData({
    required this.label,
    required this.fullName,
    required this.load,
    required this.position,
  });
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
                  fontFamily: "Inter",
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0x80FFFFFF),
                  fontFamily: "Inter",
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

class _HorseLoadVisualization extends StatelessWidget {
  final List<LegData> legData;
  final double totalLoad;
  final double centerOfGravity;

  const _HorseLoadVisualization({
    required this.legData,
    required this.totalLoad,
    required this.centerOfGravity,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 300,
        height: 340,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final cogTop = (0.5 - centerOfGravity * 0.25) * height;

            return Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 160,
                    height: 220,
                    child: CustomPaint(
                      painter: _HorseTopViewPainter(),
                    ),
                  ),
                ),
                Positioned(
                  top: cogTop,
                  left: width / 2,
                  child: _CenterOfGravityIndicator(),
                ),
                Positioned(
                  top: height * 0.1,
                  left: width * 0.5 - 20,
                  child: const Text(
                    "Vorhand",
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.0,
                      color: Color(0x55FFFFFF),
                    ),
                  ),
                ),
                Positioned(
                  bottom: height * 0.1,
                  left: width * 0.5 - 26,
                  child: const Text(
                    "Hinterhand",
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.0,
                      color: Color(0x55FFFFFF),
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(-0.55, -0.75),
                  child: LegIndicator(leg: legData[0], totalLoad: totalLoad),
                ),
                Align(
                  alignment: const Alignment(0.55, -0.75),
                  child: LegIndicator(leg: legData[1], totalLoad: totalLoad),
                ),
                Align(
                  alignment: const Alignment(-0.55, 0.75),
                  child: LegIndicator(leg: legData[2], totalLoad: totalLoad),
                ),
                Align(
                  alignment: const Alignment(0.55, 0.75),
                  child: LegIndicator(leg: legData[3], totalLoad: totalLoad),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class LegIndicator extends StatelessWidget {
  final LegData leg;
  final double totalLoad;

  const LegIndicator({
    super.key,
    required this.leg,
    required this.totalLoad,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedLoad = leg.load / 100.0;
    final fillPercentage = (leg.load / totalLoad) * 100.0;
    final fillFactor = (fillPercentage * 4 / 100).clamp(0.0, 1.0);
    final status = _statusForLoad(leg.load, totalLoad);
    final colors = _statusColors(status);
    final glowOpacity = (normalizedLoad * 0.5).clamp(0.0, 0.6);

    return SizedBox(
      width: 90,
      height: 110,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 12,
            child: Opacity(
              opacity: glowOpacity,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.glow,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            children: [
              Text(
                leg.label,
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.0,
                  color: Color(0x66FFFFFF),
                  fontFamily: "Inter",
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.05),
                        border: Border.all(
                          color: colors.glow.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: fillFactor,
                        child: Container(
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                colors.fill,
                                colors.fill.withOpacity(0.6),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colors.glow.withOpacity(glowOpacity),
                                blurRadius: 16 + normalizedLoad * 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        "${leg.load.toStringAsFixed(0)}%",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xE6FFFFFF),
                          fontFamily: "Inter",
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CenterOfGravityIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-8, -8),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEDB43A).withOpacity(0.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEDB43A).withOpacity(0.7),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEDB43A),
                border: Border.all(
                  color: Colors.white.withOpacity(0.6),
                  width: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HorseTopViewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC9B896).withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final scaleX = size.width / 200;
    final scaleY = size.height / 240;
    canvas.scale(scaleX, scaleY);

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 120), width: 64, height: 130),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 50), width: 36, height: 60),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 25), width: 24, height: 30),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(100, 185)
        ..quadraticBezierTo(100, 200, 100, 210),
      paint..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MetricsGrid extends StatelessWidget {
  final int loadDistributionIndex;
  final double pitch;
  final int frontHindRatio;
  final String mostActiveLeg;

  const _MetricsGrid({
    required this.loadDistributionIndex,
    required this.pitch,
    required this.frontHindRatio,
    required this.mostActiveLeg,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: "Lastaufnahme-Index",
                value: "$loadDistributionIndex%",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: "Pitch",
                value: "${pitch.toStringAsFixed(1)}deg",
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: "Verhaeltnis V/H",
                value: "$frontHindRatio%",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: "Aktivstes Bein",
                value: mostActiveLeg,
                highlight: true,
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
  final bool highlight;

  const _MetricCard({
    required this.title,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = highlight
        ? const Color(0x3322C55E)
        : Colors.white.withOpacity(0.05);
    final borderColor = highlight
        ? const Color(0x6622C55E)
        : Colors.white.withOpacity(0.1);
    final textColor = highlight
        ? const Color(0xFFB2F5C1)
        : const Color(0xE6FFFFFF);
    final subtitleColor =
        highlight ? const Color(0xB2A7F3B9) : const Color(0x80FFFFFF);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.0,
              color: subtitleColor,
              fontFamily: "Inter",
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: textColor,
              fontFamily: "Inter",
            ),
          ),
        ],
      ),
    );
  }
}

enum _LegStatus { harmonious, caution, alert }

class _StatusColors {
  final Color fill;
  final Color glow;

  const _StatusColors({
    required this.fill,
    required this.glow,
  });
}

_LegStatus _statusForLoad(double load, double totalLoad) {
  final legPercentage = (load / totalLoad) * 100;
  if (legPercentage < 20) return _LegStatus.alert;
  if (legPercentage < 23) return _LegStatus.caution;
  return _LegStatus.harmonious;
}

_StatusColors _statusColors(_LegStatus status) {
  switch (status) {
    case _LegStatus.harmonious:
      return const _StatusColors(
        fill: Color(0xFF10B981),
        glow: Color(0xFF10B981),
      );
    case _LegStatus.caution:
      return const _StatusColors(
        fill: Color(0xFFF59E0B),
        glow: Color(0xFFF59E0B),
      );
    case _LegStatus.alert:
      return const _StatusColors(
        fill: Color(0xFFEF4444),
        glow: Color(0xFFEF4444),
      );
  }
}
