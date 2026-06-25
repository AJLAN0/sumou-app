import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Photographer home dashboard (home tab of the photographer shell).
///
/// Static/mock content only — counts, a schedule summary, a streak placeholder,
/// and UI-only quick actions. Real stages/closure arrive in Sprint 2.
class PhotographerHomeScreen extends StatelessWidget {
  const PhotographerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 4),
        Text('أهلاً بك 👋', style: AppTextStyles.titleMedium),
        const SizedBox(height: 4),
        Text('هذه نظرة سريعة على يومك', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(
              child: SumouStatCard(
                value: '4',
                label: 'مشاريعي النشطة',
                icon: Icons.work_outline,
                accentColor: AppColors.photographerPurple,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SumouStatCard(
                value: '2',
                label: 'طلبات معلقة',
                icon: Icons.inbox_outlined,
                accentColor: AppColors.financeYellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'جدول اليوم والغد'),
        const SizedBox(height: 12),
        const SumouCard(
          child: Column(
            children: [
              _ScheduleRow(
                day: 'اليوم',
                detail: 'تصوير منتجات — greenO',
                icon: Icons.calendar_today_outlined,
              ),
              Divider(height: 20),
              _ScheduleRow(
                day: 'غداً',
                detail: 'لا توجد مواعيد',
                icon: Icons.event_available_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SumouCard(
          child: Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                color: AppColors.accentGreen,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('سلسلة الإنجاز', style: AppTextStyles.body),
                    const SizedBox(height: 2),
                    Text(
                      '5 أيام متتالية من التسليم في الوقت',
                      style: AppTextStyles.bodyMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'إجراءات سريعة'),
        const SizedBox(height: 12),
        SumouButton(label: 'تحديث مرحلة', icon: Icons.update, onPressed: () {}),
        const SizedBox(height: 10),
        SumouButton(
          label: 'طلب إغلاق',
          variant: SumouButtonVariant.secondary,
          icon: Icons.check_circle_outline,
          onPressed: () {},
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.day,
    required this.detail,
    required this.icon,
  });

  final String day;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.projectTeal, size: 20),
        const SizedBox(width: 12),
        SizedBox(width: 44, child: Text(day, style: AppTextStyles.label)),
        const SizedBox(width: 8),
        Expanded(child: Text(detail, style: AppTextStyles.body)),
      ],
    );
  }
}
