import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ─── Primary Palette ──────────────────────────────
  static const Color background   = Color(0xFF0A0A0B); // Deep Midnight
  static const Color primary      = Color(0xFF00D1FF); // Electric Blue
  static const Color accent       = Color(0xFF39FF14); // Neon Green
  static const Color surface      = Color(0xFF141416); // Card surface

  // ─── Glass Effect ─────────────────────────────────
  static const Color glassWhite   = Color(0x14FFFFFF); // 8% white
  static const Color glassBorder  = Color(0x33FFFFFF); // 20% white
  static const Color glassDark    = Color(0x1A000000); // 10% black

  // ─── Status Colors ────────────────────────────────
  static const Color success      = Color(0xFF39FF14); // Neon Green
  static const Color warning      = Color(0xFFFFB300); // Amber
  static const Color error        = Color(0xFFFF3B5C); // Red
  static const Color info         = Color(0xFF00D1FF); // Electric Blue

  // ─── Text Colors ──────────────────────────────────
  static const Color textPrimary  = Color(0xFFFFFFFF); // White
  static const Color textSecondary= Color(0xFFAAAAAA); // Grey
  static const Color textHint     = Color(0xFF555558); // Dark grey

  // ─── Order Status Colors ──────────────────────────
  static const Color pending      = Color(0xFFFFB300); // Amber
  static const Color accepted     = Color(0xFF00D1FF); // Blue
  static const Color preparing    = Color(0xFFFF8C00); // Orange
  static const Color readyPickup  = Color(0xFF7B61FF); // Purple
  static const Color pickedUp     = Color(0xFF39FF14); // Green
  static const Color delivered    = Color(0xFF39FF14); // Green
  static const Color cancelled    = Color(0xFFFF3B5C); // Red
  static const Color disputed     = Color(0xFFFF3B5C); // Red

  // ─── Role Colors ──────────────────────────────────
  static const Color merchantColor = Color(0xFF00D1FF); // Blue
  static const Color driverColor   = Color(0xFF39FF14); // Green
  static const Color customerColor = Color(0xFF7B61FF); // Purple
  static const Color adminColor    = Color(0xFFFFB300); // Amber

  // ─── Gradients ────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFF0099BB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, Color(0xFF00BB0A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0A0A0B), Color(0xFF141416)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0x1AFFFFFF), Color(0x0DFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}