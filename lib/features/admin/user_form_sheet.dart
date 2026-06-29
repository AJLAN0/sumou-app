import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/admin_providers.dart';

/// Open the add/edit user form. Pass [user] to edit, or omit to create a new
/// account. Saves through the user repository and refreshes [usersListProvider].
Future<void> showUserFormSheet(
  BuildContext context, {
  UserModel? user,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _UserFormSheet(user: user),
  );
}

/// Add/edit form for a staff account. Identity, default role, roles, photo
/// types, and the active flag. Permissions are managed in the access-control
/// screen, not here.
class _UserFormSheet extends ConsumerStatefulWidget {
  const _UserFormSheet({this.user});

  final UserModel? user;

  @override
  ConsumerState<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends ConsumerState<_UserFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _photoTypes;
  late RoleType _default;
  late Set<RoleType> _roles;
  late bool _active;
  bool _saving = false;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _name = TextEditingController(text: u?.fullName ?? '');
    _username = TextEditingController(text: u?.username ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _photoTypes = TextEditingController(text: (u?.photoTypes ?? []).join('، '));
    _default = u?.defaultRole ?? RoleType.manager;
    _roles = {...(u?.roles ?? const []), _default};
    _active = u?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _photoTypes.dispose();
    super.dispose();
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

  List<String> _parsePhotoTypes() => _photoTypes.text
      .split(RegExp(r'[،,]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final name = _name.text.trim();
    final username = _username.text.trim();
    if (name.isEmpty) {
      _snack('الاسم مطلوب');
      return;
    }
    if (username.isEmpty) {
      _snack('اسم المستخدم مطلوب');
      return;
    }
    if (_roles.isEmpty) {
      _snack('اختر دوراً واحداً على الأقل');
      return;
    }
    _roles.add(_default); // keep the invariant
    final email = _email.text.trim().isEmpty ? null : _email.text.trim();
    final photoTypes = _parsePhotoTypes();

    setState(() => _saving = true);
    final repo = ref.read(userRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final UserModel? result;
    if (_isEdit) {
      result = await repo.updateUser(
        widget.user!.id,
        fullName: name,
        username: username,
        email: email,
        defaultRole: _default,
        roles: _roles.toList(),
        photoTypes: photoTypes,
        active: _active,
      );
    } else {
      result = await repo.createUser(
        fullName: name,
        username: username,
        email: email,
        defaultRole: _default,
        roles: _roles.toList(),
        photoTypes: photoTypes,
        // New accounts start with the default permission set for their role.
        permissions: FeaturePermissions.defaultsFor(_default),
        active: _active,
      );
    }

    if (!mounted) return;
    if (result == null) {
      setState(() => _saving = false);
      _snack('تعذّر الحفظ، قد يكون اسم المستخدم مستخدماً بالفعل');
      return;
    }
    ref.invalidate(usersListProvider);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_isEdit ? 'تم تحديث المستخدم' : 'تم إضافة المستخدم'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultOptions = _roles.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isEdit ? 'تعديل المستخدم' : 'إضافة مستخدم',
                style: AppTextStyles.titleLarge,
              ),
              const SizedBox(height: 16),
              SumouTextField(
                controller: _name,
                label: 'الاسم الكامل',
                hint: 'مثال: سعد المطيري',
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 12),
              SumouTextField(
                controller: _username,
                label: 'اسم المستخدم',
                hint: 'حروف إنجليزية بدون مسافات',
                prefixIcon: Icons.alternate_email,
              ),
              const SizedBox(height: 12),
              SumouTextField(
                controller: _email,
                label: 'البريد الإلكتروني (اختياري)',
                hint: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline,
              ),
              const SizedBox(height: 12),
              SumouTextField(
                controller: _photoTypes,
                label: 'أنواع التصوير (اختياري)',
                hint: 'افصل بينها بفاصلة',
                prefixIcon: Icons.camera_alt_outlined,
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
              const SizedBox(height: 16),
              SumouCard(
                color: AppColors.surfaceSecondary,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الحساب مفعّل', style: AppTextStyles.body),
                          Text(
                            'المستخدم غير المفعّل لا يستطيع تسجيل الدخول',
                            style: AppTextStyles.label,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _active,
                      activeColor: AppColors.accentGreen,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SumouButton(
                label: _isEdit ? 'حفظ التغييرات' : 'إضافة المستخدم',
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

/// Selectable pill chip (reused by the role pickers above).
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
