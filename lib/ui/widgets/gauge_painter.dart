import 'dart:math';
import 'package:flutter/material.dart';

class SpeedometerGaugePainter extends CustomPainter {
  final double speed;
  final double maxScale;
  final double speedLimit;
  final bool isOverLimit;
  final String unit;
  final Color primaryColor;
  final Color secondaryColor;

  SpeedometerGaugePainter({
    required this.speed,
    required this.maxScale,
    required this.speedLimit,
    required this.isOverLimit,
    required this.unit,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    const startAngle = 135 * (pi / 180);
    const sweepAngle = 270 * (pi / 180);

    // 1. Dial Background
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF0F172A), Color(0xFF050811)],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.1));
    canvas.drawCircle(center, radius * 1.05, bgPaint);

    // 2. Base Dial Track Arc
    final baseTrackPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius * 0.84), startAngle, sweepAngle, false, baseTrackPaint);

    // 3. Warning Zone Arc (top 25%)
    final warnPaint = Paint()
      ..color = secondaryColor.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.84),
      startAngle + sweepAngle * 0.75,
      sweepAngle * 0.25,
      false,
      warnPaint,
    );

    // 4. Active Progress Arc
    final clampedSpeed = speed.clamp(0.0, maxScale);
    final activeSweep = sweepAngle * (clampedSpeed / maxScale);
    final progressPaint = Paint()
      ..color = isOverLimit ? secondaryColor : primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

    if (activeSweep > 0.01) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius * 0.84), startAngle, activeSweep, false, progressPaint);
    }

    // 5. Ticks & Numbers
    final tickStep = (maxScale / 12).round();
    int tickCount = (maxScale / tickStep).round();

    for (int i = 0; i <= tickCount; i++) {
      double angle = startAngle + (i / tickCount) * sweepAngle;
      bool isMajor = i % 2 == 0;
      double innerR = isMajor ? radius * 0.88 : radius * 0.92;
      double outerR = radius * 0.96;

      Offset p1 = center + Offset(cos(angle) * innerR, sin(angle) * innerR);
      Offset p2 = center + Offset(cos(angle) * outerR, sin(angle) * outerR);

      final tickPaint = Paint()
        ..color = isMajor ? primaryColor.withOpacity(0.8) : const Color(0xFF334155)
        ..strokeWidth = isMajor ? 3 : 1.5;
      canvas.drawLine(p1, p2, tickPaint);

      if (isMajor) {
        double textR = radius * 0.70;
        Offset textPos = center + Offset(cos(angle) * textR, sin(angle) * textR);
        final tp = TextPainter(
          text: TextSpan(
            text: '${i * tickStep}',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, textPos - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // 6. Pointer Needle
    double needleAngle = startAngle + activeSweep;
    final needlePaint = Paint()
      ..color = isOverLimit ? secondaryColor : Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    Offset needleTip = center + Offset(cos(needleAngle) * (radius * 0.88), sin(needleAngle) * (radius * 0.88));
    canvas.drawLine(center, needleTip, needlePaint);

    canvas.drawCircle(center, 9, Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = isOverLimit ? secondaryColor : primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 7. Digital Speed in Center
    final speedTextPainter = TextPainter(
      text: TextSpan(
        text: speed.toStringAsFixed(0),
        style: TextStyle(
          fontSize: 54,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
          color: isOverLimit ? secondaryColor : primaryColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    speedTextPainter.paint(
      canvas,
      center - Offset(speedTextPainter.width / 2, speedTextPainter.height / 2 + 10),
    );

    // 8. Unit Label Under Digital Speed
    final unitTextPainter = TextPainter(
      text: TextSpan(
        text: unit,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white54,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitTextPainter.paint(
      canvas,
      Offset(center.dx - unitTextPainter.width / 2, center.dy + speedTextPainter.height / 2 - 4),
    );
  }

  @override
  bool shouldRepaint(covariant SpeedometerGaugePainter oldDelegate) {
    return oldDelegate.speed != speed ||
        oldDelegate.isOverLimit != isOverLimit ||
        oldDelegate.maxScale != maxScale ||
        oldDelegate.speedLimit != speedLimit ||
        oldDelegate.unit != unit ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
