import '../../../core/models/closure_request_model.dart';
import '../../../core/models/project_enums.dart';
import '../../../core/models/project_model.dart';
import '../../../core/models/project_stage_model.dart';
import '../../../core/models/project_team_role.dart';

/// In-memory development data for projects, stages, team roles, and closure
/// requests. No real secrets; references mock user ids from `MockUsers`.
class MockProjects {
  MockProjects._();

  // Mock user ids (mirror MockUsers).
  static const String _manager = 'u-manager';
  static const String _managerName = 'سعد المطيري';
  static const String _photographer = 'u-photographer';
  static const String _photographerName = 'نورة الحنايا';

  /// Builds a stage list from [titles]. Stages before [currentOrder] are done,
  /// the one at [currentOrder] is current, the rest pending. When [allDone] is
  /// true every stage is marked done.
  static List<ProjectStageModel> _stages(
    String projectId,
    List<String> titles, {
    required int currentOrder,
    bool allDone = false,
  }) {
    return [
      for (var i = 0; i < titles.length; i++)
        ProjectStageModel(
          id: '$projectId-s${i + 1}',
          projectId: projectId,
          title: titles[i],
          order: i + 1,
          status: allDone
              ? ProjectStageStatus.done
              : (i + 1 < currentOrder
                    ? ProjectStageStatus.done
                    : (i + 1 == currentOrder
                          ? ProjectStageStatus.current
                          : ProjectStageStatus.pending)),
        ),
    ];
  }

  /// Active field project, assigned to a photographer.
  static final ProjectModel activeField = ProjectModel(
    id: 'p-1',
    serial: 'FLD-1A2B-3C',
    name: 'تصوير ميداني — مهرجان الرياض',
    clientName: 'هيئة الترفيه',
    managerId: _manager,
    managerName: _managerName,
    type: ProjectType.field,
    status: ProjectStatus.active,
    startDate: DateTime(2026, 6, 10),
    endDate: DateTime(2026, 6, 20),
    notes: 'تغطية كاملة لليوم الأول والثاني',
    teamRoles: const [
      ProjectTeamRole(
        id: 'p-1-r1',
        projectId: 'p-1',
        type: 'مصور فوتوغرافي',
        personName: _photographerName,
        userId: _photographer,
        value: 1500,
      ),
    ],
    stages: _stages('p-1', ProjectStageTitles.threeStage, currentOrder: 2),
  );

  /// Active social project on the 7-stage flow, assigned to a photographer.
  static final ProjectModel activeSocial = ProjectModel(
    id: 'p-2',
    serial: 'SOC-9X8Y-7Z',
    name: 'حملة انستقرام — رمضان',
    clientName: 'شركة النخيل',
    managerId: _manager,
    managerName: _managerName,
    type: ProjectType.social,
    status: ProjectStatus.inProgress,
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2026, 6, 30),
    teamRoles: const [
      ProjectTeamRole(
        id: 'p-2-r1',
        projectId: 'p-2',
        type: 'انستقرام',
        personName: _photographerName,
        userId: _photographer,
      ),
    ],
    stages: _stages('p-2', ProjectStageTitles.sevenStage, currentOrder: 4),
  );

  /// Completed project (all stages done).
  static final ProjectModel completed = ProjectModel(
    id: 'p-3',
    serial: 'FLD-5K6L-7M',
    name: 'تغطية مؤتمر — مكتمل',
    clientName: 'مجموعة الفيصل',
    managerId: _manager,
    managerName: _managerName,
    type: ProjectType.field,
    status: ProjectStatus.completed,
    startDate: DateTime(2026, 5, 1),
    endDate: DateTime(2026, 5, 3),
    teamRoles: const [
      ProjectTeamRole(
        id: 'p-3-r1',
        projectId: 'p-3',
        type: 'مصور فوتوغرافي',
        personName: _photographerName,
        userId: _photographer,
        value: 1200,
      ),
    ],
    stages: _stages(
      'p-3',
      ProjectStageTitles.threeStage,
      currentOrder: 3,
      allDone: true,
    ),
  );

  /// Wedding project with a pending closure request, assigned to a photographer.
  static final ProjectModel pendingClosure = ProjectModel(
    id: 'p-4',
    serial: 'WED-2Q3R-4S',
    name: 'تصوير زواج — العليا',
    clientName: 'عائلة الراشد',
    managerId: _manager,
    managerName: _managerName,
    type: ProjectType.wedding,
    status: ProjectStatus.pendingClosure,
    startDate: DateTime(2026, 6, 16),
    endDate: DateTime(2026, 6, 16),
    teamRoles: const [
      ProjectTeamRole(
        id: 'p-4-r1',
        projectId: 'p-4',
        type: 'مصور فوتوغرافي',
        personName: _photographerName,
        userId: _photographer,
        value: 2000,
      ),
    ],
    stages: _stages('p-4', ProjectStageTitles.threeStage, currentOrder: 3),
  );

  static final List<ProjectModel> projects = [
    activeField,
    activeSocial,
    completed,
    pendingClosure,
  ];

  static final List<ClosureRequestModel> closureRequests = [
    ClosureRequestModel(
      id: 'cr-1',
      projectId: 'p-4',
      projectName: 'تصوير زواج — العليا',
      submittedBy: _photographer,
      submittedByName: _photographerName,
      createdAt: DateTime(2026, 6, 17),
      reportFileUrl: 'mock://reports/p-4.pdf',
      deliveryLink: 'https://example.test/delivery/p-4',
    ),
  ];
}
