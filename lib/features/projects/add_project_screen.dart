import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'providers/projects_providers.dart';

/// Photo/team role types offered when assigning the team. Mock list; a real
/// catalogue arrives with the backend.
const List<String> _kPhotoTypes = [
  'مصور فوتوغرافي',
  'مصور فيديو',
  'انستقرام',
  'تصميم',
];

const List<String> _kStepTitles = [
  'المعلومات الأساسية',
  'العميل والتواريخ',
  'مدير المشروع',
  'الفريق',
  'المراجعة',
];

/// A draft team assignment built up while creating a project.
class _TeamDraft {
  _TeamDraft({
    required this.userId,
    required this.personName,
    required this.photoType,
  });

  final String? userId;
  final String personName;
  String photoType;
}

/// Full-screen, mobile-first multi-step flow for creating a project.
///
/// Mock-only: on save it writes to [MockProjectRepository] via the repository
/// interface, then opens the new project's details. No backend/secrets.
class AddProjectScreen extends ConsumerStatefulWidget {
  const AddProjectScreen({super.key});

  @override
  ConsumerState<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends ConsumerState<AddProjectScreen> {
  static const int _lastStep = 4;

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

  /// Serial previewed in the review step and persisted on save, so the value
  /// shown matches the saved project.
  String? _serialPreview;

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

  String? get _managerError =>
      _managerId == null ? 'الرجاء اختيار مدير المشروع' : null;

  bool _stepIsValid(int step) => switch (step) {
    0 => _nameError == null && _typeError == null,
    1 => _clientError == null && _startError == null && _endError == null,
    2 => _managerError == null,
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
      if (_step == _lastStep) {
        _serialPreview ??= ProjectSerial.generate(_type!);
      }
    });
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
    // Defensive re-check across all gated steps.
    if (!(_stepIsValid(0) && _stepIsValid(1) && _stepIsValid(2))) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(projectRepositoryProvider);
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
      serial: _serialPreview,
      teamRoles: [
        for (final member in _team)
          ProjectTeamRole(
            id: '',
            projectId: '',
            type: member.photoType,
            personName: member.personName,
            userId: member.userId,
          ),
      ],
    );
    ref.invalidate(managerProjectsProvider);
    if (!mounted) return;
    context.pushReplacement(AppRoutes.projectDetailsPath(project.id));
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

  Future<void> _pickManager(List<UserModel> candidates) async {
    final chosen = await _showUserPicker(
      title: 'اختر مدير المشروع',
      users: candidates,
      selectedId: _managerId,
    );
    if (chosen == null) return;
    setState(() {
      _managerId = chosen.id;
      _managerName = chosen.fullName;
    });
  }

  Future<void> _addTeamMember(List<UserModel> candidates) async {
    final chosen = await _showUserPicker(
      title: 'اختر عضو الفريق',
      users: candidates,
      selectedId: null,
    );
    if (chosen == null) return;
    setState(() {
      _team.add(
        _TeamDraft(
          userId: chosen.id,
          personName: chosen.fullName,
          photoType:
              chosen.photoTypes.isNotEmpty
                  ? chosen.photoTypes.first
                  : _kPhotoTypes.first,
        ),
      );
    });
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.fullName,
                                      style: AppTextStyles.titleMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      u.defaultRole.nameAr,
                                      style: AppTextStyles.bodyMuted,
                                    ),
                                  ],
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
    2 => _managerStep(),
    3 => _teamStep(),
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

  // Step 3 — manager.
  Widget _managerStep() {
    final managersAsync = ref.watch(managerCandidatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(title: 'مدير المشروع'),
        managersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (_, __) =>
                  Text('تعذّر تحميل المدراء', style: AppTextStyles.bodyMuted),
          data: (managers) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SumouCard(
                  onTap: () => _pickManager(managers),
                  child: Row(
                    children: [
                      Icon(
                        _managerId == null
                            ? Icons.person_add_alt
                            : Icons.badge_outlined,
                        color: AppColors.accentGreen,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _managerName ?? 'اختر مدير المشروع',
                          style:
                              _managerName == null
                                  ? AppTextStyles.bodyMuted
                                  : AppTextStyles.titleMedium,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_left,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
                if (_showErrors && _managerError != null)
                  _ErrorText(_managerError!),
              ],
            );
          },
        ),
      ],
    );
  }

  // Step 4 — team.
  Widget _teamStep() {
    final photographersAsync = ref.watch(photographerCandidatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'الفريق',
          subtitle: 'أضف المصورين وأعضاء الفريق (اختياري)',
        ),
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
              member: _team[i],
              onTypeChanged:
                  (type) => setState(() => _team[i].photoType = type),
              onRemove: () => setState(() => _team.removeAt(i)),
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 6),
        photographersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (_, __) =>
                  Text('تعذّر تحميل المصورين', style: AppTextStyles.bodyMuted),
          data:
              (photographers) => SumouButton(
                label: 'إضافة عضو للفريق',
                variant: SumouButtonVariant.secondary,
                icon: Icons.person_add_alt,
                onPressed: () => _addTeamMember(photographers),
              ),
        ),
      ],
    );
  }

  // Step 5 — review.
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
                value: _serialPreview ?? '—',
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

class _TeamMemberEditor extends StatelessWidget {
  const _TeamMemberEditor({
    required this.member,
    required this.onTypeChanged,
    required this.onRemove,
  });

  final _TeamDraft member;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
              for (final type in _kPhotoTypes)
                _ChoiceChip(
                  label: type,
                  selected: member.photoType == type,
                  onTap: () => onTypeChanged(type),
                ),
            ],
          ),
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
