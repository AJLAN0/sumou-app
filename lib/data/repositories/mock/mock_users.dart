import '../../../core/models/feature_permissions.dart';
import '../../../core/models/role_type.dart';
import '../../../core/models/user_model.dart';

/// A development-only account: a [UserModel] plus a fake password.
class MockAccount {
  const MockAccount({required this.user, required this.password});

  final UserModel user;
  final String password;
}

/// In-memory development data.
///
/// SECURITY: these are NOT real credentials. The password below is an obvious
/// placeholder for local development only and must never reach production or
/// be treated as a secret. Real auth is provided by Supabase later.
class MockUsers {
  MockUsers._();

  /// Obvious fake password shared by all mock accounts (dev only).
  static const String devPassword = 'dev-only-1234';

  static const UserModel manager = UserModel(
    id: 'u-manager',
    fullName: 'سعد المطيري',
    username: 'manager',
    defaultRole: RoleType.manager,
    roles: [RoleType.manager],
    permissions: FeaturePermissions(
      canAddProject: true,
      canEditProject: true,
      canAssignPhotographers: true,
      canUpdateStages: true,
      canApproveClosure: true,
      canViewReports: true,
    ),
  );

  static const UserModel photographer = UserModel(
    id: 'u-photographer',
    fullName: 'نورة الحنايا',
    username: 'photographer',
    defaultRole: RoleType.photographer,
    roles: [RoleType.photographer],
    photoTypes: ['مصور فوتوغرافي'],
    permissions: FeaturePermissions(
      canRequestPhotographer: true,
      canRequestDesign: true,
      canUpdateStages: true,
      canRequestClosure: true,
    ),
  );

  static const UserModel admin = UserModel(
    id: 'u-admin',
    fullName: 'إدارة سمو',
    username: 'admin',
    defaultRole: RoleType.admin,
    roles: [RoleType.admin],
    permissions: FeaturePermissions(
      canManageUsers: true,
      canManagePermissions: true,
      canViewReports: true,
    ),
  );

  /// Holds both manager and photographer roles (must pick on login).
  static const UserModel multiRole = UserModel(
    id: 'u-multi',
    fullName: 'خالد الزهراني',
    username: 'multi',
    defaultRole: RoleType.manager,
    roles: [RoleType.manager, RoleType.photographer],
    photoTypes: ['مصور فيديو'],
    permissions: FeaturePermissions(
      canAddProject: true,
      canEditProject: true,
      canAssignPhotographers: true,
      canUpdateStages: true,
      canApproveClosure: true,
      canViewReports: true,
      canRequestPhotographer: true,
      canRequestDesign: true,
      canRequestClosure: true,
    ),
  );

  /// Disabled account — used to verify login rejection.
  static const UserModel disabled = UserModel(
    id: 'u-disabled',
    fullName: 'فهد القحطاني',
    username: 'disabled',
    defaultRole: RoleType.photographer,
    roles: [RoleType.photographer],
    active: false,
  );

  static const List<UserModel> users = [
    manager,
    photographer,
    admin,
    multiRole,
    disabled,
  ];

  static const List<MockAccount> accounts = [
    MockAccount(user: manager, password: devPassword),
    MockAccount(user: photographer, password: devPassword),
    MockAccount(user: admin, password: devPassword),
    MockAccount(user: multiRole, password: devPassword),
    MockAccount(user: disabled, password: devPassword),
  ];
}
