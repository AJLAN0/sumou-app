import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';

/// Body-only profile/settings view (no Scaffold) so it can be embedded in the
/// shell's صفحتي tab and in the full-screen [/profile] route.
///
/// Shows the current user's info from auth state and offers change-password and
/// logout actions. Uses mock auth only.
class ProfileView extends ConsumerWidget {
  const ProfileView({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showSumouConfirmSheet(
      context,
      title: 'تسجيل الخروج',
      message: 'هل تريد تسجيل الخروج من حسابك؟',
      confirmLabel: 'تسجيل الخروج',
      destructive: true,
    );
    if (!confirmed) return;
    // Clears session/selected role; the router redirect returns to /entry.
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final activeRole = auth.activeRole ?? user.effectiveRole;
    final roleModel = RoleModel.of(activeRole);

    return ListView(
      children: [
        const SizedBox(height: 8),
        _ProfileHeader(
          initials: user.avatarInitials,
          fullName: user.fullName,
          username: user.username,
          roleModel: roleModel,
        ),
        const SizedBox(height: 24),
        if (user.hasMultipleRoles) ...[
          const SumouSectionHeader(title: 'الأدوار المتاحة'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in user.roles) _RoleTag(role: RoleModel.of(role)),
            ],
          ),
          const SizedBox(height: 24),
        ],
        const SumouSectionHeader(title: 'الحساب'),
        const SizedBox(height: 12),
        _AccountItem(
          icon: Icons.lock_outline,
          label: 'تغيير كلمة المرور',
          onTap: () => context.push(AppRoutes.changePassword),
        ),
        const SizedBox(height: 12),
        _AccountItem(
          icon: Icons.logout,
          label: 'تسجيل الخروج',
          color: AppColors.error,
          onTap: () => _confirmLogout(context, ref),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.initials,
    required this.fullName,
    required this.username,
    required this.roleModel,
  });

  final String initials;
  final String fullName;
  final String username;
  final RoleModel roleModel;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: roleModel.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              initials,
              style: AppTextStyles.titleMedium.copyWith(color: roleModel.color),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName, style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text('@$username', style: AppTextStyles.bodyMuted),
                const SizedBox(height: 8),
                _RoleTag(role: roleModel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.role});

  final RoleModel role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: role.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(role.icon, color: role.color, size: 14),
          const SizedBox(width: 6),
          Text(
            role.nameAr,
            style: AppTextStyles.label.copyWith(
              color: role.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountItem extends StatelessWidget {
  const _AccountItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

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
