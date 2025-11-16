import 'package:flutter/material.dart';

class HorseSilhouette extends StatelessWidget {
  final double width;
  final double height;
  final double opacity;

  const HorseSilhouette({
    super.key,
    this.width = 180,
    this.height = 360,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size(width, height),
        painter: _HorseSilhouettePainter(),
      ),
    );
  }
}

class _HorseSilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final Paint glow = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;

    final double w = size.width;
    final double h = size.height;

    // CENTRAL VERTICAL LINE
    canvas.drawLine(
      Offset(w / 2, h * 0.05),
      Offset(w / 2, h * 0.95),
      line,
    );

    // UPPER OVAL
    final Rect topOval = Rect.fromCenter(
      center: Offset(w / 2, h * 0.32),
      width: w * 0.55,
      height: h * 0.18,
    );
    canvas.drawOval(topOval, line);
    canvas.drawOval(topOval.inflate(12), glow);

    // MID OVAL
    final Rect midOval = Rect.fromCenter(
      center: Offset(w / 2, h * 0.50),
      width: w * 0.70,
      height: h * 0.22,
    );
    canvas.drawOval(midOval, line);
    canvas.drawOval(midOval.inflate(12), glow);

    // LOWER OVAL
    final Rect bottomOval = Rect.fromCenter(
      center: Offset(w / 2, h * 0.70),
      width: w * 0.55,
      height: h * 0.18,
    );
    canvas.drawOval(bottomOval, line);
    canvas.drawOval(bottomOval.inflate(12), glow);

    // MARKERS
    final Paint markerFill = Paint()
      ..color = Colors.white.withOpacity(0.28)
      ..style = PaintingStyle.fill;

    final Paint markerStroke = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    void drawMarker(Offset p) {
      canvas.drawCircle(p, 5, markerFill);
      canvas.drawCircle(p, 5, markerStroke);
    }

    // Shoulders
    drawMarker(Offset(w * 0.18, h * 0.30));
    drawMarker(Offset(w * 0.82, h * 0.30));

    // Hips
    drawMarker(Offset(w * 0.18, h * 0.70));
    drawMarker(Offset(w * 0.82, h * 0.70));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
