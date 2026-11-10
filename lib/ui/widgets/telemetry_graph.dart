import 'package:flutter/material.dart';

class SpeedHistoryGraphPainter extends CustomPainter {
  final List<double> history;
  final double maxScale;
  final double speedLimit;
  final Color lineColor;

  SpeedHistoryGraphPainter({
    required this.history,
    required this.maxScale,
    required this.speedLimit,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final width = size.width;
    final height = size.height;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, height * 0.5), Offset(width, height * 0.5), gridPaint);

    double limitY = height - (speedLimit / maxScale).clamp(0.0, 1.0) * height;
    final limitPaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, limitY), Offset(width, limitY), limitPaint);

    final path = Path();
    final fillPath = Path();

    double stepX = history.length > 1 ? width / (history.length - 1) : width;

    for (int i = 0; i < history.length; i++) {
      double x = i * stepX;
      double normalized = (history[i] / maxScale).clamp(0.0, 1.0);
      double y = height - (normalized * (height - 6)) - 3;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo((history.length - 1) * stepX, height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withOpacity(0.25), lineColor.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, width, height));
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant SpeedHistoryGraphPainter oldDelegate) {
    return true;
  }
}
