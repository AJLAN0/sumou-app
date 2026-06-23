import 'package:flutter/material.dart';

/// Sumou brand color palette.
///
/// Source of truth: `docs/MASTER_SPEC.md` (brand identity section).
/// Use these tokens everywhere — do not hardcode hex values in widgets.
class AppColors {
  AppColors._();

  // Core surfaces
  static const Color background = Color(0xFF152127); // app background (dark)
  static const Color surface = Color(0xFF1E2E35); // cards
  static const Color surfaceSecondary = Color(
    0xFF243840,
  ); // raised cards/inputs

  // Brand
  static const Color primaryTeal = Color(0xFF215C66); // brand elements
  static const Color accentGreen = Color(0xFFA7CF5B); // primary CTAs
  static const Color greenDark = Color(0xFF8AAE40); // CTA pressed/accents

  // Feedback
  static const Color error = Color(0xFFF0524B); // errors/rejections

  // Text
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0x99CBCAD4); // rgba(203,202,212,0.6)
  static const Color border = Color(0x26CBCAD4); // rgba(203,202,212,0.15)

  // Role accents
  static const Color weddingPink = Color(0xFFE8A0B0);
  static const Color financeYellow = Color(0xFFF5C842);
  static const Color designerCoral = Color(0xFFF07080);
  static const Color photographerPurple = Color(0xFFB87AF5);
  static const Color projectTeal = Color(0xFF7FD4E0); // project/admin accent
}
