import 'package:flutter/material.dart';

/// Scoped rollout: arena and creation share tokens without retheming other rooms.
abstract final class ArenaTheme {
  static const background = Color(0xFF101114);
  static const surface = Color(0xFF191B20);
  static const border = Color(0xFF2A2D34);
  static const accent = Color(0xFFE6B85C);
  static const blue = Color(0xFF6D9EEB);
  static const red = Color(0xFFDB8290);

  static ThemeData from(ThemeData base) => base.copyWith(
          colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: background,
        secondaryContainer: const Color(0xFF3A3020),
        onSecondaryContainer: const Color(0xFFF3D69B),
        surface: surface,
        onSurface: const Color(0xFFF3F4F6),
        outline: const Color(0xFF50545D),
      ));
}
