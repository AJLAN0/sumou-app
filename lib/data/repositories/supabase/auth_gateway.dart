import 'package:supabase_flutter/supabase_flutter.dart';

/// Narrow data boundary between [SupabaseAuthRepository] and Supabase.
///
/// Returns plain Dart maps/lists (already flattened from PostgREST embeds) so
/// the repository holds all the testable business logic and can be exercised
/// with a fake gateway — no live network. Every read throws on a query error
/// (never returns empty on failure), so the repository can fail closed.
/// A persisted session reduced to what the repository needs. No tokens.
class AuthSessionInfo {
  const AuthSessionInfo({required this.userId, required this.isExpired});

  final String userId;

  /// True when the access token is past its expiry and the SDK must refresh it
  /// before any RLS-protected query can succeed.
  final bool isExpired;
}

/// Auth lifecycle events reduced to the outcomes restoration cares about.
enum AuthSessionEventKind {
  /// A usable (refreshed / newly signed-in) session is available.
  refreshed,

  /// The session ended — refresh failed, the user signed out, or was deleted.
  signedOut,

  /// Anything else (user updated, password recovery…) — ignored by restoration.
  other,
}

class AuthSessionEvent {
  const AuthSessionEvent(this.kind, {this.userId});

  final AuthSessionEventKind kind;
  final String? userId;
}

abstract interface class AuthGateway {
  /// Sign in with the (internal) email; returns the authenticated user id.
  /// Throws on any failure (wrong credentials, unknown user, network).
  Future<String> signInWithPassword({
    required String email,
    required String password,
  });

  /// The persisted session (id + expiry), or `null` when signed out.
  AuthSessionInfo? currentSession();

  /// Auth lifecycle events, used to await a token refresh before querying.
  Stream<AuthSessionEvent> onAuthEvents();

  /// Idempotent sign-out.
  Future<void> signOut();

  /// The caller's OWN profile row (selected columns), or `null` when absent.
  Future<Map<String, dynamic>?> fetchProfile(String userId);

  /// The caller's own `user_roles` joined to `roles` → `{id, code, is_active}`.
  Future<List<Map<String, dynamic>>> fetchRoles(String userId);

  /// The caller's own photographer types → `{name_ar, is_active}`.
  Future<List<Map<String, dynamic>>> fetchPhotoTypes(String userId);

  /// Role defaults for the given role ids → `{code, is_active, granted}`.
  /// MUST be scoped by role id (never by permission code alone).
  Future<List<Map<String, dynamic>>> fetchRolePermissions(List<String> roleIds);

  /// The caller's own explicit overrides → `{code, is_active, granted}`.
  Future<List<Map<String, dynamic>>> fetchUserPermissions(String userId);
}

/// Real [AuthGateway] over the injected [SupabaseClient]. All reads go through
/// RLS (caller-scoped); embedded relations are flattened to simple maps.
class SupabaseAuthGateway implements AuthGateway {
  const SupabaseAuthGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<String> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = res.user;
    if (user == null) {
      throw const AuthException('sign-in returned no user');
    }
    return user.id;
  }

  @override
  AuthSessionInfo? currentSession() {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    return AuthSessionInfo(
      userId: session.user.id,
      isExpired: session.isExpired,
    );
  }

  @override
  Stream<AuthSessionEvent> onAuthEvents() {
    return _client.auth.onAuthStateChange.map((data) {
      final userId = data.session?.user.id;
      return switch (data.event) {
        // A session is present again → usable for RLS-protected queries.
        AuthChangeEvent.tokenRefreshed ||
        AuthChangeEvent.signedIn ||
        AuthChangeEvent.initialSession when userId != null => AuthSessionEvent(
          AuthSessionEventKind.refreshed,
          userId: userId,
        ),
        // Terminal: refresh failed / signed out / the account was deleted.
        // ignore: deprecated_member_use
        AuthChangeEvent.signedOut || AuthChangeEvent.userDeleted =>
          const AuthSessionEvent(AuthSessionEventKind.signedOut),
        _ => const AuthSessionEvent(AuthSessionEventKind.other),
      };
    });
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<Map<String, dynamic>?> fetchProfile(String userId) {
    return _client
        .from('profiles')
        .select(
          'id, username, full_name, avatar_initials, is_active, deleted_at, '
          'default_role_id, must_change_password',
        )
        .eq('id', userId)
        .maybeSingle();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoles(String userId) async {
    final rows = await _client
        .from('user_roles')
        .select('roles!inner(id, code, is_active)')
        .eq('user_id', userId);
    return _flattenAll(rows, 'roles');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPhotoTypes(String userId) async {
    final rows = await _client
        .from('user_photographer_types')
        .select('photographer_types!inner(name_ar, is_active)')
        .eq('user_id', userId);
    return _flattenAll(rows, 'photographer_types');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRolePermissions(
    List<String> roleIds,
  ) async {
    if (roleIds.isEmpty) return const [];
    final rows = await _client
        .from('role_permissions')
        .select('granted, permissions!inner(code, is_active)')
        .inFilter('role_id', roleIds);
    return _flattenPermissions(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUserPermissions(String userId) async {
    final rows = await _client
        .from('user_permissions')
        .select('granted, permissions!inner(code, is_active)')
        .eq('user_id', userId);
    return _flattenPermissions(rows);
  }

  // PostgREST may type an embedded to-one relation as an object OR a single-
  // element array; normalize to the object.
  static Map<String, dynamic>? _embed(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  static List<Map<String, dynamic>> _flattenAll(List<dynamic> rows, String k) {
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final embed = _embed((row as Map)[k]);
      if (embed != null) out.add(embed);
    }
    return out;
  }

  static List<Map<String, dynamic>> _flattenPermissions(List<dynamic> rows) {
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final r = row as Map;
      final p = _embed(r['permissions']);
      if (p == null) continue;
      out.add({
        'code': p['code'],
        'is_active': p['is_active'],
        'granted': r['granted'],
      });
    }
    return out;
  }
}
