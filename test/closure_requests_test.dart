// Tests for the manager approve/reject closure-request flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  // Logs in as the manager and opens the "الطلبات" (closure requests) tab.
  Future<void> openRequests(WidgetTester tester) async {
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

    await tester.tap(find.text('الطلبات'));
    await tester.pumpAndSettle();
  }

  testWidgets('manager sees a pending closure request with actions', (
    tester,
  ) async {
    await openRequests(tester);
    expect(find.text('تصوير زواج — العليا'), findsOneWidget);
    expect(find.text('قبول'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);
  });

  testWidgets('approving clears the request from the inbox', (tester) async {
    await openRequests(tester);
    await tester.tap(find.text('قبول'));
    await tester.pumpAndSettle();
    // Confirm in the bottom sheet.
    await tester.tap(find.text('قبول وإنهاء'));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد طلبات إغلاق'), findsOneWidget);
  });

  testWidgets('rejecting requires a reason then clears the request', (
    tester,
  ) async {
    await openRequests(tester);
    await tester.tap(find.text('رفض'));
    await tester.pumpAndSettle();

    // Try to confirm with no reason.
    await tester.tap(find.text('تأكيد الرفض'));
    await tester.pumpAndSettle();
    expect(find.text('الرجاء إدخال سبب الرفض'), findsOneWidget);

    // Enter a reason and confirm.
    await tester.enterText(find.byType(TextField), 'الجودة غير كافية');
    await tester.tap(find.text('تأكيد الرفض'));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد طلبات إغلاق'), findsOneWidget);
  });

  test('approveClosureRequest completes the project', () async {
    final repo = MockProjectRepository();
    final updated = await repo.approveClosureRequest('cr-1');

    expect(updated, isNotNull);
    expect(updated!.status, ClosureRequestStatus.approved);

    final project = await repo.getProjectById('p-4');
    expect(project!.status, ProjectStatus.completed);
    expect(project.stages.every((s) => s.isDone), isTrue);

    // No longer pending → a second approval is rejected.
    expect(await repo.approveClosureRequest('cr-1'), isNull);
  });

  test('rejectClosureRequest returns the project to active', () async {
    final repo = MockProjectRepository();
    final updated = await repo.rejectClosureRequest('cr-1', 'تحتاج تعديلات');

    expect(updated, isNotNull);
    expect(updated!.status, ClosureRequestStatus.rejected);
    expect(updated.rejectReason, 'تحتاج تعديلات');

    final project = await repo.getProjectById('p-4');
    expect(project!.status, ProjectStatus.active);
  });

  test('approve/reject return null for unknown requests', () async {
    final repo = MockProjectRepository();
    expect(await repo.approveClosureRequest('nope'), isNull);
    expect(await repo.rejectClosureRequest('nope', 'x'), isNull);
  });
}
