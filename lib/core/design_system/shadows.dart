import 'package:flutter/material.dart';
import 'colors.dart';

/// Mine app shadow system
/// Soft, subtle shadows for a calm premium feel
class MineShadows {
  MineShadows._();

  // ─────────────────────────────────────────────────────────────────
  // ELEVATION LEVELS
  // ─────────────────────────────────────────────────────────────────

  /// No shadow - flat
  static const List<BoxShadow> none = [];

  /// Subtle shadow - for hover states
  static const List<BoxShadow> xs = [
    BoxShadow(
      color: MineColors.shadow,
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Small shadow - for cards at rest
  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x05000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  /// Medium shadow - for elevated cards
  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x05000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Large shadow - for modals and sheets
  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Extra large shadow - for floating elements
  static const List<BoxShadow> xl = [
    BoxShadow(
      color: Color(0x10000000),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  // ─────────────────────────────────────────────────────────────────
  // SPECIAL SHADOWS
  // ─────────────────────────────────────────────────────────────────

  /// Inner shadow for pressed states
  static const List<BoxShadow> inner = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 4,
      offset: Offset(0, 2),
      spreadRadius: -2,
    ),
  ];

  /// Glow shadow for accent elements
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// Colored shadow for module cards
  static List<BoxShadow> colored(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.15),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: color.withValues(alpha: 0.08),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
}
