import '../../../core/models/role_type.dart';
import '../../../core/models/user_model.dart';

/// Sentinel so [AuthState.copyWith] can distinguish "leave unchanged" from
/// "set to null" for nullable fields.
const Object _unset = Object();

/// Immutable auth/session state consumed by the UI in later steps.
class AuthState {
  const AuthState({
    this.currentUser,
    this.selectedRole,
    this.isLoading = false,
    this.errorMessage,
  });

  /// The authenticated user, or null when signed out.
  final UserModel? currentUser;

  /// The role chosen by a multi-role user; null until chosen (or for a
  /// single-role user it is set automatically on login).
  final RoleType? selectedRole;

  /// True while an auth operation is in flight.
  final bool isLoading;

  /// Arabic, user-facing error from the last failed operation, if any.
  final String? errorMessage;

  // ---- helpers -------------------------------------------------------------

  /// Whether a user is signed in.
  bool get isAuthenticated => currentUser != null;

  /// Alias for [isAuthenticated] (per requested helper name).
  bool get hasActiveUser => currentUser != null;

  /// Roles available to the signed-in user.
  List<RoleType> get availableRoles => currentUser?.roles ?? const [];

  /// A multi-role user is signed in but hasn't chosen a role yet.
  bool get needsRoleSelection =>
      currentUser != null &&
      currentUser!.hasMultipleRoles &&
      selectedRole == null;

  /// The currently active role: the explicit [selectedRole], or — for a
  /// single-role user — their only role. Null when selection is still needed.
  RoleType? get activeRole {
    final user = currentUser;
    if (user == null) return null;
    if (selectedRole != null) return selectedRole;
    return user.hasMultipleRoles ? null : user.effectiveRole;
  }

  AuthState copyWith({
    Object? currentUser = _unset,
    Object? selectedRole = _unset,
    bool? isLoading,
    Object? errorMessage = _unset,
  }) {
    return AuthState(
      currentUser:
          identical(currentUser, _unset)
              ? this.currentUser
              : currentUser as UserModel?,
      selectedRole:
          identical(selectedRole, _unset)
              ? this.selectedRole
              : selectedRole as RoleType?,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          identical(errorMessage, _unset)
              ? this.errorMessage
              : errorMessage as String?,
    );
  }
}
