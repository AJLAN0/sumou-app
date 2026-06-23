import '../../../core/models/user_model.dart';
import '../auth_repository.dart';
import 'mock_users.dart';

/// In-memory [AuthRepository] for development.
///
/// Keeps a single session in memory. Rejects unknown/wrong credentials and
/// disabled accounts. Holds no real secrets — see [MockUsers].
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({List<MockAccount>? accounts})
    : _accounts = accounts ?? MockUsers.accounts {
    for (final account in _accounts) {
      _passwords[account.user.username] = account.password;
    }
  }

  final List<MockAccount> _accounts;
  final Map<String, String> _passwords = {};
  UserModel? _session;

  MockAccount? _findByUsername(String username) {
    for (final account in _accounts) {
      if (account.user.username == username) return account;
    }
    return null;
  }

  @override
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    final account = _findByUsername(username.trim());
    if (account == null || _passwords[username.trim()] != password) {
      throw const AuthException(AuthFailure.invalidCredentials);
    }
    if (!account.user.isActive) {
      throw const AuthException(AuthFailure.accountDisabled);
    }
    _session = account.user;
    return account.user;
  }

  @override
  Future<void> logout() async {
    _session = null;
  }

  @override
  Future<UserModel?> currentUser() async => _session;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = _session;
    if (session == null) {
      throw const AuthException(AuthFailure.notAuthenticated);
    }
    if (_passwords[session.username] != currentPassword) {
      throw const AuthException(AuthFailure.invalidCredentials);
    }
    _passwords[session.username] = newPassword;
  }
}
