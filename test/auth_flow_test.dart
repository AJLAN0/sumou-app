// End-to-end auth flow test driving the real screens with isolated auth fakes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/core/widgets/sumou_button.dart';
import 'package:sumou_app/core/widgets/sumou_text_field.dart';
import 'package:sumou_app/data/repositories/auth_repository.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/auth/screens/login_screen.dart';
import 'test_helpers.dart';

const _loginUser = UserModel(
  id: 'synthetic-login-user',
  fullName: 'مستخدم اختباري',
  username: 'synthetic.user',
  defaultRole: RoleType.manager,
  roles: [RoleType.manager],
);

class _LoginTestRepository implements AuthRepository {
  int loginCalls = 0;
  Completer<void>? loginCompleter;
  AuthFailure? failure;
  bool unexpectedFailure = false;

  @override
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    loginCalls++;
    await loginCompleter?.future;
    if (unexpectedFailure) {
      throw StateError(
        'raw network token JWT Authorization hidden@users.sumou.internal',
      );
    }
    final reason = failure;
    if (reason != null) {
      throw AuthException(
        reason,
        'raw password token JWT hidden@users.sumou.internal SQLSTATE',
      );
    }
    return _loginUser;
  }

  @override
  Future<UserModel?> currentUser() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
}

Future<ProviderContainer> _pumpLogin(
  WidgetTester tester,
  _LoginTestRepository repository,
) async {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _fillLogin(
  WidgetTester tester, {
  String username = 'synthetic.user',
  String password = 'Synthetic!Password1',
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), username);
  await tester.enterText(fields.at(1), password);
}

Finder get _loginButton => find.widgetWithText(SumouButton, 'دخول');

void main() {
  Future<void> bootToEntry(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: mockAuthOverrides(), child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('manager logs in and reaches the manager home', (tester) async {
    await bootToEntry(tester);

    await tester.tap(find.text('دخول سمو'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'manager');
    await tester.enterText(find.byType(TextField).at(1), MockUsers.devPassword);
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();

    // Lands on the authenticated shell (manager first tab).
    expect(find.text('الرئيسية'), findsWidgets);
  });

  testWidgets('disabled account is rejected with an error', (tester) async {
    await bootToEntry(tester);

    await tester.tap(find.text('دخول سمو'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'disabled');
    await tester.enterText(find.byType(TextField).at(1), MockUsers.devPassword);
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();

    // Still on the login screen with an error shown.
    expect(find.text('دخول'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  test(
    'empty username and password are rejected before repository calls',
    () async {
      final repository = _LoginTestRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      await controller.login(username: '', password: 'Synthetic!Password1');
      expect(repository.loginCalls, 0);
      expect(
        container.read(authControllerProvider).errorMessage,
        'اسم المستخدم أو كلمة المرور غير صحيحة',
      );

      await controller.login(username: 'synthetic.user', password: '');
      expect(repository.loginCalls, 0);
      expect(
        container.read(authControllerProvider).errorMessage,
        'اسم المستخدم أو كلمة المرور غير صحيحة',
      );
    },
  );

  test(
    'wrong username and password share one generic Arabic error without oracle',
    () async {
      final repository =
          _LoginTestRepository()..failure = AuthFailure.invalidCredentials;
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      await controller.login(
        username: 'unknown.user',
        password: 'Synthetic!Password1',
      );
      final unknownUserError =
          container.read(authControllerProvider).errorMessage;
      await controller.login(
        username: 'synthetic.user',
        password: 'Wrong!Password1',
      );
      final wrongPasswordError =
          container.read(authControllerProvider).errorMessage;

      expect(unknownUserError, 'اسم المستخدم أو كلمة المرور غير صحيحة');
      expect(wrongPasswordError, unknownUserError);
      expect(unknownUserError, matches(RegExp(r'[\u0600-\u06FF]')));
      expect(repository.loginCalls, 2);
    },
  );

  testWidgets(
    'pending login shows loading and rejects rapid duplicate submissions',
    (tester) async {
      final repository =
          _LoginTestRepository()..loginCompleter = Completer<void>();
      await _pumpLogin(tester, repository);
      await _fillLogin(tester);

      await tester.tap(_loginButton);
      await tester.tap(_loginButton);
      await tester.pump();

      expect(repository.loginCalls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final loginButton = find.byWidgetPredicate(
        (widget) => widget is SumouButton && widget.label == 'دخول',
      );
      expect(tester.widget<SumouButton>(loginButton).onPressed, isNull);

      repository.loginCompleter!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('login button recovers after a failed request', (tester) async {
    final repository =
        _LoginTestRepository()..failure = AuthFailure.invalidCredentials;
    await _pumpLogin(tester, repository);
    await _fillLogin(tester);

    await tester.tap(_loginButton);
    await tester.pumpAndSettle();

    expect(repository.loginCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<SumouButton>(_loginButton).onPressed, isNotNull);
  });

  testWidgets('login password visibility toggle changes obscuring', (
    tester,
  ) async {
    await _pumpLogin(tester, _LoginTestRepository());
    final passwordField = find.byType(SumouTextField).at(1);

    expect(tester.widget<SumouTextField>(passwordField).obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('toggle-login-password')));
    await tester.pump();
    expect(tester.widget<SumouTextField>(passwordField).obscureText, isFalse);
    await tester.tap(find.byKey(const ValueKey('toggle-login-password')));
    await tester.pump();
    expect(tester.widget<SumouTextField>(passwordField).obscureText, isTrue);
  });

  testWidgets('login errors never render internal email or access token', (
    tester,
  ) async {
    final repository =
        _LoginTestRepository()..failure = AuthFailure.invalidCredentials;
    await _pumpLogin(tester, repository);
    await _fillLogin(tester);
    await tester.tap(_loginButton);
    await tester.pumpAndSettle();

    final visible = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .join(' ');
    expect(visible, isNot(contains('@users.sumou.internal')));
    expect(visible, isNot(contains('token')));
    expect(visible, isNot(contains('JWT')));
    expect(visible, isNot(contains('Authorization')));
  });

  testWidgets('network failure renders only a safe Arabic error', (
    tester,
  ) async {
    final repository = _LoginTestRepository()..unexpectedFailure = true;
    await _pumpLogin(tester, repository);
    await _fillLogin(tester);
    await tester.tap(_loginButton);
    await tester.pumpAndSettle();

    expect(find.text('حدث خطأ غير متوقع، حاول مرة أخرى'), findsOneWidget);
    expect(find.textContaining('raw network'), findsNothing);
    expect(find.textContaining('token'), findsNothing);
  });

  testWidgets(
    'server and rate-limit failures stay generic and are not wrong-password errors',
    (tester) async {
      final repository =
          _LoginTestRepository()..failure = AuthFailure.loginFailed;
      await _pumpLogin(tester, repository);
      await _fillLogin(tester);
      await tester.tap(_loginButton);
      await tester.pumpAndSettle();

      expect(find.text('تعذّر تسجيل الدخول، حاول مرة أخرى'), findsOneWidget);
      expect(find.text('اسم المستخدم أو كلمة المرور غير صحيحة'), findsNothing);
      expect(find.textContaining('SQLSTATE'), findsNothing);
      expect(repository.loginCalls, 1);
    },
  );
}
