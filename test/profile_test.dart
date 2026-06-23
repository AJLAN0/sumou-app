// Tests for profile/settings, change password, and logout flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/widgets/widgets.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> pumpAs(WidgetTester tester, String username) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: username, password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  Future<void> openProfile(WidgetTester tester) async {
    await tester.tap(find.text('صفحتي'));
    await tester.pumpAndSettle();
  }

  testWidgets('profile shows current user info', (tester) async {
    await pumpAs(tester, 'photographer');
    await openProfile(tester);

    expect(find.text('نورة الحنايا'), findsOneWidget);
    expect(find.text('@photographer'), findsOneWidget);
    expect(find.text('تغيير كلمة المرور'), findsOneWidget);
  });

  testWidgets('logout confirm returns to entry', (tester) async {
    await pumpAs(tester, 'photographer');
    await openProfile(tester);

    await tester.tap(find.text('تسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(find.text('هل تريد تسجيل الخروج من حسابك؟'), findsOneWidget);

    // Confirm via the sheet button (the account item shares the same text but
    // is a SumouCard, not a SumouButton).
    await tester.tap(find.widgetWithText(SumouButton, 'تسجيل الخروج'));
    await tester.pumpAndSettle();

    expect(find.text('دخول سمو'), findsWidgets);
  });

  testWidgets('change password validates empty fields', (tester) async {
    await pumpAs(tester, 'photographer');
    await openProfile(tester);

    await tester.tap(find.text('تغيير كلمة المرور'));
    await tester.pumpAndSettle();
    expect(find.text('تحديث كلمة المرور'), findsOneWidget);

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('يرجى تعبئة جميع الحقول'), findsOneWidget);
  });

  testWidgets('change password succeeds and returns to profile',
      (tester) async {
    await pumpAs(tester, 'photographer');
    await openProfile(tester);

    await tester.tap(find.text('تغيير كلمة المرور'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).at(0), MockUsers.devPassword);
    await tester.enterText(find.byType(TextField).at(1), 'newpass123');
    await tester.enterText(find.byType(TextField).at(2), 'newpass123');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('تم تغيير كلمة المرور بنجاح'), findsOneWidget);

    // Flush the snackbar auto-dismiss timer before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });
}
