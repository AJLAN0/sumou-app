// Tests for the submit-closure-request flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  // Logs in as the photographer, opens a project, opens the closure screen.
  Future<void> openClosure(WidgetTester tester, String projectName) async {
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
    await tester.tap(find.text(projectName));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('طلب إغلاق'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('طلب إغلاق'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens the closure form', (tester) async {
    await openClosure(tester, 'تصوير ميداني — مهرجان الرياض');
    expect(find.text('بيانات التسليم'), findsOneWidget);
    expect(find.text('رابط التسليم'), findsWidgets);
  });

  testWidgets('requires a delivery link', (tester) async {
    await openClosure(tester, 'تصوير ميداني — مهرجان الرياض');
    await tester.tap(find.text('إرسال طلب الإغلاق'));
    await tester.pumpAndSettle();
    expect(find.text('الرجاء إدخال رابط التسليم'), findsOneWidget);
  });

  testWidgets('submitting moves the project to pending closure', (
    tester,
  ) async {
    await openClosure(tester, 'تصوير ميداني — مهرجان الرياض');
    await tester.enterText(
      find.byType(TextField).first,
      'https://delivery.test/p1',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال طلب الإغلاق'));
    await tester.pumpAndSettle();

    // Back on details, the project now shows the pending-approval chip.
    expect(find.text('تفاصيل المشروع'), findsOneWidget);
    expect(find.text('بانتظار الموافقة'), findsWidgets);
  });

  testWidgets('shows a notice when a pending request already exists', (
    tester,
  ) async {
    // p-4 (تصوير زواج — العليا) already has a seeded pending closure request.
    await openClosure(tester, 'تصوير زواج — العليا');
    expect(find.text('يوجد طلب إغلاق قيد المراجعة'), findsOneWidget);
    expect(find.text('إرسال طلب الإغلاق'), findsNothing);
  });

  test(
    'submitClosureRequest creates a pending request and updates project',
    () async {
      final repo = MockProjectRepository();
      final before = (await repo.getClosureRequests()).length;

      final request = await repo.submitClosureRequest(
        projectId: 'p-1',
        submittedBy: 'u-photographer',
        submittedByName: 'نورة الحنايا',
        deliveryLink: 'https://delivery.test/p1',
        notes: 'تم التسليم',
      );

      expect(request, isNotNull);
      expect(request!.status, ClosureRequestStatus.pending);
      expect(request.deliveryLink, 'https://delivery.test/p1');
      expect((await repo.getClosureRequests()).length, before + 1);

      final project = await repo.getProjectById('p-1');
      expect(project!.status, ProjectStatus.pendingClosure);
      expect(project.hasPendingClosure, isTrue);
    },
  );

  test('submitClosureRequest blocks a duplicate pending request', () async {
    final repo = MockProjectRepository();
    // p-4 already has a pending request in the seed data.
    final result = await repo.submitClosureRequest(
      projectId: 'p-4',
      submittedBy: 'u-photographer',
      submittedByName: 'نورة الحنايا',
      deliveryLink: 'https://delivery.test/p4',
    );
    expect(result, isNull);
  });

  test('submitClosureRequest returns null for an unknown project', () async {
    final repo = MockProjectRepository();
    final result = await repo.submitClosureRequest(
      projectId: 'does-not-exist',
      submittedBy: 'u-photographer',
      submittedByName: 'نورة الحنايا',
      deliveryLink: 'https://delivery.test/x',
    );
    expect(result, isNull);
  });
}
