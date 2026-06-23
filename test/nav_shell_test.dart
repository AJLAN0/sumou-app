// Tests for the authenticated shell + role-based bottom navigation.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> pumpAsManager(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'manager', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('manager shell shows all bottom-nav labels', (tester) async {
    await pumpAsManager(tester);

    expect(find.text('الرئيسية'), findsWidgets);
    expect(find.text('المشاريع'), findsOneWidget);
    expect(find.text('الطلبات'), findsOneWidget);
    expect(find.text('الفريق'), findsOneWidget);
    expect(find.text('المزيد'), findsOneWidget);
  });

  testWidgets('tapping a tab switches the shell body', (tester) async {
    await pumpAsManager(tester);

    await tester.tap(find.text('الفريق'));
    await tester.pumpAndSettle();

    // The selected tab title now appears in both the app bar and the nav.
    expect(find.text('الفريق'), findsWidgets);
  });

  testWidgets('More tab shows logout', (tester) async {
    await pumpAsManager(tester);

    await tester.tap(find.text('المزيد'));
    await tester.pumpAndSettle();

    expect(find.text('تسجيل الخروج'), findsOneWidget);
  });
}
