import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../../core/models/feature_permissions.dart';
import '../../../core/models/role_type.dart';
import '../../../core/models/user_model.dart';
import '../auth_repository.dart';
import 'auth_gateway.dart';
import 'auth_identity.dart';

/// Real Supabase-backed [AuthRepository] (Sprint 10 Step 10.5).
///
/// Username → hidden internal email → Supabase Auth sign-in → load the caller's
/// OWN public profile / active roles / active photographer types / effective
/// permissions → [UserModel]. All resolution logic lives here (testable via a
/// fake [AuthGateway]); raw Supabase queries live in [SupabaseAuthGateway].
///
/// Fail-closed everywhere: a query error is never treated as empty. The internal
/// email is never returned, logged, displayed, or placed in [UserModel]
/// (`email` stays null). RLS remains authoritative.
///
/// `changePassword` is intentionally deferred to Step 10.6.
class SupabaseAuthRepository implements AuthRepository {
  /// Production wiring: depends on the injected [SupabaseClient].
  SupabaseAuthRepository(SupabaseClient client)
    : _gateway = SupabaseAuthGateway(client);

  /// Test wiring: inject a fake [AuthGateway] boundary (no live network).
  SupabaseAuthRepository.withGateway(this._gateway);

  final AuthGateway _gateway;

  @override
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    // Invalid username syntax fails BEFORE any network request. Reported as
    // invalid credentials so it never reveals whether the username exists.
    final internalEmail = AuthIdentity.internalEmailFor(username);
    if (internalEmail == null) {
      throw const AuthException(AuthFailure.invalidCredentials);
    }

    final String authUserId;
    try {
      // Password is passed through untouched (not trimmed/altered).
      authUserId = await _gateway.signInWithPassword(
        email: internalEmail,
        password: password,
      );
    } catch (_) {
      // Wrong credentials / unknown user / sign-in error → generic, no leak.
      throw const AuthException(AuthFailure.invalidCredentials);
    }

    // Auth succeeded — load the full public context. If anything is wrong, sign
    // out so we never leave an authenticated user with no usable Flutter profile.
    try {
      return await _loadUserContext(authUserId);
    } on AuthException {
      await _safeSignOut();
      rethrow;
    } catch (_) {
      await _safeSignOut();
      throw const AuthException(AuthFailure.profileUnavailable);
    }
  }

  @override
  Future<UserModel?> currentUser() async {
    final userId = _gateway.currentSessionUserId();
    if (userId == null) return null; // no persisted session → signed out
    try {
      return await _loadUserContext(userId);
    } on AuthException {
      // Persisted account is disabled/deleted/invalid → clear the session and
      // let the caller resolve safely to signed-out.
      await _safeSignOut();
      rethrow;
    }
    // A non-AuthException (query/network failure) propagates so the caller can
    // surface a safe "restore failed" state WITHOUT signing out a valid session.
  }

  @override
  Future<void> logout() => _safeSignOut();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    // Deferred to Step 10.6: no auth.updateUser, no re-auth, no flag clearing.
    throw const AuthException(AuthFailure.passwordChangeUnavailable);
  }

  // ---- internals -----------------------------------------------------------

  Future<void> _safeSignOut() async {
    try {
      await _gateway.signOut();
    } catch (_) {
      // Idempotent: ignore (e.g. already signed out).
    }
  }

  /// Load + validate the caller's own profile, roles, photo types, and
  /// effective permissions. Throws a typed [AuthException] on any problem.
  Future<UserModel> _loadUserContext(String authUserId) async {
    // 1) Profile (own row). A query error throws here → fail closed.
    final profile = await _gateway.fetchProfile(authUserId);
    if (profile == null || profile['id'] != authUserId) {
      throw const AuthException(AuthFailure.profileUnavailable);
    }
    if (profile['deleted_at'] != null || profile['is_active'] != true) {
      throw const AuthException(AuthFailure.accountDisabled);
    }
    final defaultRoleId = profile['default_role_id'] as String?;

    // 2) Active roles (own). Inactive/finance/wedding_finance are is_active=false
    //    and excluded. Unknown ACTIVE code fails closed (never mapped to manager).
    //    client_tracking is not a staff login role and is skipped.
    final roleRows = await _gateway.fetchRoles(authUserId);
    final activeRoleIds = <String>[];
    final activeRoles = <RoleType>[];
    RoleType? defaultRole;
    for (final row in roleRows) {
      if (row['is_active'] != true) continue;
      final code = row['code'] as String?;
      final id = row['id'] as String?;
      if (code == null || id == null) {
        throw const AuthException(AuthFailure.profileUnavailable);
      }
      if (code == RoleType.clientTracking.key) continue; // not a staff role
      final role = RoleType.fromKey(code);
      if (role == null) {
        // Unknown active role code → fail closed.
        throw const AuthException(AuthFailure.profileUnavailable);
      }
      activeRoleIds.add(id);
      activeRoles.add(role);
      if (id == defaultRoleId) defaultRole = role;
    }
    if (activeRoles.isEmpty) {
      throw const AuthException(AuthFailure.profileUnavailable);
    }
    // The default role must resolve to one of the caller's active roles.
    if (defaultRoleId == null || defaultRole == null) {
      throw const AuthException(AuthFailure.profileUnavailable);
    }

    // 3) Active photographer types (own) → Arabic display names.
    final typeRows = await _gateway.fetchPhotoTypes(authUserId);
    final photoTypes = <String>[];
    for (final row in typeRows) {
      if (row['is_active'] != true) continue;
      final nameAr = row['name_ar'] as String?;
      if (nameAr != null) photoTypes.add(nameAr);
    }

    // 4) Effective permissions (own-role-scoped; fail closed on error).
    final permissions = await _resolvePermissions(authUserId, activeRoleIds);

    return UserModel(
      id: profile['id'] as String,
      username: profile['username'] as String,
      fullName: profile['full_name'] as String,
      email: null, // NEVER map the Auth email into UserModel
      avatarInitials: profile['avatar_initials'] as String?,
      active: true,
      mustChangePassword: profile['must_change_password'] == true,
      defaultRole: defaultRole,
      roles: activeRoles,
      photoTypes: photoTypes,
      permissions: permissions,
    );
  }

  /// Effective permissions:
  /// 1) explicit `user_permissions` override wins (including explicit false),
  /// 2) else OR of `role_permissions` defaults across the caller's OWN active
  ///    role ids, 3) only ACTIVE permission-catalog rows count, 4) otherwise
  ///    false. `can_manage_finance` (inactive) and unknown codes never grant.
  ///
  /// CRITICAL: role defaults are scoped by the caller's own active role ids (an
  /// admin can read ALL role_permissions via oversight RLS, so a code-only query
  /// would leak an unrelated role's grant).
  Future<FeaturePermissions> _resolvePermissions(
    String userId,
    List<String> activeRoleIds,
  ) async {
    final roleDefaults = <AppFeature, bool>{};
    for (final row in await _gateway.fetchRolePermissions(activeRoleIds)) {
      if (row['is_active'] != true) continue; // inactive permission ignored
      final feature = AppFeature.fromCode(row['code'] as String? ?? '');
      if (feature == null) continue; // unknown / can_manage_finance ignored
      final granted = row['granted'] == true;
      roleDefaults[feature] = (roleDefaults[feature] ?? false) || granted;
    }

    final overrides = <AppFeature, bool>{};
    for (final row in await _gateway.fetchUserPermissions(userId)) {
      if (row['is_active'] != true) continue;
      final feature = AppFeature.fromCode(row['code'] as String? ?? '');
      if (feature == null) continue;
      overrides[feature] = row['granted'] == true; // explicit, incl. false
    }

    var perms = const FeaturePermissions();
    for (final feature in AppFeature.values) {
      final value =
          overrides.containsKey(feature)
              ? overrides[feature]!
              : (roleDefaults[feature] ?? false);
      if (value) perms = perms.setFeature(feature, true);
    }
    return perms;
  }
}
