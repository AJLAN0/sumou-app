import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Manager home dashboard (home tab of the manager shell).
///
/// Static/mock content only — stat cards + UI-only quick actions. Real project
/// creation / requests / team screens arrive in Sprint 2.
class ManagerHomeScreen extends StatelessWidget {
  const ManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 4),
        Text('ملخص اليوم', style: AppTextStyles.titleMedium),
        const SizedBox(height: 4),
        Text('نظرة سريعة على مشاريعك وفريقك', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(
              child: SumouStatCard(
                value: '8',
                label: 'مشاريع نشطة',
                icon: Icons.work_outline,
                accentColor: AppColors.projectTeal,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SumouStatCard(
                value: '3',
                label: 'طلبات إنهاء',
                icon: Icons.inbox_outlined,
                accentColor: AppColors.financeYellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(
              child: SumouStatCard(
                value: '5 / 7',
                label: 'الفريق المتاح',
                icon: Icons.group_outlined,
                accentColor: AppColors.accentGreen,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SumouStatCard(
                value: '4',
                label: 'مهام اليوم',
                icon: Icons.calendar_today_outlined,
                accentColor: AppColors.primaryTeal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'إجراءات سريعة'),
        const SizedBox(height: 12),
        SumouButton(label: 'إضافة مشروع', icon: Icons.add, onPressed: () {}),
        const SizedBox(height: 10),
        SumouButton(
          label: 'عرض الطلبات',
          variant: SumouButtonVariant.secondary,
          icon: Icons.inbox_outlined,
          onPressed: () {},
        ),
        const SizedBox(height: 10),
        SumouButton(
          label: 'عرض الفريق',
          variant: SumouButtonVariant.secondary,
          icon: Icons.group_outlined,
          onPressed: () {},
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
