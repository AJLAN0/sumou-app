// Tests for the stage timeline + update-stage flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/widgets/widgets.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  // Logs in as the manager, opens a project, and opens the update-stage screen.
  Future<void> openUpdateStage(WidgetTester tester, String projectName) async {
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

    final updateStage = find.widgetWithText(SumouButton, 'تحديث المرحلة');
    final detailsScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      updateStage,
      500,
      scrollable: detailsScroll,
    );
    await tester.drag(detailsScroll, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(updateStage);
    await tester.pumpAndSettle();
  }

  testWidgets('opens the update-stage screen with stage options', (
    tester,
  ) async {
    await openUpdateStage(tester, 'تصوير ميداني — مهرجان الرياض');
    // App bar + a 3-stage workflow option.
    expect(find.text('اختر المرحلة الحالية'), findsOneWidget);
    expect(find.text('1. استلام الأوردر'), findsOneWidget);
    expect(find.text('3. تم التسليم'), findsOneWidget);
  });

  testWidgets('selecting a later stage updates the project progress', (
    tester,
  ) async {
    await openUpdateStage(tester, 'تصوير ميداني — مهرجان الرياض');

    // Move the current stage to the final one, then save.
    await tester.tap(find.text('3. تم التسليم'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SumouButton, 'حفظ المرحلة'));
    await tester.pumpAndSettle();

    // Back on the details screen with the new progress (2 of 3 done).
    expect(find.text('تفاصيل المشروع'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
  });

  test('updateProjectStage transitions stages and persists', () async {
    final repo = MockProjectRepository();
    final updated = await repo.updateProjectStage(
      'p-2', // 7-stage social project
      'p-2-s2', // order 2
      notes: 'بدأنا الاجتماع',
      updatedBy: 'u-photographer',
    );

    expect(updated, isNotNull);
    final byOrder = {for (final s in updated!.stages) s.order: s};
    expect(byOrder[1]!.status, ProjectStageStatus.done);
    expect(byOrder[2]!.status, ProjectStageStatus.current);
    expect(byOrder[2]!.notes, 'بدأنا الاجتماع');
    expect(byOrder[2]!.updatedBy, 'u-photographer');
    expect(byOrder[2]!.updatedAt, isNotNull);
    expect(byOrder[3]!.status, ProjectStageStatus.pending);
    expect(byOrder[7]!.status, ProjectStageStatus.pending);

    // Persisted in the repository.
    final reloaded = await repo.getProjectById('p-2');
    expect(reloaded!.currentStage?.order, 2);
  });

  test(
    'updateProjectStage returns null for unknown project or stage',
    () async {
      final repo = MockProjectRepository();
      expect(await repo.updateProjectStage('nope', 'p-1-s1'), isNull);
      expect(await repo.updateProjectStage('p-1', 'no-such-stage'), isNull);
    },
  );
}
