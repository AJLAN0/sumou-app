import 'role_type.dart';

/// Every gateable feature in the app.
///
/// Used with [FeaturePermissions.has] so callers can query a permission by
/// name without touching individual boolean fields.
enum AppFeature {
  canAddProject,
  canEditProject,
  canAssignPhotographers,
  canRequestPhotographer,
  canRequestDesign,
  canUpdateStages,
  canRequestClosure,
  canApproveClosure,
  canManageUsers,
  canManagePermissions,
  canViewReports,
  canManageAttendance,
  canManageWeddingProjects,
  canManageFinance,
}

/// Per-user feature flags. Defaults to all-false so a user is never granted
/// anything implicitly. Pure Dart value type.
class FeaturePermissions {
  const FeaturePermissions({
    this.canAddProject = false,
    this.canEditProject = false,
    this.canAssignPhotographers = false,
    this.canRequestPhotographer = false,
    this.canRequestDesign = false,
    this.canUpdateStages = false,
    this.canRequestClosure = false,
    this.canApproveClosure = false,
    this.canManageUsers = false,
    this.canManagePermissions = false,
    this.canViewReports = false,
    this.canManageAttendance = false,
    this.canManageWeddingProjects = false,
    this.canManageFinance = false,
  });

  final bool canAddProject;
  final bool canEditProject;
  final bool canAssignPhotographers;
  final bool canRequestPhotographer;
  final bool canRequestDesign;
  final bool canUpdateStages;
  final bool canRequestClosure;
  final bool canApproveClosure;
  final bool canManageUsers;
  final bool canManagePermissions;
  final bool canViewReports;
  final bool canManageAttendance;
  final bool canManageWeddingProjects;
  final bool canManageFinance;

  /// Return a copy with [feature] set to [value]. Mirrors [has], so callers can
  /// toggle a permission by [AppFeature] without touching individual fields.
  FeaturePermissions setFeature(
    AppFeature feature,
    bool value,
  ) => switch (feature) {
    AppFeature.canAddProject => copyWith(canAddProject: value),
    AppFeature.canEditProject => copyWith(canEditProject: value),
    AppFeature.canAssignPhotographers => copyWith(
      canAssignPhotographers: value,
    ),
    AppFeature.canRequestPhotographer => copyWith(
      canRequestPhotographer: value,
    ),
    AppFeature.canRequestDesign => copyWith(canRequestDesign: value),
    AppFeature.canUpdateStages => copyWith(canUpdateStages: value),
    AppFeature.canRequestClosure => copyWith(canRequestClosure: value),
    AppFeature.canApproveClosure => copyWith(canApproveClosure: value),
    AppFeature.canManageUsers => copyWith(canManageUsers: value),
    AppFeature.canManagePermissions => copyWith(canManagePermissions: value),
    AppFeature.canViewReports => copyWith(canViewReports: value),
    AppFeature.canManageAttendance => copyWith(canManageAttendance: value),
    AppFeature.canManageWeddingProjects => copyWith(
      canManageWeddingProjects: value,
    ),
    AppFeature.canManageFinance => copyWith(canManageFinance: value),
  };

  /// Query a permission by [AppFeature].
  bool has(AppFeature feature) => switch (feature) {
    AppFeature.canAddProject => canAddProject,
    AppFeature.canEditProject => canEditProject,
    AppFeature.canAssignPhotographers => canAssignPhotographers,
    AppFeature.canRequestPhotographer => canRequestPhotographer,
    AppFeature.canRequestDesign => canRequestDesign,
    AppFeature.canUpdateStages => canUpdateStages,
    AppFeature.canRequestClosure => canRequestClosure,
    AppFeature.canApproveClosure => canApproveClosure,
    AppFeature.canManageUsers => canManageUsers,
    AppFeature.canManagePermissions => canManagePermissions,
    AppFeature.canViewReports => canViewReports,
    AppFeature.canManageAttendance => canManageAttendance,
    AppFeature.canManageWeddingProjects => canManageWeddingProjects,
    AppFeature.canManageFinance => canManageFinance,
  };

  /// Sensible default feature set for a role, mirroring the reference
  /// prototype's defaults. Users may have these overridden per-account later.
  factory FeaturePermissions.defaultsFor(RoleType role) => switch (role) {
    RoleType.manager => const FeaturePermissions(
      canAddProject: true,
      canEditProject: true,
      canAssignPhotographers: true,
      canUpdateStages: true,
      canApproveClosure: true,
      canViewReports: true,
    ),
    RoleType.photographer => const FeaturePermissions(
      canRequestPhotographer: true,
      canRequestDesign: true,
      canUpdateStages: true,
      canRequestClosure: true,
    ),
    RoleType.admin => const FeaturePermissions(
      canManageUsers: true,
      canManagePermissions: true,
      canViewReports: true,
    ),
    RoleType.finance => const FeaturePermissions(
      canManageFinance: true,
      canViewReports: true,
    ),
    RoleType.weddingAdmin => const FeaturePermissions(
      canAddProject: true,
      canAssignPhotographers: true,
      canManageWeddingProjects: true,
    ),
    RoleType.weddingFinance => const FeaturePermissions(canManageFinance: true),
    RoleType.attendance => const FeaturePermissions(canManageAttendance: true),
    RoleType.designer ||
    RoleType.personalPhoto ||
    RoleType.clientTracking => const FeaturePermissions(),
  };

  FeaturePermissions copyWith({
    bool? canAddProject,
    bool? canEditProject,
    bool? canAssignPhotographers,
    bool? canRequestPhotographer,
    bool? canRequestDesign,
    bool? canUpdateStages,
    bool? canRequestClosure,
    bool? canApproveClosure,
    bool? canManageUsers,
    bool? canManagePermissions,
    bool? canViewReports,
    bool? canManageAttendance,
    bool? canManageWeddingProjects,
    bool? canManageFinance,
  }) {
    return FeaturePermissions(
      canAddProject: canAddProject ?? this.canAddProject,
      canEditProject: canEditProject ?? this.canEditProject,
      canAssignPhotographers:
          canAssignPhotographers ?? this.canAssignPhotographers,
      canRequestPhotographer:
          canRequestPhotographer ?? this.canRequestPhotographer,
      canRequestDesign: canRequestDesign ?? this.canRequestDesign,
      canUpdateStages: canUpdateStages ?? this.canUpdateStages,
      canRequestClosure: canRequestClosure ?? this.canRequestClosure,
      canApproveClosure: canApproveClosure ?? this.canApproveClosure,
      canManageUsers: canManageUsers ?? this.canManageUsers,
      canManagePermissions: canManagePermissions ?? this.canManagePermissions,
      canViewReports: canViewReports ?? this.canViewReports,
      canManageAttendance: canManageAttendance ?? this.canManageAttendance,
      canManageWeddingProjects:
          canManageWeddingProjects ?? this.canManageWeddingProjects,
      canManageFinance: canManageFinance ?? this.canManageFinance,
    );
  }
}
