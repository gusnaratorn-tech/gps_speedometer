import 'package:flutter/material.dart';

class AppThemeOption {
  final String name;
  final Color primary;
  final Color secondary;
  final Color background;
  final Color cardBackground;

  const AppThemeOption({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.cardBackground,
  });
}

const List<AppThemeOption> kAvailableThemes = [
  AppThemeOption(
    name: 'Cyberpunk Neon',
    primary: Color(0xFF00F0FF),
    secondary: Color(0xFFFF3B30),
    background: Color(0xFF070B14),
    cardBackground: Color(0xFF0D1527),
  ),
  AppThemeOption(
    name: 'Racing Red',
    primary: Color(0xFFFF2A6D),
    secondary: Color(0xFFFFD600),
    background: Color(0xFF0B0609),
    cardBackground: Color(0xFF1B0B14),
  ),
  AppThemeOption(
    name: 'Electric Lime',
    primary: Color(0xFF00FF66),
    secondary: Color(0xFFFF3B30),
    background: Color(0xFF050E08),
    cardBackground: Color(0xFF091C10),
  ),
  AppThemeOption(
    name: 'Sunset Gold',
    primary: Color(0xFFFFB800),
    secondary: Color(0xFFFF3B30),
    background: Color(0xFF0E0B05),
    cardBackground: Color(0xFF1F170A),
  ),
];
