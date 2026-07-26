import '../../core/models/user_model.dart';

/// Why an auth operation failed. UI maps these to Arabic messages.
enum AuthFailure {
  /// Wrong username/password (never reveals whether the username exists).
  invalidCredentials,

  /// The account is inactive / soft-deleted and cannot be used.
  accountDisabled,

  /// No active session for an operation that requires one.
  notAuthenticated,

  /// Authenticated, but the caller's public profile/roles/permissions could not
  /// be loaded or are invalid (the session is signed out to fail closed).
  profileUnavailable,

  /// The caller's own profile row is not readable. RLS returns no row for a
  /// missing, inactive, or soft-deleted account alike, so this is ONE generic
  /// reason — it deliberately does not distinguish those cases to the client.
  accountUnavailable,

  /// An EXPLICIT sign-out failed. The user is still considered signed in;
  /// authenticated state must not be cleared on this reason.
  logoutFailed,

  /// Restoring a persisted session failed unexpectedly (fail closed).
  sessionRestoreFailed,

  /// The backend explicitly confirmed the supplied current password is wrong.
  currentPasswordIncorrect,

  /// The new password does not satisfy the server's password policy.
  weakPassword,

  /// The password-change input is invalid (including new == current).
  invalidPasswordInput,

  /// The password change failed unexpectedly or may be partially complete.
  passwordChangeFailed,
}

/// Thrown by [AuthRepository] implementations on a failed operation.
class AuthException implements Exception {
  const AuthException(this.reason, [this.message]);

  final AuthFailure reason;
  final String? message;

  @override
  String toString() => 'AuthException(${reason.name})';
}

/// Authentication boundary for the app.
///
/// UI/state never authenticate directly — they go through this interface so a
/// Supabase-backed implementation can replace the mock without changes above.
abstract interface class AuthRepository {
  /// Authenticate a user. Throws [AuthException] on failure
  /// ([AuthFailure.invalidCredentials] or [AuthFailure.accountDisabled]).
  Future<UserModel> login({required String username, required String password});

  /// Clear the current session.
  Future<void> logout();

  /// The currently authenticated user, or null if signed out.
  Future<UserModel?> currentUser();

  /// Change the signed-in user's password through the trusted backend. Throws
  /// [AuthException] with a safe typed reason; passwords are never returned.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}
