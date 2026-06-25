import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/projects_providers.dart';
import 'widgets/project_card.dart';

/// Photo/team role types offered when assigning the team. Mock catalogue; a
/// real one arrives with the backend.
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

/// Full-screen, mobile-first flow for assigning photographers/team members to
/// an existing project.
///
/// Mock-only: loads the project by id, lets the manager pick team members,
/// choose each one's photo type and optional fee, then writes the team back via
/// [ProjectRepository.assignTeamRoles] and returns to the details screen. No
/// backend/secrets and no capacity enforcement.
class AssignPhotographersScreen extends ConsumerWidget {
  const AssignPhotographersScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      padding: EdgeInsets.zero,
      appBar: SumouAppBar(
        title: 'إسناد مصور',
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
          return _AssignBody(project: project);
        },
      ),
    );
  }
}

/// A team assignment being built up on the assign screen.
class _AssignDraft {
  _AssignDraft({
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

class _AssignBody extends ConsumerStatefulWidget {
  const _AssignBody({required this.project});

  final ProjectModel project;

  @override
  ConsumerState<_AssignBody> createState() => _AssignBodyState();
}

class _AssignBodyState extends ConsumerState<_AssignBody> {
  final List<_AssignDraft> _selected = [];
  final Map<String, TextEditingController> _feeControllers = {};

  String _query = '';
  String? _typeFilter;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-load the project's current team so saving extends it rather than
    // wiping it, and the manager sees who is already assigned.
    for (final role in widget.project.teamRoles) {
      final draft = _AssignDraft(
        userId: role.userId,
        personName: role.personName,
        photoType: role.type,
        value: role.value,
      );
      _selected.add(draft);
      _feeControllers[_keyFor(draft)] = TextEditingController(
        text: role.value > 0 ? '${role.value}' : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _feeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _keyFor(_AssignDraft d) => d.userId ?? 'name:${d.personName}';

  bool _isSelected(String userId) => _selected.any((d) => d.userId == userId);

  void _toggle(UserModel user) {
    final index = _selected.indexWhere((d) => d.userId == user.id);
    setState(() {
      if (index >= 0) {
        final removed = _selected.removeAt(index);
        _feeControllers.remove(_keyFor(removed))?.dispose();
      } else {
        final draft = _AssignDraft(
          userId: user.id,
          personName: user.fullName,
          photoType:
              user.photoTypes.isNotEmpty
                  ? user.photoTypes.first
                  : _kPhotoTypes.first,
        );
        _selected.add(draft);
        _feeControllers[_keyFor(draft)] = TextEditingController();
      }
    });
  }

  void _removeAt(int index) {
    setState(() {
      final removed = _selected.removeAt(index);
      _feeControllers.remove(_keyFor(removed))?.dispose();
    });
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار مصور واحد على الأقل')),
      );
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(projectRepositoryProvider);
    final updated = await repo.assignTeamRoles(widget.project.id, [
      for (final m in _selected)
        ProjectTeamRole(
          id: '',
          projectId: '',
          type: m.photoType,
          personName: m.personName,
          userId: m.userId,
          value: m.value,
        ),
    ]);
    // Refresh the details/list views and the capacity counts.
    ref.invalidate(projectByIdProvider(widget.project.id));
    ref.invalidate(managerProjectsProvider);
    ref.invalidate(photographerActiveCountsProvider);
    if (!mounted) return;
    if (updated == null) {
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ الإسناد')),
      );
      return;
    }
    context.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('تم تحديث فريق المشروع')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photographersAsync = ref.watch(photographerCandidatesProvider);
    final countsAsync = ref.watch(photographerActiveCountsProvider);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProjectSummary(project: widget.project),
                const SizedBox(height: 20),
                _SelectedTeam(
                  selected: _selected,
                  onTypeChanged:
                      (draft, type) => setState(() => draft.photoType = type),
                  feeControllerFor: (draft) => _feeControllers[_keyFor(draft)]!,
                  onFeeChanged:
                      (draft, raw) =>
                          draft.value = num.tryParse(raw.trim()) ?? 0,
                  onRemove: _removeAt,
                ),
                const SizedBox(height: 20),
                const SumouSectionHeader(title: 'المصورون المتاحون'),
                const SizedBox(height: 12),
                SumouTextField(
                  hint: 'بحث باسم المصور',
                  prefixIcon: Icons.search,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                photographersAsync.when(
                  loading:
                      () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  error:
                      (_, __) => Text(
                        'تعذّر تحميل المصورين',
                        style: AppTextStyles.bodyMuted,
                      ),
                  data: (photographers) {
                    final counts =
                        countsAsync.asData?.value ?? const <String, int>{};
                    return _AvailableList(
                      photographers: photographers,
                      counts: counts,
                      query: _query,
                      typeFilter: _typeFilter,
                      isSelected: _isSelected,
                      onToggle: _toggle,
                      onTypeFilter: (t) => setState(() => _typeFilter = t),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        _SaveBar(count: _selected.length, saving: _saving, onSave: _save),
      ],
    );
  }
}

// ---- project summary --------------------------------------------------------

class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context) {
    final stage = project.currentStage?.title;
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(project.name, style: AppTextStyles.titleMedium),
              ),
              const SizedBox(width: 8),
              SumouStatusChip(sumouStatusForProject(project.status)),
            ],
          ),
          const SizedBox(height: 10),
          _SummaryLine(icon: Icons.person_outline, text: project.clientName),
          _SummaryLine(
            icon: Icons.category_outlined,
            text: project.type.nameAr,
          ),
          _SummaryLine(
            icon: Icons.timeline_outlined,
            text: stage == null ? 'لا توجد مراحل' : 'المرحلة الحالية: $stage',
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}

// ---- selected team ----------------------------------------------------------

class _SelectedTeam extends StatelessWidget {
  const _SelectedTeam({
    required this.selected,
    required this.onTypeChanged,
    required this.feeControllerFor,
    required this.onFeeChanged,
    required this.onRemove,
  });

  final List<_AssignDraft> selected;
  final void Function(_AssignDraft draft, String type) onTypeChanged;
  final TextEditingController Function(_AssignDraft draft) feeControllerFor;
  final void Function(_AssignDraft draft, String raw) onFeeChanged;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SumouSectionHeader(title: 'الفريق المختار (${selected.length})'),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          SumouCard(
            child: Text(
              'لم يتم اختيار أي عضو بعد',
              style: AppTextStyles.bodyMuted,
            ),
          )
        else
          for (var i = 0; i < selected.length; i++) ...[
            _SelectedMemberCard(
              draft: selected[i],
              feeController: feeControllerFor(selected[i]),
              onTypeChanged: (type) => onTypeChanged(selected[i], type),
              onFeeChanged: (raw) => onFeeChanged(selected[i], raw),
              onRemove: () => onRemove(i),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SelectedMemberCard extends StatelessWidget {
  const _SelectedMemberCard({
    required this.draft,
    required this.feeController,
    required this.onTypeChanged,
    required this.onFeeChanged,
    required this.onRemove,
  });

  final _AssignDraft draft;
  final TextEditingController feeController;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onFeeChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      borderColor: AppColors.accentGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initials: UserModel.initialsFrom(draft.personName)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(draft.personName, style: AppTextStyles.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.error),
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
              for (final type in _typeChoicesFor(draft))
                _Chip(
                  label: type,
                  selected: draft.photoType == type,
                  onTap: () => onTypeChanged(type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SumouTextField(
            controller: feeController,
            label: 'القيمة / الأجر (اختياري)',
            hint: 'مثال: 1500',
            keyboardType: TextInputType.number,
            prefixIcon: Icons.payments_outlined,
            onChanged: onFeeChanged,
          ),
        ],
      ),
    );
  }

  /// The photo-type options for a member: the shared catalogue plus the
  /// member's current type if it isn't already listed.
  List<String> _typeChoicesFor(_AssignDraft draft) {
    if (_kPhotoTypes.contains(draft.photoType)) return _kPhotoTypes;
    return [draft.photoType, ..._kPhotoTypes];
  }
}

// ---- available list ---------------------------------------------------------

class _AvailableList extends StatelessWidget {
  const _AvailableList({
    required this.photographers,
    required this.counts,
    required this.query,
    required this.typeFilter,
    required this.isSelected,
    required this.onToggle,
    required this.onTypeFilter,
  });

  final List<UserModel> photographers;
  final Map<String, int> counts;
  final String query;
  final String? typeFilter;
  final bool Function(String userId) isSelected;
  final ValueChanged<UserModel> onToggle;
  final ValueChanged<String?> onTypeFilter;

  @override
  Widget build(BuildContext context) {
    // Photo-type filter options derived from the candidates' specialties.
    final types =
        <String>{for (final u in photographers) ...u.photoTypes}.toList();

    final q = query.trim().toLowerCase();
    final filtered =
        photographers.where((u) {
          final matchesQuery =
              q.isEmpty ||
              u.fullName.toLowerCase().contains(q) ||
              u.username.toLowerCase().contains(q);
          final matchesType =
              typeFilter == null || u.photoTypes.contains(typeFilter);
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
            message: 'جرّب تعديل البحث أو الفلتر',
            icon: Icons.person_search_outlined,
          )
        else
          for (final u in filtered) ...[
            _PhotographerCard(
              user: u,
              activeCount: counts[u.id] ?? 0,
              selected: isSelected(u.id),
              onTap: () => onToggle(u),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _PhotographerCard extends StatelessWidget {
  const _PhotographerCard({
    required this.user,
    required this.activeCount,
    required this.selected,
    required this.onTap,
  });

  final UserModel user;
  final int activeCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = _capacity(activeCount);
    return SumouCard(
      onTap: onTap,
      borderColor: selected ? AppColors.accentGreen : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initials: user.avatarInitials),
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
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? AppColors.accentGreen : AppColors.textMuted,
              ),
            ],
          ),
          if (user.photoTypes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in user.photoTypes) _SpecialtyTag(label: t),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.work_outline,
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text('$activeCount مشاريع نشطة', style: AppTextStyles.label),
              const Spacer(),
              _CapacityChip(label: label, color: color),
            ],
          ),
        ],
      ),
    );
  }

  /// Simple UI-only capacity bucket from the active-project count. Not an
  /// enforcement gate — assignment is never blocked in Sprint 2.
  (String, Color) _capacity(int count) {
    if (count >= 4) return ('ممتلئ', AppColors.error);
    if (count >= 2) return ('مشغول', AppColors.financeYellow);
    return ('متاح', AppColors.accentGreen);
  }
}

// ---- small pieces -----------------------------------------------------------

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.count,
    required this.saving,
    required this.onSave,
  });

  final int count;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SumouButton(
          label: count > 0 ? 'حفظ الإسناد ($count)' : 'حفظ الإسناد',
          icon: Icons.check,
          loading: saving,
          onPressed: saving ? null : onSave,
        ),
      ),
    );
  }
}

class _CapacityChip extends StatelessWidget {
  const _CapacityChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SpecialtyTag extends StatelessWidget {
  const _SpecialtyTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.projectTeal.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(color: AppColors.projectTeal),
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
          color:
              selected
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
          color:
              selected
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
