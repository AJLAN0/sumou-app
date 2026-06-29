import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/admin_providers.dart';
import 'widgets/admin_chips.dart';

enum _UserFilter { all, active, inactive, managers, photographers, admins }

extension _UserFilterView on _UserFilter {
  String get label => switch (this) {
    _UserFilter.all => 'الكل',
    _UserFilter.active => 'نشط',
    _UserFilter.inactive => 'غير نشط',
    _UserFilter.managers => 'المدراء',
    _UserFilter.photographers => 'المصورين',
    _UserFilter.admins => 'الأدمن',
  };

  bool matches(UserModel u) => switch (this) {
    _UserFilter.all => true,
    _UserFilter.active => u.active,
    _UserFilter.inactive => !u.active,
    _UserFilter.managers => u.hasRole(RoleType.manager),
    _UserFilter.photographers => u.hasRole(RoleType.photographer),
    _UserFilter.admins => u.hasRole(RoleType.admin),
  };
}

/// Admin users management: mobile cards with search + filters. Tapping a user
/// opens a details sheet with an activate/deactivate action (mock-backed). No
/// create/delete; profile editing is a placeholder.
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
    final matchesQuery =
        q.isEmpty ||
        user.fullName.toLowerCase().contains(q) ||
        user.username.toLowerCase().contains(q);
    return matchesQuery && _filter.matches(user);
  }

  Future<void> _showUserSheet(UserModel user) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetContext) => _UserDetailSheet(
            user: user,
            onToggleActive: () {
              Navigator.of(sheetContext).pop();
              _toggleActive(user);
            },
            onEdit: () {
              Navigator.of(sheetContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تعديل البيانات - قريبًا')),
              );
            },
          ),
    );
  }

  Future<void> _toggleActive(UserModel user) async {
    final activate = !user.active;
    final ok = await showSumouConfirmSheet(
      context,
      title: activate ? 'تفعيل المستخدم' : 'تعطيل المستخدم',
      message:
          activate
              ? 'سيتمكن ${user.fullName} من استخدام النظام.'
              : 'لن يتمكن ${user.fullName} من تسجيل الدخول.',
      confirmLabel: activate ? 'تفعيل' : 'تعطيل',
      destructive: !activate,
    );
    if (!ok) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final updated = await ref
        .read(userRepositoryProvider)
        .setUserActive(user.id, activate);
    ref.invalidate(usersListProvider);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          updated == null
              ? 'تعذّر تحديث الحالة'
              : (activate ? 'تم تفعيل المستخدم' : 'تم تعطيل المستخدم'),
        ),
      ),
    );
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
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _UserFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _UserFilter.values[i];
              return AdminFilterChip(
                label: f.label,
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (_, __) => const Center(child: Text('تعذّر تحميل المستخدمين')),
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
                itemBuilder:
                    (_, i) => _UserCard(
                      user: filtered[i],
                      onTap: () => _showUserSheet(filtered[i]),
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, this.onTap});

  final UserModel user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final roleModel = RoleModel.of(user.defaultRole);
    final extraRoles = user.roles.where((r) => r != user.defaultRole).toList();

    return SumouCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminAvatar(
                initials: user.avatarInitials,
                color: roleModel.color,
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
          if (user.photoTypes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in user.photoTypes) AdminTextChip(t)],
            ),
          ],
        ],
      ),
    );
  }
}

class _UserDetailSheet extends StatelessWidget {
  const _UserDetailSheet({
    required this.user,
    required this.onToggleActive,
    required this.onEdit,
  });

  final UserModel user;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final roleModel = RoleModel.of(user.defaultRole);
    final extraRoles = user.roles.where((r) => r != user.defaultRole).toList();
    final permissions =
        AppFeature.values.where((f) => user.hasPermission(f)).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AdminAvatar(
                    initials: user.avatarInitials,
                    color: roleModel.color,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName, style: AppTextStyles.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          '@${user.username}',
                          style: AppTextStyles.bodyMuted,
                        ),
                      ],
                    ),
                  ),
                  AdminStatusPill(active: user.active),
                ],
              ),
              const SizedBox(height: 20),
              Text('الأدوار', style: AppTextStyles.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AdminRoleChip(user.defaultRole),
                  for (final role in extraRoles) AdminRoleChip(role),
                ],
              ),
              if (user.photoTypes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('أنواع التصوير', style: AppTextStyles.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final t in user.photoTypes) AdminTextChip(t)],
                ),
              ],
              const SizedBox(height: 16),
              Text('الصلاحيات', style: AppTextStyles.label),
              const SizedBox(height: 8),
              if (permissions.isEmpty)
                Text('لا توجد صلاحيات', style: AppTextStyles.bodyMuted)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in permissions)
                      AdminTextChip(featureLabelAr(f)),
                  ],
                ),
              const SizedBox(height: 24),
              SumouButton(
                label: user.active ? 'تعطيل المستخدم' : 'تفعيل المستخدم',
                icon: user.active ? Icons.block : Icons.check_circle_outline,
                variant:
                    user.active
                        ? SumouButtonVariant.danger
                        : SumouButtonVariant.primary,
                onPressed: onToggleActive,
              ),
              const SizedBox(height: 10),
              SumouButton(
                label: 'تعديل البيانات - قريبًا',
                variant: SumouButtonVariant.secondary,
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
