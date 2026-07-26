// Tests for admin users CRUD (add / edit / delete).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/core/widgets/widgets.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/data/repositories/user_repository.dart';
import 'package:sumou_app/features/admin/users_screen.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/shell/role_based_bottom_nav.dart';
import 'test_helpers.dart';

void main() {
  Future<ProviderContainer> openUsers(
    WidgetTester tester, {
    UserRepository? repository,
  }) async {
    final container = makeMockContainer(
      extra: [
        if (repository != null)
          userRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(RoleBasedBottomNav),
        matching: find.text('المستخدمين'),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  // ---- widget flows ----

  testWidgets('add button opens the user form', (tester) async {
    await openUsers(tester);
    await tester.tap(find.text('إضافة مستخدم'));
    await tester.pumpAndSettle();

    // The form fields and the create CTA are present.
    expect(find.text('الاسم الكامل'), findsOneWidget);
    expect(find.text('إضافة المستخدم'), findsOneWidget);
  });

  testWidgets('empty repository displays the existing empty state safely', (
    tester,
  ) async {
    final container = makeMockContainer(
      extra: [
        userRepositoryProvider.overrideWith(
          (_) => MockUserRepository(users: const []),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: UsersScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا يوجد مستخدمون'), findsOneWidget);
    expect(find.text('لم تتم إضافة مستخدمين بعد'), findsOneWidget);
  });

  testWidgets('deleting a user shows a success snackbar', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openUsers(tester);
    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('حذف المستخدم'));
    await tester.tap(find.text('حذف المستخدم'));
    await tester.pumpAndSettle();
    // Confirm in the Sumou bottom sheet.
    await tester.tap(find.text('حذف'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('تم حذف المستخدم'), findsOneWidget);
  });

  testWidgets('create/reset refresh the list and clear one-time passwords', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository = _CountingUserRepository();
    await openUsers(tester, repository: repository);
    final readsBeforeCreate = repository.getUsersCalls;

    await tester.tap(find.text('إضافة مستخدم'));
    await tester.pumpAndSettle();
    await tester.enterText(_formField('الاسم الكامل'), 'مستخدم تجريبي');
    await tester.enterText(_formField('اسم المستخدم'), 'test.user');
    await tester.ensureVisible(
      find.widgetWithText(SumouButton, 'إضافة المستخدم'),
    );
    await tester.tap(find.widgetWithText(SumouButton, 'إضافة المستخدم'));
    await tester.pumpAndSettle();

    expect(find.text('Mock-Temp-Password1!'), findsOneWidget);
    expect(repository.getUsersCalls, greaterThan(readsBeforeCreate));
    final createSecret = repository.lastCreateSecret!;
    await tester.tap(find.widgetWithText(SumouButton, 'تم'));
    await tester.pumpAndSettle();
    expect(createSecret.isCleared, isTrue);
    expect(find.text('Mock-Temp-Password1!'), findsNothing);

    final readsBeforeReset = repository.getUsersCalls;
    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('إعادة تعيين كلمة المرور'));
    await tester.tap(find.text('إعادة تعيين كلمة المرور'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة التعيين'));
    await tester.pumpAndSettle();

    expect(find.text('Mock-Reset-Password1!'), findsOneWidget);
    expect(repository.getUsersCalls, greaterThan(readsBeforeReset));
    final resetSecret = repository.lastResetSecret!;
    await tester.tap(find.widgetWithText(SumouButton, 'تم'));
    await tester.pumpAndSettle();
    expect(resetSecret.isCleared, isTrue);
    expect(find.text('Mock-Reset-Password1!'), findsNothing);
  });

  testWidgets('permission and backend capabilities gate real-flow actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository = _UnsupportedMutationRepository();
    final container = makeMockContainer(
      extra: [userRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: UsersScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    expect(find.text('تفعيل وتعطيل المستخدم (غير متاح)'), findsOneWidget);
    expect(find.text('تعديل البيانات (غير متاح)'), findsOneWidget);
    expect(find.text('حذف المستخدم'), findsNothing);
    expect(
      tester
          .widget<SumouButton>(
            find.widgetWithText(
              SumouButton,
              'تفعيل وتعطيل المستخدم (غير متاح)',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('create needs both admin permissions while reset needs users', (
    tester,
  ) async {
    const limitedAdmin = UserModel(
      id: 'u-limited-admin',
      fullName: 'مدير محدود',
      username: 'limited',
      defaultRole: RoleType.admin,
      roles: [RoleType.admin],
      permissions: FeaturePermissions(canManageUsers: true),
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith(
          (_) => MockAuthRepository(
            accounts: const [
              MockAccount(user: limitedAdmin, password: MockUsers.devPassword),
            ],
          ),
        ),
        userRepositoryProvider.overrideWith((_) => MockUserRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'limited', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: UsersScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SumouButton>(find.widgetWithText(SumouButton, 'إضافة مستخدم'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SumouButton>(
            find.widgetWithText(SumouButton, 'إعادة تعيين كلمة المرور'),
          )
          .onPressed,
      isNotNull,
    );
  });

  // ---- repository ----

  test('createUser adds a user and rejects bad input', () async {
    final repo = MockUserRepository();
    final created = await repo.createUser(
      fullName: 'مستخدم جديد',
      username: 'newuser',
      defaultRole: RoleType.manager,
      roles: const [RoleType.manager],
    );
    expect(created, isNotNull);
    expect(created!.id, isNotEmpty);

    final all = await repo.getUsers();
    expect(all.any((u) => u.username == 'newuser'), isTrue);

    // Duplicate username (case-insensitive) is rejected.
    final dup = await repo.createUser(
      fullName: 'x',
      username: 'NewUser',
      defaultRole: RoleType.manager,
      roles: const [RoleType.manager],
    );
    expect(dup, isNull);

    // The default role must be within the roles list.
    final bad = await repo.createUser(
      fullName: 'y',
      username: 'yy',
      defaultRole: RoleType.admin,
      roles: const [RoleType.manager],
    );
    expect(bad, isNull);
  });

  test('updateUser changes fields and guards collisions', () async {
    final repo = MockUserRepository();
    final updated = await repo.updateUser(
      'u-photographer',
      fullName: 'نورة المحدثة',
      username: 'noura2',
      defaultRole: RoleType.photographer,
      roles: const [RoleType.photographer],
    );
    expect(updated, isNotNull);
    expect(updated!.fullName, 'نورة المحدثة');
    expect(updated.username, 'noura2');
    // Permissions are preserved (managed elsewhere).
    expect(updated.permissions.has(AppFeature.canUpdateStages), isTrue);

    // Colliding with another user's username is rejected.
    final collide = await repo.updateUser(
      'u-photographer',
      fullName: 'x',
      username: 'admin',
      defaultRole: RoleType.photographer,
      roles: const [RoleType.photographer],
    );
    expect(collide, isNull);

    // Unknown id → null.
    final unknown = await repo.updateUser(
      'nope',
      fullName: 'x',
      username: 'zz',
      defaultRole: RoleType.manager,
      roles: const [RoleType.manager],
    );
    expect(unknown, isNull);
  });

  test('deleteUser removes a user once', () async {
    final repo = MockUserRepository();
    expect(await repo.deleteUser('u-disabled'), isTrue);
    final all = await repo.getUsers();
    expect(all.any((u) => u.id == 'u-disabled'), isFalse);
    // Deleting again does nothing.
    expect(await repo.deleteUser('u-disabled'), isFalse);
  });
}

Finder _formField(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(SumouTextField),
  ),
  matching: find.byType(TextFormField),
);

class _CountingUserRepository extends MockUserRepository {
  int getUsersCalls = 0;
  OneTimePassword? lastCreateSecret;
  OneTimePassword? lastResetSecret;

  @override
  Future<List<UserModel>> getUsers() {
    getUsersCalls++;
    return super.getUsers();
  }

  @override
  Future<UserProvisioningResult> provisionUser({
    required String fullName,
    required String username,
    required RoleType defaultRole,
    required List<RoleType> roles,
    List<String> photographerTypeCodes = const [],
    Map<AppFeature, bool> permissionOverrides = const {},
  }) async {
    final result = await super.provisionUser(
      fullName: fullName,
      username: username,
      defaultRole: defaultRole,
      roles: roles,
      photographerTypeCodes: photographerTypeCodes,
      permissionOverrides: permissionOverrides,
    );
    lastCreateSecret = result.temporaryPassword;
    return result;
  }

  @override
  Future<UserPasswordResetResult> resetPassword(String userId) async {
    final result = await super.resetPassword(userId);
    lastResetSecret = result.temporaryPassword;
    return result;
  }
}

class _UnsupportedMutationRepository extends MockUserRepository {
  @override
  UserRepositoryCapabilities get capabilities =>
      const UserRepositoryCapabilities.supabaseStep10_7();
}
