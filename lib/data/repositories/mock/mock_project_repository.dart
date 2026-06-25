import '../../../core/models/closure_request_model.dart';
import '../../../core/models/project_enums.dart';
import '../../../core/models/project_model.dart';
import '../../../core/models/project_serial.dart';
import '../../../core/models/project_stage_model.dart';
import '../../../core/models/project_team_role.dart';
import '../project_repository.dart';
import 'mock_projects.dart';

/// In-memory [ProjectRepository] backed by [MockProjects].
class MockProjectRepository implements ProjectRepository {
  MockProjectRepository({
    List<ProjectModel>? projects,
    List<ClosureRequestModel>? closureRequests,
  }) : _projects = List.of(projects ?? MockProjects.projects),
       _closureRequests = List.of(
         closureRequests ?? MockProjects.closureRequests,
       );

  final List<ProjectModel> _projects;
  final List<ClosureRequestModel> _closureRequests;

  @override
  Future<List<ProjectModel>> getProjects() async =>
      List.unmodifiable(_projects);

  @override
  Future<ProjectModel?> getProjectById(String id) async {
    for (final p in _projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<ProjectModel>> getProjectsForManager(String managerId) async =>
      _projects.where((p) => p.managerId == managerId).toList();

  @override
  Future<List<ProjectModel>> getProjectsForPhotographer(String userId) async =>
      _projects.where((p) => p.isAssignedTo(userId)).toList();

  @override
  Future<List<ProjectModel>> getCompletedProjects() async =>
      _projects.where((p) => p.isCompleted).toList();

  @override
  Future<List<ProjectModel>> searchProjects(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_projects);
    return _projects.where((p) {
      final inTeam = p.teamRoles.any(
        (r) => r.personName.toLowerCase().contains(q),
      );
      return p.name.toLowerCase().contains(q) ||
          p.clientName.toLowerCase().contains(q) ||
          p.serial.toLowerCase().contains(q) ||
          inTeam;
    }).toList();
  }

  @override
  Future<List<ProjectModel>> filterProjects({
    ProjectStatus? status,
    ProjectType? type,
  }) async {
    return _projects.where((p) {
      final statusOk = status == null || p.status == status;
      final typeOk = type == null || p.type == type;
      return statusOk && typeOk;
    }).toList();
  }

  @override
  Future<List<ClosureRequestModel>> getClosureRequests() async =>
      List.unmodifiable(_closureRequests);

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
    final id = 'p-${DateTime.now().millisecondsSinceEpoch}';
    final stages = [
      for (var i = 0; i < type.defaultStageTitles.length; i++)
        ProjectStageModel(
          id: '$id-s${i + 1}',
          projectId: id,
          title: type.defaultStageTitles[i],
          order: i + 1,
          // The first stage is current on a fresh project; the rest pending.
          status:
              i == 0 ? ProjectStageStatus.current : ProjectStageStatus.pending,
        ),
    ];
    final project = ProjectModel(
      id: id,
      serial: serial ?? ProjectSerial.generate(type),
      name: name,
      clientName: clientName,
      managerId: managerId,
      managerName: managerName,
      type: type,
      status: ProjectStatus.active,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
      // Re-key any incoming team roles to this project's id.
      teamRoles: _rekeyRoles(id, teamRoles),
      stages: stages,
      createdAt: DateTime.now(),
    );
    _projects.add(project);
    return project;
  }

  @override
  Future<ProjectModel?> assignTeamRoles(
    String projectId,
    List<ProjectTeamRole> teamRoles,
  ) async {
    final index = _projects.indexWhere((p) => p.id == projectId);
    if (index < 0) return null;
    final updated = _projects[index].copyWith(
      teamRoles: _rekeyRoles(projectId, teamRoles),
      updatedAt: DateTime.now(),
    );
    _projects[index] = updated;
    return updated;
  }

  @override
  Future<ProjectModel?> updateProjectStage(
    String projectId,
    String stageId, {
    String? notes,
    String? updatedBy,
  }) async {
    final index = _projects.indexWhere((p) => p.id == projectId);
    if (index < 0) return null;
    final project = _projects[index];
    final target = project.stages.where((s) => s.id == stageId).toList();
    if (target.isEmpty) return null;
    final targetOrder = target.first.order;
    final now = DateTime.now();
    final newStages = [
      for (final s in project.stages)
        if (s.order < targetOrder)
          s.copyWith(status: ProjectStageStatus.done)
        else if (s.order == targetOrder)
          s.copyWith(
            status: ProjectStageStatus.current,
            notes: notes,
            updatedBy: updatedBy,
            updatedAt: now,
          )
        else
          s.copyWith(status: ProjectStageStatus.pending),
    ];
    final updated = project.copyWith(stages: newStages, updatedAt: now);
    _projects[index] = updated;
    return updated;
  }

  @override
  Future<ClosureRequestModel?> submitClosureRequest({
    required String projectId,
    required String submittedBy,
    required String submittedByName,
    String? deliveryLink,
    String? reportFileUrl,
    String? notes,
  }) async {
    final index = _projects.indexWhere((p) => p.id == projectId);
    if (index < 0) return null;
    // One pending request at a time per project.
    final hasPending = _closureRequests.any(
      (r) => r.projectId == projectId && r.isPending,
    );
    if (hasPending) return null;

    final project = _projects[index];
    final now = DateTime.now();
    final request = ClosureRequestModel(
      id: 'cr-${now.millisecondsSinceEpoch}',
      projectId: projectId,
      projectName: project.name,
      submittedBy: submittedBy,
      submittedByName: submittedByName,
      createdAt: now,
      deliveryLink: deliveryLink,
      reportFileUrl: reportFileUrl,
      notes: notes,
      status: ClosureRequestStatus.pending,
    );
    _closureRequests.add(request);
    _projects[index] = project.copyWith(
      status: ProjectStatus.pendingClosure,
      updatedAt: now,
    );
    return request;
  }

  @override
  Future<ClosureRequestModel?> approveClosureRequest(String requestId) async {
    final rIndex = _closureRequests.indexWhere((r) => r.id == requestId);
    if (rIndex < 0) return null;
    final request = _closureRequests[rIndex];
    if (!request.isPending) return null;
    final now = DateTime.now();
    final updated = request.copyWith(
      status: ClosureRequestStatus.approved,
      reviewedAt: now,
    );
    _closureRequests[rIndex] = updated;

    final pIndex = _projects.indexWhere((p) => p.id == request.projectId);
    if (pIndex >= 0) {
      final project = _projects[pIndex];
      // Project delivered: complete it and mark every stage done.
      final stages = [
        for (final s in project.stages)
          s.copyWith(status: ProjectStageStatus.done, updatedAt: now),
      ];
      _projects[pIndex] = project.copyWith(
        status: ProjectStatus.completed,
        stages: stages,
        updatedAt: now,
      );
    }
    return updated;
  }

  @override
  Future<ClosureRequestModel?> rejectClosureRequest(
    String requestId,
    String reason,
  ) async {
    final rIndex = _closureRequests.indexWhere((r) => r.id == requestId);
    if (rIndex < 0) return null;
    final request = _closureRequests[rIndex];
    if (!request.isPending) return null;
    final now = DateTime.now();
    final updated = request.copyWith(
      status: ClosureRequestStatus.rejected,
      rejectReason: reason,
      reviewedAt: now,
    );
    _closureRequests[rIndex] = updated;

    final pIndex = _projects.indexWhere((p) => p.id == request.projectId);
    if (pIndex >= 0) {
      // Closure declined: the project goes back to active.
      _projects[pIndex] = _projects[pIndex].copyWith(
        status: ProjectStatus.active,
        updatedAt: now,
      );
    }
    return updated;
  }

  /// Re-key team roles to belong to [projectId] with stable, ordered ids.
  static List<ProjectTeamRole> _rekeyRoles(
    String projectId,
    List<ProjectTeamRole> roles,
  ) => [
    for (var i = 0; i < roles.length; i++)
      ProjectTeamRole(
        id: '$projectId-r${i + 1}',
        projectId: projectId,
        type: roles[i].type,
        personName: roles[i].personName,
        userId: roles[i].userId,
        value: roles[i].value,
        date: roles[i].date,
      ),
  ];
}
