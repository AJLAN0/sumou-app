import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

/// First interactive screen: two large mobile entry cards — staff login and
/// public client tracking.
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryTeal,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.accentGreen,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'سمو الإبداع',
            style: AppTextStyles.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'كيف تريد المتابعة؟',
            style: AppTextStyles.bodyMuted,
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          _EntryCard(
            title: 'دخول سمو',
            subtitle: 'تسجيل دخول الموظفين',
            icon: Icons.login,
            color: AppColors.primaryTeal,
            onTap: () => context.go(AppRoutes.login),
          ),
          const SizedBox(height: 14),
          _EntryCard(
            title: 'تتبع مشروع',
            subtitle: 'للعملاء — أدخل الرمز السري',
            icon: Icons.search,
            color: AppColors.accentGreen,
            onTap: () => context.go(AppRoutes.track),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
          const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
