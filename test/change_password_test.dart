import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/app/router.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/core/widgets/sumou_button.dart';
import 'package:sumou_app/data/repositories/auth_repository.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/profile/password_policy.dart';

const _forcedManager = UserModel(
  id: 'u-forced-manager',
  fullName: 'مستخدم مؤقت',
  username: 'forced_manager',
  defaultRole: RoleType.manager,
  roles: [RoleType.manager],
  mustChangePassword: true,
);

const _forcedMulti = UserModel(
  id: 'u-forced-multi',
  fullName: 'مستخدم متعدد',
  username: 'forced_multi',
  defaultRole: RoleType.manager,
  roles: [RoleType.manager, RoleType.photographer],
  mustChangePassword: true,
);

class _ScreenAuthRepository implements AuthRepository {
  _ScreenAuthRepository(this.loginUser);

  final UserModel loginUser;
  UserModel? _session;
  int changeCalls = 0;
  Completer<void>? changeCompleter;
  AuthFailure? changeFailure;

  @override
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    _session = loginUser;
    return loginUser;
  }

  @override
  Future<UserModel?> currentUser() async => _session;

  @override
  Future<void> logout() async {
    _session = null;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changeCalls++;
    await changeCompleter?.future;
    final failure = changeFailure;
    if (failure != null) throw AuthException(failure);
  }
}

Future<ProviderContainer> _pumpForced(
  WidgetTester tester,
  UserModel user, {
  _ScreenAuthRepository? repository,
}) async {
  final repo = repository ?? _ScreenAuthRepository(user);
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWith((ref) => repo)],
  );
  addTearDown(container.dispose);
  await container
      .read(authControllerProvider.notifier)
      .login(username: user.username, password: 'Current!Pass1');
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SumouApp()),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _fillValidForm(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Current!Pass1');
  await tester.enterText(fields.at(1), 'N3w!Password2');
  await tester.enterText(fields.at(2), 'N3w!Password2');
  await tester.drag(find.byType(ListView), const Offset(0, -500));
  await tester.pumpAndSettle();
  final save = find.widgetWithText(SumouButton, 'حفظ');
  expect(save, findsOneWidget);
}

void main() {
  group('PasswordPolicy', () {
    test('accepts the 12 and 72 character boundaries', () {
      expect(
        PasswordPolicy.validate(
          currentPassword: 'Different!Pass1',
          newPassword: 'Aa1!abcdefgh',
        ).isValid,
        isTrue,
      );
      expect(
        PasswordPolicy.validate(
          currentPassword: 'Different!Pass1',
          newPassword: 'Aa1!${'x' * 68}',
        ).isValid,
        isTrue,
      );
    });

    test('rejects length, missing classes, edge whitespace, and equality', () {
      final tooShort = PasswordPolicy.validate(
        currentPassword: 'Other!Pass1',
        newPassword: 'Aa1!short',
      );
      expect(tooShort.failures, contains(PasswordPolicyFailure.tooShort));

      final tooLong = PasswordPolicy.validate(
        currentPassword: 'Other!Pass1',
        newPassword: 'Aa1!${'x' * 69}',
      );
      expect(tooLong.failures, contains(PasswordPolicyFailure.tooLong));

      final missing = PasswordPolicy.validate(
        currentPassword: 'Other!Pass1',
        newPassword: 'abcdefghijkl',
      );
      expect(
        missing.failures,
        containsAll([
          PasswordPolicyFailure.missingUppercase,
          PasswordPolicyFailure.missingDigit,
          PasswordPolicyFailure.missingSymbol,
        ]),
      );

      final whitespace = PasswordPolicy.validate(
        currentPassword: 'Other!Pass1',
        newPassword: ' Aa1!abcdefgh',
      );
      expect(
        whitespace.failures,
        contains(PasswordPolicyFailure.surroundingWhitespace),
      );

      final same = PasswordPolicy.validate(
        currentPassword: 'Same!Password1',
        newPassword: 'Same!Password1',
      );
      expect(same.failures, contains(PasswordPolicyFailure.matchesCurrent));
    });
  });

  testWidgets('forced success routes a multi-role user to role selection', (
    tester,
  ) async {
    await _pumpForced(tester, _forcedMulti);
    await _fillValidForm(tester);

    await tester.tap(find.widgetWithText(SumouButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('اختيار الدور'), findsWidgets);
  });

  testWidgets('forced success routes a single-role user to role home', (
    tester,
  ) async {
    await _pumpForced(tester, _forcedManager);
    await _fillValidForm(tester);

    await tester.tap(find.widgetWithText(SumouButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('الرئيسية'), findsWidgets);
    expect(find.text('تحديث كلمة المرور مطلوب'), findsNothing);
  });

  testWidgets('forced screen blocks route skipping and allows logout', (
    tester,
  ) async {
    final container = await _pumpForced(tester, _forcedManager);

    container.read(goRouterProvider).go(AppRoutes.managerHome);
    await tester.pumpAndSettle();
    expect(find.text('تحديث كلمة المرور مطلوب'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('forced-password-logout')));
    await tester.pumpAndSettle();
    expect(find.text('دخول سمو'), findsWidgets);
    expect(container.read(authControllerProvider).isAuthenticated, isFalse);
  });

  testWidgets('inline policy feedback and hide/show controls are present', (
    tester,
  ) async {
    await _pumpForced(tester, _forcedManager);

    expect(find.text('متطلبات كلمة المرور'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('toggle-current-password')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('toggle-new-password')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('toggle-confirm-password')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).at(1), 'Aa1!abcdefgh');
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testWidgets('loading prevents a second password-change submission', (
    tester,
  ) async {
    final repository = _ScreenAuthRepository(_forcedManager)
      ..changeCompleter = Completer<void>();
    await _pumpForced(tester, _forcedManager, repository: repository);
    await _fillValidForm(tester);
    final save = find.widgetWithText(SumouButton, 'حفظ');

    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();
    expect(repository.changeCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.changeCompleter!.complete();
    await tester.pumpAndSettle();
  });
}
