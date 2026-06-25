// Tests for the assign-photographers flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  // Opens a project's details screen, then the assign-photographers screen.
  Future<void> openAssign(WidgetTester tester, String projectName) async {
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

    await tester.scrollUntilVisible(
      find.text('إسناد مصور'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('إسناد مصور'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens the assign screen with summary and current team', (
    tester,
  ) async {
    await openAssign(tester, 'تصوير ميداني — مهرجان الرياض');
    expect(find.text('المصورون المتاحون'), findsOneWidget);
    // The project already has one assigned photographer, pre-selected.
    expect(find.text('الفريق المختار (1)'), findsOneWidget);
  });

  testWidgets('blocks saving when no member is selected', (tester) async {
    await openAssign(tester, 'تصوير ميداني — مهرجان الرياض');

    // Remove the pre-selected member, then try to save.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('الفريق المختار (0)'), findsOneWidget);

    await tester.tap(find.text('حفظ الإسناد'));
    await tester.pumpAndSettle();
    expect(find.text('الرجاء اختيار مصور واحد على الأقل'), findsOneWidget);
  });

  testWidgets('assigning a new member updates the project team', (
    tester,
  ) async {
    await openAssign(tester, 'تصوير ميداني — مهرجان الرياض');

    // Add the second photographer candidate (multi-role user).
    await tester.scrollUntilVisible(
      find.text('خالد الزهراني'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('خالد الزهراني'));
    await tester.pumpAndSettle();
    expect(find.text('الفريق المختار (2)'), findsOneWidget);

    await tester.tap(find.text('حفظ الإسناد (2)'));
    await tester.pumpAndSettle();

    // Back on the details screen, the new member shows under the team.
    expect(find.text('تفاصيل المشروع'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('خالد الزهراني'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('خالد الزهراني'), findsWidgets);
  });

  test('assignTeamRoles replaces and re-keys the team', () async {
    final repo = MockProjectRepository();
    final updated = await repo.assignTeamRoles('p-1', const [
      ProjectTeamRole(
        id: 'tmp',
        projectId: 'tmp',
        type: 'مصور فيديو',
        personName: 'خالد الزهراني',
        userId: 'u-multi',
        value: 800,
      ),
    ]);

    expect(updated, isNotNull);
    expect(updated!.teamRoles.length, 1);
    final role = updated.teamRoles.single;
    expect(role.projectId, 'p-1');
    expect(role.id, 'p-1-r1');
    expect(role.userId, 'u-multi');
    expect(role.value, 800);

    // The change is persisted in the repository.
    final reloaded = await repo.getProjectById('p-1');
    expect(reloaded!.teamRoles.single.personName, 'خالد الزهراني');
  });

  test('assignTeamRoles returns null for an unknown project', () async {
    final repo = MockProjectRepository();
    final result = await repo.assignTeamRoles('does-not-exist', const []);
    expect(result, isNull);
  });
}
