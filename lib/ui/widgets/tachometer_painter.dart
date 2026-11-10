import 'dart:math';
import 'package:flutter/material.dart';

class TachometerGaugePainter extends CustomPainter {
  final double rpm;
  final double maxRpm;
  final double redlineRpm;
  final Color primaryColor;
  final Color secondaryColor;

  TachometerGaugePainter({
    required this.rpm,
    this.maxRpm = 9000.0,
    this.redlineRpm = 6500.0,
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

    // 3. Redline Zone (6,500 to 9,000 RPM)
    final redlineFraction = (maxRpm - redlineRpm) / maxRpm;
    final redlineStartAngle = startAngle + sweepAngle * (1.0 - redlineFraction);
    final redlineSweep = sweepAngle * redlineFraction;

    final redlinePaint = Paint()
      ..color = const Color(0xFFFF2A6D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius * 0.84), redlineStartAngle, redlineSweep, false, redlinePaint);

    // 4. Active RPM Progress Arc
    final clampedRpm = rpm.clamp(0.0, maxRpm);
    final activeSweep = sweepAngle * (clampedRpm / maxRpm);
    final isRedline = clampedRpm >= redlineRpm;

    final progressPaint = Paint()
      ..color = isRedline ? const Color(0xFFFF2A6D) : primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

    if (activeSweep > 0.01) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius * 0.84), startAngle, activeSweep, false, progressPaint);
    }

    // 5. RPM Ticks & Numbers (0 to 9)
    for (int i = 0; i <= 9; i++) {
      double fraction = i / 9.0;
      double angle = startAngle + fraction * sweepAngle;
      double innerR = radius * 0.88;
      double outerR = radius * 0.96;

      Offset p1 = center + Offset(cos(angle) * innerR, sin(angle) * innerR);
      Offset p2 = center + Offset(cos(angle) * outerR, sin(angle) * outerR);

      final tickPaint = Paint()
        ..color = (i * 1000 >= redlineRpm) ? const Color(0xFFFF2A6D) : primaryColor.withOpacity(0.8)
        ..strokeWidth = 3;
      canvas.drawLine(p1, p2, tickPaint);

      // Minor ticks between numbers
      if (i < 9) {
        for (int m = 1; m < 4; m++) {
          double subFraction = (i + m * 0.25) / 9.0;
          double subAngle = startAngle + subFraction * sweepAngle;
          Offset sp1 = center + Offset(cos(subAngle) * (radius * 0.92), sin(subAngle) * (radius * 0.92));
          Offset sp2 = center + Offset(cos(subAngle) * outerR, sin(subAngle) * outerR);
          canvas.drawLine(sp1, sp2, Paint()..color = const Color(0xFF334155)..strokeWidth = 1.5);
        }
      }

      double textR = radius * 0.70;
      Offset textPos = center + Offset(cos(angle) * textR, sin(angle) * textR);
      final tp = TextPainter(
        text: TextSpan(
          text: '$i',
          style: TextStyle(
            color: (i * 1000 >= redlineRpm) ? const Color(0xFFFF2A6D) : Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, textPos - Offset(tp.width / 2, tp.height / 2));
    }

    // 6. Pointer Needle
    double needleAngle = startAngle + activeSweep;
    final needlePaint = Paint()
      ..color = isRedline ? const Color(0xFFFF2A6D) : Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    Offset needleTip = center + Offset(cos(needleAngle) * (radius * 0.88), sin(needleAngle) * (radius * 0.88));
    canvas.drawLine(center, needleTip, needlePaint);

    canvas.drawCircle(center, 9, Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = isRedline ? const Color(0xFFFF2A6D) : primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 7. Digital RPM Text in Center
    final rpmTextPainter = TextPainter(
      text: TextSpan(
        text: rpm.toInt().toString(),
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
          color: isRedline ? const Color(0xFFFF2A6D) : primaryColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rpmTextPainter.paint(
      canvas,
      center - Offset(rpmTextPainter.width / 2, rpmTextPainter.height / 2 + 10),
    );

    // 8. RPM x1000 Label
    final unitTp = TextPainter(
      text: const TextSpan(
        text: 'RPM',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitTp.paint(canvas, Offset(center.dx - unitTp.width / 2, center.dy + rpmTextPainter.height / 2 - 4));
  }

  @override
  bool shouldRepaint(covariant TachometerGaugePainter oldDelegate) {
    return oldDelegate.rpm != rpm ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
