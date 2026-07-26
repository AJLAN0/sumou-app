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
  // Starts in the "restoring" state so the router never treats a not-yet-
  // restored session as signed out (which would flash Entry before restore).
  @override
  AuthState build() => const AuthState(isInitializing: true);

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  /// The in-flight (or completed) restoration, so the operation is idempotent.
  Future<void>? _initFuture;

  /// Restore a persisted Supabase session at startup (idempotent). Splash waits
  /// for this to complete before routing. Resolves to:
  ///   • signed-out when there is no session (or the account is disabled/deleted
  ///     /invalid — the repository signs the bad session out), or
  ///   • authenticated with the full user context when a valid session exists.
  /// An unexpected restore failure resolves to signed-out with a safe message.
  ///
  /// Concurrent callers await the SAME restoration: returning the cached future
  /// (instead of an immediately-completed one) guarantees a second caller never
  /// proceeds to route while the first restoration is still in flight — which
  /// would route off a still-initializing state and could flash Entry.
  Future<void> initializeSession() => _initFuture ??= _restoreSession();

  Future<void> _restoreSession() async {
    state = state.copyWith(isInitializing: true, errorMessage: null);
    try {
      final user = await _auth.currentUser();
      if (user == null) {
        state = const AuthState(); // initialized + signed out
      } else {
        state = AuthState(
          currentUser: user,
          selectedRole: user.hasMultipleRoles ? null : user.effectiveRole,
        );
      }
    } on AuthException {
      // Disabled/deleted/invalid persisted account → safe signed-out. Terminal:
      // the repository already cleared the bad session, so no retry is wanted.
      state = const AuthState();
    } catch (_) {
      // TRANSIENT failure (network/query): clear the cached future so a later
      // call can retry — a one-off outage must not latch the app signed-out for
      // the rest of its lifetime. The persisted session is left intact.
      _initFuture = null;
      state = AuthState(
        errorMessage: _messageFor(AuthFailure.sessionRestoreFailed),
      );
    }
  }

  /// Attempt a login. On success the session is populated; for a single-role
  /// user the active role is set automatically. On failure [AuthState.errorMessage]
  /// is set (e.g. wrong credentials or a disabled account).
  Future<void> login({
    required String username,
    required String password,
  }) async {
    // An explicit login supersedes startup restoration: clear isInitializing on
    // every path (a stale `true` would hold the router on Splash and hide the
    // error) and stop a late restore from overwriting this result.
    _initFuture = Future<void>.value();
    state = state.copyWith(
      isLoading: true,
      isInitializing: false,
      errorMessage: null,
    );
    try {
      final user = await _auth.login(username: username, password: password);
      state = AuthState(
        currentUser: user,
        selectedRole: user.hasMultipleRoles ? null : user.effectiveRole,
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        isInitializing: false,
        currentUser: null,
        selectedRole: null,
        errorMessage: _messageFor(e.reason),
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        isInitializing: false,
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

  /// Sign out and reset to the signed-out state. Idempotent.
  Future<void> logout() async {
    // Mark restoration settled so returning to Splash cannot re-query (and can
    // never resurrect a just-cleared session). The reset state is NOT
    // initializing, so the router goes straight to Entry.
    _initFuture = Future<void>.value();
    await _auth.logout();
    state = const AuthState();
  }

  /// Change the signed-in user's password via the (mock) repository.
  /// Returns true on success; on failure sets [AuthState.errorMessage].
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _auth.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      state = state.copyWith(isLoading: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _messageFor(e.reason),
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'حدث خطأ غير متوقع، حاول مرة أخرى',
      );
      return false;
    }
  }

  /// Dismiss the current error message.
  void clearError() => state = state.copyWith(errorMessage: null);

  String _messageFor(AuthFailure reason) => switch (reason) {
    AuthFailure.invalidCredentials => 'اسم المستخدم أو كلمة المرور غير صحيحة',
    AuthFailure.accountDisabled => 'هذا الحساب موقوف، يرجى التواصل مع الإدارة',
    AuthFailure.notAuthenticated => 'يجب تسجيل الدخول أولاً',
    AuthFailure.profileUnavailable =>
      'تعذّر تحميل بيانات الحساب، يرجى المحاولة لاحقاً',
    AuthFailure.sessionRestoreFailed =>
      'تعذّرت استعادة الجلسة، يرجى تسجيل الدخول',
    // Step 10.6 will enable the real password change.
    AuthFailure.passwordChangeUnavailable =>
      'سيتم تفعيل تغيير كلمة المرور في الخطوة التالية',
  };
}

/// Global auth/session provider.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
