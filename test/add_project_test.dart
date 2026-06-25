// Tests for the create-project multi-step flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> openAddProject(WidgetTester tester) async {
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
    await tester.tap(find.text('مشروع جديد'));
    await tester.pumpAndSettle();
  }

  testWidgets('add button opens the create-project flow', (tester) async {
    await openAddProject(tester);
    expect(find.text('الخطوة 1 من 5'), findsOneWidget);
    expect(find.text('المعلومات الأساسية'), findsWidgets);
  });

  testWidgets('shows inline validation on the first step', (tester) async {
    await openAddProject(tester);
    // Try to advance with nothing filled.
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.text('الرجاء إدخال اسم المشروع'), findsOneWidget);
    expect(find.text('الرجاء اختيار نوع المشروع'), findsOneWidget);
    // Still on step 1.
    expect(find.text('الخطوة 1 من 5'), findsOneWidget);
  });

  testWidgets('advances to step 2 then gates on missing dates', (tester) async {
    await openAddProject(tester);

    // Step 1: name + type.
    await tester.enterText(find.byType(TextField).first, 'مشروع تجريبي');
    await tester.tap(find.text('ميداني'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    expect(find.text('الخطوة 2 من 5'), findsOneWidget);

    // Step 2: fill client but leave dates empty, then try to advance.
    await tester.enterText(find.byType(TextField).first, 'عميل تجريبي');
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    expect(find.text('الرجاء اختيار تاريخ البداية'), findsOneWidget);
    expect(find.text('الخطوة 2 من 5'), findsOneWidget);
  });

  test('MockProjectRepository.createProject persists a new project', () async {
    final repo = MockProjectRepository();
    final before = (await repo.getProjects()).length;

    final project = await repo.createProject(
      name: 'تغطية معرض',
      clientName: 'عميل تجريبي',
      managerId: 'u-manager',
      managerName: 'سعد المطيري',
      type: ProjectType.field,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 5),
      notes: 'ملاحظة',
      teamRoles: const [
        ProjectTeamRole(
          id: 'tmp',
          projectId: 'tmp',
          type: 'مصور فوتوغرافي',
          personName: 'نورة الحنايا',
          userId: 'u-photographer',
        ),
      ],
    );

    expect(project.id, isNotEmpty);
    expect(project.serial.startsWith('FLD-'), isTrue);
    expect(project.status, ProjectStatus.active);
    expect(project.stages.length, ProjectStageTitles.threeStage.length);
    expect(project.stages.first.status, ProjectStageStatus.current);
    // Team roles are re-keyed to the new project.
    expect(project.teamRoles.single.projectId, project.id);

    final after = await repo.getProjects();
    expect(after.length, before + 1);
    expect(await repo.getProjectById(project.id), isNotNull);
    final managed = await repo.getProjectsForManager('u-manager');
    expect(managed.any((p) => p.id == project.id), isTrue);
  });

  test('createProject keeps the seed data isolated between instances', () async {
    final a = MockProjectRepository();
    await a.createProject(
      name: 'x',
      clientName: 'y',
      managerId: 'u-manager',
      type: ProjectType.social,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 2),
    );
    final b = MockProjectRepository();
    // A fresh repository must not see the project added to another instance.
    expect((await b.getProjects()).length, MockProjects.projects.length);
  });
}
