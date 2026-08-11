// Tests for the project details screen (opened from the manager list).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/data/repositories/project_repository.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'test_helpers.dart';

void main() {
  Future<void> openDetails(
    WidgetTester tester,
    String projectName, {
    ProjectRepository? repository,
  }) async {
    final container = makeMockContainer(projectRepository: repository);
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
    await tester.scrollUntilVisible(
      find.text(projectName),
      300,
      scrollable: find.byType(Scrollable).last,
    );
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

  testWidgets('manager sees only supported actions for an active project', (
    tester,
  ) async {
    await openDetails(tester, 'تصوير ميداني — مهرجان الرياض');
    await tester.scrollUntilVisible(
      find.text('تعديل المشروع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('تعديل المشروع'), findsOneWidget);
    expect(find.text('إنهاء المشروع'), findsNothing);
    // Stage update / assign are merged into تعديل المشروع, not separate actions.
    expect(find.text('تحديث المرحلة'), findsNothing);
    expect(find.text('إسناد مصور'), findsNothing);
  });

  testWidgets('manager sees closure review only for pending closure', (
    tester,
  ) async {
    await openDetails(tester, 'تصوير زواج — العليا');
    await tester.scrollUntilVisible(
      find.text('إنهاء المشروع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('إنهاء المشروع'), findsOneWidget);
    expect(find.text('تعديل المشروع'), findsNothing);
  });

  testWidgets('تعديل المشروع opens the manage hub with merged options', (
    tester,
  ) async {
    await openDetails(tester, 'تصوير ميداني — مهرجان الرياض');
    await tester.scrollUntilVisible(
      find.text('تعديل المشروع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('تعديل المشروع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعديل المشروع'));
    await tester.pumpAndSettle();

    // The hub merges the three project-management flows.
    expect(find.text('تعديل بيانات المشروع'), findsOneWidget);
    expect(find.text('تحديث المرحلة'), findsOneWidget);
    expect(find.text('إدارة الفريق'), findsOneWidget);
  });

  testWidgets('manager sees read-only retained delivery-link state', (
    tester,
  ) async {
    final repository = MockProjectRepository(
      projectLinks: [
        ProjectDeliveryLink(
          id: 'link-approved',
          projectId: 'p-4',
          label: 'رابط معتمد',
          url: 'https://delivery.test/approved',
          isApproved: true,
          isClientVisible: true,
          isActive: true,
          createdAt: DateTime(2026, 8, 1),
        ),
        ProjectDeliveryLink(
          id: 'link-internal',
          projectId: 'p-4',
          label: 'رابط داخلي',
          url: 'https://delivery.test/internal',
          isApproved: false,
          isClientVisible: false,
          isActive: true,
          createdAt: DateTime(2026, 8, 2),
        ),
        ProjectDeliveryLink(
          id: 'link-removed',
          projectId: 'p-4',
          label: 'رابط محتفظ به',
          url: 'https://delivery.test/removed',
          isApproved: false,
          isClientVisible: false,
          isActive: false,
          createdAt: DateTime(2026, 8, 3),
          deletedAt: DateTime(2026, 8, 4),
        ),
      ],
    );
    await openDetails(tester, 'تصوير زواج — العليا', repository: repository);
    expect(find.text('تفاصيل المشروع'), findsOneWidget);
    expect(find.text('تعذّر تحميل المشروع'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('روابط التسليم'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('رابط محتفظ به'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('معتمد'), findsOneWidget);
    expect(find.text('مرئي للعميل'), findsOneWidget);
    expect(find.text('غير معتمد'), findsNWidgets(2));
    expect(find.text('داخلي'), findsNWidgets(2));
    expect(find.text('غير نشط / محذوف'), findsOneWidget);
    expect(find.text('إضافة رابط'), findsNothing);
    expect(find.text('حذف الرابط'), findsNothing);
  });
}
