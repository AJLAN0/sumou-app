// Tests for the admin basic project-edit flow (Sprint 5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/widgets/widgets.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

import 'test_helpers.dart';

void main() {
  Future<void> openEdit(WidgetTester tester, String projectName) async {
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

    await scrollAndTapCard(tester, 'كل المشاريع');

    await scrollAndTapCard(
      tester,
      projectName,
      scrollable: find.byType(Scrollable).last,
      scrollDelta: 200,
    );

    await scrollAndTapCard(tester, 'تعديل بيانات المشروع');
  }

  testWidgets('edit screen opens pre-filled', (tester) async {
    await openEdit(tester, 'تصوير ميداني — مهرجان الرياض');
    expect(find.text('تعديل بيانات المشروع'), findsWidgets); // app bar
    // The name field is pre-filled with the project title.
    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsWidgets);
    expect(find.widgetWithText(SumouButton, 'حفظ'), findsOneWidget);
  });

  testWidgets('saving valid data shows a success snackbar', (tester) async {
    await openEdit(tester, 'تصوير ميداني — مهرجان الرياض');
    await tester.tap(find.widgetWithText(SumouButton, 'حفظ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('تم حفظ التغييرات'), findsOneWidget);
  });

  testWidgets('clearing the name shows a validation error', (tester) async {
    await openEdit(tester, 'تصوير ميداني — مهرجان الرياض');
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.pump();
    await tester.tap(find.widgetWithText(SumouButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('الرجاء إدخال اسم المشروع'), findsOneWidget);
  });

  test('updateProjectBasics persists the edited fields', () async {
    final repo = MockProjectRepository();
    final updated = await repo.updateProjectBasics(
      'p-1',
      name: 'مشروع محدث',
      clientName: 'عميل جديد',
      type: ProjectType.social,
      status: ProjectStatus.completed,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 5),
      notes: 'ملاحظة محدثة',
    );
    expect(updated, isNotNull);
    expect(updated!.name, 'مشروع محدث');
    expect(updated.clientName, 'عميل جديد');
    expect(updated.type, ProjectType.social);
    expect(updated.status, ProjectStatus.completed);
    expect(updated.notes, 'ملاحظة محدثة');

    final reloaded = await repo.getProjectById('p-1');
    expect(reloaded!.name, 'مشروع محدث');
    // Team/serial are left untouched.
    expect(reloaded.serial, isNotEmpty);
  });

  test('updateProjectBasics returns null for an unknown project', () async {
    final repo = MockProjectRepository();
    final result = await repo.updateProjectBasics(
      'nope',
      name: 'x',
      clientName: 'y',
      type: ProjectType.field,
      status: ProjectStatus.active,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 2),
    );
    expect(result, isNull);
  });
}
