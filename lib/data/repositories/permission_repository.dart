import '../../core/models/permission_model.dart';

/// Access to per-user permission records. Mock-backed in Sprint 1; the admin
/// permissions UI (Sprint 1 basic) reads through this interface.
abstract interface class PermissionRepository {
  Future<List<PermissionModel>> getAllPermissions();
  Future<PermissionModel?> getPermissions(String userId);
  Future<void> updatePermissions(PermissionModel permission);
}
