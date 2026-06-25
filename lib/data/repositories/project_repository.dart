import '../../core/models/closure_request_model.dart';
import '../../core/models/project_enums.dart';
import '../../core/models/project_model.dart';
import '../../core/models/project_team_role.dart';

/// Read access to projects and closure requests.
///
/// Mock-backed in Sprint 2; a Supabase implementation can replace it later
/// without changing callers (they depend on this interface and the models).
abstract interface class ProjectRepository {
  Future<List<ProjectModel>> getProjects();
  Future<ProjectModel?> getProjectById(String id);

  Future<List<ProjectModel>> getProjectsForManager(String managerId);
  Future<List<ProjectModel>> getProjectsForPhotographer(String userId);
  Future<List<ProjectModel>> getCompletedProjects();

  /// Search by project name, client name, serial, or team member name.
  Future<List<ProjectModel>> searchProjects(String query);

  /// Filter by status and/or type (null = no constraint on that field).
  Future<List<ProjectModel>> filterProjects({
    ProjectStatus? status,
    ProjectType? type,
  });

  Future<List<ClosureRequestModel>> getClosureRequests();

  /// Create a new project and return the persisted model (with its id, serial,
  /// and initial stages). When [serial] is null one is generated. Mock-backed
  /// in Sprint 2.
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
  });
}
