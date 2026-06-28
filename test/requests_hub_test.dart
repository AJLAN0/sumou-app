// Tests for the Sprint 3 requests hub (manager + photographer).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> loginAndOpenRequests(
    WidgetTester tester,
    String username,
  ) async {
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
    await tester.tap(find.text('الطلبات'));
    await tester.pumpAndSettle();
  }

  testWidgets('manager hub shows categories and opens the closure inbox', (
    tester,
  ) async {
    await loginAndOpenRequests(tester, 'manager');
    // Hub categories.
    expect(find.text('طلبات الإغلاق'), findsOneWidget);
    expect(find.text('طلبات التصوير'), findsOneWidget); // placeholder

    // Tapping the closure category opens the inbox (one pending request).
    await tester.tap(find.text('طلبات الإغلاق'));
    await tester.pumpAndSettle();
    expect(find.text('تصوير زواج — العليا'), findsOneWidget);
    expect(find.text('قبول'), findsOneWidget);
  });

  testWidgets('photographer sees their submitted closure requests', (
    tester,
  ) async {
    await loginAndOpenRequests(tester, 'photographer');
    // The photographer submitted the seeded request on p-4.
    expect(find.text('طلبات الإغلاق'), findsOneWidget); // section header
    expect(find.text('تصوير زواج — العليا'), findsWidgets);
    expect(find.text('بانتظار الموافقة'), findsWidgets); // status chip
  });
}
