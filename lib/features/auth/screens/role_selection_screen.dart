import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../providers/auth_controller.dart';

/// Shown to multi-role users. Picking a role updates `selectedRole`; the
/// router redirect then moves to that role's home.
class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final roles = auth.availableRoles;

    return SumouScaffold(
      appBar: const SumouAppBar(title: 'اختيار الدور'),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Text(
            'لديك أكثر من دور، اختر الدور للمتابعة',
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 16),
          for (final role in roles) ...[
            _RoleCard(
              role: RoleModel.of(role),
              onTap:
                  () => ref
                      .read(authControllerProvider.notifier)
                      .selectRole(role),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed:
                  () => ref.read(authControllerProvider.notifier).logout(),
              child: Text(
                'تسجيل الخروج',
                style: AppTextStyles.label.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.onTap});

  final RoleModel role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: role.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(role.icon, color: role.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(role.nameAr, style: AppTextStyles.titleMedium)),
          const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
