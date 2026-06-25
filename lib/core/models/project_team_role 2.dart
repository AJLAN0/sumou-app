/// A team assignment on a project: a photo-type role filled by a person.
///
/// [userId] links to a [UserModel] when the person has an account; [personName]
/// covers external people without one. [value] is the agreed amount (SAR).
class ProjectTeamRole {
  const ProjectTeamRole({
    required this.id,
    required this.projectId,
    required this.type,
    required this.personName,
    this.userId,
    this.value = 0,
    this.date,
  });

  final String id;
  final String projectId;

  /// Photography type, e.g. «مصور فوتوغرافي».
  final String type;
  final String personName;

  /// Linked user id, or null for an external person.
  final String? userId;
  final num value;
  final DateTime? date;

  bool get hasAccount => userId != null;
}
