import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../projects/providers/projects_providers.dart';
import 'providers/admin_providers.dart';

/// Photo/team role types offered when editing a project team.
const List<String> _kPhotoTypes = [
  'مصور فوتوغرافي',
  'مصور فيديو',
  'درون',
  'مونتاج',
  'مساعد مصور',
  'كواليس',
  'انستقرام',
  'تيك توك',
];

/// A team assignment being edited.
class _TeamDraft {
  _TeamDraft({
    required this.userId,
    required this.personName,
    required this.photoType,
    this.value = 0,
  });

  final String? userId;
  final String personName;
  String photoType;
  num value;
}

/// Admin team oversight + editing for one project: change manager, add/remove
/// photographers, change a member's role/type. Mock-backed.
class AdminProjectTeamScreen extends ConsumerWidget {
  const AdminProjectTeamScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      padding: EdgeInsets.zero,
      appBar: SumouAppBar(
        title: 'إدارة الفريق',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: projectAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('تعذّر تحميل المشروع')),
        data: (project) {
          if (project == null) {
            return const SumouEmptyState(
              title: 'المشروع غير موجود',
              icon: Icons.search_off,
            );
          }
          return _TeamBody(project: project);
        },
      ),
    );
  }
}

class _TeamBody extends ConsumerStatefulWidget {
  const _TeamBody({required this.project});

  final ProjectModel project;

  @override
  ConsumerState<_TeamBody> createState() => _TeamBodyState();
}

class _TeamBodyState extends ConsumerState<_TeamBody> {
  final List<_TeamDraft> _team = [];
  late String _managerId;
  String? _managerName;
  String _query = '';
  String? _typeFilter;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _managerId = widget.project.managerId;
    _managerName = widget.project.managerName;
    for (final r in widget.project.teamRoles) {
      _team.add(
        _TeamDraft(
          userId: r.userId,
          personName: r.personName,
          photoType: r.type,
          value: r.value,
        ),
      );
    }
  }

  bool _isAdded(String userId) => _team.any((d) => d.userId == userId);

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _changeManager(List<UserModel> managers) async {
    final chosen = await _showUserPicker(
      title: 'اختر مدير المشروع',
      users: managers,
      selectedId: _managerId,
    );
    if (chosen == null || chosen.id == _managerId) return;
    if (!mounted) return;
    final ok = await showSumouConfirmSheet(
      context,
      title: 'تغيير مدير المشروع',
      message: 'سيتم تعيين «${chosen.fullName}» مديراً لهذا المشروع.',
      confirmLabel: 'تأكيد',
    );
    if (!ok) return;
    final messenger = ScaffoldMessenger.of(context);
    final updated = await ref
        .read(projectRepositoryProvider)
        .setProjectManager(
          widget.project.id,
          managerId: chosen.id,
          managerName: chosen.fullName,
        );
    ref.invalidate(projectByIdProvider(widget.project.id));
    ref.invalidate(allProjectsProvider);
    ref.invalidate(managerProjectsProvider);
    if (!mounted) return;
    if (updated == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر تغيير المدير')),
      );
      return;
    }
    setState(() {
      _managerId = chosen.id;
      _managerName = chosen.fullName;
    });
    messenger.showSnackBar(const SnackBar(content: Text('تم تغيير المدير')));
  }

  void _addPhotographer(UserModel u) {
    setState(() {
      _team.add(
        _TeamDraft(
          userId: u.id,
          personName: u.fullName,
          photoType: u.photoTypes.isNotEmpty
              ? u.photoTypes.first
              : _kPhotoTypes.first,
        ),
      );
    });
  }

  Future<void> _removeAt(int index) async {
    final draft = _team[index];
    final ok = await showSumouConfirmSheet(
      context,
      title: 'إزالة عضو',
      message: 'إزالة «${draft.personName}» من فريق المشروع؟',
      confirmLabel: 'إزالة',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _team.removeAt(index));
  }

  Future<void> _saveTeam() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final updated = await ref.read(projectRepositoryProvider).assignTeamRoles(
      widget.project.id,
      [
        for (final m in _team)
          ProjectTeamRole(
            id: '',
            projectId: '',
            type: m.photoType,
            personName: m.personName,
            userId: m.userId,
            value: m.value,
          ),
      ],
    );
    ref.invalidate(projectByIdProvider(widget.project.id));
    ref.invalidate(allProjectsProvider);
    ref.invalidate(managerProjectsProvider);
    ref.invalidate(photographerProjectsProvider);
    ref.invalidate(photographerActiveCountsProvider);
    if (!mounted) return;
    if (updated == null) {
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ الفريق')),
      );
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('تم تحديث فريق المشروع')));
  }

  Future<UserModel?> _showUserPicker({
    required String title,
    required List<UserModel> users,
    required String? selectedId,
  }) {
    return showModalBottomSheet<UserModel>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (users.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'لا يوجد أشخاص متاحون',
                      style: AppTextStyles.bodyMuted,
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final u = users[i];
                        final selected = u.id == selectedId;
                        return SumouCard(
                          borderColor: selected ? AppColors.accentGreen : null,
                          onTap: () => Navigator.of(sheetContext).pop(u),
                          child: Row(
                            children: [
                              _Avatar(initials: u.avatarInitials),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  u.fullName,
                                  style: AppTextStyles.titleMedium,
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.accentGreen,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final managersAsync = ref.watch(managerCandidatesProvider);
    final photographersAsync = ref.watch(photographerCandidatesProvider);
    final counts =
        ref.watch(photographerActiveCountsProvider).valueOrNull ??
        const <String, int>{};
    final usersById = {
      for (final u in ref.watch(usersListProvider).valueOrNull ??
          const <UserModel>[])
        u.id: u,
    };

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- project + manager ----
                SumouCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.project.name,
                        style: AppTextStyles.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.project.clientName,
                        style: AppTextStyles.bodyMuted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SumouSectionHeader(title: 'مدير المشروع'),
                const SizedBox(height: 12),
                managersAsync.when(
                  loading: () => const SumouCard(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const SumouCard(
                    child: Text(
                      'تعذّر تحميل المدراء',
                      style: AppTextStyles.bodyMuted,
                    ),
                  ),
                  data: (managers) => SumouCard(
                    onTap: () => _changeManager(managers),
                    child: Row(
                      children: [
                        _Avatar(
                          initials: UserModel.initialsFrom(_managerName ?? '—'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _managerName ?? '—',
                                style: AppTextStyles.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'اضغط لتغيير المدير',
                                style: AppTextStyles.label,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.swap_horiz, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ---- current team ----
                SumouSectionHeader(title: 'الفريق الحالي (${_team.length})'),
                const SizedBox(height: 12),
                if (_team.isEmpty)
                  SumouCard(
                    child: Text(
                      'لا يوجد أعضاء في الفريق',
                      style: AppTextStyles.bodyMuted,
                    ),
                  )
                else
                  for (var i = 0; i < _team.length; i++) ...[
                    _TeamMemberEditor(
                      draft: _team[i],
                      active: _team[i].userId == null
                          ? null
                          : usersById[_team[i].userId]?.active,
                      onTypeChanged: (t) =>
                          setState(() => _team[i].photoType = t),
                      onRemove: () => _removeAt(i),
                    ),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 20),

                // ---- add photographers ----
                const SumouSectionHeader(title: 'إضافة مصور'),
                const SizedBox(height: 12),
                SumouTextField(
                  hint: 'بحث باسم المصور',
                  prefixIcon: Icons.search,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                photographersAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => Text(
                    'تعذّر تحميل المصورين',
                    style: AppTextStyles.bodyMuted,
                  ),
                  data: (photographers) => _AddList(
                    photographers: photographers,
                    counts: counts,
                    query: _query,
                    typeFilter: _typeFilter,
                    isAdded: _isAdded,
                    onAdd: _addPhotographer,
                    onTypeFilter: (t) => setState(() => _typeFilter = t),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SumouButton(
              label: 'حفظ التغييرات',
              icon: Icons.check,
              loading: _saving,
              onPressed: _saving ? null : _saveTeam,
            ),
          ),
        ),
      ],
    );
  }
}

// ---- current-team editor ----------------------------------------------------

class _TeamMemberEditor extends StatelessWidget {
  const _TeamMemberEditor({
    required this.draft,
    required this.onTypeChanged,
    required this.onRemove,
    this.active,
  });

  final _TeamDraft draft;
  final bool? active;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final types = _kPhotoTypes.contains(draft.photoType)
        ? _kPhotoTypes
        : [draft.photoType, ..._kPhotoTypes];
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initials: UserModel.initialsFrom(draft.personName)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  draft.personName,
                  style: AppTextStyles.titleMedium,
                ),
              ),
              if (active != null) _StatusPill(active: active!),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: onRemove,
                tooltip: 'إزالة',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('نوع التصوير', style: AppTextStyles.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in types)
                _Chip(
                  label: t,
                  selected: draft.photoType == t,
                  onTap: () => onTypeChanged(t),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- add list ---------------------------------------------------------------

class _AddList extends StatelessWidget {
  const _AddList({
    required this.photographers,
    required this.counts,
    required this.query,
    required this.typeFilter,
    required this.isAdded,
    required this.onAdd,
    required this.onTypeFilter,
  });

  final List<UserModel> photographers;
  final Map<String, int> counts;
  final String query;
  final String? typeFilter;
  final bool Function(String userId) isAdded;
  final ValueChanged<UserModel> onAdd;
  final ValueChanged<String?> onTypeFilter;

  @override
  Widget build(BuildContext context) {
    final types = <String>{
      for (final u in photographers) ...u.photoTypes,
    }.toList();
    final q = query.trim().toLowerCase();
    final filtered = photographers.where((u) {
      if (isAdded(u.id)) return false; // no duplicates
      final matchesQuery = q.isEmpty ||
          u.fullName.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q);
      final matchesType = typeFilter == null || u.photoTypes.contains(typeFilter);
      return matchesQuery && matchesType;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (types.isNotEmpty) ...[
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'الكل',
                  selected: typeFilter == null,
                  onTap: () => onTypeFilter(null),
                ),
                for (final t in types) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: t,
                    selected: typeFilter == t,
                    onTap: () => onTypeFilter(t),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (filtered.isEmpty)
          const SumouEmptyState(
            title: 'لا يوجد مصورون',
            message: 'تمت إضافة الجميع أو لا توجد نتائج',
            icon: Icons.person_search_outlined,
          )
        else
          for (final u in filtered) ...[
            _AddCard(
              user: u,
              activeCount: counts[u.id] ?? 0,
              onAdd: () => onAdd(u),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _AddCard extends StatelessWidget {
  const _AddCard({
    required this.user,
    required this.activeCount,
    required this.onAdd,
  });

  final UserModel user;
  final int activeCount;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      onTap: onAdd,
      child: Row(
        children: [
          _Avatar(initials: user.avatarInitials),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName, style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '@${user.username} · $activeCount مشاريع نشطة',
                  style: AppTextStyles.bodyMuted,
                ),
              ],
            ),
          ),
          const Icon(Icons.add_circle_outline, color: AppColors.accentGreen),
        ],
      ),
    );
  }
}

// ---- small bits -------------------------------------------------------------

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentGreen : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? 'نشط' : 'غير نشط',
        style: AppTextStyles.label.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
        child: Text(label, style: AppTextStyles.label.copyWith(color: color)),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.surfaceSecondary,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: AppTextStyles.label.copyWith(color: AppColors.textWhite),
      ),
    );
  }
}
