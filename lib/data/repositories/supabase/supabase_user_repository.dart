import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../../core/models/feature_permissions.dart';
import '../../../core/models/role_type.dart';
import '../../../core/models/user_model.dart';
import '../user_repository.dart';
import 'auth_identity.dart';
import 'user_gateway.dart';

/// Real admin user repository over admin-readable RLS and the two existing
/// trusted Edge Functions. All mutation methods without a backend contract fail
/// closed; there are no direct Flutter writes to identity/access tables.
class SupabaseUserRepository implements UserRepository {
  SupabaseUserRepository(SupabaseClient client)
    : _gateway = SupabaseUserAdminGateway(client);

  SupabaseUserRepository.withGateway(this._gateway);

  final UserAdminGateway _gateway;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _photoTypeCode = RegExp(r'^[a-z][a-z_]*$');

  @override
  UserRepositoryCapabilities get capabilities =>
      const UserRepositoryCapabilities.supabaseStep10_7();

  @override
  Future<List<UserModel>> getUsers() => _loadUsers();

  @override
  Future<UserModel?> getUserById(String id) async {
    final normalized = id.trim().toLowerCase();
    if (!_uuid.hasMatch(normalized)) return null;
    final users = await _loadUsers(userId: normalized);
    return users.isEmpty ? null : users.single;
  }

  @override
  Future<UserModel?> getUserByUsername(String username) async {
    final normalized = AuthIdentity.normalize(username);
    if (!AuthIdentity.isValid(normalized)) return null;
    final users = await _loadUsers(username: normalized);
    return users.isEmpty ? null : users.single;
  }

  @override
  Future<List<StaffPhotoTypeOption>> getAvailablePhotoTypes() async {
    try {
      final rows = await _gateway.fetchActivePhotoTypes();
      final seen = <String>{};
      final result = <StaffPhotoTypeOption>[];
      for (final row in rows) {
        final code = _requiredString(row, 'code');
        final nameAr = _requiredString(row, 'name_ar').trim();
        final active = _requiredBool(row, 'is_active');
        if (!active || !_photoTypeCode.hasMatch(code) || !seen.add(code)) {
          _invalidData();
        }
        result.add(StaffPhotoTypeOption(code: code, nameAr: nameAr));
      }
      return List.unmodifiable(result);
    } on UserRepositoryException {
      rethrow;
    } catch (_) {
      throw const UserRepositoryException(UserRepositoryFailure.loadFailed);
    }
  }

  @override
  Future<UserProvisioningResult> provisionUser({
    required String fullName,
    required String username,
    required RoleType defaultRole,
    required List<RoleType> roles,
    List<String> photographerTypeCodes = const [],
    Map<AppFeature, bool> permissionOverrides = const {},
  }) async {
    final normalizedUsername = AuthIdentity.normalize(username);
    final normalizedName = fullName.trim();
    final roleCodes = roles.map((role) => role.key).toList(growable: false);
    final typeCodes = photographerTypeCodes
        .map((code) => code.trim())
        .toList(growable: false);

    if (!AuthIdentity.isValid(normalizedUsername) ||
        normalizedName.isEmpty ||
        roles.isEmpty ||
        !roles.contains(defaultRole) ||
        roles.any(_isExcludedStaffRole) ||
        roleCodes.toSet().length != roleCodes.length ||
        typeCodes.any((code) => !_photoTypeCode.hasMatch(code)) ||
        typeCodes.toSet().length != typeCodes.length ||
        permissionOverrides.keys.contains(AppFeature.canManageFinance)) {
      throw const UserRepositoryException(UserRepositoryFailure.invalidInput);
    }

    final overrides = permissionOverrides.entries
        .map(
          (entry) => <String, dynamic>{
            'code': entry.key.code,
            'granted': entry.value,
          },
        )
        .toList(growable: false);
    final body = adminCreateUserRequestBody(
      username: normalizedUsername,
      fullName: normalizedName,
      defaultRole: defaultRole.key,
      roles: roleCodes,
      photographerTypes: typeCodes,
      permissionOverrides: overrides,
    );

    final AdminUserFunctionResponse response;
    try {
      response = await _gateway.invokeCreateUser(body);
    } catch (_) {
      throw const UserRepositoryException(UserRepositoryFailure.createFailed);
    }
    if (response.status != 201) {
      throw UserRepositoryException(_createFailureForStatus(response.status));
    }

    final parsed = _parseCreateSuccess(
      response.data,
      expectedUsername: normalizedUsername,
      expectedName: normalizedName,
      expectedDefaultRole: defaultRole.key,
      expectedRoles: roleCodes,
      expectedPhotoTypes: typeCodes,
      expectedOverrides: overrides,
    );
    return UserProvisioningResult(
      userId: parsed.userId,
      temporaryPassword: OneTimePassword(parsed.temporaryPassword),
    );
  }

  @override
  Future<UserPasswordResetResult> resetPassword(String userId) async {
    final normalized = userId.trim().toLowerCase();
    if (!_uuid.hasMatch(normalized)) {
      throw const UserRepositoryException(UserRepositoryFailure.invalidInput);
    }

    final AdminUserFunctionResponse response;
    try {
      response = await _gateway.invokeResetPassword(
        adminResetPasswordRequestBody(normalized),
      );
    } catch (_) {
      throw const UserRepositoryException(UserRepositoryFailure.resetFailed);
    }
    if (response.status != 200) {
      throw UserRepositoryException(_resetFailureForStatus(response.status));
    }

    final parsed = _parseResetSuccess(response.data, normalized);
    return UserPasswordResetResult(
      userId: normalized,
      mustChangePassword: true,
      temporaryPassword: OneTimePassword(parsed),
    );
  }

  Future<List<UserModel>> _loadUsers({String? userId, String? username}) async {
    try {
      final profileRows = await _gateway.fetchProfiles(
        userId: userId,
        username: username,
      );
      if (profileRows.isEmpty) return const [];

      final profiles = <String, _Profile>{};
      for (final row in profileRows) {
        final profile = _parseProfile(row);
        if (profiles.containsKey(profile.id)) _invalidData();
        profiles[profile.id] = profile;
      }
      final userIds = profiles.keys.toList(growable: false);

      final roleRows = await _gateway.fetchRoleAssignments(userIds);
      final rolesByUser = <String, List<_AssignedRole>>{};
      final allRoleIds = <String>{};
      for (final row in roleRows) {
        final assigned = _parseAssignedRole(row, profiles);
        if (assigned == null) continue;
        final userRoles = rolesByUser.putIfAbsent(
          assigned.userId,
          () => <_AssignedRole>[],
        );
        if (userRoles.any((existing) => existing.id == assigned.id)) {
          _invalidData();
        }
        userRoles.add(assigned);
        allRoleIds.add(assigned.id);
      }

      final photoRows = await _gateway.fetchPhotoTypeAssignments(userIds);
      final photoTypesByUser = <String, List<String>>{};
      for (final row in photoRows) {
        final userId = _requiredString(row, 'user_id');
        if (!profiles.containsKey(userId)) _invalidData();
        final embedded = row['photographer_type'];
        if (embedded is! Map) _invalidData();
        final type = Map<String, dynamic>.from(embedded);
        if (!_requiredBool(type, 'is_active')) continue;
        final code = _requiredString(type, 'code');
        final nameAr = _requiredString(type, 'name_ar').trim();
        if (!_photoTypeCode.hasMatch(code)) _invalidData();
        final names = photoTypesByUser.putIfAbsent(userId, () => <String>[]);
        if (names.contains(nameAr)) _invalidData();
        names.add(nameAr);
      }

      final rolePermissionRows = await _gateway.fetchRolePermissions(
        allRoleIds.toList(growable: false),
      );
      final roleGrants = _parseRolePermissions(rolePermissionRows, allRoleIds);

      final userPermissionRows = await _gateway.fetchUserPermissions(userIds);
      final userOverrides = _parseUserPermissions(userPermissionRows, profiles);

      final users = <UserModel>[];
      for (final profile in profiles.values) {
        final assignedRoles =
            rolesByUser[profile.id] ?? const <_AssignedRole>[];
        if (assignedRoles.isEmpty) _invalidData();
        final defaultAssigned =
            assignedRoles
                .where((role) => role.id == profile.defaultRoleId)
                .toList();
        if (defaultAssigned.length != 1) _invalidData();

        var permissions = const FeaturePermissions();
        final overrides = userOverrides[profile.id] ?? const {};
        for (final feature in AppFeature.values) {
          if (feature == AppFeature.canManageFinance) continue;
          final override = overrides[feature];
          final granted =
              override ??
              assignedRoles.any(
                (role) => roleGrants[role.id]?[feature] == true,
              );
          permissions = permissions.setFeature(feature, granted);
        }

        users.add(
          UserModel(
            id: profile.id,
            fullName: profile.fullName,
            username: profile.username,
            email: null,
            avatarInitials: profile.avatarInitials,
            active: profile.isActive,
            mustChangePassword: profile.mustChangePassword,
            defaultRole: defaultAssigned.single.role,
            roles: List.unmodifiable(
              assignedRoles.map((assigned) => assigned.role),
            ),
            photoTypes: List.unmodifiable(
              photoTypesByUser[profile.id] ?? const [],
            ),
            permissions: permissions,
          ),
        );
      }
      users.sort((a, b) => a.fullName.compareTo(b.fullName));
      return List.unmodifiable(users);
    } on UserRepositoryException {
      rethrow;
    } catch (_) {
      throw const UserRepositoryException(UserRepositoryFailure.loadFailed);
    }
  }

  _Profile _parseProfile(Map<String, dynamic> row) {
    final id = _requiredString(row, 'id').toLowerCase();
    final username = _requiredString(row, 'username');
    final fullName = _requiredString(row, 'full_name').trim();
    final defaultRoleId = _requiredString(row, 'default_role_id').toLowerCase();
    final active = _requiredBool(row, 'is_active');
    final mustChange = _requiredBool(row, 'must_change_password');
    if (!_uuid.hasMatch(id) ||
        !_uuid.hasMatch(defaultRoleId) ||
        !AuthIdentity.isValid(username) ||
        row['deleted_at'] != null) {
      _invalidData();
    }
    final avatar = row['avatar_initials'];
    if (avatar != null && avatar is! String) _invalidData();
    return _Profile(
      id: id,
      username: username,
      fullName: fullName,
      avatarInitials: avatar as String?,
      isActive: active,
      mustChangePassword: mustChange,
      defaultRoleId: defaultRoleId,
    );
  }

  _AssignedRole? _parseAssignedRole(
    Map<String, dynamic> row,
    Map<String, _Profile> profiles,
  ) {
    final userId = _requiredString(row, 'user_id').toLowerCase();
    final roleId = _requiredString(row, 'role_id').toLowerCase();
    if (!profiles.containsKey(userId) || !_uuid.hasMatch(roleId)) {
      _invalidData();
    }
    final embedded = row['role'];
    if (embedded is! Map) _invalidData();
    final roleRow = Map<String, dynamic>.from(embedded);
    if (_requiredString(roleRow, 'id').toLowerCase() != roleId) _invalidData();
    final active = _requiredBool(roleRow, 'is_active');
    final code = _requiredString(roleRow, 'code');
    if (!active) return null;
    final role = RoleType.fromKey(code);
    if (role == null) _invalidData();
    if (_isExcludedStaffRole(role)) return null;
    return _AssignedRole(userId: userId, id: roleId, role: role);
  }

  Map<String, Map<AppFeature, bool>> _parseRolePermissions(
    List<Map<String, dynamic>> rows,
    Set<String> roleIds,
  ) {
    final result = <String, Map<AppFeature, bool>>{};
    for (final row in rows) {
      final roleId = _requiredString(row, 'role_id').toLowerCase();
      if (!roleIds.contains(roleId)) _invalidData();
      final permission = _parsePermission(row);
      if (permission == null) continue;
      final grants = result.putIfAbsent(roleId, () => <AppFeature, bool>{});
      if (grants.containsKey(permission.feature)) _invalidData();
      grants[permission.feature] = permission.granted;
    }
    return result;
  }

  Map<String, Map<AppFeature, bool>> _parseUserPermissions(
    List<Map<String, dynamic>> rows,
    Map<String, _Profile> profiles,
  ) {
    final result = <String, Map<AppFeature, bool>>{};
    for (final row in rows) {
      final userId = _requiredString(row, 'user_id').toLowerCase();
      if (!profiles.containsKey(userId)) _invalidData();
      final permission = _parsePermission(row);
      if (permission == null) continue;
      final overrides = result.putIfAbsent(userId, () => <AppFeature, bool>{});
      if (overrides.containsKey(permission.feature)) _invalidData();
      overrides[permission.feature] = permission.granted;
    }
    return result;
  }

  _PermissionValue? _parsePermission(Map<String, dynamic> row) {
    final granted = _requiredBool(row, 'granted');
    final embedded = row['permission'];
    if (embedded is! Map) _invalidData();
    final permission = Map<String, dynamic>.from(embedded);
    final code = _requiredString(permission, 'code');
    final active = _requiredBool(permission, 'is_active');
    if (!active) return null;
    final feature = AppFeature.fromCode(code);
    if (feature == null || feature == AppFeature.canManageFinance) return null;
    return _PermissionValue(feature, granted);
  }

  _CreateSuccess _parseCreateSuccess(
    dynamic data, {
    required String expectedUsername,
    required String expectedName,
    required String expectedDefaultRole,
    required List<String> expectedRoles,
    required List<String> expectedPhotoTypes,
    required List<Map<String, dynamic>> expectedOverrides,
  }) {
    if (data is! Map || !_hasExactKeys(data, const {'user', 'temp_password'})) {
      throw const UserRepositoryException(UserRepositoryFailure.createFailed);
    }
    final rawUser = data['user'];
    final password = data['temp_password'];
    if (rawUser is! Map || !_validTemporaryPassword(password)) {
      throw const UserRepositoryException(UserRepositoryFailure.createFailed);
    }
    const expectedKeys = {
      'id',
      'username',
      'full_name',
      'default_role',
      'roles',
      'photographer_types',
      'permission_overrides',
      'is_active',
      'must_change_password',
    };
    if (!_hasExactKeys(rawUser, expectedKeys)) {
      throw const UserRepositoryException(UserRepositoryFailure.createFailed);
    }
    final id = rawUser['id'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        rawUser['username'] != expectedUsername ||
        rawUser['full_name'] != expectedName ||
        rawUser['default_role'] != expectedDefaultRole ||
        rawUser['is_active'] != true ||
        rawUser['must_change_password'] != true ||
        !_sameStringSet(rawUser['roles'], expectedRoles) ||
        !_sameStringSet(rawUser['photographer_types'], expectedPhotoTypes) ||
        !_sameOverrides(rawUser['permission_overrides'], expectedOverrides)) {
      throw const UserRepositoryException(UserRepositoryFailure.createFailed);
    }
    return _CreateSuccess(id.toLowerCase(), password as String);
  }

  String _parseResetSuccess(dynamic data, String expectedUserId) {
    if (data is! Map || !_hasExactKeys(data, const {'user', 'temp_password'})) {
      throw const UserRepositoryException(UserRepositoryFailure.resetFailed);
    }
    final rawUser = data['user'];
    final password = data['temp_password'];
    if (rawUser is! Map ||
        !_hasExactKeys(rawUser, const {
          'id',
          'must_change_password',
          'is_active',
        }) ||
        rawUser['id'] != expectedUserId ||
        rawUser['must_change_password'] != true ||
        rawUser['is_active'] is! bool ||
        !_validTemporaryPassword(password)) {
      throw const UserRepositoryException(UserRepositoryFailure.resetFailed);
    }
    return password as String;
  }

  static UserRepositoryFailure _createFailureForStatus(int status) =>
      switch (status) {
        400 => UserRepositoryFailure.invalidInput,
        401 => UserRepositoryFailure.unauthenticated,
        403 => UserRepositoryFailure.forbidden,
        409 => UserRepositoryFailure.usernameTaken,
        _ => UserRepositoryFailure.createFailed,
      };

  static UserRepositoryFailure _resetFailureForStatus(int status) =>
      switch (status) {
        400 => UserRepositoryFailure.invalidInput,
        401 => UserRepositoryFailure.unauthenticated,
        403 => UserRepositoryFailure.forbidden,
        404 => UserRepositoryFailure.userNotFound,
        _ => UserRepositoryFailure.resetFailed,
      };

  static bool _isExcludedStaffRole(RoleType role) =>
      role == RoleType.finance ||
      role == RoleType.weddingFinance ||
      role == RoleType.clientTracking;

  static bool _hasExactKeys(Map<dynamic, dynamic> map, Set<String> keys) =>
      map.length == keys.length && map.keys.every(keys.contains);

  static bool _sameStringSet(dynamic raw, List<String> expected) {
    if (raw is! List || raw.any((value) => value is! String)) return false;
    final actual = raw.cast<String>();
    return actual.length == expected.length &&
        actual.toSet().length == actual.length &&
        actual.toSet().containsAll(expected);
  }

  static bool _sameOverrides(dynamic raw, List<Map<String, dynamic>> expected) {
    if (raw is! List || raw.length != expected.length) return false;
    final actual = <String, bool>{};
    for (final value in raw) {
      if (value is! Map ||
          !_hasExactKeys(value, const {'code', 'granted'}) ||
          value['code'] is! String ||
          value['granted'] is! bool) {
        return false;
      }
      final code = value['code'] as String;
      if (actual.containsKey(code)) return false;
      actual[code] = value['granted'] as bool;
    }
    return expected.every((value) => actual[value['code']] == value['granted']);
  }

  static bool _validTemporaryPassword(dynamic value) =>
      value is String && value.length >= 12 && value.length <= 72;

  static String _requiredString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) _invalidData();
    return value;
  }

  static bool _requiredBool(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! bool) _invalidData();
    return value;
  }

  static Never _invalidData() =>
      throw const UserRepositoryException(UserRepositoryFailure.invalidData);

  UserRepositoryException _unsupported() =>
      const UserRepositoryException(UserRepositoryFailure.unsupportedOperation);

  // No trusted Step 10.7 backend contracts exist for these mutations.
  @override
  Future<UserModel?> setUserActive(String userId, bool active) =>
      Future.error(_unsupported());

  @override
  Future<UserModel?> updateUserRoles(
    String userId, {
    required RoleType defaultRole,
    required List<RoleType> roles,
  }) => Future.error(_unsupported());

  @override
  Future<UserModel?> updateUserPermissions(
    String userId,
    FeaturePermissions permissions,
  ) => Future.error(_unsupported());

  @override
  Future<UserModel?> createUser({
    required String fullName,
    required String username,
    String? email,
    required RoleType defaultRole,
    required List<RoleType> roles,
    List<String> photoTypes = const [],
    FeaturePermissions permissions = const FeaturePermissions(),
    bool active = true,
  }) => Future.error(_unsupported());

  @override
  Future<UserModel?> updateUser(
    String userId, {
    required String fullName,
    required String username,
    String? email,
    required RoleType defaultRole,
    required List<RoleType> roles,
    List<String> photoTypes = const [],
    bool active = true,
  }) => Future.error(_unsupported());

  @override
  Future<bool> deleteUser(String userId) => Future.error(_unsupported());
}

class _Profile {
  const _Profile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarInitials,
    required this.isActive,
    required this.mustChangePassword,
    required this.defaultRoleId,
  });

  final String id;
  final String username;
  final String fullName;
  final String? avatarInitials;
  final bool isActive;
  final bool mustChangePassword;
  final String defaultRoleId;
}

class _AssignedRole {
  const _AssignedRole({
    required this.userId,
    required this.id,
    required this.role,
  });

  final String userId;
  final String id;
  final RoleType role;
}

class _PermissionValue {
  const _PermissionValue(this.feature, this.granted);

  final AppFeature feature;
  final bool granted;
}

class _CreateSuccess {
  const _CreateSuccess(this.userId, this.temporaryPassword);

  final String userId;
  final String temporaryPassword;
}
