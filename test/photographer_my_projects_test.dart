// Tests for the photographer "my projects" (مشاريعي) flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  // Logs in as the photographer and opens the "مشاريعي" tab.
  Future<void> openMyProjects(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'photographer', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('مشاريعي'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the photographer\'s assigned projects with role', (
    tester,
  ) async {
    await openMyProjects(tester);
    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsOneWidget);
    // The viewer's own role on the project is shown.
    expect(find.text('دوري: مصور فوتوغرافي'), findsWidgets);
  });

  testWidgets('filters by type (سوشال)', (tester) async {
    await openMyProjects(tester);
    // 'سوشال' only appears as the filter chip (type label is 'سوشيال').
    await tester.tap(find.text('سوشال'));
    await tester.pumpAndSettle();

    expect(find.text('حملة انستقرام — رمضان'), findsOneWidget);
    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsNothing);
  });

  testWidgets('shows an empty-result state when search matches nothing', (
    tester,
  ) async {
    await openMyProjects(tester);
    await tester.enterText(find.byType(TextField).first, 'zzz-nomatch');
    await tester.pumpAndSettle();
    expect(find.text('لا توجد نتائج'), findsOneWidget);
  });

  testWidgets('tapping a project opens the details screen', (tester) async {
    await openMyProjects(tester);
    await tester.tap(find.text('تصوير ميداني — مهرجان الرياض'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل المشروع'), findsOneWidget);
  });

  test('getProjectsForPhotographer returns only assigned projects', () async {
    final repo = MockProjectRepository();
    final mine = await repo.getProjectsForPhotographer('u-photographer');
    expect(mine, isNotEmpty);
    expect(mine.every((p) => p.isAssignedTo('u-photographer')), isTrue);

    // A user who is not a team member on any project sees none.
    final none = await repo.getProjectsForPhotographer('u-manager');
    expect(none, isEmpty);
  });
}
