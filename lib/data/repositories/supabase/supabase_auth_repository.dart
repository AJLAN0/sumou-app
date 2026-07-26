import 'dart:async';

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
    : _gateway = SupabaseAuthGateway(client),
      _refreshTimeout = defaultRefreshTimeout;

  /// Test wiring: inject a fake [AuthGateway] boundary (no live network).
  SupabaseAuthRepository.withGateway(
    this._gateway, {
    Duration refreshTimeout = defaultRefreshTimeout,
  }) : _refreshTimeout = refreshTimeout;

  /// How long to wait for the SDK to refresh an expired token before failing.
  static const Duration defaultRefreshTimeout = Duration(seconds: 10);

  final AuthGateway _gateway;
  final Duration _refreshTimeout;

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
      await _bestEffortSignOut();
      rethrow;
    } catch (_) {
      await _bestEffortSignOut();
      throw const AuthException(AuthFailure.profileUnavailable);
    }
  }

  @override
  Future<UserModel?> currentUser() async {
    final session = _gateway.currentSession();
    if (session == null) return null; // no persisted session → signed out

    // An EXPIRED persisted token cannot pass RLS: querying now would look like
    // "no rows" and be misread as a disabled account. Wait for the SDK to
    // refresh first; a failed refresh resolves to a clean signed-out.
    var userId = session.userId;
    if (session.isExpired) {
      final refreshedUserId = await _awaitUsableSession();
      if (refreshedUserId == null) return null; // signed out during refresh
      userId = refreshedUserId;
    }

    try {
      return await _loadUserContext(userId);
    } on AuthException {
      // Persisted account is unusable (unreadable/disabled/invalid) → clear the
      // session best-effort and let the caller resolve safely to signed-out.
      await _bestEffortSignOut();
      rethrow;
    }
    // A non-AuthException (query/network failure) propagates so the caller can
    // surface a safe "restore failed" state WITHOUT signing out a valid session.
  }

  /// Wait until the SDK produces a usable session for an expired token.
  ///
  /// Returns the user id on refresh, or `null` when the session ended
  /// (signed out / user deleted) — a clean signed-out, not an error. Throws
  /// [AuthFailure.sessionRestoreFailed] on a stream error or timeout. The
  /// subscription is ALWAYS cancelled, including on timeout/error.
  Future<String?> _awaitUsableSession() async {
    final completer = Completer<String?>();
    StreamSubscription<AuthSessionEvent>? sub;
    try {
      sub = _gateway.onAuthEvents().listen(
        (event) {
          if (completer.isCompleted) return;
          switch (event.kind) {
            case AuthSessionEventKind.refreshed:
              completer.complete(event.userId);
            case AuthSessionEventKind.signedOut:
              completer.complete(null);
            case AuthSessionEventKind.other:
              break; // not decisive — keep waiting
          }
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.completeError(
              const AuthException(AuthFailure.sessionRestoreFailed),
            );
          }
        },
      );

      // RACE RE-CHECK: the SDK may have refreshed (or ended the session) between
      // the expiry check and this subscription, in which case no event is ever
      // delivered and we would wait for the full timeout.
      final now = _gateway.currentSession();
      if (!completer.isCompleted) {
        if (now == null) {
          completer.complete(null); // session ended already
        } else if (!now.isExpired) {
          completer.complete(now.userId); // already refreshed
        }
      }

      return await completer.future.timeout(_refreshTimeout);
    } on TimeoutException {
      throw const AuthException(AuthFailure.sessionRestoreFailed);
    } finally {
      await sub?.cancel();
    }
  }

  @override
  Future<void> logout() async {
    // EXPLICIT logout: unlike best-effort cleanup, a failure is surfaced so the
    // caller does not clear authenticated state while the session still exists.
    try {
      await _gateway.signOut();
    } catch (_) {
      throw const AuthException(AuthFailure.logoutFailed);
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    // Deferred to Step 10.6: no auth.updateUser, no re-auth, no flag clearing.
    throw const AuthException(AuthFailure.passwordChangeUnavailable);
  }

  // ---- internals -----------------------------------------------------------

  /// BEST-EFFORT cleanup used when rejecting an unusable session. Swallows
  /// failures on purpose: the caller is already failing closed, and a cleanup
  /// error must not mask the real reason. Distinct from the explicit [logout].
  Future<void> _bestEffortSignOut() async {
    try {
      await _gateway.signOut();
    } catch (_) {
      // Ignored by design (e.g. already signed out / offline).
    }
  }

  /// Load + validate the caller's own profile, roles, photo types, and
  /// effective permissions. Throws a typed [AuthException] on any problem.
  Future<UserModel> _loadUserContext(String authUserId) async {
    // 1) Profile (own row). A query error throws here → fail closed.
    final profileRow = await _gateway.fetchProfile(authUserId);
    // RLS returns NO ROW for a missing, inactive, or soft-deleted account alike.
    // Collapse those into ONE generic reason so the client cannot tell them apart.
    if (profileRow == null) {
      throw const AuthException(AuthFailure.accountUnavailable);
    }
    // Parse FIRST so a malformed payload is reported as malformed
    // (profileUnavailable) rather than masquerading as an id mismatch.
    final profile = _parseProfile(profileRow);
    // A well-formed row for someone else is also "unavailable" to this caller.
    if (profile.id != authUserId) {
      throw const AuthException(AuthFailure.accountUnavailable);
    }
    if (profile.deletedAt != null || !profile.isActive) {
      throw const AuthException(AuthFailure.accountDisabled);
    }
    final defaultRoleId = profile.defaultRoleId;

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
    if (defaultRole == null) {
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
      id: profile.id,
      username: profile.username,
      fullName: profile.fullName,
      email: null, // NEVER map the Auth email into UserModel
      avatarInitials: profile.avatarInitials,
      active: true,
      mustChangePassword: profile.mustChangePassword,
      defaultRole: defaultRole,
      roles: activeRoles,
      photoTypes: photoTypes,
      permissions: permissions,
    );
  }

  /// STRICT profile parsing. Every required field must be present with the
  /// right runtime type — a malformed payload raises a typed, safe
  /// [AuthFailure.profileUnavailable] instead of an unhandled `TypeError`.
  /// In particular `must_change_password` must be a real bool: a null/string/int
  /// must never be silently coerced to `false` (that would quietly drop a forced
  /// password change).
  _ProfileFields _parseProfile(Map<String, dynamic> row) {
    // Every rejection uses the SAME typed reason — a malformed payload must
    // never surface as an unhandled TypeError nor leak which field was bad.
    Never reject() => throw const AuthException(AuthFailure.profileUnavailable);

    /// A required identifier/text column: present, a String, non-blank once
    /// trimmed (a whitespace-only value is malformed, not a valid name/id).
    String requireNonBlank(String key) {
      final value = row[key];
      if (value is! String) reject();
      final trimmed = value.trim();
      if (trimmed.isEmpty) reject();
      return trimmed;
    }

    bool requireBool(String key) {
      final value = row[key];
      if (value is! bool) reject();
      return value;
    }

    final avatar = row['avatar_initials'];
    if (avatar != null && avatar is! String) reject();

    // The username is the login identity: it must satisfy the SAME frozen rule
    // the backend enforces (`^[a-z0-9._-]{2,50}$`), so a corrupted/unnormalized
    // row can never become a usable identity in the app.
    final username = requireNonBlank('username');
    if (!AuthIdentity.isValid(username)) reject();

    // `deleted_at` is either SQL NULL or a PostgREST timestamptz string
    // (ISO-8601). Anything else (number, bool, unparseable text) is malformed —
    // it must NOT be treated as "not deleted", which would revive a
    // soft-deleted account.
    final rawDeletedAt = row['deleted_at'];
    DateTime? deletedAt;
    if (rawDeletedAt != null) {
      if (rawDeletedAt is! String) reject();
      final parsed = DateTime.tryParse(rawDeletedAt);
      if (parsed == null) reject();
      deletedAt = parsed;
    }

    return _ProfileFields(
      id: requireNonBlank('id'),
      username: username,
      fullName: requireNonBlank('full_name'),
      avatarInitials: avatar as String?,
      isActive: requireBool('is_active'),
      mustChangePassword: requireBool('must_change_password'),
      defaultRoleId: requireNonBlank('default_role_id'),
      deletedAt: deletedAt,
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

/// Validated profile columns (see `_parseProfile`). Never holds an Auth email.
class _ProfileFields {
  const _ProfileFields({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarInitials,
    required this.isActive,
    required this.mustChangePassword,
    required this.defaultRoleId,
    required this.deletedAt,
  });

  final String id;
  final String username;
  final String fullName;
  final String? avatarInitials;
  final bool isActive;
  final bool mustChangePassword;
  final String defaultRoleId;
  final DateTime? deletedAt;
}
