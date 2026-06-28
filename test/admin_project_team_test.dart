// Tests for admin team oversight + editing (Sprint 5).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> openTeam(WidgetTester tester, String projectName) async {
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

    await tester.scrollUntilVisible(
      find.text('تعديل الفريق'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('تعديل الفريق'));
    await tester.pumpAndSettle();
  }

  testWidgets('admin opens the team management screen', (tester) async {
    await openTeam(tester, 'تصوير ميداني — مهرجان الرياض');
    expect(find.text('إدارة الفريق'), findsOneWidget); // app bar
    expect(find.text('مدير المشروع'), findsWidgets); // section
    expect(find.text('الفريق الحالي (1)'), findsOneWidget);
    expect(find.text('حفظ التغييرات'), findsOneWidget);
  });

  testWidgets('saving the team shows a success snackbar', (tester) async {
    await openTeam(tester, 'تصوير ميداني — مهرجان الرياض');
    await tester.tap(find.text('حفظ التغييرات'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('تم تحديث فريق المشروع'), findsOneWidget);
  });

  test('setProjectManager reassigns the manager', () async {
    final repo = MockProjectRepository();
    final updated = await repo.setProjectManager(
      'p-1',
      managerId: 'u-multi',
      managerName: 'خالد الزهراني',
    );
    expect(updated, isNotNull);
    expect(updated!.managerId, 'u-multi');
    expect(updated.managerName, 'خالد الزهراني');

    final reloaded = await repo.getProjectById('p-1');
    expect(reloaded!.managerId, 'u-multi');
    // Team is untouched by a manager change.
    expect(reloaded.teamRoles, isNotEmpty);
  });

  test('setProjectManager returns null for an unknown project', () async {
    final repo = MockProjectRepository();
    final result = await repo.setProjectManager(
      'nope',
      managerId: 'u-manager',
      managerName: 'سعد المطيري',
    );
    expect(result, isNull);
  });
}
