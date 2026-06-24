import '../../core/models/closure_request_model.dart';
import '../../core/models/project_enums.dart';
import '../../core/models/project_model.dart';

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
}
