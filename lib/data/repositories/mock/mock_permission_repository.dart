import '../../../core/models/permission_model.dart';
import '../../../core/models/user_model.dart';
import '../permission_repository.dart';
import 'mock_users.dart';

/// In-memory [PermissionRepository] derived from the mock users.
///
/// Each user's permission record is built from their model fields and kept in
/// a mutable map so the (basic) admin permissions UI can update it later.
class MockPermissionRepository implements PermissionRepository {
  MockPermissionRepository({List<UserModel>? users}) {
    for (final user in users ?? MockUsers.users) {
      _permissions[user.id] = PermissionModel(
        userId: user.id,
        active: user.active,
        roles: user.roles,
        photoTypes: user.photoTypes,
        features: user.permissions,
      );
    }
  }

  final Map<String, PermissionModel> _permissions = {};

  @override
  Future<List<PermissionModel>> getAllPermissions() async =>
      List.unmodifiable(_permissions.values);

  @override
  Future<PermissionModel?> getPermissions(String userId) async =>
      _permissions[userId];

  @override
  Future<void> updatePermissions(PermissionModel permission) async {
    _permissions[permission.userId] = permission;
  }
}
