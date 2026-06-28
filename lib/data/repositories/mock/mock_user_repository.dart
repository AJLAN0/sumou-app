import '../../../core/models/user_model.dart';
import '../user_repository.dart';
import 'mock_users.dart';

/// In-memory [UserRepository] backed by [MockUsers].
class MockUserRepository implements UserRepository {
  // Copy the seed so per-instance toggles don't mutate the shared const list.
  MockUserRepository({List<UserModel>? users})
    : _users = List.of(users ?? MockUsers.users);

  final List<UserModel> _users;

  @override
  Future<List<UserModel>> getUsers() async => List.unmodifiable(_users);

  @override
  Future<UserModel?> setUserActive(String userId, bool active) async {
    final i = _users.indexWhere((u) => u.id == userId);
    if (i < 0) return null;
    final updated = _users[i].copyWith(active: active);
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
}
