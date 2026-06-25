import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'providers/projects_providers.dart';
import 'widgets/project_card.dart';

/// Full-screen, mobile-first flow for submitting a project closure request.
///
/// Mock-only: loads the project by id, collects a delivery link (+ optional
/// report URL and notes), writes a pending request via
/// [ProjectRepository.submitClosureRequest], and returns to the details screen.
/// No real file upload / storage.
class SubmitClosureRequestScreen extends ConsumerWidget {
  const SubmitClosureRequestScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      padding: EdgeInsets.zero,
      appBar: SumouAppBar(
        title: 'طلب إغلاق المشروع',
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
          return _ClosureBody(project: project);
        },
      ),
    );
  }
}

class _ClosureBody extends ConsumerStatefulWidget {
  const _ClosureBody({required this.project});

  final ProjectModel project;

  @override
  ConsumerState<_ClosureBody> createState() => _ClosureBodyState();
}

class _ClosureBodyState extends ConsumerState<_ClosureBody> {
  final _linkController = TextEditingController();
  final _reportController = TextEditingController();
  final _notesController = TextEditingController();

  bool _showErrors = false;
  bool _saving = false;

  @override
  void dispose() {
    _linkController.dispose();
    _reportController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? get _linkError {
    final v = _linkController.text.trim();
    if (v.isEmpty) return 'الرجاء إدخال رابط التسليم';
    final uri = Uri.tryParse(v);
    final validScheme =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!validScheme || uri.host.isEmpty) {
      return 'الرجاء إدخال رابط صحيح يبدأ بـ http';
    }
    return null;
  }

  /// The submitter's own role/photo type on this project, if any.
  String? get _myRole {
    final userId = ref.read(authControllerProvider).currentUser?.id;
    if (userId == null) return null;
    for (final r in widget.project.teamRoles) {
      if (r.userId == userId) return r.type;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_linkError != null) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(projectRepositoryProvider);
    final user = ref.read(authControllerProvider).currentUser;
    final report = _reportController.text.trim();
    final notes = _notesController.text.trim();
    final request = await repo.submitClosureRequest(
      projectId: widget.project.id,
      submittedBy: user?.id ?? '',
      submittedByName: user?.fullName ?? '',
      deliveryLink: _linkController.text.trim(),
      reportFileUrl: report.isEmpty ? null : report,
      notes: notes.isEmpty ? null : notes,
    );
    ref.invalidate(projectByIdProvider(widget.project.id));
    ref.invalidate(managerProjectsProvider);
    ref.invalidate(photographerProjectsProvider);
    ref.invalidate(pendingClosureForProjectProvider(widget.project.id));
    ref.invalidate(managerClosureRequestsProvider);
    ref.invalidate(managerAllClosureRequestsProvider);
    ref.invalidate(photographerClosureRequestsProvider);
    if (!mounted) return;
    if (request == null) {
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر إرسال الطلب')),
      );
      return;
    }
    context.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('تم إرسال طلب الإغلاق')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alreadyPending = widget.project.hasPendingClosure;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProjectSummary(project: widget.project, role: _myRole),
                const SizedBox(height: 20),
                if (alreadyPending) const _PendingNotice() else _buildForm(),
              ],
            ),
          ),
        ),
        if (!alreadyPending)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SumouButton(
                label: 'إرسال طلب الإغلاق',
                icon: Icons.check,
                loading: _saving,
                onPressed: _saving ? null : _submit,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SumouSectionHeader(title: 'بيانات التسليم'),
        const SizedBox(height: 12),
        SumouTextField(
          controller: _linkController,
          label: 'رابط التسليم',
          hint: 'https://...',
          keyboardType: TextInputType.url,
          prefixIcon: Icons.link,
          onChanged: (_) => setState(() {}),
        ),
        if (_showErrors && _linkError != null) _ErrorText(_linkError!),
        const SizedBox(height: 16),
        SumouTextField(
          controller: _reportController,
          label: 'رابط ملف التقرير (اختياري)',
          hint: 'الصق رابط الملف مؤقتاً',
          keyboardType: TextInputType.url,
          prefixIcon: Icons.description_outlined,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Text(
          'رفع الملفات غير متاح بعد — أدخل الرابط كنص فقط.',
          style: AppTextStyles.label.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        SumouTextField(
          controller: _notesController,
          label: 'ملاحظات (اختياري)',
          hint: 'أي تفاصيل إضافية للمدير',
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'مراجعة الطلب'),
        const SizedBox(height: 12),
        SumouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewLine(
                label: 'رابط التسليم',
                value: _linkController.text.trim(),
                valueColor: AppColors.accentGreen,
              ),
              _ReviewLine(
                label: 'ملف التقرير',
                value: _reportController.text.trim(),
              ),
              _ReviewLine(
                label: 'ملاحظات',
                value: _notesController.text.trim(),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('الحالة بعد الإرسال:', style: AppTextStyles.label),
                  const SizedBox(width: 8),
                  const SumouStatusChip(SumouStatus.pendingApproval),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- project summary --------------------------------------------------------

class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary({required this.project, this.role});

  final ProjectModel project;
  final String? role;

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
            icon: Icons.timeline_outlined,
            text: stage == null ? 'لا توجد مراحل' : 'المرحلة الحالية: $stage',
          ),
          if (role != null)
            _SummaryLine(icon: Icons.camera_alt_outlined, text: 'دوري: $role'),
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

// ---- small pieces -----------------------------------------------------------

class _PendingNotice extends StatelessWidget {
  const _PendingNotice();

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      borderColor: AppColors.financeYellow,
      child: Row(
        children: [
          const Icon(Icons.hourglass_top, color: AppColors.financeYellow),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'يوجد طلب إغلاق قيد المراجعة',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'لا يمكن إرسال طلب جديد حتى يبتّ المدير في الطلب الحالي.',
                  style: AppTextStyles.bodyMuted,
                ),
              ],
            ),
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
