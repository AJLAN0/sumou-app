import 'dart:async';

import 'package:sumou_app/data/repositories/supabase/auth_gateway.dart';

/// In-memory [AuthGateway] for unit tests — no live network. Configurable rows,
/// records calls, and can throw a "query error" on a named method to exercise
/// fail-closed behavior.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({
    this.userId = 'u1',
    this.signInError = false,
    this.profile,
    this.roles = const [],
    this.photoTypes = const [],
    this.rolePermissions = const [],
    this.userPermissions = const [],
    this.session,
    this.sessionExpired = false,
    this.errorOn = const <String>{},
    this.signOutError = false,
    this.passwordChangeResponse = const PasswordChangeFunctionResponse(
      status: 200,
      data: {
        'user': {'id': 'u1', 'must_change_password': false, 'is_active': true},
      },
    ),
    this.passwordChangeError = false,
  });

  /// User id returned by a successful sign-in.
  String userId;

  /// When true, [signInWithPassword] throws (wrong credentials).
  bool signInError;

  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> roles;
  List<Map<String, dynamic>> photoTypes;
  List<Map<String, dynamic>> rolePermissions;
  List<Map<String, dynamic>> userPermissions;

  /// Persisted-session user id (null → signed out).
  String? session;

  /// Whether the persisted access token is expired (needs a refresh first).
  bool sessionExpired;

  /// Method names that should throw a simulated query error.
  Set<String> errorOn;

  /// When true, [signOut] throws (explicit logout must surface this).
  bool signOutError;

  PasswordChangeFunctionResponse passwordChangeResponse;

  /// When true, the function invocation throws a simulated SDK/network error.
  bool passwordChangeError;

  /// Drives [onAuthEvents]; tests emit refresh/sign-out events or an error.
  final StreamController<AuthSessionEvent> authEvents =
      StreamController<AuthSessionEvent>.broadcast();

  // ---- call recorders ----
  int signInCalls = 0;
  int signOutCalls = 0;
  int authEventSubscriptions = 0;
  int authEventCancellations = 0;
  int fetchProfileCalls = 0;
  int passwordChangeCalls = 0;
  String? lastEmail;
  String? lastPassword;
  String? lastCurrentPassword;
  String? lastNewPassword;
  List<String>? lastRolePermissionIds;

  /// True when every auth-event subscription has been cleaned up.
  bool get allSubscriptionsCancelled =>
      authEventSubscriptions == authEventCancellations;

  Future<void> dispose() => authEvents.close();

  void _maybeThrow(String method) {
    if (errorOn.contains(method)) {
      throw StateError('simulated query failure: $method');
    }
  }

  @override
  Future<String> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    lastEmail = email;
    lastPassword = password;
    if (signInError) throw StateError('invalid credentials');
    return userId;
  }

  /// Scripted responses for successive [currentSession] calls (last repeats).
  /// Models the session changing BETWEEN the initial expiry check and the
  /// race re-check — the only way to exercise that window deterministically.
  List<AuthSessionInfo?>? sessionScript;
  int currentSessionCalls = 0;

  @override
  AuthSessionInfo? currentSession() {
    final index = currentSessionCalls++;
    final script = sessionScript;
    if (script != null && script.isNotEmpty) {
      return script[index < script.length ? index : script.length - 1];
    }
    final id = session;
    if (id == null) return null;
    return AuthSessionInfo(userId: id, isExpired: sessionExpired);
  }

  @override
  Stream<AuthSessionEvent> onAuthEvents() {
    // Proxy that counts subscribe/cancel, so tests can assert the repository
    // ALWAYS cleans up its subscription (including on timeout and stream error).
    late final StreamController<AuthSessionEvent> proxy;
    StreamSubscription<AuthSessionEvent>? inner;
    proxy = StreamController<AuthSessionEvent>(
      onListen: () {
        authEventSubscriptions++;
        inner = authEvents.stream.listen(
          proxy.add,
          onError: proxy.addError,
          onDone: proxy.close,
        );
      },
      onCancel: () async {
        authEventCancellations++;
        await inner?.cancel();
      },
    );
    return proxy.stream;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (signOutError) throw StateError('simulated sign-out failure');
  }

  @override
  Future<PasswordChangeFunctionResponse> invokeChangeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    passwordChangeCalls++;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
    if (passwordChangeError) {
      throw StateError('simulated password-change network failure');
    }
    return passwordChangeResponse;
  }

  @override
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    fetchProfileCalls++;
    _maybeThrow('fetchProfile');
    return profile;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoles(String userId) async {
    _maybeThrow('fetchRoles');
    return roles;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPhotoTypes(String userId) async {
    _maybeThrow('fetchPhotoTypes');
    return photoTypes;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRolePermissions(
    List<String> roleIds,
  ) async {
    lastRolePermissionIds = roleIds;
    _maybeThrow('fetchRolePermissions');
    return rolePermissions;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUserPermissions(String userId) async {
    _maybeThrow('fetchUserPermissions');
    return userPermissions;
  }
}

// ---- row builders -----------------------------------------------------------

Map<String, dynamic> profileRow({
  String id = 'u1',
  String username = 'manager',
  String fullName = 'مدير النظام',
  String? avatarInitials,
  bool isActive = true,
  Object? deletedAt,
  String? defaultRoleId = 'r-manager',
  bool mustChangePassword = false,
}) => {
  'id': id,
  'username': username,
  'full_name': fullName,
  'avatar_initials': avatarInitials,
  'is_active': isActive,
  'deleted_at': deletedAt,
  'default_role_id': defaultRoleId,
  'must_change_password': mustChangePassword,
};

Map<String, dynamic> roleRow(String id, String code, {bool isActive = true}) =>
    {'id': id, 'code': code, 'is_active': isActive};

Map<String, dynamic> photoTypeRow(String nameAr, {bool isActive = true}) => {
  'name_ar': nameAr,
  'is_active': isActive,
};

Map<String, dynamic> permRow(
  String code,
  bool granted, {
  bool isActive = true,
}) => {'code': code, 'is_active': isActive, 'granted': granted};
