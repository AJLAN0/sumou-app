import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Sumou typography scale.
///
/// Arabic-first. Primary font is Alexandria when bundled; until the font asset
/// is added we fall back to the platform Arabic-friendly default by leaving
/// [fontFamily] null. Keep text readable on mobile — no tiny text.
class AppTextStyles {
  AppTextStyles._();

  // TODO(sprint1): bundle the Alexandria font and set this to 'Alexandria'.
  static const String? fontFamily = null;

  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textWhite,
    height: 1.3,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textWhite,
    height: 1.3,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textWhite,
    height: 1.45,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.45,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
}
