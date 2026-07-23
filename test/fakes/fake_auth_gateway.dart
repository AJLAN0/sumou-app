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
    this.errorOn = const <String>{},
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

  /// Method names that should throw a simulated query error.
  Set<String> errorOn;

  // ---- call recorders ----
  int signInCalls = 0;
  int signOutCalls = 0;
  String? lastEmail;
  String? lastPassword;
  List<String>? lastRolePermissionIds;

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

  @override
  String? currentSessionUserId() => session;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
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
