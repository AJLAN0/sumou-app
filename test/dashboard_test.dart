// Tests that each role's home tab renders its dashboard.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
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

  testWidgets('manager home shows dashboard stats and quick actions', (
    tester,
  ) async {
    await pumpAs(tester, 'manager');
    expect(find.text('مشاريع نشطة'), findsOneWidget);
    expect(find.text('طلبات إنهاء'), findsOneWidget);
    expect(find.text('إضافة مشروع'), findsOneWidget);
  });

  testWidgets('photographer home shows dashboard content', (tester) async {
    await pumpAs(tester, 'photographer');
    expect(find.text('مشاريعي النشطة'), findsOneWidget);

    // The quick-action button is below the fold; scroll it into view.
    await tester.scrollUntilVisible(
      find.text('تحديث مرحلة'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('تحديث مرحلة'), findsOneWidget);
  });

  testWidgets('admin home shows system overview', (tester) async {
    await pumpAs(tester, 'admin');
    expect(find.text('نظرة عامة على النظام'), findsOneWidget);
    // 'المستخدمون' appears in both the headline strip and the team card.
    expect(find.text('المستخدمون'), findsWidgets);
  });
}
