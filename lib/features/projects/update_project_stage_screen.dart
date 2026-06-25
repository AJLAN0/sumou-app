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

/// Full-screen, mobile-first flow for updating a project's current stage.
///
/// Mock-only: loads the project by id, lets the user pick the current stage and
/// add optional notes, then writes it back via
/// [ProjectRepository.updateProjectStage] and returns to the details screen.
class UpdateProjectStageScreen extends ConsumerWidget {
  const UpdateProjectStageScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      padding: EdgeInsets.zero,
      appBar: SumouAppBar(
        title: 'تحديث المرحلة',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: projectAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('تعذّر تحميل المشروع')),
        data: (project) {
          if (project == null) {
            return const SumouEmptyState(
              title: 'المشروع غير موجود',
              icon: Icons.search_off,
            );
          }
          return _UpdateStageBody(project: project);
        },
      ),
    );
  }
}

class _UpdateStageBody extends ConsumerStatefulWidget {
  const _UpdateStageBody({required this.project});

  final ProjectModel project;

  @override
  ConsumerState<_UpdateStageBody> createState() => _UpdateStageBodyState();
}

class _UpdateStageBodyState extends ConsumerState<_UpdateStageBody> {
  final _notesController = TextEditingController();
  String? _selectedStageId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Default the selection to the project's current stage.
    _selectedStageId = widget.project.currentStage?.id;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  List<ProjectStageModel> get _stages {
    final list = [...widget.project.stages];
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<void> _save() async {
    if (_selectedStageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار المرحلة')),
      );
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(projectRepositoryProvider);
    final userId = ref.read(authControllerProvider).currentUser?.id;
    final notes = _notesController.text.trim();
    final updated = await repo.updateProjectStage(
      widget.project.id,
      _selectedStageId!,
      notes: notes.isEmpty ? null : notes,
      updatedBy: userId,
    );
    ref.invalidate(projectByIdProvider(widget.project.id));
    ref.invalidate(managerProjectsProvider);
    ref.invalidate(photographerProjectsProvider);
    if (!mounted) return;
    if (updated == null) {
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر تحديث المرحلة')),
      );
      return;
    }
    context.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('تم تحديث مرحلة المشروع')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stages = _stages;
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
                const SumouSectionHeader(title: 'اختر المرحلة الحالية'),
                const SizedBox(height: 12),
                if (stages.isEmpty)
                  SumouCard(
                    child: Text(
                      'لا توجد مراحل لهذا المشروع',
                      style: AppTextStyles.bodyMuted,
                    ),
                  )
                else
                  for (final s in stages) ...[
                    _StageOption(
                      stage: s,
                      selected: _selectedStageId == s.id,
                      onTap: () => setState(() => _selectedStageId = s.id),
                    ),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 10),
                SumouTextField(
                  controller: _notesController,
                  label: 'ملاحظات (اختياري)',
                  hint: 'أضف ملاحظة على هذه المرحلة',
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
            child: SumouButton(
              label: 'حفظ المرحلة',
              icon: Icons.check,
              loading: _saving,
              onPressed: (_saving || stages.isEmpty) ? null : _save,
            ),
          ),
        ),
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

// ---- stage option -----------------------------------------------------------

class _StageOption extends StatelessWidget {
  const _StageOption({
    required this.stage,
    required this.selected,
    required this.onTap,
  });

  final ProjectStageModel stage;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (stage.status) {
      ProjectStageStatus.done => (AppColors.accentGreen, Icons.check_circle),
      ProjectStageStatus.current => (
        AppColors.projectTeal,
        Icons.radio_button_checked,
      ),
      ProjectStageStatus.pending => (
        AppColors.textMuted,
        Icons.circle_outlined,
      ),
    };

    return SumouCard(
      onTap: onTap,
      borderColor: selected ? AppColors.accentGreen : null,
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stage.order}. ${stage.title}',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(stage.status.nameAr, style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected ? AppColors.accentGreen : AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
