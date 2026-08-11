import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/project_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../projects/providers/projects_providers.dart';

String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

/// Admin basic-edit for a project (full-screen form). The trusted contract edits
/// only title, client, dates, and notes while preserving type and status.
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
    if (_saving || !widget.project.isActive) return;
    if (!_valid) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    ProjectModel? updated;
    String? failureMessage;
    try {
      updated = await ref
          .read(projectRepositoryProvider)
          .updateProjectBasics(
            widget.project.id,
            name: _nameController.text.trim(),
            clientName: _clientController.text.trim(),
            type: widget.project.type,
            status: widget.project.status,
            startDate: _startDate,
            endDate: _endDate,
            notes: _notesController.text.trim(),
          );
    } on ProjectRepositoryException catch (error) {
      failureMessage = error.messageAr;
    } catch (_) {
      failureMessage = 'تعذّر حفظ المشروع بأمان، حاول مرة أخرى';
    }
    if (!mounted) return;
    if (updated == null) {
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage ?? 'تعذّر حفظ التغييرات')),
      );
      return;
    }
    // Refresh the details + lists.
    ref.invalidate(projectByIdProvider(widget.project.id));
    ref.invalidate(allProjectsProvider);
    ref.invalidate(managerProjectsProvider);
    ref.invalidate(photographerProjectsProvider);
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('تم حفظ التغييرات')));
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.project.isActive;
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
                  enabled: canEdit,
                  onChanged: (_) => setState(() {}),
                ),
                if (_showErrors && _nameError != null) _ErrorText(_nameError!),
                const SizedBox(height: 16),
                SumouTextField(
                  controller: _clientController,
                  label: 'اسم العميل',
                  enabled: canEdit,
                  onChanged: (_) => setState(() {}),
                ),
                if (_showErrors && _clientError != null)
                  _ErrorText(_clientError!),
                const SizedBox(height: 16),
                _ReadOnlyField(
                  label: 'نوع المشروع (غير قابل للتغيير)',
                  value: widget.project.type.nameAr,
                ),
                const SizedBox(height: 16),
                _ReadOnlyField(
                  label: 'حالة المشروع (تتغير عبر المسار المعتمد فقط)',
                  value: widget.project.status.nameAr,
                ),
                const SizedBox(height: 16),
                _DateField(
                  label: 'تاريخ البداية',
                  value: _startDate,
                  onTap: canEdit ? () => _pickDate(isStart: true) : null,
                ),
                const SizedBox(height: 16),
                _DateField(
                  label: 'تاريخ التسليم',
                  value: _endDate,
                  onTap: canEdit ? () => _pickDate(isStart: false) : null,
                ),
                if (_showErrors && _dateError != null) _ErrorText(_dateError!),
                const SizedBox(height: 16),
                SumouTextField(
                  controller: _notesController,
                  label: 'ملاحظات (اختياري)',
                  maxLines: 3,
                  enabled: canEdit,
                ),
                if (!canEdit) ...[
                  const SizedBox(height: 16),
                  const SumouErrorBox(
                    message:
                        'تعديل البيانات متاح فقط للمشاريع النشطة أو قيد التنفيذ',
                  ),
                ],
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
                    onPressed: _saving || !canEdit ? null : _save,
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

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 8),
        SumouCard(child: Text(value, style: AppTextStyles.bodyMuted)),
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
  final DateTime value;
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
