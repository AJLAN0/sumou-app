// Tests for the create-project multi-step flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'test_helpers.dart';

void main() {
  Future<ProviderContainer> openAddProject(
    WidgetTester tester, {
    MockProjectRepository? repository,
  }) async {
    final container = makeMockContainer(
      extra: [
        if (repository != null)
          projectRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
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
    return container;
  }

  testWidgets('add button opens the create-project flow', (tester) async {
    await openAddProject(tester);
    expect(find.text('الخطوة 1 من 4'), findsOneWidget);
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
    expect(find.text('الخطوة 1 من 4'), findsOneWidget);
  });

  testWidgets('advances to step 2 then gates on missing dates', (tester) async {
    await openAddProject(tester);

    // Step 1: name + type.
    await tester.enterText(find.byType(TextField).first, 'مشروع تجريبي');
    await tester.tap(find.text('ميداني'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    expect(find.text('الخطوة 2 من 4'), findsOneWidget);

    // Step 2: fill client but leave dates empty, then try to advance.
    await tester.enterText(find.byType(TextField).first, 'عميل تجريبي');
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    expect(find.text('الرجاء اختيار تاريخ البداية'), findsOneWidget);
    expect(find.text('الخطوة 2 من 4'), findsOneWidget);
  });

  testWidgets('create team uses selected date and backend catalog types', (
    tester,
  ) async {
    final repository = _RecordingCreateRepository();
    await openAddProject(tester, repository: repository);

    await tester.enterText(find.byType(TextField).first, 'مشروع فريق تجريبي');
    await tester.tap(find.text('ميداني'));
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'عميل تجريبي');
    await _chooseDate(
      tester,
      find.text('اختر التاريخ').first,
      DateTime(2026, 8, 11),
    );
    await _chooseDate(
      tester,
      find.text('اختر التاريخ').first,
      DateTime(2026, 8, 12),
    );
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    expect(repository.candidateDates, contains(DateTime(2026, 8, 11)));
    expect(repository.excludeProjectIds, everyElement(isNull));
    expect(find.text('تاريخ الإسناد للمصور الجديد'), findsOneWidget);
    expect(find.text('درون'), findsNothing);
    expect(find.text('تيك توك'), findsNothing);

    await tester.tap(find.text('إضافة عضو للفريق'));
    await tester.pumpAndSettle();
    expect(find.text('مصور فيديو، تصميم'), findsOneWidget);
    await tester.tap(find.text('خالد الزهراني'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تصميم'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ المشروع'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(repository.lastCreatedRoles, hasLength(2));
    expect(
      repository.lastCreatedRoles.map((role) => role.photographerTypeCode),
      containsAll(<String>['video', 'design']),
    );
    expect(repository.lastCreatedRoles.map((role) => role.date).toSet(), {
      DateTime(2026, 8, 11),
    });
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

  test(
    'createProject keeps the seed data isolated between instances',
    () async {
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
    },
  );
}

Future<void> _chooseDate(
  WidgetTester tester,
  Finder trigger,
  DateTime date,
) async {
  await tester.tap(trigger);
  await tester.pumpAndSettle();
  final picker = tester.widget<CalendarDatePicker>(
    find.byType(CalendarDatePicker),
  );
  picker.onDateChanged(date);
  await tester.pump();
  final dialogContext = tester.element(find.byType(DatePickerDialog));
  final confirmLabel = MaterialLocalizations.of(dialogContext).okButtonLabel;
  await tester.tap(find.text(confirmLabel).last);
  await tester.pumpAndSettle();
}

class _RecordingCreateRepository extends MockProjectRepository {
  final List<DateTime> candidateDates = [];
  final List<String?> excludeProjectIds = [];
  List<ProjectTeamRole> lastCreatedRoles = const [];
  int createCalls = 0;

  @override
  Future<List<AssignableProjectStaff>> getAssignableProjectStaff({
    required DateTime onDate,
    String? excludeProjectId,
  }) async {
    candidateDates.add(onDate);
    excludeProjectIds.add(excludeProjectId);
    return super.getAssignableProjectStaff(
      onDate: onDate,
      excludeProjectId: excludeProjectId,
    );
  }

  @override
  Future<ProjectModel> createProject({
    required String name,
    required String clientName,
    required String managerId,
    String? managerName,
    required ProjectType type,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
    String? serial,
    List<ProjectTeamRole> teamRoles = const [],
  }) async {
    createCalls++;
    lastCreatedRoles = List.unmodifiable(teamRoles);
    return super.createProject(
      name: name,
      clientName: clientName,
      managerId: managerId,
      managerName: managerName,
      type: type,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
      serial: serial,
      teamRoles: teamRoles,
    );
  }
}
