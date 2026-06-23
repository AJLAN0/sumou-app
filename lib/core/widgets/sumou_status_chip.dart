import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The consistent set of status badges used across the app.
///
/// This is a presentation-only vocabulary (label + color); it is intentionally
/// decoupled from any domain status field so screens map their data onto it.
enum SumouStatus {
  active, // نشط
  ended, // منتهي
  pendingApproval, // بانتظار الموافقة
  rejected, // مرفوض
  accepted, // مقبول
  inProgress, // قيد التنفيذ
  creating, // جاري الإبداع
  delivered, // تم التسليم
}

extension SumouStatusView on SumouStatus {
  String get labelAr => switch (this) {
        SumouStatus.active => 'نشط',
        SumouStatus.ended => 'منتهي',
        SumouStatus.pendingApproval => 'بانتظار الموافقة',
        SumouStatus.rejected => 'مرفوض',
        SumouStatus.accepted => 'مقبول',
        SumouStatus.inProgress => 'قيد التنفيذ',
        SumouStatus.creating => 'جاري الإبداع',
        SumouStatus.delivered => 'تم التسليم',
      };

  Color get color => switch (this) {
        SumouStatus.active => AppColors.projectTeal,
        SumouStatus.ended => AppColors.textMuted,
        SumouStatus.pendingApproval => AppColors.financeYellow,
        SumouStatus.rejected => AppColors.error,
        SumouStatus.accepted => AppColors.accentGreen,
        SumouStatus.inProgress => AppColors.primaryTeal,
        SumouStatus.creating => AppColors.projectTeal,
        SumouStatus.delivered => AppColors.accentGreen,
      };
}

/// Small pill badge showing a [SumouStatus].
class SumouStatusChip extends StatelessWidget {
  const SumouStatusChip(this.status, {super.key});

  final SumouStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.labelAr,
        style: AppTextStyles.label.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
