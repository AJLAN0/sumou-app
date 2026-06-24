import 'project_enums.dart';
import 'project_stage_model.dart';
import 'project_team_role.dart';

/// A production project.
///
/// Pure Dart value type. Helpers cover status checks, stage progress, and team
/// queries used across Sprint 2 screens.
class ProjectModel {
  const ProjectModel({
    required this.id,
    required this.serial,
    required this.name,
    required this.clientName,
    required this.managerId,
    required this.type,
    required this.startDate,
    required this.endDate,
    this.managerName,
    this.status = ProjectStatus.active,
    this.notes,
    this.teamRoles = const [],
    this.stages = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Client-facing secret code.
  final String serial;
  final String name;
  final String clientName;
  final String managerId;
  final String? managerName;
  final ProjectType type;
  final ProjectStatus status;
  final DateTime startDate;
  final DateTime endDate;
  final String? notes;
  final List<ProjectTeamRole> teamRoles;
  final List<ProjectStageModel> stages;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ---- helpers -------------------------------------------------------------

  bool get isActive =>
      status == ProjectStatus.active || status == ProjectStatus.inProgress;

  bool get isCompleted =>
      status == ProjectStatus.completed ||
      status == ProjectStatus.delivered ||
      status == ProjectStatus.approved;

  bool get hasPendingClosure => status == ProjectStatus.pendingClosure;

  bool get supportsSevenStageFlow => type.isSevenStage;
  bool get supportsThreeStageFlow => type.isThreeStage;

  /// The active stage: the one marked current, else the first not-done stage,
  /// else the last stage. Null when there are no stages.
  ProjectStageModel? get currentStage {
    if (stages.isEmpty) return null;
    for (final s in stages) {
      if (s.isCurrent) return s;
    }
    for (final s in stages) {
      if (!s.isDone) return s;
    }
    return stages.last;
  }

  /// Completion percentage based on done stages (0–100).
  int get stageProgressPercent {
    if (stages.isEmpty) return isCompleted ? 100 : 0;
    final done = stages.where((s) => s.isDone).length;
    return ((done / stages.length) * 100).round();
  }

  /// Distinct user ids of assigned team members (those with accounts).
  List<String> get assignedPhotographers {
    final ids = <String>{};
    for (final role in teamRoles) {
      final id = role.userId;
      if (id != null) ids.add(id);
    }
    return ids.toList();
  }

  bool isAssignedTo(String userId) => assignedPhotographers.contains(userId);

  ProjectModel copyWith({
    String? name,
    String? clientName,
    String? managerId,
    String? managerName,
    ProjectType? type,
    ProjectStatus? status,
    DateTime? startDate,
    DateTime? endDate,
    String? notes,
    List<ProjectTeamRole>? teamRoles,
    List<ProjectStageModel>? stages,
    DateTime? updatedAt,
  }) {
    return ProjectModel(
      id: id,
      serial: serial,
      name: name ?? this.name,
      clientName: clientName ?? this.clientName,
      managerId: managerId ?? this.managerId,
      managerName: managerName ?? this.managerName,
      type: type ?? this.type,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      notes: notes ?? this.notes,
      teamRoles: teamRoles ?? this.teamRoles,
      stages: stages ?? this.stages,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
