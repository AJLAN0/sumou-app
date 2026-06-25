import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Admin dashboard (home tab of the admin shell).
///
/// Static/mock content only — overview stats + a system status card. User
/// management and permission editing are NOT implemented here.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 4),
        Text('نظرة عامة على النظام', style: AppTextStyles.titleMedium),
        const SizedBox(height: 4),
        Text('ملخص المستخدمين والصلاحيات', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(
              child: SumouStatCard(
                value: '24',
                label: 'إجمالي المستخدمين',
                icon: Icons.people_outline,
                accentColor: AppColors.projectTeal,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SumouStatCard(
                value: '21',
                label: 'المستخدمون النشطون',
                icon: Icons.verified_user_outlined,
                accentColor: AppColors.accentGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(
              child: SumouStatCard(
                value: '8',
                label: 'الأدوار',
                icon: Icons.shield_outlined,
                accentColor: AppColors.photographerPurple,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SumouStatCard(
                value: '14',
                label: 'الصلاحيات',
                icon: Icons.lock_outline,
                accentColor: AppColors.financeYellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'حالة النظام'),
        const SizedBox(height: 12),
        SumouCard(
          child: Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.accentGreen,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('النظام يعمل بشكل طبيعي', style: AppTextStyles.body),
                    const SizedBox(height: 2),
                    Text('آخر تحديث: اليوم', style: AppTextStyles.bodyMuted),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
