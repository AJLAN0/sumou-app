import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/project_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/projects_providers.dart';
import 'widgets/project_card.dart';

/// Mobile team-assignment flow backed only by the trusted candidate catalog.
class AssignPhotographersScreen extends ConsumerWidget {
  const AssignPhotographersScreen({
    super.key,
    required this.projectId,
    this.title = 'إسناد مصور',
  });

  final String projectId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));
    return SumouScaffold(
      padding: EdgeInsets.zero,
      appBar: SumouAppBar(
        title: title,
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
          if (!project.isActive) {
            return const SumouEmptyState(
              title: 'إدارة الفريق غير متاحة',
              message: 'يمكن تعديل الفريق فقط للمشاريع النشطة أو قيد التنفيذ.',
              icon: Icons.lock_outline,
            );
          }
          return _AssignBody(project: project);
        },
      ),
    );
  }
}

class _AssignmentDraft {
  _AssignmentDraft({
    required this.userId,
    required this.teamMemberId,
    required this.personName,
    required this.date,
    required this.value,
  });

  final String? userId;
  final String? teamMemberId;
  final String personName;
  DateTime? date;
  num value;
  final Map<String, ProjectPhotographerType> selectedTypes = {};
  List<ProjectPhotographerType> availableTypes = const [];
  String? validationMessage;

  bool get isExternal => userId == null;
  String get key => userId ?? 'external:$teamMemberId';
}

class _AssignBody extends ConsumerStatefulWidget {
  const _AssignBody({required this.project});

  final ProjectModel project;

  @override
  ConsumerState<_AssignBody> createState() => _AssignBodyState();
}

class _AssignBodyState extends ConsumerState<_AssignBody> {
  final List<_AssignmentDraft> _selected = [];
  String _query = '';
  String? _typeFilter;
  late DateTime _candidateDate;
  List<AssignableProjectStaff>? _candidates;
  bool _loadingCandidates = false;
  bool _saving = false;
  String? _candidateError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _candidateDate = widget.project.startDate;
    _hydrateExistingTeam();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCandidates(_candidateDate);
    });
  }

  void _hydrateExistingTeam() {
    final drafts = <String, _AssignmentDraft>{};
    for (final role in widget.project.teamRoles) {
      final key = role.userId ?? 'external:${role.teamMemberId ?? role.id}';
      final draft = drafts.putIfAbsent(
        key,
        () => _AssignmentDraft(
          userId: role.userId,
          teamMemberId: role.teamMemberId,
          personName: role.personName,
          date: role.date,
          value: role.value,
        ),
      );
      if (draft.value == 0 && role.value != 0) draft.value = role.value;
      final typeId = role.photographerTypeId;
      final typeCode = role.photographerTypeCode;
      if (typeId != null && typeCode != null) {
        draft.selectedTypes[typeId] = ProjectPhotographerType(
          id: typeId,
          code: typeCode,
          nameAr: role.type,
        );
      } else {
        draft.validationMessage = 'تعذّر التحقق من نوع تصوير محفوظ';
      }
    }
    for (final draft in drafts.values.where((item) => !item.isExternal)) {
      draft.availableTypes = draft.selectedTypes.values.toList(growable: false);
    }
    _selected.addAll(drafts.values);
  }

  Future<void> _loadCandidates(DateTime date) async {
    final generation = ++_loadGeneration;
    setState(() {
      _candidateDate = date;
      _loadingCandidates = true;
      _candidateError = null;
    });
    try {
      final candidates = await ref
          .read(projectRepositoryProvider)
          .getAssignableProjectStaff(
            onDate: date,
            excludeProjectId: widget.project.id,
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _candidates = candidates;
        _loadingCandidates = false;
        _revalidateDraftsForDate(date, candidates);
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadingCandidates = false;
        _candidateError = 'تعذّر تحميل الفريق المتاح بأمان';
      });
    }
  }

  void _revalidateDraftsForDate(
    DateTime date,
    List<AssignableProjectStaff> candidates,
  ) {
    for (final draft in _selected) {
      if (draft.isExternal || !_sameDate(draft.date, date)) continue;
      final candidate =
          candidates.where((item) => item.userId == draft.userId).firstOrNull;
      if (candidate == null || !candidate.isAvailable) {
        draft.availableTypes = const [];
        draft.validationMessage = 'هذا العضو غير متاح في التاريخ المحدد';
        continue;
      }
      draft.availableTypes = candidate.photographerTypes;
      final allowed = {
        for (final type in candidate.photographerTypes) type.id: type.code,
      };
      draft.selectedTypes.removeWhere((id, type) => allowed[id] != type.code);
      draft.validationMessage =
          draft.selectedTypes.isEmpty
              ? 'اختر نوع تصوير واحداً على الأقل'
              : null;
    }
  }

  bool _isSelected(String userId) =>
      _selected.any((draft) => draft.userId == userId);

  void _toggleCandidate(AssignableProjectStaff candidate) {
    if (!candidate.isAvailable) return;
    final index = _selected.indexWhere(
      (draft) => draft.userId == candidate.userId,
    );
    setState(() {
      if (index >= 0) {
        _selected.removeAt(index);
      } else {
        final draft = _AssignmentDraft(
          userId: candidate.userId,
          teamMemberId: null,
          personName: candidate.fullName,
          date: _candidateDate,
          value: 0,
        )..availableTypes = candidate.photographerTypes;
        final firstType = candidate.photographerTypes.first;
        draft.selectedTypes[firstType.id] = firstType;
        _selected.add(draft);
      }
    });
  }

  void _toggleType(_AssignmentDraft draft, ProjectPhotographerType type) {
    setState(() {
      if (draft.selectedTypes.containsKey(type.id)) {
        if (draft.selectedTypes.length == 1) {
          draft.validationMessage = 'اختر نوع تصوير واحداً على الأقل';
          return;
        }
        draft.selectedTypes.remove(type.id);
      } else {
        draft.selectedTypes[type.id] = type;
      }
      draft.validationMessage = null;
    });
  }

  Future<void> _pickCandidateDate() async {
    final picked = await _pickDate(_candidateDate);
    if (picked != null) await _loadCandidates(picked);
  }

  Future<void> _pickMemberDate(_AssignmentDraft draft) async {
    final picked = await _pickDate(draft.date ?? _candidateDate);
    if (picked == null) return;
    setState(() {
      draft.date = picked;
      draft.validationMessage = 'جارٍ التحقق من التوفر والأنواع';
    });
    await _loadCandidates(picked);
  }

  Future<DateTime?> _pickDate(DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 7),
    );
  }

  Future<bool> _preflightSelections() async {
    final repository = ref.read(projectRepositoryProvider);
    final byDate = <String, List<AssignableProjectStaff>>{};
    for (final draft in _selected.where((item) => !item.isExternal)) {
      final date = draft.date;
      if (date == null || draft.selectedTypes.isEmpty) return false;
      final key = _dateKey(date);
      final candidates =
          byDate[key] ??= await repository.getAssignableProjectStaff(
            onDate: date,
            excludeProjectId: widget.project.id,
          );
      final candidate =
          candidates.where((item) => item.userId == draft.userId).firstOrNull;
      if (candidate == null || !candidate.isAvailable) return false;
      final allowed = {
        for (final type in candidate.photographerTypes) type.id: type.code,
      };
      if (draft.selectedTypes.entries.any(
        (entry) => allowed[entry.key] != entry.value.code,
      )) {
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_selected.isEmpty) {
      final confirmed = await showSumouConfirmSheet(
        context,
        title: 'إزالة جميع أعضاء الفريق',
        message: 'سيتم حفظ المشروع من دون فريق. هل تريد المتابعة؟',
        confirmLabel: 'حفظ من دون فريق',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await _preflightSelections()) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.unavailable,
        );
      }
      final roles = <ProjectTeamRole>[
        for (final draft in _selected)
          for (var index = 0; index < draft.selectedTypes.length; index++)
            ProjectTeamRole(
              id: '',
              projectId: widget.project.id,
              teamMemberId: draft.teamMemberId,
              photographerTypeId:
                  draft.selectedTypes.values.elementAt(index).id,
              photographerTypeCode:
                  draft.selectedTypes.values.elementAt(index).code,
              type: draft.selectedTypes.values.elementAt(index).nameAr,
              personName: draft.personName,
              userId: draft.userId,
              value: index == 0 ? draft.value : 0,
              date: draft.date,
            ),
      ];
      final updated = await ref
          .read(projectRepositoryProvider)
          .assignTeamRoles(widget.project.id, roles);
      if (updated == null) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.saveFailed,
        );
      }
      ref.invalidate(projectByIdProvider(widget.project.id));
      ref.invalidate(managerProjectsProvider);
      ref.invalidate(photographerProjectsProvider);
      if (!mounted) return;
      context.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تحديث فريق المشروع')),
      );
    } on ProjectRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(error.messageAr)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ فريق المشروع بأمان')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  onToggleType: _toggleType,
                  onPickDate: _pickMemberDate,
                  onValueChanged: (draft, value) => draft.value = value,
                  onRemove: (draft) {
                    if (draft.isExternal) return;
                    setState(() => _selected.remove(draft));
                  },
                ),
                const SizedBox(height: 20),
                const SumouSectionHeader(title: 'المصورون المتاحون'),
                const SizedBox(height: 12),
                _DateField(
                  label: 'تاريخ الإسناد للمصور الجديد',
                  value: _candidateDate,
                  onTap: _pickCandidateDate,
                ),
                const SizedBox(height: 12),
                SumouTextField(
                  hint: 'بحث باسم المصور',
                  prefixIcon: Icons.search,
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 12),
                _candidateSection(),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SumouButton(
              label:
                  _selected.isEmpty
                      ? 'حفظ الإسناد'
                      : 'حفظ الإسناد (${_selected.length})',
              icon: Icons.check,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
        ),
      ],
    );
  }

  Widget _candidateSection() {
    if (_loadingCandidates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_candidateError != null) {
      return SumouCard(
        child: Column(
          children: [
            Text(_candidateError!, style: AppTextStyles.bodyMuted),
            const SizedBox(height: 12),
            SumouButton(
              label: 'إعادة المحاولة',
              variant: SumouButtonVariant.secondary,
              onPressed: () => _loadCandidates(_candidateDate),
            ),
          ],
        ),
      );
    }
    return _AvailableList(
      candidates: _candidates ?? const [],
      query: _query,
      typeFilter: _typeFilter,
      isSelected: _isSelected,
      onToggle: _toggleCandidate,
      onTypeFilter: (value) => setState(() => _typeFilter = value),
    );
  }
}

class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.name, style: AppTextStyles.titleMedium),
                const SizedBox(height: 4),
                Text(project.clientName, style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
          SumouStatusChip(sumouStatusForProject(project.status)),
        ],
      ),
    );
  }
}

class _SelectedTeam extends StatelessWidget {
  const _SelectedTeam({
    required this.selected,
    required this.onToggleType,
    required this.onPickDate,
    required this.onValueChanged,
    required this.onRemove,
  });

  final List<_AssignmentDraft> selected;
  final void Function(_AssignmentDraft draft, ProjectPhotographerType type)
  onToggleType;
  final ValueChanged<_AssignmentDraft> onPickDate;
  final void Function(_AssignmentDraft draft, num value) onValueChanged;
  final ValueChanged<_AssignmentDraft> onRemove;

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
          for (final draft in selected) ...[
            _SelectedMemberCard(
              key: ValueKey(draft.key),
              draft: draft,
              onToggleType: (type) => onToggleType(draft, type),
              onPickDate: () => onPickDate(draft),
              onValueChanged: (value) => onValueChanged(draft, value),
              onRemove: draft.isExternal ? null : () => onRemove(draft),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SelectedMemberCard extends StatefulWidget {
  const _SelectedMemberCard({
    super.key,
    required this.draft,
    required this.onToggleType,
    required this.onPickDate,
    required this.onValueChanged,
    required this.onRemove,
  });

  final _AssignmentDraft draft;
  final ValueChanged<ProjectPhotographerType> onToggleType;
  final VoidCallback onPickDate;
  final ValueChanged<num> onValueChanged;
  final VoidCallback? onRemove;

  @override
  State<_SelectedMemberCard> createState() => _SelectedMemberCardState();
}

class _SelectedMemberCardState extends State<_SelectedMemberCard> {
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(
      text: widget.draft.value == 0 ? '' : '${widget.draft.value}',
    );
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final typeOptions =
        draft.isExternal
            ? draft.selectedTypes.values.toList(growable: false)
            : draft.availableTypes;
    return SumouCard(
      borderColor:
          draft.validationMessage == null
              ? AppColors.accentGreen
              : AppColors.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initials: _initials(draft.personName)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(draft.personName, style: AppTextStyles.titleMedium),
                    if (draft.isExternal)
                      Text('عضو خارجي محفوظ', style: AppTextStyles.bodyMuted),
                  ],
                ),
              ),
              if (widget.onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.error),
                  tooltip: 'إزالة',
                  onPressed: widget.onRemove,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('أنواع التصوير', style: AppTextStyles.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in typeOptions)
                _ChoiceChip(
                  label: type.nameAr,
                  selected: draft.selectedTypes.containsKey(type.id),
                  enabled: !draft.isExternal,
                  onTap: () => widget.onToggleType(type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'تاريخ الإسناد',
            value: draft.date,
            onTap: draft.isExternal ? null : widget.onPickDate,
          ),
          const SizedBox(height: 12),
          SumouTextField(
            controller: _valueController,
            label: 'قيمة الإسناد (اختياري)',
            hint: '0',
            keyboardType: TextInputType.number,
            prefixIcon: Icons.tag,
            enabled: !draft.isExternal,
            onChanged:
                (value) =>
                    widget.onValueChanged(num.tryParse(value.trim()) ?? 0),
          ),
          if (draft.validationMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              draft.validationMessage!,
              style: AppTextStyles.label.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _AvailableList extends StatelessWidget {
  const _AvailableList({
    required this.candidates,
    required this.query,
    required this.typeFilter,
    required this.isSelected,
    required this.onToggle,
    required this.onTypeFilter,
  });

  final List<AssignableProjectStaff> candidates;
  final String query;
  final String? typeFilter;
  final bool Function(String userId) isSelected;
  final ValueChanged<AssignableProjectStaff> onToggle;
  final ValueChanged<String?> onTypeFilter;

  @override
  Widget build(BuildContext context) {
    final types = <String, String>{};
    for (final candidate in candidates) {
      for (final type in candidate.photographerTypes) {
        types[type.code] = type.nameAr;
      }
    }
    final normalizedQuery = query.trim().toLowerCase();
    final filtered =
        candidates.where((candidate) {
          final matchesName =
              normalizedQuery.isEmpty ||
              candidate.fullName.toLowerCase().contains(normalizedQuery);
          final matchesType =
              typeFilter == null ||
              candidate.photographerTypes.any(
                (type) => type.code == typeFilter,
              );
          return matchesName && matchesType;
        }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (types.isNotEmpty) ...[
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'الكل',
                  selected: typeFilter == null,
                  onTap: () => onTypeFilter(null),
                ),
                for (final entry in types.entries) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: entry.value,
                    selected: typeFilter == entry.key,
                    onTap: () => onTypeFilter(entry.key),
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
            message: 'جرّب تاريخاً أو بحثاً مختلفاً',
            icon: Icons.person_search_outlined,
          )
        else
          for (final candidate in filtered) ...[
            Opacity(
              opacity: candidate.isAvailable ? 1 : 0.55,
              child: SumouCard(
                onTap: candidate.isAvailable ? () => onToggle(candidate) : null,
                borderColor:
                    isSelected(candidate.userId) ? AppColors.accentGreen : null,
                child: Row(
                  children: [
                    _Avatar(initials: _initials(candidate.fullName)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            candidate.fullName,
                            style: AppTextStyles.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            candidate.isAvailable
                                ? candidate.photographerTypes
                                    .map((type) => type.nameAr)
                                    .join('، ')
                                : 'غير متاح في هذا التاريخ',
                            style: AppTextStyles.bodyMuted.copyWith(
                              color:
                                  candidate.isAvailable
                                      ? null
                                      : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected(candidate.userId)
                          ? Icons.check_circle
                          : candidate.isAvailable
                          ? Icons.add_circle_outline
                          : Icons.block,
                      color:
                          candidate.isAvailable
                              ? AppColors.accentGreen
                              : AppColors.error,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        SumouCard(
          onTap: onTap,
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value == null ? 'اختر التاريخ' : _formatDate(value!),
                  style:
                      value == null
                          ? AppTextStyles.bodyMuted
                          : AppTextStyles.body,
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_left, color: AppColors.textMuted),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentGreen : AppColors.textMuted;
    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
    return _ChoiceChip(
      label: label,
      selected: selected,
      enabled: true,
      onTap: onTap,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.surfaceSecondary,
        shape: BoxShape.circle,
      ),
      child: Text(initials, style: AppTextStyles.label),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '؟';
  return parts.take(2).map((part) => part[0]).join();
}

String _formatDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/'
    '${date.day.toString().padLeft(2, '0')}';

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

bool _sameDate(DateTime? left, DateTime right) =>
    left != null &&
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
