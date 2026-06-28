import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

enum _PermFilter {
  all,
  management,
  addProject,
  assign,
  updateStages,
  requestClosure,
  approveClosure,
}

extension _PermFilterView on _PermFilter {
  String get label => switch (this) {
    _PermFilter.all => 'الكل',
    _PermFilter.management => 'لديه صلاحيات إدارة',
    _PermFilter.addProject => 'يستطيع إنشاء مشاريع',
    _PermFilter.assign => 'يستطيع إسناد مصورين',
    _PermFilter.updateStages => 'يستطيع تحديث المراحل',
    _PermFilter.requestClosure => 'يستطيع طلب الإغلاق',
    _PermFilter.approveClosure => 'يستطيع اعتماد الإغلاق',
  };

  bool matches(UserModel u) => switch (this) {
    _PermFilter.all => true,
    _PermFilter.management =>
      u.hasPermission(AppFeature.canManageUsers) ||
          u.hasPermission(AppFeature.canManagePermissions),
    _PermFilter.addProject => u.hasPermission(AppFeature.canAddProject),
    _PermFilter.assign => u.hasPermission(AppFeature.canAssignPhotographers),
    _PermFilter.updateStages => u.hasPermission(AppFeature.canUpdateStages),
    _PermFilter.requestClosure => u.hasPermission(AppFeature.canRequestClosure),
    _PermFilter.approveClosure => u.hasPermission(AppFeature.canApproveClosure),
  };
}

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

/// Admin permissions control: per-user feature permission summary + editor.
/// Mock-backed. No role management here.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  String _query = '';
  _PermFilter _filter = _PermFilter.all;

  bool _matches(UserModel u) {
    final q = _query.trim().toLowerCase();
    final matchesQuery =
        q.isEmpty ||
        u.fullName.toLowerCase().contains(q) ||
        u.username.toLowerCase().contains(q);
    return matchesQuery && _filter.matches(u);
  }

  Future<void> _editPermissions(UserModel user) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PermissionEditSheet(user: user),
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
            itemCount: _PermFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _PermFilter.values[i];
              return _FilterChip(
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
                const Center(child: Text('تعذّر تحميل الصلاحيات')),
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
                itemBuilder: (_, i) => _PermissionCard(
                  user: filtered[i],
                  onTap: () => _editPermissions(filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.user, required this.onTap});

  final UserModel user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roleModel = RoleModel.of(user.defaultRole);
    final enabled = AppFeature.values
        .where((f) => user.permissions.has(f))
        .toList();
    final top = enabled.take(3).toList();

    return SumouCard(
      onTap: onTap,
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
              AdminStatusPill(active: user.active),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final r in user.roles) AdminRoleChip(r)],
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

class _PermissionEditSheet extends ConsumerStatefulWidget {
  const _PermissionEditSheet({required this.user});

  final UserModel user;

  @override
  ConsumerState<_PermissionEditSheet> createState() =>
      _PermissionEditSheetState();
}

class _PermissionEditSheetState extends ConsumerState<_PermissionEditSheet> {
  late FeaturePermissions _perms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _perms = widget.user.permissions;
  }

  void _toggle(AppFeature f, bool value) {
    setState(() => _perms = _perms.setFeature(f, value));
  }

  bool get _sensitiveChanged => _sensitive.any(
    (f) => _perms.has(f) != widget.user.permissions.has(f),
  );

  Future<void> _save() async {
    final ok = await showSumouConfirmSheet(
      context,
      title: 'حفظ الصلاحيات',
      message: _sensitiveChanged
          ? 'تتضمن التغييرات صلاحيات حساسة (إدارة/اعتماد). هل تريد الحفظ؟'
          : 'تحديث صلاحيات ${widget.user.fullName}؟',
      confirmLabel: 'حفظ',
      destructive: _sensitiveChanged,
    );
    if (!ok) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final updated = await ref
        .read(userRepositoryProvider)
        .updateUserPermissions(widget.user.id, _perms);
    ref.invalidate(usersListProvider);
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          updated == null ? 'تعذّر تحديث الصلاحيات' : 'تم تحديث الصلاحيات',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
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
              for (final group in _permGroups) ...[
                const SizedBox(height: 16),
                Text(group.title, style: AppTextStyles.titleMedium),
                const SizedBox(height: 8),
                for (final f in group.features)
                  _PermSwitch(
                    label: featureLabelAr(f),
                    description: _featureDescAr(f),
                    value: _perms.has(f),
                    sensitive: _sensitive.contains(f),
                    onChanged: (v) => _toggle(f, v),
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
              Text('كيف تعمل الصلاحيات', style: AppTextStyles.label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'الصلاحيات تتحكم في ظهور الأزرار والإجراءات داخل التطبيق.',
            style: AppTextStyles.bodyMuted,
          ),
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
