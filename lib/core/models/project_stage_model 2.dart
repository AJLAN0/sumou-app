import 'project_enums.dart';

/// A single stage in a project's workflow.
class ProjectStageModel {
  const ProjectStageModel({
    required this.id,
    required this.projectId,
    required this.title,
    required this.order,
    this.status = ProjectStageStatus.pending,
    this.notes,
    this.updatedBy,
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String title;

  /// 1-based position in the workflow.
  final int order;
  final ProjectStageStatus status;
  final String? notes;

  /// User id of whoever last advanced the stage.
  final String? updatedBy;
  final DateTime? updatedAt;

  bool get isDone => status == ProjectStageStatus.done;
  bool get isCurrent => status == ProjectStageStatus.current;
  bool get isPending => status == ProjectStageStatus.pending;

  ProjectStageModel copyWith({
    ProjectStageStatus? status,
    String? notes,
    String? updatedBy,
    DateTime? updatedAt,
  }) {
    return ProjectStageModel(
      id: id,
      projectId: projectId,
      title: title,
      order: order,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
