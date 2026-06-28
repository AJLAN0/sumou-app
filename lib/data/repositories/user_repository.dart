import '../../core/models/user_model.dart';

/// Read access to app users (staff). Backed by mock data in Sprint 1; a
/// Supabase implementation replaces it later without touching callers.
abstract interface class UserRepository {
  Future<List<UserModel>> getUsers();
  Future<UserModel?> getUserById(String id);
  Future<UserModel?> getUserByUsername(String username);

  /// Activate or deactivate a user. Returns the updated user, or null when the
  /// id is unknown. Mock-backed in this sprint.
  Future<UserModel?> setUserActive(String userId, bool active);
}
