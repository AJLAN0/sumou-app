import '../../../core/models/feature_permissions.dart';
import '../../../core/models/role_type.dart';
import '../../../core/models/user_model.dart';
import '../user_repository.dart';
import 'mock_users.dart';

/// In-memory [UserRepository] backed by [MockUsers].
class MockUserRepository implements UserRepository {
  // Copy the seed so per-instance toggles don't mutate the shared const list.
  MockUserRepository({List<UserModel>? users})
    : _users = List.of(users ?? MockUsers.users);

  final List<UserModel> _users;

  // Monotonic counter so generated ids are unique within a session.
  int _seq = 0;

  String _newId() => 'u-new-${DateTime.now().millisecondsSinceEpoch}-${_seq++}';

  bool _usernameTaken(String username, {String? exceptId}) {
    final target = username.trim().toLowerCase();
    return _users.any(
      (u) => u.id != exceptId && u.username.trim().toLowerCase() == target,
    );
  }

  @override
  Future<List<UserModel>> getUsers() async => List.unmodifiable(_users);

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
  }) async {
    if (!roles.contains(defaultRole)) return null;
    if (_usernameTaken(username)) return null;
    final user = UserModel(
      id: _newId(),
      fullName: fullName,
      username: username,
      email: email,
      defaultRole: defaultRole,
      roles: List.of(roles),
      photoTypes: List.of(photoTypes),
      permissions: permissions,
      active: active,
    );
    _users.add(user);
    return user;
  }

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
  }) async {
    final i = _users.indexWhere((u) => u.id == userId);
    if (i < 0) return null;
    if (!roles.contains(defaultRole)) return null;
    if (_usernameTaken(username, exceptId: userId)) return null;
    // Build a fresh model so cleared fields (e.g. email) actually clear, while
    // preserving permissions (managed separately).
    final updated = UserModel(
      id: userId,
      fullName: fullName,
      username: username,
      email: email,
      defaultRole: defaultRole,
      roles: List.of(roles),
      photoTypes: List.of(photoTypes),
      permissions: _users[i].permissions,
      active: active,
    );
    _users[i] = updated;
    return updated;
  }

  @override
  Future<bool> deleteUser(String userId) async {
    final before = _users.length;
    _users.removeWhere((u) => u.id == userId);
    return _users.length != before;
  }

  @override
  Future<UserModel?> setUserActive(String userId, bool active) async {
    final i = _users.indexWhere((u) => u.id == userId);
    if (i < 0) return null;
    final updated = _users[i].copyWith(active: active);
    _users[i] = updated;
    return updated;
  }

  @override
  Future<UserModel?> updateUserRoles(
    String userId, {
    required RoleType defaultRole,
    required List<RoleType> roles,
  }) async {
    final i = _users.indexWhere((u) => u.id == userId);
    if (i < 0) return null;
    if (!roles.contains(defaultRole)) return null;
    final updated = _users[i].copyWith(
      defaultRole: defaultRole,
      roles: List.of(roles),
    );
    _users[i] = updated;
    return updated;
  }

  @override
  Future<UserModel?> getUserById(String id) async {
    for (final user in _users) {
      if (user.id == id) return user;
    }
    return null;
  }

  @override
  Future<UserModel?> getUserByUsername(String username) async {
    for (final user in _users) {
      if (user.username == username) return user;
    }
    return null;
  }

  @override
  Future<UserModel?> updateUserPermissions(
    String userId,
    FeaturePermissions permissions,
  ) async {
    final i = _users.indexWhere((u) => u.id == userId);
    if (i < 0) return null;
    final updated = _users[i].copyWith(permissions: permissions);
    _users[i] = updated;
    return updated;
  }
}
