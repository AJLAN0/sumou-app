import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/admin_providers.dart';
import 'widgets/admin_chips.dart';

/// Admin permissions view (read-only). Each user's roles, photo types, and
/// enabled feature permissions shown as readable Arabic chips. No editing.
class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersListProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('تعذّر تحميل الصلاحيات')),
      data: (users) {
        if (users.isEmpty) {
          return const SumouEmptyState(
            title: 'لا توجد صلاحيات',
            icon: Icons.shield_outlined,
          );
        }
        return ListView.separated(
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _PermissionCard(user: users[i]),
        );
      },
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final roleModel = RoleModel.of(user.defaultRole);
    final enabled = AppFeature.values
        .where((f) => user.permissions.has(f))
        .toList();

    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: roleModel.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  user.avatarInitials,
                  style: AppTextStyles.body.copyWith(color: roleModel.color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName, style: AppTextStyles.titleMedium),
                    const SizedBox(height: 2),
                    Text('@${user.username}', style: AppTextStyles.bodyMuted),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Group(
            title: 'الأدوار',
            children: [
              for (final role in user.roles) AdminRoleChip(role),
            ],
          ),
          if (user.photoTypes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Group(
              title: 'أنواع التصوير',
              children: [
                for (final type in user.photoTypes)
                  AdminTextChip(type, color: AppColors.photographerPurple),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _Group(
            title: 'الصلاحيات',
            emptyLabel: 'لا توجد صلاحيات مفعّلة',
            children: [
              for (final feature in enabled) AdminTextChip(featureLabelAr(feature)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.children,
    this.emptyLabel,
  });

  final String title;
  final List<Widget> children;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.label),
        const SizedBox(height: 8),
        if (children.isEmpty)
          Text(
            emptyLabel ?? '—',
            style: AppTextStyles.bodyMuted,
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}
