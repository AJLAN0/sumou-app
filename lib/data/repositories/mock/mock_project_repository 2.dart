import '../../../core/models/closure_request_model.dart';
import '../../../core/models/project_enums.dart';
import '../../../core/models/project_model.dart';
import '../project_repository.dart';
import 'mock_projects.dart';

/// In-memory [ProjectRepository] backed by [MockProjects].
class MockProjectRepository implements ProjectRepository {
  MockProjectRepository({
    List<ProjectModel>? projects,
    List<ClosureRequestModel>? closureRequests,
  }) : _projects = projects ?? MockProjects.projects,
       _closureRequests = closureRequests ?? MockProjects.closureRequests;

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
}
