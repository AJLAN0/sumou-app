import 'package:flutter/material.dart';

import '../../core/models/role_type.dart';

/// A single bottom-navigation entry.
class NavItem {
  const NavItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Role-based bottom navigation configuration.
///
/// Manager, photographer, and admin are fully configured for Sprint 1; the
/// remaining roles have placeholder configs (correct labels, screens stubbed)
/// until their sprints.
class RoleNavConfig {
  RoleNavConfig._();

  /// Label used to detect the "More" tab (renders [MoreMenuScreen]).
  static const String moreLabel = 'المزيد';

  /// Label used to detect the profile tab (renders the profile view).
  static const String profileLabel = 'صفحتي';

  /// Admin tab labels (used to route to the admin screens).
  static const String usersLabel = 'المستخدمين';
  static const String permissionsLabel = 'الصلاحيات';
  static const String reportsLabel = 'التقارير';

  static List<NavItem> forRole(RoleType role) => switch (role) {
    RoleType.manager => const [
      NavItem(label: 'الرئيسية', icon: Icons.home_outlined),
      NavItem(label: 'المشاريع', icon: Icons.work_outline),
      NavItem(label: 'الطلبات', icon: Icons.inbox_outlined),
      NavItem(label: 'الفريق', icon: Icons.group_outlined),
      NavItem(label: moreLabel, icon: Icons.more_horiz),
    ],
    RoleType.photographer => const [
      NavItem(label: 'الرئيسية', icon: Icons.home_outlined),
      NavItem(label: 'مشاريعي', icon: Icons.work_outline),
      NavItem(label: 'تقويمي', icon: Icons.calendar_today_outlined),
      NavItem(label: 'الطلبات', icon: Icons.inbox_outlined),
      NavItem(label: 'صفحتي', icon: Icons.person_outline),
    ],
    RoleType.admin => const [
      NavItem(label: 'لوحة التحكم', icon: Icons.dashboard_outlined),
      NavItem(label: usersLabel, icon: Icons.group_outlined),
      NavItem(label: permissionsLabel, icon: Icons.shield_outlined),
      NavItem(label: reportsLabel, icon: Icons.bar_chart),
      NavItem(label: moreLabel, icon: Icons.more_horiz),
    ],
    // ----- placeholder configs (later sprints) -----
    RoleType.designer => const [
      NavItem(label: 'الرئيسية', icon: Icons.home_outlined),
      NavItem(label: 'طلبات التصميم', icon: Icons.brush_outlined),
      NavItem(label: 'التصاميم المنجزة', icon: Icons.check_circle_outline),
      NavItem(label: 'صفحتي', icon: Icons.person_outline),
    ],
    RoleType.finance => const [
      NavItem(label: 'الرئيسية', icon: Icons.home_outlined),
      NavItem(label: 'طلبات التحويل', icon: Icons.payments_outlined),
      NavItem(label: 'المشاريع المحولة', icon: Icons.check_circle_outline),
      NavItem(label: reportsLabel, icon: Icons.bar_chart),
      NavItem(label: 'صفحتي', icon: Icons.person_outline),
    ],
    RoleType.weddingAdmin => const [
      NavItem(label: 'الرئيسية', icon: Icons.home_outlined),
      NavItem(label: 'طلبات ركاز', icon: Icons.inbox_outlined),
      NavItem(label: 'الزواجات', icon: Icons.favorite_outline),
      NavItem(label: 'التقويم', icon: Icons.calendar_today_outlined),
      NavItem(label: moreLabel, icon: Icons.more_horiz),
    ],
    RoleType.weddingFinance => const [
      NavItem(label: 'الرئيسية', icon: Icons.home_outlined),
      NavItem(label: 'طلبات التحويل', icon: Icons.payments_outlined),
      NavItem(label: 'الأرشيف', icon: Icons.archive_outlined),
      NavItem(label: 'صفحتي', icon: Icons.person_outline),
    ],
    RoleType.attendance => const [
      NavItem(label: 'تسجيل الحضور', icon: Icons.access_time),
      NavItem(label: 'سجلاتي', icon: Icons.calendar_today_outlined),
      NavItem(label: 'الجداول', icon: Icons.event_note_outlined),
      NavItem(label: reportsLabel, icon: Icons.bar_chart),
    ],
    RoleType.personalPhoto => const [
      NavItem(label: 'الرئيسية', icon: Icons.home_outlined),
      NavItem(label: 'الحجوزات', icon: Icons.list_alt_outlined),
      NavItem(label: 'التقويم', icon: Icons.calendar_today_outlined),
      NavItem(label: 'إضافة حجز', icon: Icons.add_circle_outline),
      NavItem(label: 'صفحتي', icon: Icons.person_outline),
    ],
    // Tracking is not an authenticated shell role.
    RoleType.clientTracking => const [
      NavItem(label: 'الرئيسية', icon: Icons.home_outlined),
    ],
  };
}
