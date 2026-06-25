/// Project category. Determines which stage workflow applies.
enum ProjectType {
  field,
  social,
  wedding;

  String get key => switch (this) {
    ProjectType.field => 'field',
    ProjectType.social => 'social',
    ProjectType.wedding => 'wedding',
  };

  String get nameAr => switch (this) {
    ProjectType.field => 'ميداني',
    ProjectType.social => 'سوشيال',
    ProjectType.wedding => 'زواج',
  };

  /// Social/marketing projects use the 7-stage flow; field and wedding use the
  /// simple 3-stage flow.
  bool get isSevenStage => this == ProjectType.social;
  bool get isThreeStage => !isSevenStage;

  /// Default stage titles for a fresh project of this type.
  List<String> get defaultStageTitles =>
      isSevenStage
          ? ProjectStageTitles.sevenStage
          : ProjectStageTitles.threeStage;

  static ProjectType? fromKey(String key) {
    for (final t in ProjectType.values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// Canonical stage titles (Arabic) for each workflow.
class ProjectStageTitles {
  ProjectStageTitles._();

  static const List<String> threeStage = [
    'استلام الأوردر',
    'في رحلة الإبداع',
    'تم التسليم',
  ];

  static const List<String> sevenStage = [
    'استلام الأوردر',
    'الاجتماع مع العميل',
    'كتابة الخطة',
    'رحلة الإبداع',
    'رحلة التعديل',
    'التسليم',
    'النشر',
  ];
}

/// Lifecycle status of a project.
enum ProjectStatus {
  active,
  completed,
  pendingClosure,
  rejected,
  approved,
  inProgress,
  delivered;

  String get key => switch (this) {
    ProjectStatus.active => 'active',
    ProjectStatus.completed => 'completed',
    ProjectStatus.pendingClosure => 'pending_closure',
    ProjectStatus.rejected => 'rejected',
    ProjectStatus.approved => 'approved',
    ProjectStatus.inProgress => 'in_progress',
    ProjectStatus.delivered => 'delivered',
  };

  String get nameAr => switch (this) {
    ProjectStatus.active => 'نشط',
    ProjectStatus.completed => 'منتهي',
    ProjectStatus.pendingClosure => 'بانتظار الموافقة',
    ProjectStatus.rejected => 'مرفوض',
    ProjectStatus.approved => 'مقبول',
    ProjectStatus.inProgress => 'قيد التنفيذ',
    ProjectStatus.delivered => 'تم التسليم',
  };

  static ProjectStatus? fromKey(String key) {
    for (final s in ProjectStatus.values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// Status of a single project stage.
enum ProjectStageStatus {
  pending,
  current,
  done;

  String get nameAr => switch (this) {
    ProjectStageStatus.pending => 'بانتظار',
    ProjectStageStatus.current => 'جارية',
    ProjectStageStatus.done => 'مكتملة',
  };
}
