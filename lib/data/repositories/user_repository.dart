import '../../core/models/role_type.dart';
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

  /// Replace a user's [defaultRole] and full [roles] list. Returns the updated
  /// user, or null when the id is unknown or the default role isn't in [roles].
  /// Mock-backed in this sprint.
  Future<UserModel?> updateUserRoles(
    String userId, {
    required RoleType defaultRole,
    required List<RoleType> roles,
  });
}
