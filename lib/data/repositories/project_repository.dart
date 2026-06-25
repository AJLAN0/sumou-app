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

  /// Replace the full team on an existing project and return the updated model.
  /// Roles are re-keyed to the project. Returns null when [projectId] is
  /// unknown. Mock-backed in Sprint 2.
  Future<ProjectModel?> assignTeamRoles(
    String projectId,
    List<ProjectTeamRole> teamRoles,
  );

  /// Set the project's current stage to [stageId]: earlier stages become done,
  /// the target becomes current, later stages pending. Optional [notes] and
  /// [updatedBy] are recorded on the target stage. Returns the updated project,
  /// or null when the project or stage is unknown. Mock-backed in Sprint 2.
  Future<ProjectModel?> updateProjectStage(
    String projectId,
    String stageId, {
    String? notes,
    String? updatedBy,
  });

  /// Submit a closure request for [projectId] and move the project to
  /// pendingClosure. Returns the created (pending) request, or null when the
  /// project is unknown or already has a pending request. Mock-backed in
  /// Sprint 2 (no file upload — [reportFileUrl] is plain text).
  Future<ClosureRequestModel?> submitClosureRequest({
    required String projectId,
    required String submittedBy,
    required String submittedByName,
    String? deliveryLink,
    String? reportFileUrl,
    String? notes,
  });

  /// Approve a pending closure request: marks it approved, completes the
  /// project, and marks all its stages done. Returns the updated request, or
  /// null when the request is unknown or not pending. Mock-backed.
  Future<ClosureRequestModel?> approveClosureRequest(String requestId);

  /// Reject a pending closure request with [reason]: marks it rejected and
  /// returns the project to active. Returns the updated request, or null when
  /// the request is unknown or not pending. Mock-backed.
  Future<ClosureRequestModel?> rejectClosureRequest(
    String requestId,
    String reason,
  );
}
