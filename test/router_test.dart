// Routing/redirect tests driven by the auth state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/app/router.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/core/widgets/widgets.dart';
import 'package:sumou_app/data/repositories/auth_repository.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/data/repositories/tracking_repository.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/shell/role_based_bottom_nav.dart';
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

const _allOperationalRoles = UserModel(
  id: 'multi-operational-user',
  fullName: 'مستخدم متعدد الصلاحيات',
  username: 'multi_operational',
  defaultRole: RoleType.manager,
  roles: [RoleType.manager, RoleType.photographer, RoleType.admin],
);

class _PendingSessionRepository implements AuthRepository {
  final currentUserCompleter = Completer<UserModel?>();

  @override
  Future<UserModel?> currentUser() => currentUserCompleter.future;

  @override
  Future<UserModel> login({
    required String username,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();
}

class _HostileTrackingRepository implements TrackingRepository {
  static const rawFailure =
      'PostgREST SQLSTATE 42501 details=synthetic_hint '
      'user=11111111-1111-4111-8111-111111111111';

  @override
  Future<ClientTrackingModel?> trackBySerial(String serial) {
    throw StateError(rawFailure);
  }

  @override
  Future<void> submitReview({
    required String serial,
    required int rating,
    String? message,
  }) => throw UnimplementedError();
}

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

String _location(ProviderContainer container) =>
    container.read(goRouterProvider).routeInformationProvider.value.uri.path;

Future<ProviderContainer> _restoredContainer(UserModel user) async {
  final repository = _repositoryFor(user);
  await repository.login(username: user.username, password: 'Current!Pass1');
  final container = makeMockContainer(
    extra: [authRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
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

  testWidgets(
    'signed-out initialization remains on splash until restoration completes',
    (tester) async {
      final repository = _PendingSessionRepository();
      final container = makeMockContainer(
        extra: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SumouApp(),
        ),
      );
      await tester.pump();
      expect(find.byType(LiquidLogoLoader), findsOneWidget);
      expect(find.text('دخول سمو'), findsNothing);
      expect(find.byType(RoleBasedBottomNav), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(LiquidLogoLoader), findsOneWidget);
      expect(_location(container), AppRoutes.splash);

      repository.currentUserCompleter.complete(null);
      await tester.pumpAndSettle();
      expect(_location(container), AppRoutes.entry);
      expect(find.text('دخول سمو'), findsOneWidget);
      expect(find.byType(RoleBasedBottomNav), findsNothing);
    },
  );

  testWidgets(
    'anonymous tracking stays public, returns publicly, and hides hostile diagnostics',
    (tester) async {
      final container = makeMockContainer(
        trackingRepository: _HostileTrackingRepository(),
      );
      addTearDown(container.dispose);
      await _pumpApp(tester, container);

      await tester.tap(find.text('تتبع مشروع'));
      await tester.pump();
      expect(_location(container), AppRoutes.track);
      expect(find.byType(RoleBasedBottomNav), findsNothing);
      expect(find.text('لوحة التحكم'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('تتبع مشروعك'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'FLD-A1B2-C3');
      await tester.tap(find.text('تتبع'));
      await tester.pumpAndSettle();
      expect(
        find.text('تعذّر تتبع المشروع الآن، حاول مرة أخرى'),
        findsOneWidget,
      );
      expect(
        find.textContaining(_HostileTrackingRepository.rawFailure),
        findsNothing,
      );
      expect(
        find.textContaining('11111111-1111-4111-8111-111111111111'),
        findsNothing,
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(_location(container), AppRoutes.entry);
      expect(find.text('دخول سمو'), findsOneWidget);
    },
  );

  testWidgets('signed-out protected deep link redirects safely to entry', (
    tester,
  ) async {
    final container = makeMockContainer();
    addTearDown(container.dispose);
    await _pumpApp(tester, container);

    container.read(goRouterProvider).go(AppRoutes.adminUsers);
    await tester.pumpAndSettle();

    expect(_location(container), AppRoutes.entry);
    expect(find.text('دخول سمو'), findsOneWidget);
    expect(find.text('إدارة المستخدمين'), findsNothing);
  });

  for (final routeCase in <({RoleType role, String path})>[
    (role: RoleType.admin, path: AppRoutes.adminHome),
    (role: RoleType.manager, path: AppRoutes.managerHome),
    (role: RoleType.photographer, path: AppRoutes.photographerHome),
  ]) {
    testWidgets('restored ${routeCase.role.key} routes to its role home', (
      tester,
    ) async {
      final user = UserModel(
        id: 'restored-${routeCase.role.key}',
        fullName: 'مستخدم مستعاد',
        username: 'restored_${routeCase.role.key}',
        defaultRole: routeCase.role,
        roles: [routeCase.role],
      );
      final container = await _restoredContainer(user);

      await _pumpApp(tester, container);

      expect(_location(container), routeCase.path);
      expect(container.read(authControllerProvider).activeRole, routeCase.role);
      expect(find.byType(RoleBasedBottomNav), findsOneWidget);
    });
  }

  for (final roleCase in <({RoleType role, String path})>[
    (role: RoleType.manager, path: AppRoutes.managerHome),
    (role: RoleType.photographer, path: AppRoutes.photographerHome),
    (role: RoleType.admin, path: AppRoutes.adminHome),
  ]) {
    testWidgets('selecting ${roleCase.role.key} opens its home', (
      tester,
    ) async {
      final container = await _restoredContainer(_allOperationalRoles);
      await _pumpApp(tester, container);
      expect(_location(container), AppRoutes.roleSelect);

      await tester.tap(find.text(roleCase.role.nameAr));
      await tester.pumpAndSettle();

      expect(_location(container), roleCase.path);
      expect(
        container.read(authControllerProvider).selectedRole,
        roleCase.role,
      );
    });
  }

  testWidgets('selected role survives navigation and idempotent restoration', (
    tester,
  ) async {
    final container = await _restoredContainer(_allOperationalRoles);
    await _pumpApp(tester, container);
    await tester.tap(find.text(RoleType.manager.nameAr));
    await tester.pumpAndSettle();
    expect(_location(container), AppRoutes.managerHome);

    container.read(goRouterProvider).go(AppRoutes.calendar);
    await tester.pumpAndSettle();
    expect(_location(container), AppRoutes.calendar);
    expect(
      container.read(authControllerProvider).selectedRole,
      RoleType.manager,
    );

    await container.read(authControllerProvider.notifier).initializeSession();
    await tester.pumpAndSettle();
    expect(
      container.read(authControllerProvider).selectedRole,
      RoleType.manager,
    );
    expect(_location(container), AppRoutes.calendar);
  });

  testWidgets('logout action is reachable for every authenticated role', (
    tester,
  ) async {
    for (final role in <RoleType>[
      RoleType.manager,
      RoleType.photographer,
      RoleType.admin,
    ]) {
      final user = UserModel(
        id: 'logout-${role.key}',
        fullName: 'مستخدم خروج',
        username: 'logout_${role.key}',
        defaultRole: role,
        roles: [role],
      );
      final container = await _restoredContainer(user);
      await _pumpApp(tester, container);

      final destination = role == RoleType.photographer ? 'صفحتي' : 'المزيد';
      await tester.tap(find.text(destination));
      await tester.pumpAndSettle();
      expect(find.text('تسجيل الخروج'), findsOneWidget, reason: role.key);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
