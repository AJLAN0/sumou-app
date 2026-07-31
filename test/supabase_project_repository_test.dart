import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/project_repository.dart';
import 'package:sumou_app/data/repositories/supabase/project_gateway.dart';
import 'package:sumou_app/data/repositories/supabase/supabase_project_repository.dart';

const projectId = '11111111-1111-4111-8111-111111111111';
const secondProjectId = '22222222-2222-4222-8222-222222222222';
const thirdProjectId = '33333333-3333-4333-8333-333333333333';
const managerId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const secondManagerId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const memberId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const externalMemberId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const photographerId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const photoTypeId = '10000000-0000-4000-8000-000000000001';
const videoTypeId = '10000000-0000-4000-8000-000000000002';
const firstTypeLinkId = '20000000-0000-4000-8000-000000000001';
const secondTypeLinkId = '20000000-0000-4000-8000-000000000002';

void main() {
  group('SupabaseProjectRepository visible reads', () {
    test('empty visible project query returns an empty list', () async {
      final gateway = FakeProjectGateway();
      final repository = SupabaseProjectRepository.withGateway(gateway);

      expect(await repository.getProjects(), isEmpty);
      expect(gateway.stagesCalls, 0);
      expect(gateway.teamMemberCalls, 0);
      expect(gateway.teamTypeCalls, 0);
      expect(gateway.profileCalls, 0);
    });

    test('strictly parses a project and its UTC timestamps', () async {
      final gateway = validGateway();
      final repository = SupabaseProjectRepository.withGateway(gateway);

      final project = (await repository.getProjects()).single;

      expect(project.id, projectId);
      expect(project.serial, 'FLD-A1B2-C3');
      expect(project.type, ProjectType.field);
      expect(project.status, ProjectStatus.active);
      expect(project.managerName, 'مدير المشروع');
      expect(project.createdAt!.isUtc, isTrue);
      expect(project.updatedAt!.isUtc, isTrue);
    });

    test('sorts one project with multiple stages by strict order', () async {
      final gateway = validGateway();
      gateway.stages = gateway.stages.reversed.toList();
      final repository = SupabaseProjectRepository.withGateway(gateway);

      final stages = (await repository.getProjects()).single.stages;

      expect(stages.map((stage) => stage.order), [1, 2, 3]);
      expect(stages.map((stage) => stage.title), ProjectStageTitles.threeStage);
    });

    test(
      'fans one member with multiple active types without duplicating metadata',
      () async {
        final gateway = validGatewayWithTeam();
        gateway.teamTypes = [
          validTeamType(),
          validTeamType(
            id: secondTypeLinkId,
            typeId: videoTypeId,
            code: 'video',
            nameAr: 'مصور فيديو',
          ),
        ];
        final repository = SupabaseProjectRepository.withGateway(gateway);

        final roles = (await repository.getProjects()).single.teamRoles;

        expect(roles, hasLength(2));
        expect(roles.map((role) => role.type), [
          'مصور فوتوغرافي',
          'مصور فيديو',
        ]);
        expect(roles.map((role) => role.value), [250, 0]);
      },
    );

    test('parses an external member with a null user id', () async {
      final gateway = validGateway();
      gateway.teamMembers = [
        validTeamMember(id: externalMemberId, userId: null, name: 'مصور خارجي'),
      ];
      gateway.teamTypes = [validTeamType(member: externalMemberId)];
      final repository = SupabaseProjectRepository.withGateway(gateway);

      final role = (await repository.getProjects()).single.teamRoles.single;

      expect(role.userId, isNull);
      expect(role.personName, 'مصور خارجي');
    });

    test('accepts assigned-staff partial team visibility', () async {
      final gateway = validGatewayWithTeam();
      final repository = SupabaseProjectRepository.withGateway(gateway);

      final project = (await repository.getProjects()).single;

      expect(project.teamRoles, hasLength(1));
      expect(project.teamRoles.single.userId, photographerId);
    });

    test('leaves a hidden manager profile name nullable', () async {
      final gateway = validGateway()..profiles = const [];
      final repository = SupabaseProjectRepository.withGateway(gateway);

      final project = (await repository.getProjects()).single;

      expect(project.managerName, isNull);
      expect(project.teamRoles, isEmpty);
    });

    test('maps every exact project and stage enum value', () async {
      const statuses = <String, ProjectStatus>{
        'active': ProjectStatus.active,
        'completed': ProjectStatus.completed,
        'pending_closure': ProjectStatus.pendingClosure,
        'rejected': ProjectStatus.rejected,
        'approved': ProjectStatus.approved,
        'in_progress': ProjectStatus.inProgress,
        'delivered': ProjectStatus.delivered,
      };
      for (final entry in statuses.entries) {
        final gateway = validGateway(project: validProject(status: entry.key));
        expect(
          (await SupabaseProjectRepository.withGateway(gateway).getProjects())
              .single
              .status,
          entry.value,
        );
      }

      const types = <String, ProjectType>{
        'field': ProjectType.field,
        'social': ProjectType.social,
        'wedding': ProjectType.wedding,
      };
      for (final entry in types.entries) {
        final gateway = validGateway(
          project: validProject(
            type: entry.key,
            serial: switch (entry.key) {
              'social' => 'SOC-A1B2-C3',
              'wedding' => 'WED-A1B2-C3',
              _ => 'FLD-A1B2-C3',
            },
          ),
          type: entry.value,
        );
        expect(
          (await SupabaseProjectRepository.withGateway(gateway).getProjects())
              .single
              .type,
          entry.value,
        );
      }

      final gateway = validGateway();
      gateway.stages = validStages(
        statuses: const ['done', 'current', 'pending'],
      );
      final stages =
          (await SupabaseProjectRepository.withGateway(gateway).getProjects())
              .single
              .stages;
      expect(stages.map((stage) => stage.status), [
        ProjectStageStatus.done,
        ProjectStageStatus.current,
        ProjectStageStatus.pending,
      ]);
    });

    test('rejects unknown project and stage enum values', () async {
      for (final gateway in [
        validGateway(project: validProject(type: 'other')),
        validGateway(project: validProject(status: 'unknown')),
        validGateway()..stages.first['status'] = 'unknown',
      ]) {
        await expectInvalidData(
          SupabaseProjectRepository.withGateway(gateway).getProjects(),
        );
      }
    });

    test('rejects malformed UUIDs', () async {
      final gateway = validGateway(
        project: validProject()..['manager_id'] = 'not-a-uuid',
      );

      await expectInvalidData(
        SupabaseProjectRepository.withGateway(gateway).getProjects(),
      );
      await expectLater(
        SupabaseProjectRepository.withGateway(
          validGateway(),
        ).getProjectById('bad-id'),
        throwsReason(ProjectRepositoryFailure.invalidInput),
      );
    });

    test('rejects malformed dates and timestamps', () async {
      for (final gateway in [
        validGateway(project: validProject()..['start_date'] = '2026-02-30'),
        validGateway(
          project: validProject()..['created_at'] = '2026-07-14T12:00:00',
        ),
      ]) {
        await expectInvalidData(
          SupabaseProjectRepository.withGateway(gateway).getProjects(),
        );
      }
    });

    test(
      'preserves date-only calendar values without timezone shifting',
      () async {
        final gateway = validGateway(
          project: validProject(startDate: '2026-01-01', endDate: '2026-12-31'),
        );

        final project =
            (await SupabaseProjectRepository.withGateway(gateway).getProjects())
                .single;

        expect(project.startDate, DateTime(2026, 1, 1));
        expect(project.endDate, DateTime(2026, 12, 31));
        expect(project.startDate.isUtc, isFalse);
        expect(project.startDate.hour, 0);
        expect(project.endDate.hour, 0);
      },
    );

    test('rejects duplicate project IDs', () async {
      final gateway =
          validGateway()..projects = [validProject(), validProject()];

      await expectInvalidData(
        SupabaseProjectRepository.withGateway(gateway).getProjects(),
      );
    });

    test('rejects duplicate stage IDs and orders', () async {
      final duplicateId = validGateway();
      duplicateId.stages[1]['id'] = duplicateId.stages.first['id'];
      final duplicateOrder = validGateway();
      duplicateOrder.stages[1]['stage_order'] = 1;

      await expectInvalidData(
        SupabaseProjectRepository.withGateway(duplicateId).getProjects(),
      );
      await expectInvalidData(
        SupabaseProjectRepository.withGateway(duplicateOrder).getProjects(),
      );
    });

    test('rejects duplicate member IDs and assignments', () async {
      final duplicateId = validGatewayWithTeam();
      duplicateId.teamMembers.add(validTeamMember());
      final duplicateUser = validGatewayWithTeam();
      duplicateUser.teamMembers.add(
        validTeamMember(id: externalMemberId, userId: photographerId),
      );

      await expectInvalidData(
        SupabaseProjectRepository.withGateway(duplicateId).getProjects(),
      );
      await expectInvalidData(
        SupabaseProjectRepository.withGateway(duplicateUser).getProjects(),
      );
    });

    test('rejects duplicate photographer types for one member', () async {
      final gateway = validGatewayWithTeam();
      gateway.teamTypes.add(
        validTeamType(id: secondTypeLinkId, typeId: photoTypeId),
      );

      await expectInvalidData(
        SupabaseProjectRepository.withGateway(gateway).getProjects(),
      );
    });

    test('rejects inactive or malformed joined photographer types', () async {
      final inactive = validGatewayWithTeam();
      (inactive.teamTypes.single['photographer_type']
              as Map<String, dynamic>)['is_active'] =
          false;
      final malformed = validGatewayWithTeam();
      malformed.teamTypes.single['photographer_type'] = null;

      await expectInvalidData(
        SupabaseProjectRepository.withGateway(inactive).getProjects(),
      );
      await expectInvalidData(
        SupabaseProjectRepository.withGateway(malformed).getProjects(),
      );
    });

    test('excludes inactive and soft-deleted project rows', () async {
      final gateway =
          validGateway()
            ..projects = [
              validProject(),
              validProject(id: secondProjectId)..['is_active'] = false,
              validProject(id: thirdProjectId)
                ..['deleted_at'] = '2026-07-14T12:00:00+03:00',
            ];

      final projects =
          await SupabaseProjectRepository.withGateway(gateway).getProjects();

      expect(projects.map((project) => project.id), [projectId]);
    });

    test('maps SDK and network failures to one safe load failure', () async {
      final gateway = FakeProjectGateway()..throwOnProjects = true;
      final repository = SupabaseProjectRepository.withGateway(gateway);

      await expectLater(
        repository.getProjects(),
        throwsA(
          isA<ProjectRepositoryException>()
              .having(
                (error) => error.reason,
                'reason',
                ProjectRepositoryFailure.loadFailed,
              )
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains('raw-query-token')),
              ),
        ),
      );
    });

    test(
      'getProjectById returns null only for a legitimate no-row result',
      () async {
        final repository = SupabaseProjectRepository.withGateway(
          validGateway(),
        );

        expect(await repository.getProjectById(secondProjectId), isNull);
      },
    );

    test(
      'manager and photographer filters use only hydrated visible rows',
      () async {
        final gateway = twoProjectGateway();
        final repository = SupabaseProjectRepository.withGateway(gateway);

        expect(
          (await repository.getProjectsForManager(
            managerId,
          )).map((project) => project.id),
          [projectId],
        );
        expect(
          (await repository.getProjectsForPhotographer(
            photographerId,
          )).map((project) => project.id),
          [projectId],
        );
        expect(gateway.lastProjectId, isNull);
      },
    );

    test('search and filter never broaden the RLS-visible graph', () async {
      final gateway = twoProjectGateway();
      final repository = SupabaseProjectRepository.withGateway(gateway);

      expect(
        (await repository.searchProjects('المصور المرئي')).single.id,
        projectId,
      );
      expect(await repository.searchProjects('زميل مخفي'), isEmpty);
      expect(
        (await repository.filterProjects(
          status: ProjectStatus.completed,
          type: ProjectType.wedding,
        )).single.id,
        secondProjectId,
      );
    });
  });

  group('SupabaseProjectRepository write boundary', () {
    test('unsupported methods fail safely without any gateway call', () async {
      final gateway = FakeProjectGateway();
      final repository = SupabaseProjectRepository.withGateway(gateway);
      final operations = <Future<dynamic> Function()>[
        repository.getClosureRequests,
        () => repository.createProject(
          name: 'مشروع',
          clientName: 'عميل',
          managerId: managerId,
          type: ProjectType.field,
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 2),
        ),
        () => repository.updateProjectBasics(
          projectId,
          name: 'مشروع',
          clientName: 'عميل',
          type: ProjectType.field,
          status: ProjectStatus.active,
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 2),
        ),
        () => repository.setProjectManager(projectId, managerId: managerId),
        () => repository.assignTeamRoles(projectId, const []),
        () => repository.updateProjectStage(projectId, projectId),
        () => repository.submitClosureRequest(
          projectId: projectId,
          submittedBy: photographerId,
          submittedByName: 'مصور',
        ),
        () => repository.approveClosureRequest(projectId),
        () => repository.rejectClosureRequest(projectId, 'السبب'),
      ];

      for (final operation in operations) {
        await expectLater(
          operation(),
          throwsReason(ProjectRepositoryFailure.unsupportedOperation),
        );
      }
      expect(gateway.totalCalls, 0);
    });

    test('gateway source contains SELECT-only operations', () {
      final source =
          File(
            'lib/data/repositories/supabase/project_gateway.dart',
          ).readAsStringSync();
      final repositorySource =
          File(
            'lib/data/repositories/supabase/supabase_project_repository.dart',
          ).readAsStringSync();

      expect(source, isNot(contains('service_role')));
      expect(repositorySource, isNot(contains('service_role')));
      for (final mutation in ['.insert(', '.update(', '.upsert(', '.delete(']) {
        expect(source, isNot(contains(mutation)));
        expect(repositorySource, isNot(contains(mutation)));
      }
    });
  });
}

Matcher throwsReason(ProjectRepositoryFailure reason) => throwsA(
  isA<ProjectRepositoryException>().having(
    (error) => error.reason,
    'reason',
    reason,
  ),
);

Future<void> expectInvalidData(Future<dynamic> future) =>
    expectLater(future, throwsReason(ProjectRepositoryFailure.invalidData));

FakeProjectGateway validGateway({
  Map<String, dynamic>? project,
  ProjectType type = ProjectType.field,
}) =>
    FakeProjectGateway()
      ..projects = [project ?? validProject()]
      ..stages = validStages(type: type)
      ..profiles = [validProfile()];

FakeProjectGateway validGatewayWithTeam() =>
    validGateway()
      ..teamMembers = [validTeamMember()]
      ..teamTypes = [validTeamType()];

FakeProjectGateway twoProjectGateway() {
  final gateway = validGatewayWithTeam();
  gateway.projects = [
    validProject(),
    validProject(
      id: secondProjectId,
      serial: 'WED-D4E5-F6',
      manager: secondManagerId,
      type: 'wedding',
      status: 'completed',
      name: 'مشروع زواج',
    ),
  ];
  gateway.stages = [
    ...validStages(),
    ...validStages(project: secondProjectId, type: ProjectType.wedding),
  ];
  gateway.teamMembers.first['person_name'] = 'المصور المرئي';
  gateway.profiles = [validProfile(), validProfile(id: secondManagerId)];
  return gateway;
}

Map<String, dynamic> validProject({
  String id = projectId,
  String serial = 'FLD-A1B2-C3',
  String manager = managerId,
  String type = 'field',
  String status = 'active',
  String name = 'مشروع اختبار',
  String startDate = '2026-01-01',
  String endDate = '2026-01-02',
}) => {
  'id': id,
  'serial': serial,
  'name': name,
  'client_name': 'عميل اختبار',
  'manager_id': manager,
  'type': type,
  'status': status,
  'start_date': startDate,
  'end_date': endDate,
  'notes': null,
  'is_active': true,
  'created_at': '2026-07-14T09:00:00+03:00',
  'updated_at': '2026-07-14T10:00:00+03:00',
  'deleted_at': null,
};

List<Map<String, dynamic>> validStages({
  String project = projectId,
  ProjectType type = ProjectType.field,
  List<String>? statuses,
}) => [
  for (var index = 0; index < type.defaultStageTitles.length; index++)
    {
      'id':
          '${project.substring(0, 8)}-1000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
      'project_id': project,
      'title': type.defaultStageTitles[index],
      'stage_order': index + 1,
      'status': statuses?[index] ?? (index == 0 ? 'current' : 'pending'),
      'notes': null,
      'updated_by': null,
      'updated_at': null,
    },
];

Map<String, dynamic> validTeamMember({
  String id = memberId,
  String project = projectId,
  String? userId = photographerId,
  String name = 'مصور اختبار',
}) => {
  'id': id,
  'project_id': project,
  'user_id': userId,
  'person_name': name,
  'value': 250,
  'date': '2026-01-01',
};

Map<String, dynamic> validTeamType({
  String id = firstTypeLinkId,
  String member = memberId,
  String typeId = photoTypeId,
  String code = 'photo',
  String nameAr = 'مصور فوتوغرافي',
}) => {
  'id': id,
  'team_member_id': member,
  'photographer_type_id': typeId,
  'photographer_type': {
    'id': typeId,
    'code': code,
    'name_ar': nameAr,
    'is_active': true,
  },
};

Map<String, dynamic> validProfile({String id = managerId}) => {
  'id': id,
  'full_name': 'مدير المشروع',
  'is_active': true,
  'deleted_at': null,
};

class FakeProjectGateway implements ProjectGateway {
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> stages = [];
  List<Map<String, dynamic>> teamMembers = [];
  List<Map<String, dynamic>> teamTypes = [];
  List<Map<String, dynamic>> profiles = [];
  bool throwOnProjects = false;

  int projectCalls = 0;
  int stagesCalls = 0;
  int teamMemberCalls = 0;
  int teamTypeCalls = 0;
  int profileCalls = 0;
  String? lastProjectId;

  int get totalCalls =>
      projectCalls +
      stagesCalls +
      teamMemberCalls +
      teamTypeCalls +
      profileCalls;

  @override
  Future<List<Map<String, dynamic>>> fetchProjects({String? projectId}) async {
    projectCalls++;
    lastProjectId = projectId;
    if (throwOnProjects) throw StateError('raw-query-token');
    return projects
        .where((row) => projectId == null || row['id'] == projectId)
        .map(Map<String, dynamic>.from)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStages(
    List<String> projectIds,
  ) async {
    stagesCalls++;
    return stages
        .where((row) => projectIds.contains(row['project_id']))
        .map(Map<String, dynamic>.from)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTeamMembers(
    List<String> projectIds,
  ) async {
    teamMemberCalls++;
    return teamMembers
        .where((row) => projectIds.contains(row['project_id']))
        .map(Map<String, dynamic>.from)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTeamTypes(
    List<String> teamMemberIds,
  ) async {
    teamTypeCalls++;
    return teamTypes
        .where((row) => teamMemberIds.contains(row['team_member_id']))
        .map(Map<String, dynamic>.from)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchVisibleProfiles(
    List<String> profileIds,
  ) async {
    profileCalls++;
    return profiles
        .where((row) => profileIds.contains(row['id']))
        .map(Map<String, dynamic>.from)
        .toList();
  }
}
