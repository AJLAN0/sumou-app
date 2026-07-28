import '../../core/models/feature_permissions.dart';
import '../../core/models/role_type.dart';
import '../../core/models/user_model.dart';

enum UserRepositoryFailure {
  loadFailed,
  invalidData,
  invalidInput,
  unauthenticated,
  forbidden,
  usernameTaken,
  userNotFound,
  createFailed,
  resetFailed,
  unsupportedOperation,
}

/// Safe, typed user-management failure. Raw Supabase/Auth/Postgres errors are
/// deliberately never retained or exposed to the UI.
class UserRepositoryException implements Exception {
  const UserRepositoryException(this.reason);

  final UserRepositoryFailure reason;

  String get messageAr => switch (reason) {
    UserRepositoryFailure.loadFailed ||
    UserRepositoryFailure.invalidData => 'تعذّر تحميل بيانات المستخدمين بأمان',
    UserRepositoryFailure.invalidInput =>
      'تحقق من بيانات المستخدم وحاول مرة أخرى',
    UserRepositoryFailure.unauthenticated =>
      'انتهت الجلسة، سجّل الدخول مرة أخرى',
    UserRepositoryFailure.forbidden => 'ليست لديك صلاحية لتنفيذ هذا الإجراء',
    UserRepositoryFailure.usernameTaken => 'اسم المستخدم مستخدم بالفعل',
    UserRepositoryFailure.userNotFound => 'المستخدم غير موجود',
    UserRepositoryFailure.createFailed => 'تعذّر إنشاء المستخدم، حاول مرة أخرى',
    UserRepositoryFailure.resetFailed =>
      'تعذّر إعادة تعيين كلمة المرور، حاول مرة أخرى',
    UserRepositoryFailure.unsupportedOperation =>
      'هذا الإجراء غير متاح حتى يجهز مسار الخادم الآمن',
  };

  @override
  String toString() => 'UserRepositoryException(${reason.name})';
}

class UserRepositoryCapabilities {
  const UserRepositoryCapabilities({
    required this.canCreate,
    required this.canResetPassword,
    required this.canSetActive,
    required this.canEditProfile,
    required this.canEditRoles,
    required this.canEditPermissions,
    required this.canDelete,
  });

  const UserRepositoryCapabilities.mock()
    : canCreate = true,
      canResetPassword = true,
      canSetActive = true,
      canEditProfile = true,
      canEditRoles = true,
      canEditPermissions = true,
      canDelete = true;

  const UserRepositoryCapabilities.supabaseStep10_7()
    : canCreate = true,
      canResetPassword = true,
      canSetActive = false,
      canEditProfile = false,
      canEditRoles = false,
      canEditPermissions = false,
      canDelete = false;

  final bool canCreate;
  final bool canResetPassword;
  final bool canSetActive;
  final bool canEditProfile;
  final bool canEditRoles;
  final bool canEditPermissions;
  final bool canDelete;
}

class StaffPhotoTypeOption {
  const StaffPhotoTypeOption({required this.code, required this.nameAr});

  final String code;
  final String nameAr;
}

/// Mutable, UI-scoped holder for a server-generated temporary password.
///
/// The repository never caches this object. The dialog clears it on dismissal,
/// and [toString] is always redacted so accidental diagnostics cannot reveal it.
class OneTimePassword {
  OneTimePassword(String value) : _value = value;

  String? _value;

  String? get value => _value;
  bool get isCleared => _value == null;

  void clear() => _value = null;

  @override
  String toString() => 'OneTimePassword(redacted)';
}

class UserProvisioningResult {
  const UserProvisioningResult({
    required this.userId,
    required this.temporaryPassword,
  });

  final String userId;
  final OneTimePassword temporaryPassword;
}

class UserPasswordResetResult {
  const UserPasswordResetResult({
    required this.userId,
    required this.mustChangePassword,
    required this.temporaryPassword,
  });

  final String userId;
  final bool mustChangePassword;
  final OneTimePassword temporaryPassword;
}

/// Staff-user access. The normal app uses the Supabase implementation; tests
/// explicitly override it with [MockUserRepository].
abstract interface class UserRepository {
  UserRepositoryCapabilities get capabilities;

  Future<List<UserModel>> getUsers();
  Future<UserModel?> getUserById(String id);
  Future<UserModel?> getUserByUsername(String username);
  Future<List<StaffPhotoTypeOption>> getAvailablePhotoTypes();

  /// Trusted create contract. The temporary password is returned once in a
  /// clearable UI-scoped holder and is never retained by the repository.
  Future<UserProvisioningResult> provisionUser({
    required String fullName,
    required String username,
    required RoleType defaultRole,
    required List<RoleType> roles,
    List<String> photographerTypeCodes,
    Map<AppFeature, bool> permissionOverrides,
  });

  /// Trusted admin reset contract. The backend preserves the target's active
  /// state and sets `must_change_password=true`.
  Future<UserPasswordResetResult> resetPassword(String userId);

  /// Activate or deactivate a user. Returns the updated user, or null when the
  /// id is unknown. Mock-backed in this sprint.
  Future<UserModel?> setUserActive(String userId, bool active);

  /// Replace a user's [defaultRole] and full [roles] list. Returns the updated
  /// user, or null when the id is unknown or the default role isn't in [roles].
  /// Mock-backed in this sprint.
  Future<UserModel?> updateUserRoles(
    String userId, {
    required RoleType defaultRole,
    required List<RoleType> roles,
  });

  /// Replace a user's feature [permissions]. Returns the updated user, or null
  /// when the id is unknown. Mock-backed in this sprint.
  Future<UserModel?> updateUserPermissions(
    String userId,
    FeaturePermissions permissions,
  );

  /// Create a new user. The id is generated by the repository. Returns the
  /// created user, or null when [username] is already taken or [defaultRole]
  /// isn't in [roles]. Mock-backed in this sprint.
  Future<UserModel?> createUser({
    required String fullName,
    required String username,
    String? email,
    required RoleType defaultRole,
    required List<RoleType> roles,
    List<String> photoTypes,
    FeaturePermissions permissions,
    bool active,
  });

  /// Update a user's profile: identity, roles, photo types, and active flag.
  /// Permissions are managed separately. Returns the updated user, or null when
  /// the id is unknown, [username] collides with another user, or [defaultRole]
  /// isn't in [roles]. Mock-backed in this sprint.
  Future<UserModel?> updateUser(
    String userId, {
    required String fullName,
    required String username,
    String? email,
    required RoleType defaultRole,
    required List<RoleType> roles,
    List<String> photoTypes,
    bool active,
  });

  /// Permanently remove a user. Returns true when a user was removed, false
  /// when the id is unknown. Mock-backed in this sprint.
  Future<bool> deleteUser(String userId);
}
