// Tests for the project details screen (opened from the manager list).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> openDetails(WidgetTester tester, String projectName) async {
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

    await tester.tap(find.text('المشاريع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(projectName));
    await tester.pumpAndSettle();
  }

  testWidgets('shows summary and team member', (tester) async {
    await openDetails(tester, 'تصوير ميداني — مهرجان الرياض');
    expect(find.text('تفاصيل المشروع'), findsOneWidget); // app bar
    expect(find.text('مراحل المشروع'), findsOneWidget);

    // Team member is further down; scroll it into view.
    await tester.scrollUntilVisible(
      find.text('نورة الحنايا'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('نورة الحنايا'), findsOneWidget);
  });

  testWidgets('7-stage social project shows all stages', (tester) async {
    await openDetails(tester, 'حملة انستقرام — رمضان');
    // A stage unique to the 7-stage flow.
    expect(find.text('3. كتابة الخطة'), findsOneWidget);
    expect(find.text('7. النشر'), findsOneWidget);
  });

  testWidgets('manager sees permitted action buttons', (tester) async {
    await openDetails(tester, 'تصوير ميداني — مهرجان الرياض');
    // Actions are at the bottom; scroll to them.
    await tester.scrollUntilVisible(
      find.text('إسناد مصور'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('إسناد مصور'), findsOneWidget);
    expect(find.text('تحديث المرحلة'), findsOneWidget);
  });
}
