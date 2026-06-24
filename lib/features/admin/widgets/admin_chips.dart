import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

/// Arabic label for a feature permission.
String featureLabelAr(AppFeature feature) => switch (feature) {
  AppFeature.canAddProject => 'إضافة مشروع',
  AppFeature.canEditProject => 'تعديل مشروع',
  AppFeature.canAssignPhotographers => 'إسناد مصورين',
  AppFeature.canRequestPhotographer => 'طلب مصور',
  AppFeature.canRequestDesign => 'طلب تصميم',
  AppFeature.canUpdateStages => 'تحديث المراحل',
  AppFeature.canRequestClosure => 'طلب إغلاق',
  AppFeature.canApproveClosure => 'اعتماد الإغلاق',
  AppFeature.canManageUsers => 'إدارة المستخدمين',
  AppFeature.canManagePermissions => 'إدارة الصلاحيات',
  AppFeature.canViewReports => 'عرض التقارير',
  AppFeature.canManageAttendance => 'إدارة الحضور',
  AppFeature.canManageWeddingProjects => 'إدارة الزواجات',
  AppFeature.canManageFinance => 'إدارة المالية',
};

/// Small colored role chip (icon + Arabic name).
class AdminRoleChip extends StatelessWidget {
  const AdminRoleChip(this.role, {super.key});

  final RoleType role;

  @override
  Widget build(BuildContext context) {
    final model = RoleModel.of(role);
    return _Pill(color: model.color, icon: model.icon, label: model.nameAr);
  }
}

/// Active/inactive status pill.
class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentGreen : AppColors.error;
    return _Pill(color: color, label: active ? 'نشط' : 'موقوف');
  }
}

/// Neutral chip for a feature permission / photo type.
class AdminTextChip extends StatelessWidget {
  const AdminTextChip(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return _Pill(color: color ?? AppColors.primaryTeal, label: label);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.label, this.icon});

  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
