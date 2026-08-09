/// Minimal photographer-type metadata exposed by the assignable-staff RPC.
class ProjectPhotographerType {
  const ProjectPhotographerType({
    required this.id,
    required this.code,
    required this.nameAr,
  });

  final String id;
  final String code;
  final String nameAr;
}

/// Minimal, immutable staff candidate returned for project assignment.
class AssignableProjectStaff {
  AssignableProjectStaff({
    required this.userId,
    required this.fullName,
    required List<ProjectPhotographerType> photographerTypes,
    required this.isAvailable,
  }) : photographerTypes = List.unmodifiable(photographerTypes);

  final String userId;
  final String fullName;
  final List<ProjectPhotographerType> photographerTypes;
  final bool isAvailable;
}
