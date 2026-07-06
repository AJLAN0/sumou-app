import 'package:flutter/material.dart';

import '../constants/app_assets.dart';

/// The Sumou brand logo.
///
/// Renders the bundled PNG with [BoxFit.contain] (never stretched). If the
/// asset isn't present yet, it degrades to [fallback] (or nothing) instead of
/// showing a broken image — so the app keeps working before the logo files are
/// dropped in.
class SumouLogo extends StatelessWidget {
  /// Full logo with the wordmark — for the entry/landing screen.
  const SumouLogo.full({super.key, this.height, this.fallback})
    : _asset = AppAssets.logoFull;

  /// Icon-only logo — for the small brand mark in app headers.
  const SumouLogo.icon({super.key, this.height, this.fallback})
    : _asset = AppAssets.logoIcon;

  final String _asset;
  final double? height;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback ?? const SizedBox.shrink(),
    );
  }
}
