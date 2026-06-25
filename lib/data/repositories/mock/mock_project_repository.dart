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
              i == 0
                  ? ProjectStageStatus.current
                  : ProjectStageStatus.pending,
        ),
    ];
    // Re-key any incoming team roles to this project's id.
    final roles = [
      for (var i = 0; i < teamRoles.length; i++)
        ProjectTeamRole(
          id: '$id-r${i + 1}',
          projectId: id,
          type: teamRoles[i].type,
          personName: teamRoles[i].personName,
          userId: teamRoles[i].userId,
          value: teamRoles[i].value,
          date: teamRoles[i].date,
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
      teamRoles: roles,
      stages: stages,
      createdAt: DateTime.now(),
    );
    _projects.add(project);
    return project;
  }
}
