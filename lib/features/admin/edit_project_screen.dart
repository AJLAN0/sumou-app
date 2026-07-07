import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../projects/providers/projects_providers.dart';

/// Editable project statuses for the admin basic-edit flow. Closure approval is
/// not done here — this is a mock admin override only.
const List<ProjectStatus> _kEditableStatuses = [
  ProjectStatus.active,
  ProjectStatus.completed,
  ProjectStatus.pendingClosure,
];

String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

/// Admin basic-edit for a project (full-screen form). Edits title, client, type,
/// status, dates, and notes only — no team/stage/manager/closure changes.
class AdminEditProjectScreen extends ConsumerWidget {
  const AdminEditProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      padding: EdgeInsets.zero,
      appBar: SumouAppBar(
        title: 'تعديل بيانات المشروع',
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
          return _EditBody(project: project);
        },
      ),
    );
  }
}

class _EditBody extends ConsumerStatefulWidget {
  const _EditBody({required this.project});

  final ProjectModel project;

  @override
  ConsumerState<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends ConsumerState<_EditBody> {
  late final TextEditingController _nameController;
  late final TextEditingController _clientController;
  late final TextEditingController _notesController;
  late ProjectType _type;
  late ProjectStatus _status;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _nameController = TextEditingController(text: p.name);
    _clientController = TextEditingController(text: p.clientName);
    _notesController = TextEditingController(text: p.notes ?? '');
    _type = p.type;
    _status = p.status;
    _startDate = p.startDate;
    _endDate = p.endDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? get _nameError =>
      _nameController.text.trim().isEmpty ? 'الرجاء إدخال اسم المشروع' : null;

  String? get _clientError =>
      _clientController.text.trim().isEmpty ? 'الرجاء إدخال اسم العميل' : null;

  String? get _dateError =>
      _endDate.isBefore(_startDate)
          ? 'تاريخ التسليم لا يمكن أن يسبق تاريخ البداية'
          : null;

  bool get _valid =>
      _nameError == null && _clientError == null && _dateError == null;

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_valid) {
      setState(() => _showErrors = true);
      return;
    }
    // Confirm when the status changes (mock admin override).
    if (_status != widget.project.status) {
      final ok = await showSumouConfirmSheet(
        context,
        title: 'تغيير حالة المشروع',
        message:
            'سيتم تغيير حالة المشروع إلى «${sumouStatusLabel(_status)}». هل تريد المتابعة؟',
        confirmLabel: 'تأكيد',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final updated = await ref
        .read(projectRepositoryProvider)
        .updateProjectBasics(
          widget.project.id,
          name: _nameController.text.trim(),
          clientName: _clientController.text.trim(),
          type: _type,
          status: _status,
          startDate: _startDate,
          endDate: _endDate,
          notes: _notesController.text.trim(),
        );
    // Refresh the details + lists.
    ref.invalidate(projectByIdProvider(widget.project.id));
    ref.invalidate(allProjectsProvider);
    ref.invalidate(managerProjectsProvider);
    ref.invalidate(photographerProjectsProvider);
    if (!mounted) return;
    if (updated == null) {
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ التغييرات')),
      );
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('تم حفظ التغييرات')));
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
                SumouTextField(
                  controller: _nameController,
                  label: 'اسم المشروع',
                  onChanged: (_) => setState(() {}),
                ),
                if (_showErrors && _nameError != null) _ErrorText(_nameError!),
                const SizedBox(height: 16),
                SumouTextField(
                  controller: _clientController,
                  label: 'اسم العميل',
                  onChanged: (_) => setState(() {}),
                ),
                if (_showErrors && _clientError != null)
                  _ErrorText(_clientError!),
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
                const SizedBox(height: 16),
                Text('حالة المشروع', style: AppTextStyles.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _kEditableStatuses)
                      _ChoiceChip(
                        label: sumouStatusLabel(s),
                        selected: _status == s,
                        onTap: () => setState(() => _status = s),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _DateField(
                  label: 'تاريخ البداية',
                  value: _startDate,
                  onTap: () => _pickDate(isStart: true),
                ),
                const SizedBox(height: 16),
                _DateField(
                  label: 'تاريخ التسليم',
                  value: _endDate,
                  onTap: () => _pickDate(isStart: false),
                ),
                if (_showErrors && _dateError != null) _ErrorText(_dateError!),
                const SizedBox(height: 16),
                SumouTextField(
                  controller: _notesController,
                  label: 'ملاحظات (اختياري)',
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: SumouButton(
                    label: 'إلغاء',
                    variant: SumouButtonVariant.secondary,
                    onPressed: _saving ? null : () => context.pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SumouButton(
                    label: 'حفظ',
                    icon: Icons.check,
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Arabic label for an editable project status.
String sumouStatusLabel(ProjectStatus status) => switch (status) {
  ProjectStatus.active => 'نشط',
  ProjectStatus.completed => 'منتهي',
  ProjectStatus.pendingClosure => 'بانتظار الإغلاق',
  _ => status.nameAr,
};

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
  final DateTime value;
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
              Expanded(child: Text(_fmtDate(value), style: AppTextStyles.body)),
              const Icon(Icons.chevron_left, color: AppColors.textMuted),
            ],
          ),
        ),
      ],
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
