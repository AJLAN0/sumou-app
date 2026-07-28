// Routing/redirect tests driven by the auth state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/app/router.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'test_helpers.dart';

const _forcedManager = UserModel(
  id: 'forced-manager',
  fullName: 'مستخدم مؤقت',
  username: 'forced_manager',
  defaultRole: RoleType.manager,
  roles: [RoleType.manager],
  mustChangePassword: true,
);

const _forcedMulti = UserModel(
  id: 'forced-multi',
  fullName: 'مستخدم متعدد',
  username: 'forced_multi',
  defaultRole: RoleType.manager,
  roles: [RoleType.manager, RoleType.photographer],
  mustChangePassword: true,
);

MockAuthRepository _repositoryFor(UserModel user) => MockAuthRepository(
  accounts: [MockAccount(user: user, password: 'Current!Pass1')],
);

ProviderContainer _containerFor(MockAuthRepository repository) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWith((ref) => repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SumouApp()),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  test('homePathFor maps the supported roles', () {
    expect(homePathFor(RoleType.manager), AppRoutes.managerHome);
    expect(homePathFor(RoleType.photographer), AppRoutes.photographerHome);
    expect(homePathFor(RoleType.admin), AppRoutes.adminHome);
  });

  testWidgets('authenticated single-role user lands on their role home', (
    tester,
  ) async {
    final container = makeMockContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'manager', password: MockUsers.devPassword);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Manager lands on the shell; the first tab is الرئيسية (app bar + nav).
    expect(find.text('الرئيسية'), findsWidgets);
  });

  testWidgets('multi-role user is sent to role selection', (tester) async {
    final container = makeMockContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'multi', password: MockUsers.devPassword);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('اختيار الدور'), findsWidgets);
  });

  testWidgets('forced route applies immediately after login', (tester) async {
    final repository = _repositoryFor(_forcedManager);
    final container = _containerFor(repository);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'forced_manager', password: 'Current!Pass1');

    await _pumpApp(tester, container);

    expect(find.text('تحديث كلمة المرور مطلوب'), findsOneWidget);
    expect(find.text('الرئيسية'), findsNothing);
  });

  testWidgets('forced route applies after persisted session restoration', (
    tester,
  ) async {
    final repository = _repositoryFor(_forcedManager);
    // Seed the mock repository's persisted session before the app/controller
    // starts. Splash must await currentUser() and then force password change.
    await repository.login(
      username: 'forced_manager',
      password: 'Current!Pass1',
    );
    final container = _containerFor(repository);

    await _pumpApp(tester, container);

    expect(find.text('تحديث كلمة المرور مطلوب'), findsOneWidget);
    expect(container.read(authControllerProvider).isInitializing, isFalse);
  });

  testWidgets('forced password route outranks multi-role selection', (
    tester,
  ) async {
    final repository = _repositoryFor(_forcedMulti);
    final container = _containerFor(repository);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'forced_multi', password: 'Current!Pass1');

    await _pumpApp(tester, container);

    expect(find.text('تحديث كلمة المرور مطلوب'), findsOneWidget);
    expect(find.text('اختيار الدور'), findsNothing);
  });

  testWidgets('public tracking remains public during forced flow', (
    tester,
  ) async {
    final repository = _repositoryFor(_forcedManager);
    final container = _containerFor(repository);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'forced_manager', password: 'Current!Pass1');
    await _pumpApp(tester, container);

    container.read(goRouterProvider).go(AppRoutes.track);
    await tester.pumpAndSettle();

    expect(find.text('تتبع مشروعك'), findsOneWidget);
    expect(find.text('تحديث كلمة المرور مطلوب'), findsNothing);
  });
}
