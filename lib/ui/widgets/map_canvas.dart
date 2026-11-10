import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/themes.dart';
import '../../models/speed_camera.dart';

class InteractiveMapCanvas extends StatelessWidget {
  final Position? currentPosition;
  final double heading;
  final List<Position> breadcrumbs;
  final List<SpeedCameraZone> speedCameras;
  final AppThemeOption theme;
  final bool isMiniMap;

  const InteractiveMapCanvas({
    super.key,
    required this.currentPosition,
    required this.heading,
    required this.breadcrumbs,
    required this.speedCameras,
    required this.theme,
    this.isMiniMap = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF060912),
        borderRadius: BorderRadius.circular(isMiniMap ? 12 : 0),
        border: isMiniMap ? Border.all(color: theme.primary.withOpacity(0.3)) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isMiniMap ? 12 : 0),
        child: Stack(
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: _MapTrackPainter(
                currentPosition: currentPosition,
                heading: heading,
                breadcrumbs: breadcrumbs,
                speedCameras: speedCameras,
                primaryColor: theme.primary,
                secondaryColor: theme.secondary,
              ),
            ),
            // Compass Rose in top right
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.rotate(
                      angle: (heading * pi / 180),
                      child: const Icon(Icons.navigation, color: Colors.redAccent, size: 14),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${heading.toStringAsFixed(0)}°',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            // Map Scale Info in bottom left
            Positioned(
              bottom: 8,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers_outlined, color: Colors.white38, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'GPS Trail: ${breadcrumbs.length} pts',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
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

class _MapTrackPainter extends CustomPainter {
  final Position? currentPosition;
  final double heading;
  final List<Position> breadcrumbs;
  final List<SpeedCameraZone> speedCameras;
  final Color primaryColor;
  final Color secondaryColor;

  _MapTrackPainter({
    required this.currentPosition,
    required this.heading,
    required this.breadcrumbs,
    required this.speedCameras,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. Draw Grid Lines (Radar / Map Tiles)
    final gridPaint = Paint()
      ..color = const Color(0xFF131C2E)
      ..strokeWidth = 1;

    const double step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Concentric Range Rings
    final ringPaint = Paint()
      ..color = primaryColor.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, 60, ringPaint);
    canvas.drawCircle(center, 120, ringPaint);
    canvas.drawCircle(center, 180, ringPaint);

    if (currentPosition == null) {
      final waitingTp = TextPainter(
        text: TextSpan(
          text: 'ACQUIRING GPS SATELLITES...',
          style: TextStyle(color: primaryColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      waitingTp.paint(canvas, center - Offset(waitingTp.width / 2, waitingTp.height / 2));
      return;
    }

    // Scale: 1 meter ~ 0.5 pixels
    const double metersToPixels = 0.5;

    // 2. Draw GPS Breadcrumb Route Track
    if (breadcrumbs.length > 1) {
      final trackPath = Path();
      for (int i = 0; i < breadcrumbs.length; i++) {
        final p = breadcrumbs[i];
        double dx = (p.longitude - currentPosition!.longitude) * 111320 * cos(currentPosition!.latitude * pi / 180) * metersToPixels;
        double dy = -(p.latitude - currentPosition!.latitude) * 110540 * metersToPixels;

        Offset pt = center + Offset(dx, dy);
        if (i == 0) {
          trackPath.moveTo(pt.dx, pt.dy);
        } else {
          trackPath.lineTo(pt.dx, pt.dy);
        }
      }

      final trackGlowPaint = Paint()
        ..color = primaryColor.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);
      canvas.drawPath(trackPath, trackGlowPaint);

      final trackLinePaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(trackPath, trackLinePaint);
    }

    // 3. Draw Speed Camera POIs on Map
    for (var cam in speedCameras) {
      double dx = (cam.longitude - currentPosition!.longitude) * 111320 * cos(currentPosition!.latitude * pi / 180) * metersToPixels;
      double dy = -(cam.latitude - currentPosition!.latitude) * 110540 * metersToPixels;
      Offset camOffset = center + Offset(dx, dy);

      // Only draw if on screen
      if (camOffset.dx >= -20 && camOffset.dx <= size.width + 20 && camOffset.dy >= -20 && camOffset.dy <= size.height + 20) {
        final camPaint = Paint()..color = const Color(0xFFFF9900);
        canvas.drawCircle(camOffset, 7, camPaint);
        canvas.drawCircle(camOffset, 12, Paint()..color = const Color(0xFFFF9900).withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2);

        final labelTp = TextPainter(
          text: TextSpan(
            text: '📷 ${cam.speedLimit.toInt()}',
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelTp.paint(canvas, camOffset + const Offset(-12, 9));
      }
    }

    // 4. Draw Current Vehicle Arrow at Center
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((heading * pi / 180));

    final arrowPath = Path()
      ..moveTo(0, -18)
      ..lineTo(12, 14)
      ..lineTo(0, 8)
      ..lineTo(-12, 14)
      ..close();

    final arrowPaint = Paint()..color = secondaryColor;
    canvas.drawPath(arrowPath, arrowPaint);

    final arrowBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(arrowPath, arrowBorder);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapTrackPainter oldDelegate) {
    return true;
  }
}
