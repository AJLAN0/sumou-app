// Tests for the Riverpod AuthController / AuthState.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'test_helpers.dart';

const _forcedMultiUser = UserModel(
  id: 'u-forced',
  fullName: 'مستخدم مؤقت',
  username: 'forced',
  defaultRole: RoleType.manager,
  roles: [RoleType.manager, RoleType.photographer],
  mustChangePassword: true,
  permissions: FeaturePermissions(canAddProject: true, canRequestClosure: true),
);

void main() {
  ProviderContainer makeContainer() {
    final container = makeMockContainer();
    addTearDown(container.dispose);
    return container;
  }

  AuthController controllerOf(ProviderContainer c) =>
      c.read(authControllerProvider.notifier);

  test('initial state is signed out', () {
    final c = makeContainer();
    final s = c.read(authControllerProvider);
    expect(s.isAuthenticated, isFalse);
    expect(s.hasActiveUser, isFalse);
    expect(s.activeRole, isNull);
  });

  test('single-role login resolves active role without selection', () async {
    final c = makeContainer();
    await controllerOf(
      c,
    ).login(username: 'manager', password: MockUsers.devPassword);
    final s = c.read(authControllerProvider);
    expect(s.isAuthenticated, isTrue);
    expect(s.needsRoleSelection, isFalse);
    expect(s.activeRole, RoleType.manager);
    expect(s.isLoading, isFalse);
    expect(s.errorMessage, isNull);
  });

  test('multi-role login requires role selection', () async {
    final c = makeContainer();
    await controllerOf(
      c,
    ).login(username: 'multi', password: MockUsers.devPassword);
    var s = c.read(authControllerProvider);
    expect(s.needsRoleSelection, isTrue);
    expect(s.activeRole, isNull);
    expect(
      s.availableRoles,
      containsAll([RoleType.manager, RoleType.photographer]),
    );

    controllerOf(c).selectRole(RoleType.photographer);
    s = c.read(authControllerProvider);
    expect(s.needsRoleSelection, isFalse);
    expect(s.activeRole, RoleType.photographer);
  });

  test('selectRole ignores a role the user does not hold', () async {
    final c = makeContainer();
    await controllerOf(
      c,
    ).login(username: 'multi', password: MockUsers.devPassword);
    controllerOf(c).selectRole(RoleType.admin);
    expect(c.read(authControllerProvider).selectedRole, isNull);
  });

  test('wrong password sets an error and no user', () async {
    final c = makeContainer();
    await controllerOf(c).login(username: 'manager', password: 'wrong');
    final s = c.read(authControllerProvider);
    expect(s.isAuthenticated, isFalse);
    expect(s.errorMessage, isNotNull);
  });

  test('disabled account is rejected with an error', () async {
    final c = makeContainer();
    await controllerOf(
      c,
    ).login(username: 'disabled', password: MockUsers.devPassword);
    final s = c.read(authControllerProvider);
    expect(s.isAuthenticated, isFalse);
    expect(s.errorMessage, isNotNull);
  });

  test('logout resets to signed-out state', () async {
    final c = makeContainer();
    await controllerOf(
      c,
    ).login(username: 'admin', password: MockUsers.devPassword);
    await controllerOf(c).logout();
    final s = c.read(authControllerProvider);
    expect(s.isAuthenticated, isFalse);
    expect(s.selectedRole, isNull);
  });

  test('successful password change clears only the forced flag', () async {
    final repository = MockAuthRepository(
      accounts: const [
        MockAccount(user: _forcedMultiUser, password: 'Current!Pass1'),
      ],
    );
    final c = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWith((ref) => repository)],
    );
    addTearDown(c.dispose);
    final controller = controllerOf(c);
    await controller.login(username: 'forced', password: 'Current!Pass1');
    controller.selectRole(RoleType.photographer);
    final before = c.read(authControllerProvider);

    final ok = await controller.changePassword(
      currentPassword: 'Current!Pass1',
      newPassword: 'N3w!Password2',
    );

    final after = c.read(authControllerProvider);
    expect(ok, isTrue);
    expect(after.currentUser!.mustChangePassword, isFalse);
    expect(after.currentUser!.id, before.currentUser!.id);
    expect(after.currentUser!.roles, same(before.currentUser!.roles));
    expect(
      after.currentUser!.permissions,
      same(before.currentUser!.permissions),
    );
    expect(after.selectedRole, RoleType.photographer);
  });

  test('failed password change keeps forced flag true', () async {
    final repository = MockAuthRepository(
      accounts: const [
        MockAccount(user: _forcedMultiUser, password: 'Current!Pass1'),
      ],
    );
    final c = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWith((ref) => repository)],
    );
    addTearDown(c.dispose);
    final controller = controllerOf(c);
    await controller.login(username: 'forced', password: 'Current!Pass1');

    final ok = await controller.changePassword(
      currentPassword: 'Wrong!Password1',
      newPassword: 'N3w!Password2',
    );

    final state = c.read(authControllerProvider);
    expect(ok, isFalse);
    expect(state.currentUser!.mustChangePassword, isTrue);
    expect(state.errorMessage, 'كلمة المرور الحالية غير صحيحة');
  });
}
