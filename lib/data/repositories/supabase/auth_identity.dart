/// Value-free username normalization + hidden internal-email construction.
///
/// Frozen identity rule (decision D2): `normalized = lower(trim(username))`,
/// validated against `^[a-z0-9._-]{2,50}$`. The internal Auth email
/// (`<normalized>@users.sumou.internal`) is constructed **only** here in the
/// data/auth layer — it is never stored in `UserModel`, returned in errors,
/// displayed, logged, put in analytics, or exposed to widgets/controllers.
library;

class AuthIdentity {
  AuthIdentity._();

  static final RegExp _usernameRe = RegExp(r'^[a-z0-9._-]{2,50}$');
  static const String _internalDomain = 'users.sumou.internal';

  /// Trim + lowercase. Deterministic; no I/O.
  static String normalize(String username) => username.trim().toLowerCase();

  /// True when [normalized] matches the frozen username syntax.
  static bool isValid(String normalized) => _usernameRe.hasMatch(normalized);

  /// The hidden internal Auth email for a VALID username, or `null` when the
  /// (normalized) username is malformed — so callers fail **before** any network
  /// request. Never log or display the returned value.
  static String? internalEmailFor(String rawUsername) {
    final normalized = normalize(rawUsername);
    if (!isValid(normalized)) return null;
    return '$normalized@$_internalDomain';
  }
}
