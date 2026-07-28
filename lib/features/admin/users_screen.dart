import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/user_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'providers/admin_providers.dart';
import 'temporary_password_dialog.dart';
import 'user_form_sheet.dart';
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

/// Routed wrapper for [UsersScreen] (used by the admin dashboard deep-link).
/// The shell renders [UsersScreen] directly as a tab body, so it stays
/// app-bar-less; this page adds the scaffold + back button for push navigation.
class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'إدارة المستخدمين',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const UsersScreen(),
    );
  }
}

/// Admin users management: real RLS reads plus trusted create/reset operations.
/// Other mutations stay available only in explicit mock repositories.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';
  _UserFilter _filter = _UserFilter.all;
  final Set<String> _busyUserIds = {};

  bool _matches(UserModel user) {
    final q = _query.trim().toLowerCase();
    final matchesQuery =
        q.isEmpty ||
        user.fullName.toLowerCase().contains(q) ||
        user.username.toLowerCase().contains(q);
    return matchesQuery && _filter.matches(user);
  }

  Future<void> _showUserSheet(UserModel user) {
    final repo = ref.read(userRepositoryProvider);
    final actor = ref.read(authControllerProvider).currentUser;
    final isAdmin = actor?.hasRole(RoleType.admin) ?? false;
    final canManageUsers =
        isAdmin && (actor?.hasPermission(AppFeature.canManageUsers) ?? false);
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
            canToggleActive: canManageUsers && repo.capabilities.canSetActive,
            canEdit: canManageUsers && repo.capabilities.canEditProfile,
            canResetPassword:
                canManageUsers && repo.capabilities.canResetPassword,
            showDelete: canManageUsers && repo.capabilities.canDelete,
            busy: _busyUserIds.contains(user.id),
            onToggleActive: () {
              Navigator.of(sheetContext).pop();
              _toggleActive(user);
            },
            onEdit: () {
              Navigator.of(sheetContext).pop();
              showUserFormSheet(context, user: user);
            },
            onResetPassword: () {
              Navigator.of(sheetContext).pop();
              _resetPassword(user);
            },
            onDelete: () {
              Navigator.of(sheetContext).pop();
              _deleteUser(user);
            },
          ),
    );
  }

  Future<void> _createUser() async {
    final result = await showUserFormSheet(context);
    if (result == null) return;
    if (!mounted) {
      result.temporaryPassword.clear();
      return;
    }
    await showTemporaryPasswordDialog(
      context,
      password: result.temporaryPassword,
      title: 'تم إنشاء المستخدم',
    );
  }

  Future<void> _resetPassword(UserModel user) async {
    if (_busyUserIds.contains(user.id)) return;
    final confirmed = await showSumouConfirmSheet(
      context,
      title: 'إعادة تعيين كلمة المرور',
      message:
          'سيتم إنشاء كلمة مرور مؤقتة لـ ${user.fullName} وإلزامه بتغييرها عند تسجيل الدخول.',
      confirmLabel: 'إعادة التعيين',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyUserIds.add(user.id));
    try {
      final result = await ref
          .read(userRepositoryProvider)
          .resetPassword(user.id);
      ref.invalidate(usersListProvider);
      if (!mounted) {
        result.temporaryPassword.clear();
        return;
      }
      await showTemporaryPasswordDialog(
        context,
        password: result.temporaryPassword,
        title: 'تمت إعادة تعيين كلمة المرور',
      );
    } on UserRepositoryException catch (error) {
      if (mounted) _showMessage(error.messageAr);
    } catch (_) {
      if (mounted) _showMessage('تعذّر تنفيذ العملية، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _busyUserIds.remove(user.id));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteUser(UserModel user) async {
    final ok = await showSumouConfirmSheet(
      context,
      title: 'حذف المستخدم',
      message: 'سيتم حذف حساب ${user.fullName} نهائياً. لا يمكن التراجع.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed = await ref
          .read(userRepositoryProvider)
          .deleteUser(user.id);
      ref.invalidate(usersListProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(removed ? 'تم حذف المستخدم' : 'تعذّر حذف المستخدم'),
        ),
      );
    } on UserRepositoryException catch (error) {
      if (mounted) _showMessage(error.messageAr);
    }
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
    try {
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
    } on UserRepositoryException catch (error) {
      if (mounted) _showMessage(error.messageAr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersListProvider);
    final repository = ref.read(userRepositoryProvider);
    final actor = ref.watch(authControllerProvider).currentUser;
    final isAdmin = actor?.hasRole(RoleType.admin) ?? false;
    final canCreate =
        repository.capabilities.canCreate &&
        isAdmin &&
        (actor?.hasPermission(AppFeature.canManageUsers) ?? false) &&
        (actor?.hasPermission(AppFeature.canManagePermissions) ?? false);

    return Column(
      children: [
        SumouButton(
          label: 'إضافة مستخدم',
          icon: Icons.person_add_alt_1,
          onPressed: canCreate ? _createUser : null,
        ),
        const SizedBox(height: 12),
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
                (_, __) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('تعذّر تحميل المستخدمين'),
                      TextButton(
                        onPressed: () => ref.invalidate(usersListProvider),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
            data: (users) {
              final filtered = users.where(_matches).toList();
              if (filtered.isEmpty) {
                return SumouEmptyState(
                  title: 'لا يوجد مستخدمون',
                  message:
                      users.isEmpty
                          ? 'لم تتم إضافة مستخدمين بعد'
                          : 'لا توجد نتائج مطابقة',
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
    required this.canToggleActive,
    required this.canEdit,
    required this.canResetPassword,
    required this.showDelete,
    required this.busy,
    required this.onToggleActive,
    required this.onEdit,
    required this.onResetPassword,
    required this.onDelete,
  });

  final UserModel user;
  final bool canToggleActive;
  final bool canEdit;
  final bool canResetPassword;
  final bool showDelete;
  final bool busy;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;

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
                label:
                    canToggleActive
                        ? (user.active ? 'تعطيل المستخدم' : 'تفعيل المستخدم')
                        : 'تفعيل وتعطيل المستخدم (غير متاح)',
                icon: user.active ? Icons.block : Icons.check_circle_outline,
                variant:
                    user.active
                        ? SumouButtonVariant.danger
                        : SumouButtonVariant.primary,
                onPressed: canToggleActive && !busy ? onToggleActive : null,
              ),
              const SizedBox(height: 10),
              SumouButton(
                label: canEdit ? 'تعديل البيانات' : 'تعديل البيانات (غير متاح)',
                variant: SumouButtonVariant.secondary,
                icon: Icons.edit_outlined,
                onPressed: canEdit && !busy ? onEdit : null,
              ),
              const SizedBox(height: 10),
              SumouButton(
                label: 'إعادة تعيين كلمة المرور',
                variant: SumouButtonVariant.secondary,
                icon: Icons.password_outlined,
                loading: busy,
                onPressed: canResetPassword && !busy ? onResetPassword : null,
              ),
              if (showDelete) ...[
                const SizedBox(height: 10),
                SumouButton(
                  label: 'حذف المستخدم',
                  variant: SumouButtonVariant.danger,
                  icon: Icons.delete_outline,
                  onPressed: busy ? null : onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
