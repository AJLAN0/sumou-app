import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/admin_providers.dart';
import 'widgets/admin_chips.dart';

/// Admin role management: view every user's roles and change them. Mock-backed.
/// No permission-flag editing here — that is a separate step.
class AdminRoleManagementScreen extends ConsumerStatefulWidget {
  const AdminRoleManagementScreen({super.key});

  @override
  ConsumerState<AdminRoleManagementScreen> createState() =>
      _AdminRoleManagementScreenState();
}

class _AdminRoleManagementScreenState
    extends ConsumerState<AdminRoleManagementScreen> {
  String _query = '';
  RoleType? _roleFilter; // null = all

  bool _matches(UserModel u) {
    final q = _query.trim().toLowerCase();
    final matchesQuery =
        q.isEmpty ||
        u.fullName.toLowerCase().contains(q) ||
        u.username.toLowerCase().contains(q);
    final matchesRole = _roleFilter == null || u.hasRole(_roleFilter!);
    return matchesQuery && matchesRole;
  }

  Future<void> _editRoles(UserModel user) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RoleEditSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersListProvider);

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'إدارة الأدوار',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('تعذّر تحميل المستخدمين')),
        data: (users) {
          // Role filter options: only roles actually held by some user.
          final present = <RoleType>{for (final u in users) ...u.roles}.toList();
          final filtered = users.where(_matches).toList();

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
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'الكل',
                      selected: _roleFilter == null,
                      onTap: () => setState(() => _roleFilter = null),
                    ),
                    for (final r in present) ...[
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: r.nameAr,
                        selected: _roleFilter == r,
                        onTap: () => setState(() => _roleFilter = r),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const SumouEmptyState(
                        title: 'لا يوجد مستخدمون',
                        message: 'لا توجد نتائج مطابقة',
                        icon: Icons.group_outlined,
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _RoleUserCard(
                          user: filtered[i],
                          onTap: () => _editRoles(filtered[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoleUserCard extends StatelessWidget {
  const _RoleUserCard({required this.user, required this.onTap});

  final UserModel user;
  final VoidCallback onTap;

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
              _Avatar(initials: user.avatarInitials, color: roleModel.color),
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
          Text('الدور الافتراضي', style: AppTextStyles.label),
          const SizedBox(height: 6),
          AdminRoleChip(user.defaultRole),
          if (extraRoles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('أدوار إضافية', style: AppTextStyles.label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final r in extraRoles) AdminRoleChip(r)],
            ),
          ],
        ],
      ),
    );
  }
}

/// Stateful editor for one user's roles. Keeps a local working copy and saves
/// it through the mock repository on confirm.
class _RoleEditSheet extends ConsumerStatefulWidget {
  const _RoleEditSheet({required this.user});

  final UserModel user;

  @override
  ConsumerState<_RoleEditSheet> createState() => _RoleEditSheetState();
}

class _RoleEditSheetState extends ConsumerState<_RoleEditSheet> {
  late RoleType _default;
  late Set<RoleType> _roles;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _default = widget.user.defaultRole;
    _roles = {...widget.user.roles};
    // Keep the invariant that the default is always part of the roles.
    _roles.add(_default);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _toggleRole(RoleType r) {
    if (_roles.contains(r)) {
      if (r == _default) {
        _snack('لا يمكن إزالة الدور الافتراضي، غيّر الدور الافتراضي أولاً');
        return;
      }
      setState(() => _roles.remove(r));
    } else {
      setState(() => _roles.add(r));
    }
  }

  Future<void> _save() async {
    if (!_roles.contains(_default)) {
      _snack('الدور الافتراضي يجب أن يكون ضمن أدوار المستخدم');
      return;
    }
    final ok = await showSumouConfirmSheet(
      context,
      title: 'حفظ الأدوار',
      message: 'تحديث أدوار ${widget.user.fullName}؟',
      confirmLabel: 'حفظ',
    );
    if (!ok) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final updated = await ref
        .read(userRepositoryProvider)
        .updateUserRoles(
          widget.user.id,
          defaultRole: _default,
          roles: _roles.toList(),
        );
    ref.invalidate(usersListProvider);
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          updated == null ? 'تعذّر تحديث الأدوار' : 'تم تحديث الأدوار',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final defaultOptions = _roles.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _Avatar(
                    initials: user.avatarInitials,
                    color: RoleModel.of(_default).color,
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
              const SizedBox(height: 12),
              Text(
                'الأدوار تحدد التنقل والإجراءات المتاحة للمستخدم.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 20),
              Text('الدور الافتراضي', style: AppTextStyles.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in defaultOptions)
                    _SelectChip(
                      label: r.nameAr,
                      selected: _default == r,
                      onTap: () => setState(() => _default = r),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('كل الأدوار', style: AppTextStyles.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in RoleType.values)
                    _SelectChip(
                      label: r.nameAr,
                      selected: _roles.contains(r),
                      onTap: () => _toggleRole(r),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SumouButton(
                label: 'حفظ التغييرات',
                icon: Icons.check,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- shared bits ------------------------------------------------------------

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
        child: Text(label, style: AppTextStyles.label.copyWith(color: color)),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentGreen.withValues(alpha: 0.15)
              : AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accentGreen : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 14, color: AppColors.accentGreen),
              const SizedBox(width: 4),
            ],
            Text(label, style: AppTextStyles.label.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Text(initials, style: AppTextStyles.body.copyWith(color: color)),
    );
  }
}
