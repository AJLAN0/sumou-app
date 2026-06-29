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

/// Short Arabic description for a feature permission (shown in the editor).
String _featureDescAr(AppFeature f) => switch (f) {
  AppFeature.canAddProject => 'إنشاء مشاريع جديدة',
  AppFeature.canEditProject => 'تعديل بيانات المشاريع',
  AppFeature.canAssignPhotographers => 'إسناد المصورين للمشاريع',
  AppFeature.canUpdateStages => 'تحديث مراحل المشروع',
  AppFeature.canRequestClosure => 'إرسال طلب إغلاق',
  AppFeature.canApproveClosure => 'اعتماد أو رفض طلبات الإغلاق',
  AppFeature.canManageUsers => 'إدارة حسابات المستخدمين',
  AppFeature.canManagePermissions => 'التحكم في صلاحيات المستخدمين',
  AppFeature.canViewReports => 'الاطلاع على التقارير',
  AppFeature.canManageAttendance => 'إدارة الحضور والانصراف',
  _ => '',
};

/// Sensitive permissions that warrant a confirmation before saving.
const Set<AppFeature> _sensitive = {
  AppFeature.canManageUsers,
  AppFeature.canManagePermissions,
  AppFeature.canApproveClosure,
};

/// Grouped feature permissions shown in the editor.
const List<({String title, List<AppFeature> features})> _permGroups = [
  (
    title: 'إدارة المشاريع',
    features: [
      AppFeature.canAddProject,
      AppFeature.canEditProject,
      AppFeature.canAssignPhotographers,
    ],
  ),
  (
    title: 'المراحل والإغلاق',
    features: [
      AppFeature.canUpdateStages,
      AppFeature.canRequestClosure,
      AppFeature.canApproveClosure,
    ],
  ),
  (
    title: 'إدارة النظام',
    features: [
      AppFeature.canManageUsers,
      AppFeature.canManagePermissions,
      AppFeature.canViewReports,
    ],
  ),
  (title: 'الحضور', features: [AppFeature.canManageAttendance]),
];

enum _AccessFilter { all, managers, photographers, admins, management }

extension _AccessFilterView on _AccessFilter {
  String get label => switch (this) {
    _AccessFilter.all => 'الكل',
    _AccessFilter.managers => 'المدراء',
    _AccessFilter.photographers => 'المصورين',
    _AccessFilter.admins => 'الأدمن',
    _AccessFilter.management => 'صلاحيات إدارة',
  };

  bool matches(UserModel u) => switch (this) {
    _AccessFilter.all => true,
    _AccessFilter.managers => u.hasRole(RoleType.manager),
    _AccessFilter.photographers => u.hasRole(RoleType.photographer),
    _AccessFilter.admins => u.hasRole(RoleType.admin),
    _AccessFilter.management =>
      u.hasPermission(AppFeature.canManageUsers) ||
          u.hasPermission(AppFeature.canManagePermissions),
  };
}

/// Routed wrapper for [AccessControlScreen] (admin dashboard deep-link). The
/// shell renders the screen directly as a tab body without an app bar.
class AdminAccessPage extends StatelessWidget {
  const AdminAccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'الأدوار والصلاحيات',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const AccessControlScreen(),
    );
  }
}

/// Unified access control: manage each user's **roles** (what they can navigate)
/// and **permissions** (what actions they can take) from one place. Mock-backed.
///
/// Roles and permissions were previously two separate screens; merging them
/// lets the admin see and adjust both together, with a one-tap "apply the
/// role's default permissions" helper to keep them in sync.
class AccessControlScreen extends ConsumerStatefulWidget {
  const AccessControlScreen({super.key});

  @override
  ConsumerState<AccessControlScreen> createState() =>
      _AccessControlScreenState();
}

class _AccessControlScreenState extends ConsumerState<AccessControlScreen> {
  String _query = '';
  _AccessFilter _filter = _AccessFilter.all;

  bool _matches(UserModel u) {
    final q = _query.trim().toLowerCase();
    final matchesQuery =
        q.isEmpty ||
        u.fullName.toLowerCase().contains(q) ||
        u.username.toLowerCase().contains(q);
    return matchesQuery && _filter.matches(u);
  }

  Future<void> _edit(UserModel user) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AccessEditSheet(user: user),
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
            itemCount: _AccessFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _AccessFilter.values[i];
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
            error: (_, __) =>
                const Center(child: Text('تعذّر تحميل المستخدمين')),
            data: (users) {
              final filtered = users.where(_matches).toList();
              if (filtered.isEmpty) {
                return const SumouEmptyState(
                  title: 'لا توجد نتائج',
                  message: 'جرّب تعديل البحث أو الفلاتر',
                  icon: Icons.shield_outlined,
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _AccessCard(
                  user: filtered[i],
                  onTap: () => _edit(filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.user, required this.onTap});

  final UserModel user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roleModel = RoleModel.of(user.defaultRole);
    final extraRoles = user.roles.where((r) => r != user.defaultRole).toList();
    final enabled =
        AppFeature.values.where((f) => user.permissions.has(f)).toList();
    final top = enabled.take(3).toList();

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
              AdminStatusPill(active: user.active),
            ],
          ),
          const SizedBox(height: 12),
          Text('الأدوار', style: AppTextStyles.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminRoleChip(user.defaultRole),
              for (final r in extraRoles) AdminRoleChip(r),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'الصلاحيات المفعّلة: ${enabled.length}',
            style: AppTextStyles.label.copyWith(color: AppColors.accentGreen),
          ),
          const SizedBox(height: 8),
          if (enabled.isEmpty)
            Text('لا توجد صلاحيات مفعّلة', style: AppTextStyles.bodyMuted)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in top) AdminTextChip(featureLabelAr(f)),
                if (enabled.length > top.length)
                  AdminTextChip(
                    '+${enabled.length - top.length}',
                    color: AppColors.textMuted,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Combined roles + permissions editor for one user. Keeps a local working copy
/// and saves both through the mock repository on confirm.
class _AccessEditSheet extends ConsumerStatefulWidget {
  const _AccessEditSheet({required this.user});

  final UserModel user;

  @override
  ConsumerState<_AccessEditSheet> createState() => _AccessEditSheetState();
}

class _AccessEditSheetState extends ConsumerState<_AccessEditSheet> {
  late RoleType _default;
  late Set<RoleType> _roles;
  late FeaturePermissions _perms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _default = widget.user.defaultRole;
    _roles = {...widget.user.roles, _default};
    _perms = widget.user.permissions;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  void _togglePerm(AppFeature f, bool value) {
    setState(() => _perms = _perms.setFeature(f, value));
  }

  /// Smart helper: overwrite permissions with the default set for the chosen
  /// default role, keeping roles and permissions consistent in one tap.
  void _applyRoleDefaults() {
    setState(() => _perms = FeaturePermissions.defaultsFor(_default));
    _snack('تم تطبيق صلاحيات دور ${_default.nameAr}');
  }

  bool get _sensitiveChanged =>
      _sensitive.any((f) => _perms.has(f) != widget.user.permissions.has(f));

  Future<void> _save() async {
    if (!_roles.contains(_default)) {
      _snack('الدور الافتراضي يجب أن يكون ضمن أدوار المستخدم');
      return;
    }
    final ok = await showSumouConfirmSheet(
      context,
      title: 'حفظ الأدوار والصلاحيات',
      message: _sensitiveChanged
          ? 'تتضمن التغييرات صلاحيات حساسة (إدارة/اعتماد). هل تريد الحفظ؟'
          : 'تحديث أدوار وصلاحيات ${widget.user.fullName}؟',
      confirmLabel: 'حفظ',
      destructive: _sensitiveChanged,
    );
    if (!ok) return;
    if (!mounted) return;
    setState(() => _saving = true);
    final repo = ref.read(userRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final rolesResult = await repo.updateUserRoles(
      widget.user.id,
      defaultRole: _default,
      roles: _roles.toList(),
    );
    final permsResult =
        await repo.updateUserPermissions(widget.user.id, _perms);
    ref.invalidate(usersListProvider);
    if (!mounted) return;
    navigator.pop();
    final ok2 = rolesResult != null && permsResult != null;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok2 ? 'تم تحديث الأدوار والصلاحيات' : 'تعذّر تحديث الأدوار والصلاحيات',
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
          maxHeight: MediaQuery.of(context).size.height * 0.92,
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
              const SizedBox(height: 16),
              const _ImpactNote(),

              // ---- roles ----
              const SizedBox(height: 20),
              Text('الأدوار', style: AppTextStyles.titleMedium),
              const SizedBox(height: 8),
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
              const SizedBox(height: 16),
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

              // ---- permissions ----
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text('الصلاحيات', style: AppTextStyles.titleMedium),
                  ),
                  GestureDetector(
                    onTap: _applyRoleDefaults,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_fix_high,
                          size: 16,
                          color: AppColors.accentGreen,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'تطبيق صلاحيات الدور',
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.accentGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              for (final group in _permGroups) ...[
                const SizedBox(height: 14),
                Text(group.title, style: AppTextStyles.label),
                const SizedBox(height: 8),
                for (final f in group.features)
                  _PermSwitch(
                    label: featureLabelAr(f),
                    description: _featureDescAr(f),
                    value: _perms.has(f),
                    sensitive: _sensitive.contains(f),
                    onChanged: (v) => _togglePerm(f, v),
                  ),
              ],
              const SizedBox(height: 20),
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

class _ImpactNote extends StatelessWidget {
  const _ImpactNote();

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      color: AppColors.surfaceSecondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.projectTeal,
              ),
              const SizedBox(width: 8),
              Text('الأدوار والصلاحيات', style: AppTextStyles.label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'الأدوار تتحكم في التنقل العام.',
            style: AppTextStyles.bodyMuted,
          ),
          Text(
            'الصلاحيات تتحكم في الأفعال المتاحة داخل الدور.',
            style: AppTextStyles.bodyMuted,
          ),
        ],
      ),
    );
  }
}

class _PermSwitch extends StatelessWidget {
  const _PermSwitch({
    required this.label,
    required this.description,
    required this.value,
    required this.sensitive,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final bool sensitive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: AppTextStyles.body),
                    if (sensitive) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.lock_outline,
                        size: 13,
                        color: AppColors.financeYellow,
                      ),
                    ],
                  ],
                ),
                if (description.isNotEmpty)
                  Text(description, style: AppTextStyles.label),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: AppColors.accentGreen,
            onChanged: onChanged,
          ),
        ],
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
