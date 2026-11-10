import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/themes.dart';

class DashcamOverlayWidget extends StatefulWidget {
  final double speed;
  final String unit;
  final double heading;
  final double gForce;
  final double speedLimit;
  final AppThemeOption theme;

  const DashcamOverlayWidget({
    super.key,
    required this.speed,
    required this.unit,
    required this.heading,
    required this.gForce,
    required this.speedLimit,
    required this.theme,
  });

  @override
  State<DashcamOverlayWidget> createState() => _DashcamOverlayWidgetState();
}

class _DashcamOverlayWidgetState extends State<DashcamOverlayWidget> {
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (_isRecording) {
        _recordSeconds = 0;
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          setState(() => _recordSeconds++);
        });
      } else {
        _recordTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    super.dispose();
  }

  String _formatRecTime(int sec) {
    int m = sec ~/ 60;
    int s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.9),
            const Color(0xFF0F172A),
            Colors.black.withOpacity(0.9),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          // Simulated Road Horizon & Lane Guidelines
          Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: CustomPaint(
                painter: _RoadGuidelinesPainter(color: widget.theme.primary.withOpacity(0.25)),
              ),
            ),
          ),

          // Top Status Bar (Recording Indicator & Timestamp)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? Colors.redAccent : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isRecording ? 'REC ${_formatRecTime(_recordSeconds)}' : 'STANDBY',
                      style: TextStyle(
                        color: _isRecording ? Colors.redAccent : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                Text(
                  timeStr,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),

          // Center Cockpit Telemetry Crosshairs
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.speed.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    color: widget.speed > widget.speedLimit ? widget.theme.secondary : widget.theme.primary,
                    shadows: [
                      Shadow(color: widget.theme.primary.withOpacity(0.7), blurRadius: 20),
                    ],
                  ),
                ),
                Text(
                  widget.unit.toUpperCase(),
                  style: TextStyle(
                    color: widget.theme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

          // Bottom Telemetry Strip & Record Button
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HEADING: ${widget.heading.toStringAsFixed(0)}°',
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text('G-FORCE: ${widget.gForce >= 0 ? '+' : ''}${widget.gForce.toStringAsFixed(2)}G',
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.redAccent : widget.theme.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: _toggleRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.videocam),
                  label: Text(_isRecording ? 'STOP REC' : 'START REC', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadGuidelinesPainter extends CustomPainter {
  final Color color;
  _RoadGuidelinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height * 0.4);

    // Left road line
    canvas.drawLine(center, Offset(size.width * 0.1, size.height), paint);
    // Right road line
    canvas.drawLine(center, Offset(size.width * 0.9, size.height), paint);

    // Center dash line
    final dashPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 2;
    canvas.drawLine(center, Offset(size.width / 2, size.height), dashPaint);

    // Crosshairs
    canvas.drawLine(center - const Offset(20, 0), center + const Offset(20, 0), paint);
    canvas.drawLine(center - const Offset(0, 20), center + const Offset(0, 20), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
