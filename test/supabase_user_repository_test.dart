import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/supabase/supabase_user_repository.dart';
import 'package:sumou_app/data/repositories/supabase/user_gateway.dart';
import 'package:sumou_app/data/repositories/user_repository.dart';

const userId = '11111111-1111-4111-8111-111111111111';
const managerRoleId = '22222222-2222-4222-8222-222222222222';

void main() {
  group('SupabaseUserRepository reads', () {
    test('empty DEV profiles produce an empty staff list', () async {
      final gateway = FakeUserAdminGateway();
      final repository = SupabaseUserRepository.withGateway(gateway);

      expect(await repository.getUsers(), isEmpty);
      expect(gateway.roleAssignmentCalls, 0);
      expect(gateway.photoAssignmentCalls, 0);
    });

    test(
      'strictly parses user context and resolves effective permissions',
      () async {
        final gateway =
            FakeUserAdminGateway()
              ..profiles = [validProfile()]
              ..roleAssignments = [
                {
                  'user_id': userId,
                  'role_id': managerRoleId,
                  'role': {
                    'id': managerRoleId,
                    'code': 'manager',
                    'is_active': true,
                  },
                },
              ]
              ..photoAssignments = [
                {
                  'user_id': userId,
                  'photographer_type': {
                    'code': 'video',
                    'name_ar': 'مصور فيديو',
                    'is_active': true,
                  },
                },
              ]
              ..rolePermissions = [
                permissionRow(
                  roleId: managerRoleId,
                  code: 'can_add_project',
                  granted: true,
                ),
                permissionRow(
                  roleId: managerRoleId,
                  code: 'can_manage_finance',
                  granted: true,
                ),
              ]
              ..userPermissions = [
                userPermissionRow(code: 'can_add_project', granted: false),
                userPermissionRow(code: 'can_view_reports', granted: true),
              ];
        final repository = SupabaseUserRepository.withGateway(gateway);

        final users = await repository.getUsers();

        expect(users, hasLength(1));
        final user = users.single;
        expect(user.email, isNull);
        expect(user.roles, [RoleType.manager]);
        expect(user.photoTypes, ['مصور فيديو']);
        expect(user.hasPermission(AppFeature.canAddProject), isFalse);
        expect(user.hasPermission(AppFeature.canViewReports), isTrue);
        expect(user.hasPermission(AppFeature.canManageFinance), isFalse);
      },
    );

    test('malformed profile data fails with one safe typed reason', () async {
      final gateway =
          FakeUserAdminGateway()
            ..profiles = [
              {...validProfile(), 'must_change_password': 'false'},
            ];
      final repository = SupabaseUserRepository.withGateway(gateway);

      await expectLater(
        repository.getUsers(),
        throwsA(
          isA<UserRepositoryException>().having(
            (error) => error.reason,
            'reason',
            UserRepositoryFailure.invalidData,
          ),
        ),
      );
    });

    test(
      'query failures do not become an empty list or expose raw errors',
      () async {
        final gateway = FakeUserAdminGateway()..throwOnProfiles = true;
        final repository = SupabaseUserRepository.withGateway(gateway);

        await expectLater(
          repository.getUsers(),
          throwsA(
            isA<UserRepositoryException>()
                .having(
                  (error) => error.reason,
                  'reason',
                  UserRepositoryFailure.loadFailed,
                )
                .having(
                  (error) => error.toString(),
                  'safe text',
                  isNot(contains('database-secret')),
                ),
          ),
        );
      },
    );
  });

  group('create user', () {
    test(
      'sends the exact trusted request and returns a clearable password',
      () async {
        final gateway =
            FakeUserAdminGateway()
              ..createResponse = const AdminUserFunctionResponse(
                status: 201,
                data: {
                  'user': {
                    'id': userId,
                    'username': 'new.user',
                    'full_name': 'مستخدم جديد',
                    'default_role': 'manager',
                    'roles': ['manager'],
                    'photographer_types': ['video'],
                    'permission_overrides': [
                      {'code': 'can_view_reports', 'granted': false},
                    ],
                    'is_active': true,
                    'must_change_password': true,
                  },
                  'temp_password': 'Temp-Password9!',
                },
              );
        final repository = SupabaseUserRepository.withGateway(gateway);

        final result = await repository.provisionUser(
          fullName: '  مستخدم جديد ',
          username: ' New.User ',
          defaultRole: RoleType.manager,
          roles: const [RoleType.manager],
          photographerTypeCodes: const ['video'],
          permissionOverrides: const {AppFeature.canViewReports: false},
        );

        expect(gateway.lastCreateBody, {
          'username': 'new.user',
          'full_name': 'مستخدم جديد',
          'default_role': 'manager',
          'roles': ['manager'],
          'photographer_types': ['video'],
          'permission_overrides': [
            {'code': 'can_view_reports', 'granted': false},
          ],
        });
        expect(
          gateway.lastCreateBody!.keys,
          isNot(containsAll(<String>['email', 'id', 'is_active', 'password'])),
        );
        expect(
          gateway.lastCreateBody.toString(),
          isNot(contains('service_role')),
        );
        expect(result.temporaryPassword.value, 'Temp-Password9!');
        expect(
          result.temporaryPassword.toString(),
          isNot(contains('Temp-Password9!')),
        );
        result.temporaryPassword.clear();
        expect(result.temporaryPassword.isCleared, isTrue);
      },
    );

    test('maps create statuses to safe typed failures', () async {
      final cases = {
        400: UserRepositoryFailure.invalidInput,
        401: UserRepositoryFailure.unauthenticated,
        403: UserRepositoryFailure.forbidden,
        409: UserRepositoryFailure.usernameTaken,
        500: UserRepositoryFailure.createFailed,
      };
      for (final entry in cases.entries) {
        final gateway =
            FakeUserAdminGateway()
              ..createResponse = AdminUserFunctionResponse(
                status: entry.key,
                data: const {
                  'error': {
                    'code': 'raw_backend_error',
                    'message': 'database-secret',
                  },
                },
              );
        final repository = SupabaseUserRepository.withGateway(gateway);

        await expectLater(
          repository.provisionUser(
            fullName: 'مستخدم',
            username: 'newuser',
            defaultRole: RoleType.manager,
            roles: const [RoleType.manager],
          ),
          throwsA(
            isA<UserRepositoryException>()
                .having((error) => error.reason, 'reason', entry.value)
                .having(
                  (error) => error.toString(),
                  'safe text',
                  isNot(contains('database-secret')),
                ),
          ),
        );
      }
    });

    test(
      'rejects success payloads containing unsupported identity fields',
      () async {
        final gateway =
            FakeUserAdminGateway()
              ..createResponse = const AdminUserFunctionResponse(
                status: 201,
                data: {
                  'user': {
                    'id': userId,
                    'username': 'newuser',
                    'full_name': 'مستخدم',
                    'default_role': 'manager',
                    'roles': ['manager'],
                    'photographer_types': [],
                    'permission_overrides': [],
                    'is_active': true,
                    'must_change_password': true,
                    'internal_email': 'hidden@example.invalid',
                  },
                  'temp_password': 'Temp-Password9!',
                },
              );
        final repository = SupabaseUserRepository.withGateway(gateway);

        await expectLater(
          repository.provisionUser(
            fullName: 'مستخدم',
            username: 'newuser',
            defaultRole: RoleType.manager,
            roles: const [RoleType.manager],
          ),
          throwsA(
            isA<UserRepositoryException>().having(
              (error) => error.reason,
              'reason',
              UserRepositoryFailure.createFailed,
            ),
          ),
        );
      },
    );
  });

  group('reset password', () {
    test('sends only user_id and returns a one-time password', () async {
      final gateway =
          FakeUserAdminGateway()
            ..resetResponse = const AdminUserFunctionResponse(
              status: 200,
              data: {
                'user': {
                  'id': userId,
                  'must_change_password': true,
                  'is_active': false,
                },
                'temp_password': 'Reset-Password9!',
              },
            );
      final repository = SupabaseUserRepository.withGateway(gateway);

      final result = await repository.resetPassword(userId);

      expect(gateway.lastResetBody, {'user_id': userId});
      expect(result.mustChangePassword, isTrue);
      expect(result.temporaryPassword.value, 'Reset-Password9!');
      result.temporaryPassword.clear();
      expect(result.temporaryPassword.isCleared, isTrue);
    });

    test('maps reset statuses to safe typed failures', () async {
      final cases = {
        400: UserRepositoryFailure.invalidInput,
        401: UserRepositoryFailure.unauthenticated,
        403: UserRepositoryFailure.forbidden,
        404: UserRepositoryFailure.userNotFound,
        500: UserRepositoryFailure.resetFailed,
      };
      for (final entry in cases.entries) {
        final gateway =
            FakeUserAdminGateway()
              ..resetResponse = AdminUserFunctionResponse(
                status: entry.key,
                data: const {
                  'error': {'message': 'token password service_role'},
                },
              );
        final repository = SupabaseUserRepository.withGateway(gateway);

        await expectLater(
          repository.resetPassword(userId),
          throwsA(
            isA<UserRepositoryException>()
                .having((error) => error.reason, 'reason', entry.value)
                .having(
                  (error) => error.toString(),
                  'safe text',
                  isNot(contains('token password service_role')),
                ),
          ),
        );
      }
    });
  });

  test('unsupported mutations fail closed without gateway writes', () async {
    final gateway = FakeUserAdminGateway();
    final repository = SupabaseUserRepository.withGateway(gateway);

    expect(repository.capabilities.canSetActive, isFalse);
    expect(repository.capabilities.canEditProfile, isFalse);
    expect(repository.capabilities.canEditRoles, isFalse);
    expect(repository.capabilities.canEditPermissions, isFalse);
    expect(repository.capabilities.canDelete, isFalse);
    await expectLater(
      repository.setUserActive(userId, false),
      _unsupportedFailure(),
    );
    await expectLater(repository.deleteUser(userId), _unsupportedFailure());
    expect(gateway.createCalls, 0);
    expect(gateway.resetCalls, 0);
  });
}

Matcher _unsupportedFailure() => throwsA(
  isA<UserRepositoryException>().having(
    (error) => error.reason,
    'reason',
    UserRepositoryFailure.unsupportedOperation,
  ),
);

Map<String, dynamic> validProfile() => {
  'id': userId,
  'username': 'manager',
  'full_name': 'مدير النظام',
  'avatar_initials': null,
  'is_active': true,
  'deleted_at': null,
  'default_role_id': managerRoleId,
  'must_change_password': false,
};

Map<String, dynamic> permissionRow({
  required String roleId,
  required String code,
  required bool granted,
}) => {
  'role_id': roleId,
  'granted': granted,
  'permission': {'code': code, 'is_active': true},
};

Map<String, dynamic> userPermissionRow({
  required String code,
  required bool granted,
}) => {
  'user_id': userId,
  'granted': granted,
  'permission': {'code': code, 'is_active': true},
};

class FakeUserAdminGateway implements UserAdminGateway {
  List<Map<String, dynamic>> profiles = [];
  List<Map<String, dynamic>> roleAssignments = [];
  List<Map<String, dynamic>> photoAssignments = [];
  List<Map<String, dynamic>> rolePermissions = [];
  List<Map<String, dynamic>> userPermissions = [];
  List<Map<String, dynamic>> photoTypes = [];
  bool throwOnProfiles = false;
  AdminUserFunctionResponse createResponse = const AdminUserFunctionResponse(
    status: 500,
    data: {},
  );
  AdminUserFunctionResponse resetResponse = const AdminUserFunctionResponse(
    status: 500,
    data: {},
  );

  int roleAssignmentCalls = 0;
  int photoAssignmentCalls = 0;
  int createCalls = 0;
  int resetCalls = 0;
  Map<String, dynamic>? lastCreateBody;
  Map<String, String>? lastResetBody;

  @override
  Future<List<Map<String, dynamic>>> fetchProfiles({
    String? userId,
    String? username,
  }) async {
    if (throwOnProfiles) throw StateError('database-secret');
    return profiles;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoleAssignments(
    List<String> userIds,
  ) async {
    roleAssignmentCalls++;
    return roleAssignments;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPhotoTypeAssignments(
    List<String> userIds,
  ) async {
    photoAssignmentCalls++;
    return photoAssignments;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRolePermissions(
    List<String> roleIds,
  ) async => rolePermissions;

  @override
  Future<List<Map<String, dynamic>>> fetchUserPermissions(
    List<String> userIds,
  ) async => userPermissions;

  @override
  Future<List<Map<String, dynamic>>> fetchActivePhotoTypes() async =>
      photoTypes;

  @override
  Future<AdminUserFunctionResponse> invokeCreateUser(
    Map<String, dynamic> body,
  ) async {
    createCalls++;
    lastCreateBody = body;
    return createResponse;
  }

  @override
  Future<AdminUserFunctionResponse> invokeResetPassword(
    Map<String, String> body,
  ) async {
    resetCalls++;
    lastResetBody = body;
    return resetResponse;
  }
}
