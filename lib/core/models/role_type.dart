/// The roles a user can hold in the system.
///
/// `key` matches the backend/prototype string (snake_case) for serialization;
/// `nameAr` / `nameEn` are display labels. Pure Dart — no Flutter imports — so
/// it stays reusable across layers.
enum RoleType {
  admin,
  manager,
  photographer,
  designer,
  finance,
  weddingAdmin,
  weddingFinance,
  attendance,
  personalPhoto,
  clientTracking;

  /// Stable serialization key (matches backend / reference prototype).
  String get key => switch (this) {
        RoleType.admin => 'admin',
        RoleType.manager => 'manager',
        RoleType.photographer => 'photographer',
        RoleType.designer => 'designer',
        RoleType.finance => 'finance',
        RoleType.weddingAdmin => 'wedding_admin',
        RoleType.weddingFinance => 'wedding_finance',
        RoleType.attendance => 'attendance',
        RoleType.personalPhoto => 'personal_photo',
        RoleType.clientTracking => 'client_tracking',
      };

  String get nameAr => switch (this) {
        RoleType.admin => 'الإدارة',
        RoleType.manager => 'مدير مشاريع',
        RoleType.photographer => 'مصور',
        RoleType.designer => 'مصمم',
        RoleType.finance => 'مالية سمو',
        RoleType.weddingAdmin => 'إدارة الزواجات',
        RoleType.weddingFinance => 'مالية الزواجات',
        RoleType.attendance => 'تسجيل الحضور',
        RoleType.personalPhoto => 'التصوير الشخصي',
        RoleType.clientTracking => 'تتبع مشروع',
      };

  String get nameEn => switch (this) {
        RoleType.admin => 'Admin',
        RoleType.manager => 'Project Manager',
        RoleType.photographer => 'Photographer',
        RoleType.designer => 'Designer',
        RoleType.finance => 'Finance',
        RoleType.weddingAdmin => 'Wedding Admin',
        RoleType.weddingFinance => 'Wedding Finance',
        RoleType.attendance => 'Attendance',
        RoleType.personalPhoto => 'Personal Photography',
        RoleType.clientTracking => 'Client Tracking',
      };

  /// Resolve a [RoleType] from its serialization [key].
  /// Returns null when the key is unknown (caller decides the fallback).
  static RoleType? fromKey(String key) {
    for (final role in RoleType.values) {
      if (role.key == key) return role;
    }
    return null;
  }
}
