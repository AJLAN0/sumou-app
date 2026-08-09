// Tests for the assign-photographers flow.

import 'dart:async';

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
  // Opens a project's details screen, then the assign-photographers screen.
  Future<ProviderContainer> openAssign(
    WidgetTester tester,
    String projectName, {
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
    await tester.tap(find.text(projectName));
    await tester.pumpAndSettle();

    // Team management now lives inside the "تعديل المشروع" hub.
    await tester.scrollUntilVisible(
      find.text('تعديل المشروع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('تعديل المشروع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعديل المشروع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إدارة الفريق'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('opens the assign screen with summary and current team', (
    tester,
  ) async {
    await openAssign(tester, 'تصوير ميداني — مهرجان الرياض');
    expect(find.text('المصورون المتاحون'), findsOneWidget);
    // The project already has one assigned photographer, pre-selected.
    expect(find.text('الفريق المختار (1)'), findsOneWidget);
  });

  testWidgets('requires confirmation before clearing the whole team', (
    tester,
  ) async {
    await openAssign(tester, 'تصوير ميداني — مهرجان الرياض');

    // Remove the pre-selected member, then try to save.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('الفريق المختار (0)'), findsOneWidget);

    await tester.tap(find.text('حفظ الإسناد'));
    await tester.pumpAndSettle();
    expect(find.text('إزالة جميع أعضاء الفريق'), findsOneWidget);
    expect(find.text('حفظ من دون فريق'), findsOneWidget);
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

  testWidgets('uses backend labels, explicit date, and multiple types', (
    tester,
  ) async {
    final repository = _RecordingProjectRepository();
    await openAssign(
      tester,
      'تصوير ميداني — مهرجان الرياض',
      repository: repository,
    );

    expect(find.text('تاريخ الإسناد للمصور الجديد'), findsOneWidget);
    expect(find.text('2026/06/10'), findsWidgets);
    expect(find.text('درون'), findsNothing);
    expect(find.text('تيك توك'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('خالد الزهراني'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('خالد الزهراني'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('تصميم').first,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('تصميم').first);
    await tester.pumpAndSettle();
    expect(find.text('مصور فيديو'), findsWidgets);
    expect(find.text('تصميم'), findsWidgets);

    await tester.tap(find.text('حفظ الإسناد (2)'));
    await tester.pumpAndSettle();
    final selectedTypes = repository.lastAssignedRoles
        .where((role) => role.userId == 'u-multi')
        .map((role) => role.photographerTypeCode);
    expect(selectedTypes, containsAll(<String>['video', 'design']));
  });

  testWidgets('date change reloads candidates and saves the selected date', (
    tester,
  ) async {
    final repository = _RecordingProjectRepository();
    await openAssign(
      tester,
      'تصوير ميداني — مهرجان الرياض',
      repository: repository,
    );

    expect(repository.candidateDates, contains(DateTime(2026, 6, 10)));
    expect(repository.excludeProjectIds, contains('p-1'));

    await _chooseDate(
      tester,
      find.text('2026/06/10').first,
      DateTime(2026, 6, 11),
    );
    expect(repository.candidateDates.last, DateTime(2026, 6, 11));

    await tester.tap(find.text('حفظ الإسناد (1)'));
    await tester.pumpAndSettle();
    expect(repository.assignCalls, 1);
    expect(repository.lastAssignedRoles.single.date, DateTime(2026, 6, 11));
  });

  testWidgets(
    'date change flags a selected photographer that became unavailable',
    (tester) async {
      final repository = _RecordingProjectRepository();
      await openAssign(
        tester,
        'تصوير ميداني — مهرجان الرياض',
        repository: repository,
      );

      await _chooseDate(
        tester,
        find.text('2026/06/10').first,
        DateTime(2026, 8, 10),
      );
      expect(find.text('هذا العضو غير متاح في التاريخ المحدد'), findsOneWidget);

      await tester.tap(find.text('حفظ الإسناد (1)'));
      await tester.pumpAndSettle();
      expect(repository.assignCalls, 0);
    },
  );

  testWidgets('requires an explicit date for every internal assignment', (
    tester,
  ) async {
    final undated = MockProjects.activeField.teamRoles.single;
    final project = MockProjects.activeField.copyWith(
      teamRoles: [
        ProjectTeamRole(
          id: undated.id,
          projectId: undated.projectId,
          teamMemberId: undated.teamMemberId,
          photographerTypeId: undated.photographerTypeId,
          photographerTypeCode: undated.photographerTypeCode,
          type: undated.type,
          personName: undated.personName,
          userId: undated.userId,
          value: undated.value,
        ),
      ],
    );
    final repository = _RecordingProjectRepository(projects: [project]);
    await openAssign(
      tester,
      'تصوير ميداني — مهرجان الرياض',
      repository: repository,
    );

    expect(find.text('اختر التاريخ'), findsOneWidget);
    await tester.tap(find.text('حفظ الإسناد (1)'));
    await tester.pumpAndSettle();
    expect(repository.assignCalls, 0);
    expect(find.text('الإجراء غير متاح حاليًا، حاول لاحقًا'), findsOneWidget);
  });

  testWidgets('save loading guard prevents a duplicate mutation', (
    tester,
  ) async {
    final repository =
        _RecordingProjectRepository()..assignmentBarrier = Completer<void>();
    await openAssign(
      tester,
      'تصوير ميداني — مهرجان الرياض',
      repository: repository,
    );

    final save = find.text('حفظ الإسناد (1)');
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();
    await tester.pump();
    expect(repository.assignCalls, 1);

    repository.assignmentBarrier!.complete();
    await tester.pumpAndSettle();
    expect(repository.assignCalls, 1);
  });

  testWidgets('shows a safe retry state when candidate discovery fails', (
    tester,
  ) async {
    final repository = _RecordingProjectRepository()..candidateFailure = true;
    await openAssign(
      tester,
      'تصوير ميداني — مهرجان الرياض',
      repository: repository,
    );

    expect(find.text('تعذّر تحميل الفريق المتاح بأمان'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.textContaining('SQL'), findsNothing);
  });

  testWidgets('keeps an existing external member visible and preserved', (
    tester,
  ) async {
    final external = ProjectTeamRole(
      id: 'p-1-external-role',
      projectId: 'p-1',
      teamMemberId: 'p-1-external-member',
      photographerTypeId: '10000000-0000-4000-8000-000000000002',
      photographerTypeCode: 'video',
      type: 'مصور فيديو',
      personName: 'مصور خارجي',
      value: 250,
    );
    final project = MockProjects.activeField.copyWith(
      teamRoles: [...MockProjects.activeField.teamRoles, external],
    );
    final repository = _RecordingProjectRepository(projects: [project]);
    await openAssign(
      tester,
      'تصوير ميداني — مهرجان الرياض',
      repository: repository,
    );

    expect(find.text('مصور خارجي'), findsOneWidget);
    expect(find.text('عضو خارجي محفوظ'), findsOneWidget);
    await tester.tap(find.text('حفظ الإسناد (2)'));
    await tester.pumpAndSettle();

    final preserved = repository.lastAssignedRoles.where(
      (role) => role.userId == null,
    );
    expect(preserved, hasLength(1));
    expect(preserved.single.personName, 'مصور خارجي');
    expect(preserved.single.photographerTypeCode, 'video');
    expect(preserved.single.date, isNull);
  });

  testWidgets('keeps unavailable candidate disabled without a reason', (
    tester,
  ) async {
    final repository = _UnavailableCandidateRepository();
    await openAssign(
      tester,
      'تصوير ميداني — مهرجان الرياض',
      repository: repository,
    );

    await tester.scrollUntilVisible(
      find.text('خالد الزهراني'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('غير متاح في هذا التاريخ'), findsOneWidget);
    expect(find.text('محجوز في نفس التاريخ'), findsNothing);
    expect(find.text('لديه إذن في نفس اليوم'), findsNothing);
    await tester.tap(find.text('خالد الزهراني'));
    await tester.pumpAndSettle();
    expect(find.text('الفريق المختار (1)'), findsOneWidget);
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

class _RecordingProjectRepository extends MockProjectRepository {
  _RecordingProjectRepository({super.projects});

  final List<DateTime> candidateDates = [];
  final List<String?> excludeProjectIds = [];
  List<ProjectTeamRole> lastAssignedRoles = const [];
  int assignCalls = 0;
  bool candidateFailure = false;
  Completer<void>? assignmentBarrier;

  @override
  Future<List<AssignableProjectStaff>> getAssignableProjectStaff({
    required DateTime onDate,
    String? excludeProjectId,
  }) async {
    candidateDates.add(onDate);
    excludeProjectIds.add(excludeProjectId);
    if (candidateFailure) throw StateError('hidden backend failure');
    return super.getAssignableProjectStaff(
      onDate: onDate,
      excludeProjectId: excludeProjectId,
    );
  }

  @override
  Future<ProjectModel?> assignTeamRoles(
    String projectId,
    List<ProjectTeamRole> teamRoles,
  ) async {
    assignCalls++;
    lastAssignedRoles = List.unmodifiable(teamRoles);
    await assignmentBarrier?.future;
    return super.assignTeamRoles(projectId, teamRoles);
  }
}

class _UnavailableCandidateRepository extends MockProjectRepository {
  @override
  Future<List<AssignableProjectStaff>> getAssignableProjectStaff({
    required DateTime onDate,
    String? excludeProjectId,
  }) async {
    final candidates = await super.getAssignableProjectStaff(
      onDate: onDate,
      excludeProjectId: excludeProjectId,
    );
    return [
      for (final candidate in candidates)
        AssignableProjectStaff(
          userId: candidate.userId,
          fullName: candidate.fullName,
          photographerTypes: candidate.photographerTypes,
          isAvailable:
              candidate.userId == 'u-multi' ? false : candidate.isAvailable,
        ),
    ];
  }
}
