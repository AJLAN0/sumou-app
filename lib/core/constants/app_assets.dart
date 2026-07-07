/// Centralized asset paths.
///
/// Reference these constants instead of hardcoding raw asset strings across the
/// app, so paths live in one place.
class AppAssets {
  AppAssets._();

  static const String _branding = 'assets/branding';

  /// Full Sumou logo with the wordmark — used on the entry/landing screen.
  static const String logoFull = '$_branding/sumou_logo_full.png';

  /// Icon-only Sumou logo — used as the small brand mark in app headers.
  static const String logoIcon = '$_branding/sumou_logo_icon.png';
}
