import 'package:flutter/material.dart';

class DragTreeLights extends StatelessWidget {
  final int stage; // 0: None, 1: Pre-Stage, 2: Amber, 3: Green GO

  const DragTreeLights({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    bool isPreStage = stage >= 1;
    bool isAmber = stage >= 2;
    bool isGreen = stage >= 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF050811),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTreeLightDot('PRE', const Color(0xFFFF9900), isPreStage),
          const SizedBox(width: 14),
          _buildTreeLightDot('STAGED', const Color(0xFFFFCC00), isAmber),
          const SizedBox(width: 14),
          _buildTreeLightDot('GO', const Color(0xFF00FF66), isGreen),
        ],
      ),
    );
  }

  Widget _buildTreeLightDot(String label, Color activeColor, bool isActive) {
    return Column(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? activeColor : activeColor.withOpacity(0.15),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
