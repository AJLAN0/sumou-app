/// Immutable Supabase runtime configuration (Sprint 10 Step 10.4).
///
/// Values come from **compile-time** Dart defines (`--dart-define` /
/// `--dart-define-from-file`), never from committed secrets:
///
/// ```
/// flutter run --dart-define-from-file=config/dev.json
/// ```
///
/// Only the **public** client values live here — `SUPABASE_URL` and
/// `SUPABASE_ANON_KEY` (the dashboard may call the latter a *publishable* key).
/// The `service_role` key, database password, and access tokens are **never** in
/// the Flutter app. The anon key is treated as sensitive for logging: it is
/// **never** included in [toString], error text, or any log line.
library;

/// A specific reason [SupabaseConfig] is not usable, mapped to a safe,
/// value-free message by [SupabaseConfigException].
enum SupabaseConfigError {
  missingUrl,
  invalidUrl,
  notHttps,
  placeholderUrl,
  missingAnonKey,
  placeholderAnonKey,
}

/// Thrown during bootstrap when the Supabase configuration is incomplete or
/// invalid. Its [message] is deliberately value-free (no key, no raw input) so
/// it is safe to surface in logs or a crash screen.
class SupabaseConfigException implements Exception {
  const SupabaseConfigException(this.error);

  final SupabaseConfigError error;

  String get message => switch (error) {
    SupabaseConfigError.missingUrl =>
      'SUPABASE_URL is not set. Provide it via '
          '--dart-define-from-file=config/dev.json (see config/dev.example.json).',
    SupabaseConfigError.invalidUrl => 'SUPABASE_URL is not a valid URL.',
    SupabaseConfigError.notHttps => 'SUPABASE_URL must use https://.',
    SupabaseConfigError.placeholderUrl =>
      'SUPABASE_URL is still the example placeholder; set the real DEV URL.',
    SupabaseConfigError.missingAnonKey =>
      'SUPABASE_ANON_KEY is not set. Provide it via '
          '--dart-define-from-file=config/dev.json (see config/dev.example.json).',
    SupabaseConfigError.placeholderAnonKey =>
      'SUPABASE_ANON_KEY is still the example placeholder; set the real key.',
  };

  @override
  String toString() => 'SupabaseConfigException(${error.name}): $message';
}

/// Immutable, validated Supabase client configuration.
class SupabaseConfig {
  const SupabaseConfig._({required this.url, required this.anonKey});

  /// Build from already-known raw strings, trimming surrounding whitespace.
  /// Used by tests and by [SupabaseConfig.fromEnvironment].
  factory SupabaseConfig.from({
    required String rawUrl,
    required String rawAnonKey,
  }) => SupabaseConfig._(url: rawUrl.trim(), anonKey: rawAnonKey.trim());

  /// Read the compile-time Dart defines. Missing defines resolve to `''`.
  factory SupabaseConfig.fromEnvironment() => SupabaseConfig.from(
    rawUrl: const String.fromEnvironment('SUPABASE_URL'),
    rawAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  /// Public project URL (safe to display). Trimmed.
  final String url;

  /// Public anon/publishable key. Trimmed. **Never** logged or shown.
  final String anonKey;

  static const _placeholderUrls = <String>{'https://your-project.supabase.co'};
  static const _placeholderKeys = <String>{
    'your-anon-key',
    'your-publishable-key',
    'your-publishable-or-anon-key',
  };

  /// Both values are present (non-empty after trimming). Does not imply validity.
  bool get isComplete => url.isNotEmpty && anonKey.isNotEmpty;

  /// `null` when the configuration is valid; otherwise the first failure reason.
  SupabaseConfigError? validate() {
    if (url.isEmpty) return SupabaseConfigError.missingUrl;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      return SupabaseConfigError.invalidUrl;
    }
    if (uri.scheme != 'https') return SupabaseConfigError.notHttps;
    if (_placeholderUrls.contains(url) || uri.host.startsWith('your-project')) {
      return SupabaseConfigError.placeholderUrl;
    }
    if (anonKey.isEmpty) return SupabaseConfigError.missingAnonKey;
    if (_placeholderKeys.contains(anonKey) || anonKey.startsWith('your-')) {
      return SupabaseConfigError.placeholderAnonKey;
    }
    return null;
  }

  /// True when [validate] finds no problem.
  bool get isValid => validate() == null;

  /// Throws [SupabaseConfigException] when invalid; otherwise returns `this`.
  SupabaseConfig requireValid() {
    final error = validate();
    if (error != null) throw SupabaseConfigException(error);
    return this;
  }

  /// Value-free: shows the (public) URL but **never** the anon key.
  @override
  String toString() =>
      'SupabaseConfig(url: ${url.isEmpty ? '<unset>' : url}, '
      'anonKey: ${anonKey.isEmpty ? '<unset>' : '<redacted>'})';
}
