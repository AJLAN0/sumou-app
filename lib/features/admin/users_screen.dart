import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/admin_providers.dart';
import 'widgets/admin_chips.dart';

enum _UserFilter { all, active, inactive }

/// Admin users list (read-only). Mobile cards with search + active filter.
/// No create/edit/delete.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';
  _UserFilter _filter = _UserFilter.all;

  bool _matches(UserModel user) {
    final q = _query.trim().toLowerCase();
    final matchesQuery = q.isEmpty ||
        user.fullName.toLowerCase().contains(q) ||
        user.username.toLowerCase().contains(q);
    final matchesFilter = switch (_filter) {
      _UserFilter.all => true,
      _UserFilter.active => user.active,
      _UserFilter.inactive => !user.active,
    };
    return matchesQuery && matchesFilter;
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersListProvider);

    return Column(
      children: [
        SumouTextField(
          hint: 'بحث بالاسم أو اسم المستخدم',
          prefixIcon: Icons.search,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _FilterChip(
              label: 'الكل',
              selected: _filter == _UserFilter.all,
              onTap: () => setState(() => _filter = _UserFilter.all),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'النشطون',
              selected: _filter == _UserFilter.active,
              onTap: () => setState(() => _filter = _UserFilter.active),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'الموقوفون',
              selected: _filter == _UserFilter.inactive,
              onTap: () => setState(() => _filter = _UserFilter.inactive),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(
              child: Text('تعذّر تحميل المستخدمين'),
            ),
            data: (users) {
              final filtered = users.where(_matches).toList();
              if (filtered.isEmpty) {
                return const SumouEmptyState(
                  title: 'لا يوجد مستخدمون',
                  message: 'لا توجد نتائج مطابقة',
                  icon: Icons.group_outlined,
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _UserCard(user: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentGreen : AppColors.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentGreen.withValues(alpha: 0.15)
              : AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accentGreen : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(color: color),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final roleModel = RoleModel.of(user.defaultRole);
    final extraRoles =
        user.roles.where((r) => r != user.defaultRole).toList();

    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
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
              const SizedBox(width: 14),
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
              AdminStatusPill(active: user.active),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminRoleChip(user.defaultRole),
              for (final role in extraRoles) AdminRoleChip(role),
            ],
          ),
          if (extraRoles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '+${extraRoles.length} دور إضافي',
              style: AppTextStyles.label,
            ),
          ],
        ],
      ),
    );
  }
}
