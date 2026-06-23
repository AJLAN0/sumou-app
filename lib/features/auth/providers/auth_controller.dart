import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/role_type.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../data/repositories/auth_repository.dart';
import 'auth_state.dart';

/// Drives login / role selection / logout on top of [AuthRepository].
///
/// UI in later steps watches [authControllerProvider] for [AuthState] and
/// calls these methods. No navigation or widgets here — pure state.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  /// Attempt a login. On success the session is populated; for a single-role
  /// user the active role is set automatically. On failure [AuthState.errorMessage]
  /// is set (e.g. wrong credentials or a disabled account).
  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _auth.login(username: username, password: password);
      state = AuthState(
        currentUser: user,
        selectedRole: user.hasMultipleRoles ? null : user.effectiveRole,
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        currentUser: null,
        selectedRole: null,
        errorMessage: _messageFor(e.reason),
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'حدث خطأ غير متوقع، حاول مرة أخرى',
      );
    }
  }

  /// Choose the active role for a multi-role user. Ignored if the user does
  /// not hold that role.
  void selectRole(RoleType role) {
    final user = state.currentUser;
    if (user == null || !user.hasRole(role)) return;
    state = state.copyWith(selectedRole: role);
  }

  /// Clear the current role selection (e.g. to return to role selection).
  void clearRole() {
    if (state.currentUser == null) return;
    state = state.copyWith(selectedRole: null);
  }

  /// Sign out and reset to the initial state.
  Future<void> logout() async {
    await _auth.logout();
    state = const AuthState();
  }

  /// Dismiss the current error message.
  void clearError() => state = state.copyWith(errorMessage: null);

  String _messageFor(AuthFailure reason) => switch (reason) {
    AuthFailure.invalidCredentials => 'اسم المستخدم أو كلمة المرور غير صحيحة',
    AuthFailure.accountDisabled => 'هذا الحساب موقوف، يرجى التواصل مع الإدارة',
    AuthFailure.notAuthenticated => 'يجب تسجيل الدخول أولاً',
  };
}

/// Global auth/session provider.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
