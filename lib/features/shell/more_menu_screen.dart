import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';

/// Placeholder "More" menu for roles that have a المزيد tab.
///
/// Most items are placeholders for later steps (profile/settings/notifications);
/// logout is wired because it already exists from the auth step.
class MoreMenuScreen extends ConsumerWidget {
  const MoreMenuScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showSumouConfirmSheet(
      context,
      title: 'تسجيل الخروج',
      message: 'هل تريد تسجيل الخروج من حسابك؟',
      confirmLabel: 'تسجيل الخروج',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        const SizedBox(height: 8),
        _MoreItem(
          icon: Icons.calendar_month_outlined,
          label: 'التقويم',
          onTap: () => context.push(AppRoutes.calendar),
        ),
        const SizedBox(height: 12),
        _MoreItem(
          icon: Icons.person_outline,
          label: 'صفحتي',
          onTap: () => context.push(AppRoutes.profile),
        ),
        const SizedBox(height: 12),
        const _MoreItem(icon: Icons.notifications_outlined, label: 'الإشعارات'),
        const SizedBox(height: 12),
        _MoreItem(
          icon: Icons.logout,
          label: 'تسجيل الخروج',
          color: AppColors.error,
          onTap: () => _confirmLogout(context, ref),
        ),
      ],
    );
  }
}

class _MoreItem extends StatelessWidget {
  const _MoreItem({
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textWhite;
    return SumouCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: tint, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: AppTextStyles.body.copyWith(color: tint)),
          ),
          const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
