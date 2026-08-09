import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/project_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'providers/projects_providers.dart';

const List<String> _kStepTitles = [
  'المعلومات الأساسية',
  'العميل والتواريخ',
  'الفريق',
  'المراجعة',
];

/// A draft team assignment built up while creating a project. A photographer can
/// hold more than one [photoTypes] and an optional [value] (assignment metadata
/// only — no finance records are created).
class _TeamDraft {
  _TeamDraft({
    required this.userId,
    required this.personName,
    required this.photoTypes,
    required this.availableTypes,
    required this.date,
  });

  final String userId;
  final String personName;
  final Map<String, ProjectPhotographerType> photoTypes;
  List<ProjectPhotographerType> availableTypes;
  DateTime date;
  num value = 0;
  String? validationMessage;
}

/// Full-screen, mobile-first multi-step flow for creating a project.
///
/// The normal provider remains mock-backed until the planned repository cutover;
/// the screen itself uses only the repository contract and never calls Supabase.
class AddProjectScreen extends ConsumerStatefulWidget {
  const AddProjectScreen({super.key});

  @override
  ConsumerState<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends ConsumerState<AddProjectScreen> {
  static const int _lastStep = 3;

  int _step = 0;
  bool _showErrors = false;
  bool _saving = false;

  final _nameController = TextEditingController();
  final _clientController = TextEditingController();
  final _notesController = TextEditingController();

  ProjectType? _type;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _managerId;
  String? _managerName;
  final List<_TeamDraft> _team = [];
  DateTime? _candidateDate;
  List<AssignableProjectStaff>? _teamCandidates;
  bool _loadingTeamCandidates = false;
  String? _teamCandidateError;
  int _candidateGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Default the manager to the signed-in user when they can manage projects.
    final user = ref.read(authControllerProvider).currentUser;
    if (user != null && user.hasRole(RoleType.manager)) {
      _managerId = user.id;
      _managerName = user.fullName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ---- validation ----------------------------------------------------------

  String? get _nameError =>
      _nameController.text.trim().isEmpty ? 'الرجاء إدخال اسم المشروع' : null;

  String? get _typeError => _type == null ? 'الرجاء اختيار نوع المشروع' : null;

  String? get _clientError =>
      _clientController.text.trim().isEmpty ? 'الرجاء إدخال اسم العميل' : null;

  String? get _startError =>
      _startDate == null ? 'الرجاء اختيار تاريخ البداية' : null;

  String? get _endError {
    if (_endDate == null) return 'الرجاء اختيار تاريخ النهاية';
    if (_startDate != null && _endDate!.isBefore(_startDate!)) {
      return 'تاريخ النهاية لا يمكن أن يسبق تاريخ البداية';
    }
    return null;
  }

  bool _stepIsValid(int step) => switch (step) {
    0 => _nameError == null && _typeError == null,
    1 => _clientError == null && _startError == null && _endError == null,
    // Step 2 (team) is optional; step 3 is review.
    _ => true,
  };

  // ---- navigation ----------------------------------------------------------

  void _next() {
    if (!_stepIsValid(_step)) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() {
      _showErrors = false;
      _step++;
    });
    if (_step == 2 && _startDate != null) {
      _candidateDate ??= _startDate;
      _loadTeamCandidates(_candidateDate!);
    }
  }

  void _back() {
    if (_step == 0) {
      context.pop();
      return;
    }
    setState(() {
      _showErrors = false;
      _step--;
    });
  }

  Future<void> _save() async {
    // Defensive re-check across the gated steps.
    if (!(_stepIsValid(0) && _stepIsValid(1))) {
      setState(() => _showErrors = true);
      return;
    }
    // The project manager is always the signed-in manager (no manager step).
    if (_managerId == null) {
      final user = ref.read(authControllerProvider).currentUser;
      _managerId = user?.id;
      _managerName = user?.fullName;
    }
    if (_managerId == null) return; // no signed-in manager — nothing to save
    setState(() => _saving = true);
    final repo = ref.read(projectRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await _preflightCreateTeam()) {
        throw const ProjectRepositoryException(
          ProjectRepositoryFailure.unavailable,
        );
      }
      final notes = _notesController.text.trim();
      final project = await repo.createProject(
        name: _nameController.text.trim(),
        clientName: _clientController.text.trim(),
        managerId: _managerId!,
        managerName: _managerName,
        type: _type!,
        startDate: _startDate!,
        endDate: _endDate!,
        notes: notes.isEmpty ? null : notes,
        teamRoles: [
          for (final member in _team)
            for (var index = 0; index < member.photoTypes.length; index++)
              ProjectTeamRole(
                id: '',
                projectId: '',
                photographerTypeId:
                    member.photoTypes.values.elementAt(index).id,
                photographerTypeCode:
                    member.photoTypes.values.elementAt(index).code,
                type: member.photoTypes.values.elementAt(index).nameAr,
                personName: member.personName,
                userId: member.userId,
                value: index == 0 ? member.value : 0,
                date: member.date,
              ),
        ],
      );
      ref.invalidate(managerProjectsProvider);
      if (!mounted) return;
      context.pushReplacement(AppRoutes.projectDetailsPath(project.id));
    } on ProjectRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(error.messageAr)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ المشروع بأمان')),
      );
    }
  }

  // ---- pickers --------------------------------------------------------------

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ?? _startDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // Keep the range coherent.
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _loadTeamCandidates(DateTime date) async {
    final generation = ++_candidateGeneration;
    setState(() {
      _candidateDate = date;
      _loadingTeamCandidates = true;
      _teamCandidateError = null;
    });
    try {
      final candidates = await ref
          .read(projectRepositoryProvider)
          .getAssignableProjectStaff(onDate: date);
      if (!mounted || generation != _candidateGeneration) return;
      setState(() {
        _teamCandidates = candidates;
        _loadingTeamCandidates = false;
        _revalidateCreateDrafts(date, candidates);
      });
    } catch (_) {
      if (!mounted || generation != _candidateGeneration) return;
      setState(() {
        _loadingTeamCandidates = false;
        _teamCandidateError = 'تعذّر تحميل الفريق المتاح بأمان';
      });
    }
  }

  void _revalidateCreateDrafts(
    DateTime date,
    List<AssignableProjectStaff> candidates,
  ) {
    for (final draft in _team) {
      if (!_sameCalendarDate(draft.date, date)) continue;
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
      draft.photoTypes.removeWhere((id, type) => allowed[id] != type.code);
      draft.validationMessage =
          draft.photoTypes.isEmpty ? 'اختر نوع تصوير واحداً على الأقل' : null;
    }
  }

  Future<void> _addTeamMember() async {
    final chosen = await _showCandidatePicker(
      _teamCandidates ?? const <AssignableProjectStaff>[],
    );
    if (chosen == null || _candidateDate == null) return;
    final firstType = chosen.photographerTypes.first;
    setState(() {
      _team.add(
        _TeamDraft(
          userId: chosen.userId,
          personName: chosen.fullName,
          photoTypes: {firstType.id: firstType},
          availableTypes: chosen.photographerTypes,
          date: _candidateDate!,
        ),
      );
    });
  }

  Future<AssignableProjectStaff?> _showCandidatePicker(
    List<AssignableProjectStaff> candidates,
  ) {
    final selectedIds = _team.map((member) => member.userId).toSet();
    final selectable = candidates
        .where((candidate) => !selectedIds.contains(candidate.userId))
        .toList(growable: false);
    return showModalBottomSheet<AssignableProjectStaff>(
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
                  'اختر عضو الفريق',
                  style: AppTextStyles.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (selectable.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'لا يوجد أشخاص للاختيار',
                      style: AppTextStyles.bodyMuted,
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: selectable.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final candidate = selectable[i];
                        final locked = !candidate.isAvailable;
                        return Opacity(
                          opacity: locked ? 0.55 : 1,
                          child: SumouCard(
                            onTap:
                                locked
                                    ? null
                                    : () => Navigator.of(
                                      sheetContext,
                                    ).pop(candidate),
                            child: Row(
                              children: [
                                _Avatar(
                                  initials: UserModel.initialsFrom(
                                    candidate.fullName,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        candidate.fullName,
                                        style: AppTextStyles.titleMedium,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        locked
                                            ? 'غير متاح في هذا التاريخ'
                                            : candidate.photographerTypes
                                                .map((type) => type.nameAr)
                                                .join('، '),
                                        style: AppTextStyles.bodyMuted.copyWith(
                                          color:
                                              locked ? AppColors.error : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (locked)
                                  const Icon(
                                    Icons.lock_outline,
                                    color: AppColors.error,
                                    size: 18,
                                  )
                                else
                                  const Icon(
                                    Icons.add_circle_outline,
                                    color: AppColors.accentGreen,
                                  ),
                              ],
                            ),
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

  Future<void> _pickTeamCandidateDate() async {
    if (_candidateDate == null) return;
    final picked = await _pickAssignmentDate(_candidateDate!);
    if (picked != null) await _loadTeamCandidates(picked);
  }

  Future<void> _pickMemberAssignmentDate(_TeamDraft draft) async {
    final picked = await _pickAssignmentDate(draft.date);
    if (picked == null) return;
    setState(() {
      draft.date = picked;
      draft.validationMessage = 'جارٍ التحقق من التوفر والأنواع';
    });
    await _loadTeamCandidates(picked);
  }

  Future<DateTime?> _pickAssignmentDate(DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 7),
    );
  }

  Future<bool> _preflightCreateTeam() async {
    final repository = ref.read(projectRepositoryProvider);
    final candidatesByDate = <String, List<AssignableProjectStaff>>{};
    for (final draft in _team) {
      if (draft.photoTypes.isEmpty) return false;
      final key = _dateOnlyKey(draft.date);
      final candidates =
          candidatesByDate[key] ??= await repository.getAssignableProjectStaff(
            onDate: draft.date,
          );
      final candidate =
          candidates.where((item) => item.userId == draft.userId).firstOrNull;
      if (candidate == null || !candidate.isAvailable) return false;
      final allowed = {
        for (final type in candidate.photographerTypes) type.id: type.code,
      };
      if (draft.photoTypes.entries.any(
        (entry) => allowed[entry.key] != entry.value.code,
      )) {
        return false;
      }
    }
    return true;
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      padding: EdgeInsets.zero,
      appBar: SumouAppBar(
        title: 'مشروع جديد',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          _StepIndicator(step: _step, total: _kStepTitles.length),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _buildStep(),
            ),
          ),
          _BottomBar(
            isLastStep: _step == _lastStep,
            canGoBack: true,
            saving: _saving,
            onNext: _next,
            onBack: _back,
            onSave: _save,
          ),
        ],
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
    0 => _basicInfoStep(),
    1 => _clientDatesStep(),
    2 => _teamStep(),
    _ => _reviewStep(),
  };

  // Step 1 — basic info.
  Widget _basicInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(title: 'المعلومات الأساسية'),
        SumouTextField(
          controller: _nameController,
          label: 'اسم المشروع',
          hint: 'مثال: تغطية مؤتمر الرياض',
          onChanged: (_) => setState(() {}),
        ),
        if (_showErrors && _nameError != null) _ErrorText(_nameError!),
        const SizedBox(height: 16),
        Text('نوع المشروع', style: AppTextStyles.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in ProjectType.values)
              _ChoiceChip(
                label: t.nameAr,
                selected: _type == t,
                onTap: () => setState(() => _type = t),
              ),
          ],
        ),
        if (_showErrors && _typeError != null) _ErrorText(_typeError!),
        const SizedBox(height: 16),
        SumouTextField(
          controller: _notesController,
          label: 'ملاحظات (اختياري)',
          hint: 'أي تفاصيل إضافية عن المشروع',
          maxLines: 3,
        ),
      ],
    );
  }

  // Step 2 — client + dates.
  Widget _clientDatesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(title: 'العميل والتواريخ'),
        SumouTextField(
          controller: _clientController,
          label: 'اسم العميل',
          hint: 'مثال: هيئة الترفيه',
          onChanged: (_) => setState(() {}),
        ),
        if (_showErrors && _clientError != null) _ErrorText(_clientError!),
        const SizedBox(height: 16),
        _DateField(
          label: 'تاريخ البداية',
          value: _startDate,
          onTap: () => _pickDate(isStart: true),
        ),
        if (_showErrors && _startError != null) _ErrorText(_startError!),
        const SizedBox(height: 16),
        _DateField(
          label: 'تاريخ النهاية',
          value: _endDate,
          onTap: () => _pickDate(isStart: false),
        ),
        if (_showErrors && _endError != null) _ErrorText(_endError!),
      ],
    );
  }

  // Step 3 — team.
  Widget _teamStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'الفريق',
          subtitle: 'أضف المصورين وحدّد تاريخ الإسناد والأنواع',
        ),
        _DateField(
          label: 'تاريخ الإسناد للمصور الجديد',
          value: _candidateDate,
          onTap: _pickTeamCandidateDate,
        ),
        const SizedBox(height: 12),
        if (_team.isEmpty)
          SumouCard(
            child: Text(
              'لم تتم إضافة أعضاء بعد',
              style: AppTextStyles.bodyMuted,
            ),
          )
        else
          for (var i = 0; i < _team.length; i++) ...[
            _TeamMemberEditor(
              key: ValueKey(_team[i].userId),
              member: _team[i],
              onToggleType:
                  (type) => setState(() {
                    final types = _team[i].photoTypes;
                    if (types.containsKey(type.id)) {
                      if (types.length > 1) types.remove(type.id);
                    } else {
                      types[type.id] = type;
                    }
                    _team[i].validationMessage = null;
                  }),
              onValueChanged: (value) => _team[i].value = value,
              onPickDate: () => _pickMemberAssignmentDate(_team[i]),
              onRemove: () => setState(() => _team.removeAt(i)),
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 6),
        if (_loadingTeamCandidates)
          const Center(child: CircularProgressIndicator())
        else if (_teamCandidateError != null)
          SumouCard(
            child: Column(
              children: [
                Text(_teamCandidateError!, style: AppTextStyles.bodyMuted),
                const SizedBox(height: 10),
                SumouButton(
                  label: 'إعادة المحاولة',
                  variant: SumouButtonVariant.secondary,
                  onPressed:
                      _candidateDate == null
                          ? null
                          : () => _loadTeamCandidates(_candidateDate!),
                ),
              ],
            ),
          )
        else
          SumouButton(
            label: 'إضافة عضو للفريق',
            variant: SumouButtonVariant.secondary,
            icon: Icons.person_add_alt,
            onPressed: _addTeamMember,
          ),
      ],
    );
  }

  // Step 4 — review.
  Widget _reviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'المراجعة',
          subtitle: 'تأكد من البيانات قبل الحفظ',
        ),
        SumouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewLine(label: 'اسم المشروع', value: _nameController.text),
              _ReviewLine(
                label: 'الرقم التسلسلي',
                value: 'يُنشأ تلقائياً عند الحفظ',
                valueColor: AppColors.accentGreen,
              ),
              _ReviewLine(label: 'العميل', value: _clientController.text),
              _ReviewLine(label: 'النوع', value: _type?.nameAr ?? '—'),
              _ReviewLine(
                label: 'الفترة',
                value: '${_fmtDate(_startDate)} ← ${_fmtDate(_endDate)}',
              ),
              _ReviewLine(label: 'المدير', value: _managerName ?? '—'),
              _ReviewLine(
                label: 'الفريق',
                value:
                    _team.isEmpty
                        ? 'لا يوجد'
                        : _team.map((m) => m.personName).join('، '),
              ),
              if (_notesController.text.trim().isNotEmpty)
                _ReviewLine(
                  label: 'ملاحظات',
                  value: _notesController.text.trim(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

bool _sameCalendarDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _dateOnlyKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

// ---- private widgets --------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الخطوة ${step + 1} من $total', style: AppTextStyles.label),
              Text(_kStepTitles[step], style: AppTextStyles.label),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (step + 1) / total,
              minHeight: 6,
              backgroundColor: AppColors.surfaceSecondary,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.accentGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isLastStep,
    required this.canGoBack,
    required this.saving,
    required this.onNext,
    required this.onBack,
    required this.onSave,
  });

  final bool isLastStep;
  final bool canGoBack;
  final bool saving;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (canGoBack) ...[
              Expanded(
                child: SumouButton(
                  label: 'السابق',
                  variant: SumouButtonVariant.secondary,
                  onPressed: saving ? null : onBack,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child:
                  isLastStep
                      ? SumouButton(
                        label: 'حفظ المشروع',
                        icon: Icons.check,
                        loading: saving,
                        onPressed: saving ? null : onSave,
                      )
                      : SumouButton(label: 'التالي', onPressed: onNext),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: AppTextStyles.bodyMuted),
          ],
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: AppColors.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.label.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

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
                  value == null ? 'اختر التاريخ' : _fmtDate(value),
                  style:
                      value == null
                          ? AppTextStyles.bodyMuted
                          : AppTextStyles.body,
                ),
              ),
              const Icon(Icons.chevron_left, color: AppColors.textMuted),
            ],
          ),
        ),
      ],
    );
  }
}

class _TeamMemberEditor extends StatefulWidget {
  const _TeamMemberEditor({
    super.key,
    required this.member,
    required this.onToggleType,
    required this.onValueChanged,
    required this.onPickDate,
    required this.onRemove,
  });

  final _TeamDraft member;
  final ValueChanged<ProjectPhotographerType> onToggleType;
  final ValueChanged<num> onValueChanged;
  final VoidCallback onPickDate;
  final VoidCallback onRemove;

  @override
  State<_TeamMemberEditor> createState() => _TeamMemberEditorState();
}

class _TeamMemberEditorState extends State<_TeamMemberEditor> {
  late final TextEditingController _value;

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(
      text: widget.member.value > 0 ? '${widget.member.value}' : '',
    );
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initials: UserModel.initialsFrom(member.personName)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  member.personName,
                  style: AppTextStyles.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: widget.onRemove,
                tooltip: 'إزالة',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('أنواع التصوير', style: AppTextStyles.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in member.availableTypes)
                _ChoiceChip(
                  label: type.nameAr,
                  selected: member.photoTypes.containsKey(type.id),
                  onTap: () => widget.onToggleType(type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'تاريخ الإسناد',
            value: member.date,
            onTap: widget.onPickDate,
          ),
          const SizedBox(height: 12),
          SumouTextField(
            controller: _value,
            label: 'قيمة الإسناد (اختياري)',
            hint: '0',
            keyboardType: TextInputType.number,
            prefixIcon: Icons.tag,
            onChanged:
                (value) =>
                    widget.onValueChanged(num.tryParse(value.trim()) ?? 0),
          ),
          if (member.validationMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              member.validationMessage!,
              style: AppTextStyles.label.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(label, style: AppTextStyles.label)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTextStyles.body.copyWith(color: valueColor),
            ),
          ),
        ],
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
