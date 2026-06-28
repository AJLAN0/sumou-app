// Tests for the admin read-only project details (Sprint 5).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/projects/providers/projects_providers.dart';

void main() {
  Future<void> openAdminDetails(WidgetTester tester, String projectName) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('كل المشاريع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('كل المشاريع'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(projectName),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(projectName));
    await tester.pumpAndSettle();
  }

  testWidgets('admin opens read-only project oversight', (tester) async {
    await openAdminDetails(tester, 'تصوير ميداني — مهرجان الرياض');
    expect(find.text('مراقبة المشروع'), findsOneWidget); // app bar
    expect(find.text('المدير: سعد المطيري'), findsWidgets);

    // The admin action cards are present (scroll to them).
    await tester.scrollUntilVisible(
      find.text('تعديل بيانات المشروع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('تعديل بيانات المشروع'), findsOneWidget);
  });

  testWidgets('team action opens team management', (tester) async {
    await openAdminDetails(tester, 'تصوير ميداني — مهرجان الرياض');
    await tester.scrollUntilVisible(
      find.text('تعديل الفريق'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('تعديل الفريق'));
    await tester.pumpAndSettle();
    expect(find.text('إدارة الفريق'), findsOneWidget);
  });

  test('closureRequestForProjectProvider returns the project request', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // p-4 has a seeded closure request; p-1 has none.
    final req = await container.read(
      closureRequestForProjectProvider('p-4').future,
    );
    expect(req, isNotNull);
    expect(req!.projectId, 'p-4');

    final none = await container.read(
      closureRequestForProjectProvider('p-1').future,
    );
    expect(none, isNull);
  });
}
