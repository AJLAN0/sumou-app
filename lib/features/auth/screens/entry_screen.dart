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
    // Size the logo to the screen so it reads clearly on any device, while
    // keeping sensible min/max bounds. The source art is wordmark-width, so we
    // size by width and let the height follow the aspect ratio.
    final logoWidth = (MediaQuery.sizeOf(context).width * 0.68).clamp(
      220.0,
      360.0,
    );
    return SumouScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          // Full Sumou logo (with wordmark), centered and never stretched.
          Center(
            child: SumouLogo.full(
              width: logoWidth,
              fallback: const _BrandFallback(),
            ),
          ),
          const SizedBox(height: 24),
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

/// Shown on the entry screen while the full logo asset isn't available yet —
/// mirrors the previous branded header (teal icon + name).
class _BrandFallback extends StatelessWidget {
  const _BrandFallback();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
        const SizedBox(height: 16),
        Text(
          'سمو الإبداع',
          style: AppTextStyles.titleLarge,
          textAlign: TextAlign.center,
        ),
      ],
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
