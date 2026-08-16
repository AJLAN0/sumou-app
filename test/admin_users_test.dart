// Tests for admin users CRUD (add / edit / delete).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/core/widgets/widgets.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/data/repositories/user_repository.dart';
import 'package:sumou_app/features/admin/users_screen.dart';
import 'package:sumou_app/features/admin/widgets/admin_chips.dart';
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

  Future<void> openCreateForm(
    WidgetTester tester,
    _RecordingUserRepository repository,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await openUsers(tester, repository: repository);
    await tester.tap(find.text('إضافة مستخدم'));
    await tester.pumpAndSettle();
  }

  Future<void> submitCreate(WidgetTester tester) async {
    final submit = find.widgetWithText(SumouButton, 'إضافة المستخدم');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> pumpUsersScreen(
    WidgetTester tester,
    UserRepository repository, {
    bool settle = true,
  }) async {
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
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
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

  testWidgets(
    'loading failure and explicit retry perform one additional load',
    (tester) async {
      final repository = _ControlledListUserRepository();
      await pumpUsersScreen(tester, repository, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.getUsersCalls, 1);

      repository.firstLoad.completeError(
        const UserRepositoryException(UserRepositoryFailure.loadFailed),
      );
      await tester.pumpAndSettle();

      expect(find.text('تعذّر تحميل المستخدمين'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.textContaining('database-secret'), findsNothing);
      expect(repository.getUsersCalls, 1);

      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();

      expect(repository.getUsersCalls, 2);
      expect(find.text(_adminListUsers.first.fullName), findsOneWidget);
      expect(find.text('تعذّر تحميل المستخدمين'), findsNothing);
    },
  );

  testWidgets(
    'user cards show default and extra roles without private identity fields',
    (tester) async {
      await pumpUsersScreen(tester, MockUserRepository(users: _adminListUsers));

      expect(find.text('أحمد السالم'), findsOneWidget);
      expect(find.text('@ahmad.manager'), findsOneWidget);
      expect(find.text(RoleType.manager.nameAr), findsOneWidget);
      expect(find.text(RoleType.admin.nameAr), findsNWidgets(2));
      expect(find.text('synthetic.internal@auth.invalid'), findsNothing);
      expect(find.textContaining('Synthetic-Temporary'), findsNothing);
      expect(find.textContaining('service_role'), findsNothing);
      expect(find.textContaining('synthetic-access-token'), findsNothing);

      final fieldsBeforeDetails = find.byType(TextFormField).evaluate().length;
      await tester.tap(find.text('أحمد السالم'));
      await tester.pumpAndSettle();

      expect(find.text('الأدوار'), findsOneWidget);
      expect(find.text(RoleType.manager.nameAr), findsNWidgets(2));
      expect(find.text(RoleType.admin.nameAr), findsNWidgets(3));
      expect(find.byType(TextFormField).evaluate().length, fieldsBeforeDetails);
      expect(find.text('synthetic.internal@auth.invalid'), findsNothing);
      expect(find.textContaining('Synthetic-Temporary'), findsNothing);
      expect(find.textContaining('service_role'), findsNothing);
      expect(find.textContaining('synthetic-access-token'), findsNothing);
    },
  );

  testWidgets('full-name and username search return deterministic users', (
    tester,
  ) async {
    await pumpUsersScreen(tester, MockUserRepository(users: _adminListUsers));
    final search = find.byType(TextFormField);

    await tester.enterText(search, 'نورة');
    await tester.pump();
    expect(find.text('نورة الفهد'), findsOneWidget);
    expect(find.text('أحمد السالم'), findsNothing);
    expect(find.text('ليلى المسؤول'), findsNothing);

    await tester.enterText(search, 'layla.admin');
    await tester.pump();
    expect(find.text('ليلى المسؤول'), findsOneWidget);
    expect(find.text('أحمد السالم'), findsNothing);
    expect(find.text('نورة الفهد'), findsNothing);
  });

  testWidgets('status and role filters return deterministic user subsets', (
    tester,
  ) async {
    await pumpUsersScreen(tester, MockUserRepository(users: _adminListUsers));

    Future<void> expectFilter(
      String label, {
      required List<String> visible,
      required List<String> hidden,
    }) async {
      await tester.tap(find.widgetWithText(AdminFilterChip, label));
      await tester.pump();
      for (final name in visible) {
        expect(find.text(name), findsOneWidget, reason: '$label: $name');
      }
      for (final name in hidden) {
        expect(find.text(name), findsNothing, reason: '$label: $name');
      }
    }

    await expectFilter(
      'نشط',
      visible: ['أحمد السالم', 'ليلى المسؤول'],
      hidden: ['نورة الفهد'],
    );
    await expectFilter(
      'غير نشط',
      visible: ['نورة الفهد'],
      hidden: ['أحمد السالم', 'ليلى المسؤول'],
    );
    await expectFilter(
      'المدراء',
      visible: ['أحمد السالم'],
      hidden: ['نورة الفهد', 'ليلى المسؤول'],
    );
    await expectFilter(
      'المصورين',
      visible: ['نورة الفهد'],
      hidden: ['أحمد السالم', 'ليلى المسؤول'],
    );
    await expectFilter(
      'الأدمن',
      visible: ['أحمد السالم', 'ليلى المسؤول'],
      hidden: ['نورة الفهد'],
    );
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
    final copiedValues = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedValues.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
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
    expect(find.textContaining('مرة واحدة فقط'), findsOneWidget);
    await tester.tap(find.text('نسخ'));
    await tester.pump();
    expect(copiedValues, contains('Mock-Temp-Password1!'));
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
    await tester.tap(find.text('نسخ'));
    await tester.pump();
    expect(copiedValues, contains('Mock-Reset-Password1!'));
    expect(repository.getUsersCalls, greaterThan(readsBeforeReset));
    final resetSecret = repository.lastResetSecret!;
    await tester.tap(find.widgetWithText(SumouButton, 'تم'));
    await tester.pumpAndSettle();
    expect(resetSecret.isCleared, isTrue);
    expect(find.text('Mock-Reset-Password1!'), findsNothing);
  });

  testWidgets('create validates required name and username syntax locally', (
    tester,
  ) async {
    final repository = _RecordingUserRepository();
    await openCreateForm(tester, repository);
    final name = _formField('الاسم الكامل');
    final username = _formField('اسم المستخدم');

    await tester.enterText(name, 'مستخدم اختبار');
    await submitCreate(tester);
    expect(find.text('اسم المستخدم مطلوب'), findsOneWidget);
    expect(repository.provisionCalls, 0);

    for (final invalid in ['a', 'a' * 51, 'bad user!']) {
      await tester.enterText(username, invalid);
      await submitCreate(tester);
      expect(repository.provisionCalls, 0);
    }

    await tester.enterText(name, '   ');
    await tester.enterText(username, 'valid.user');
    await submitCreate(tester);
    expect(repository.provisionCalls, 0);
  });

  testWidgets('create normalizes username and preserves role invariants', (
    tester,
  ) async {
    final repository = _RecordingUserRepository();
    await openCreateForm(tester, repository);
    await tester.enterText(_formField('الاسم الكامل'), 'مستخدم اختبار');
    await tester.enterText(_formField('اسم المستخدم'), '  TEST.User  ');
    await submitCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.provisionCalls, 1);
    expect(repository.lastUsername, 'test.user');
    expect(repository.lastRoles, contains(RoleType.manager));
    expect(repository.lastRoles!.toSet().length, repository.lastRoles!.length);
    expect(repository.lastDefaultRole, RoleType.manager);
    expect(repository.lastRoles, contains(repository.lastDefaultRole));
  });

  testWidgets('photographer requires unique allowlisted type selections', (
    tester,
  ) async {
    final repository = _RecordingUserRepository();
    await openCreateForm(tester, repository);
    await tester.enterText(_formField('الاسم الكامل'), 'مصور اختبار');
    await tester.enterText(_formField('اسم المستخدم'), 'photo.user');
    await tester.ensureVisible(find.text('مصور').last);
    await tester.tap(find.text('مصور').last);
    await tester.pump();
    await submitCreate(tester);
    expect(find.text('اختر نوع تصوير واحداً على الأقل للمصور'), findsOneWidget);
    expect(repository.provisionCalls, 0);

    for (final label in ['تصوير', 'فيديو', 'إنستغرام', 'تصميم']) {
      await tester.tap(find.text(label));
    }
    await submitCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.provisionCalls, 1);
    expect(
      repository.lastRoles,
      containsAll([RoleType.manager, RoleType.photographer]),
    );
    expect(repository.lastRoles!.toSet().length, repository.lastRoles!.length);
    expect(
      repository.lastPhotoTypes,
      containsAll(['photo', 'video', 'instagram', 'design']),
    );
    expect(
      repository.lastPhotoTypes!.toSet().length,
      repository.lastPhotoTypes!.length,
    );
  });

  testWidgets('create form excludes Finance roles and Finance permission', (
    tester,
  ) async {
    await openCreateForm(tester, _RecordingUserRepository());

    expect(find.text(RoleType.finance.nameAr), findsNothing);
    expect(find.text(RoleType.weddingFinance.nameAr), findsNothing);
    expect(find.textContaining('إدارة المالية'), findsNothing);
  });

  testWidgets('pending create locks submit and deduplicates requests', (
    tester,
  ) async {
    final repository =
        _RecordingUserRepository()
          ..provisionCompleter = Completer<UserProvisioningResult>();
    await openCreateForm(tester, repository);
    await tester.enterText(_formField('الاسم الكامل'), 'مستخدم اختبار');
    await tester.enterText(_formField('اسم المستخدم'), 'pending.user');
    final submit = find.widgetWithText(SumouButton, 'إضافة المستخدم');
    await tester.ensureVisible(submit);

    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(repository.provisionCalls, 1);
    expect(
      tester.widget<SumouButton>(find.byType(SumouButton).last).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.provisionCompleter!.complete(
      UserProvisioningResult(
        userId: 'created-user',
        temporaryPassword: OneTimePassword('Synthetic-Temp1!'),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('failed creation never displays a temporary password', (
    tester,
  ) async {
    final repository =
        _RecordingUserRepository()
          ..provisionFailure = UserRepositoryFailure.createFailed;
    await openCreateForm(tester, repository);
    await tester.enterText(_formField('الاسم الكامل'), 'مستخدم اختبار');
    await tester.enterText(_formField('اسم المستخدم'), 'failed.user');
    await submitCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.provisionCalls, 1);
    expect(find.text('تعذّر إنشاء المستخدم، حاول مرة أخرى'), findsOneWidget);
    expect(find.textContaining('Synthetic-Temp'), findsNothing);
    expect(find.textContaining('كلمة المرور المؤقتة هذه'), findsNothing);
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

  testWidgets('reset is unavailable to a non-admin even with permission', (
    tester,
  ) async {
    const manager = UserModel(
      id: 'u-manager-only',
      fullName: 'مدير مشاريع',
      username: 'manager_only',
      defaultRole: RoleType.manager,
      roles: [RoleType.manager],
      permissions: FeaturePermissions(canManageUsers: true),
    );
    final repository = _RecordingUserRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith(
          (_) => MockAuthRepository(
            accounts: const [
              MockAccount(user: manager, password: MockUsers.devPassword),
            ],
          ),
        ),
        userRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: manager.username, password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: UsersScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();

    final reset = find.widgetWithText(SumouButton, 'إعادة تعيين كلمة المرور');
    expect(tester.widget<SumouButton>(reset).onPressed, isNull);
    expect(repository.resetCalls, 0);
  });

  testWidgets('reset cancel performs zero repository requests', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository = _RecordingUserRepository();
    await openUsers(tester, repository: repository);
    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة تعيين كلمة المرور'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(repository.resetCalls, 0);
  });

  testWidgets('pending reset deduplicates confirmation submissions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository =
        _RecordingUserRepository()
          ..resetCompleter = Completer<UserPasswordResetResult>();
    await openUsers(tester, repository: repository);
    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة تعيين كلمة المرور'));
    await tester.pumpAndSettle();
    final confirm = find.text('إعادة التعيين');
    await tester.ensureVisible(confirm);

    await tester.tap(confirm);
    await tester.pump();

    expect(repository.resetCalls, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('سعد المطيري'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final pendingReset = find.byWidgetPredicate(
      (widget) =>
          widget is SumouButton && widget.label == 'إعادة تعيين كلمة المرور',
    );
    expect(tester.widget<SumouButton>(pendingReset).onPressed, isNull);
    await tester.tap(pendingReset, warnIfMissed: false);
    await tester.pump();
    expect(repository.resetCalls, 1);

    repository.resetCompleter!.complete(
      UserPasswordResetResult(
        userId: repository.lastResetUserId!,
        mustChangePassword: true,
        temporaryPassword: OneTimePassword('Synthetic-Reset1!'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Synthetic-Reset1!'), findsOneWidget);
    await tester.tap(find.widgetWithText(SumouButton, 'تم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
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

const _adminListUsers = <UserModel>[
  UserModel(
    id: 'list-manager-admin',
    fullName: 'أحمد السالم',
    username: 'ahmad.manager',
    email: 'synthetic.internal@auth.invalid',
    defaultRole: RoleType.manager,
    roles: [RoleType.manager, RoleType.admin],
  ),
  UserModel(
    id: 'list-photographer',
    fullName: 'نورة الفهد',
    username: 'noura.photo',
    defaultRole: RoleType.photographer,
    roles: [RoleType.photographer],
    active: false,
  ),
  UserModel(
    id: 'list-admin',
    fullName: 'ليلى المسؤول',
    username: 'layla.admin',
    defaultRole: RoleType.admin,
    roles: [RoleType.admin],
  ),
];

class _ControlledListUserRepository extends MockUserRepository {
  final Completer<List<UserModel>> firstLoad = Completer<List<UserModel>>();
  int getUsersCalls = 0;

  @override
  Future<List<UserModel>> getUsers() {
    getUsersCalls++;
    if (getUsersCalls == 1) return firstLoad.future;
    return Future<List<UserModel>>.value(_adminListUsers);
  }
}

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

class _RecordingUserRepository extends MockUserRepository {
  int provisionCalls = 0;
  int resetCalls = 0;
  String? lastUsername;
  RoleType? lastDefaultRole;
  List<RoleType>? lastRoles;
  List<String>? lastPhotoTypes;
  String? lastResetUserId;
  Completer<UserProvisioningResult>? provisionCompleter;
  Completer<UserPasswordResetResult>? resetCompleter;
  UserRepositoryFailure? provisionFailure;

  @override
  Future<List<StaffPhotoTypeOption>> getAvailablePhotoTypes() async => const [
    StaffPhotoTypeOption(code: 'photo', nameAr: 'تصوير'),
    StaffPhotoTypeOption(code: 'video', nameAr: 'فيديو'),
    StaffPhotoTypeOption(code: 'instagram', nameAr: 'إنستغرام'),
    StaffPhotoTypeOption(code: 'design', nameAr: 'تصميم'),
  ];

  @override
  Future<UserProvisioningResult> provisionUser({
    required String fullName,
    required String username,
    required RoleType defaultRole,
    required List<RoleType> roles,
    List<String> photographerTypeCodes = const [],
    Map<AppFeature, bool> permissionOverrides = const {},
  }) async {
    provisionCalls++;
    lastUsername = username;
    lastDefaultRole = defaultRole;
    lastRoles = List.of(roles);
    lastPhotoTypes = List.of(photographerTypeCodes);
    final completer = provisionCompleter;
    if (completer != null) return completer.future;
    final failure = provisionFailure;
    if (failure != null) throw UserRepositoryException(failure);
    return UserProvisioningResult(
      userId: 'synthetic-created-user',
      temporaryPassword: OneTimePassword('Synthetic-Temp1!'),
    );
  }

  @override
  Future<UserPasswordResetResult> resetPassword(String userId) async {
    resetCalls++;
    lastResetUserId = userId;
    final completer = resetCompleter;
    if (completer != null) return completer.future;
    return UserPasswordResetResult(
      userId: userId,
      mustChangePassword: true,
      temporaryPassword: OneTimePassword('Synthetic-Reset1!'),
    );
  }
}
