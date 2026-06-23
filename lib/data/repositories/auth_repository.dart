import '../../core/models/user_model.dart';

/// Why an auth operation failed. UI maps these to Arabic messages later.
enum AuthFailure { invalidCredentials, accountDisabled, notAuthenticated }

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

  /// Change the signed-in user's password. Throws [AuthException] when no
  /// session exists or the current password is wrong.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}
