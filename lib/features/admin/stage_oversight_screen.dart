import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../projects/providers/projects_providers.dart';
import 'widgets/admin_chips.dart';
import 'widgets/admin_project_card.dart';

/// A project is "delayed" when it isn't completed and its delivery date has
/// already passed (date-only). Simple, mock-based.
bool _isDelayed(ProjectModel p, DateTime today) =>
    !p.isCompleted && DateUtils.dateOnly(p.endDate).isBefore(today);

enum _StageFilter { all, inProgress, pendingClosure, completed, delayed, field, social }

extension _StageFilterView on _StageFilter {
  String get label => switch (this) {
    _StageFilter.all => 'الكل',
    _StageFilter.inProgress => 'قيد التنفيذ',
    _StageFilter.pendingClosure => 'بانتظار الإغلاق',
    _StageFilter.completed => 'مكتمل',
    _StageFilter.delayed => 'متأخر',
    _StageFilter.field => 'ميداني',
    _StageFilter.social => 'سوشال',
  };

  bool matches(ProjectModel p, DateTime today) => switch (this) {
    _StageFilter.all => true,
    _StageFilter.inProgress => p.isActive,
    _StageFilter.pendingClosure => p.hasPendingClosure,
    _StageFilter.completed => p.isCompleted,
    _StageFilter.delayed => _isDelayed(p, today),
    _StageFilter.field => p.type == ProjectType.field,
    _StageFilter.social => p.type == ProjectType.social,
  };
}

/// Admin stage oversight (read-only): monitor stage progress across every
/// project, spot delayed/pending ones, and open the read-only details. No stage
/// editing here.
class AdminStageOversightScreen extends ConsumerStatefulWidget {
  const AdminStageOversightScreen({super.key});

  @override
  ConsumerState<AdminStageOversightScreen> createState() =>
      _AdminStageOversightScreenState();
}

class _AdminStageOversightScreenState
    extends ConsumerState<AdminStageOversightScreen> {
  String _query = '';
  _StageFilter _filter = _StageFilter.all;

  bool _matches(ProjectModel p, DateTime today) {
    final q = _query.trim().toLowerCase();
    final matchesQuery = q.isEmpty ||
        p.name.toLowerCase().contains(q) ||
        p.clientName.toLowerCase().contains(q) ||
        p.serial.toLowerCase().contains(q);
    return matchesQuery && _filter.matches(p, today);
  }

  void _openDetails(String id) =>
      context.push(AppRoutes.adminProjectDetailsPath(id));

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(allProjectsProvider);
    final today = DateUtils.dateOnly(DateTime.now());

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'مراقبة المراحل',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('تعذّر تحميل المشاريع')),
        data: (projects) {
          final filtered =
              projects.where((p) => _matches(p, today)).toList();
          return Column(
            children: [
              _StatsStrip(projects: projects, today: today),
              const SizedBox(height: 12),
              SumouTextField(
                hint: 'بحث بالمشروع أو العميل أو الكود',
                prefixIcon: Icons.search,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _StageFilter.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = _StageFilter.values[i];
                    return AdminFilterChip(
                      label: f.label,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: projects.isEmpty
                    ? const SumouEmptyState(
                        title: 'لا توجد مشاريع',
                        icon: Icons.timeline_outlined,
                      )
                    : filtered.isEmpty
                        ? const SumouEmptyState(
                            title: 'لا توجد نتائج مطابقة',
                            message: 'جرّب تعديل البحث أو الفلاتر',
                            icon: Icons.search_off,
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              final p = filtered[i];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_isDelayed(p, today))
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 6),
                                      child: _DelayedTag(),
                                    ),
                                  AdminProjectCard(
                                    project: p,
                                    onTap: () => _openDetails(p.id),
                                  ),
                                ],
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---- summary ----------------------------------------------------------------

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.projects, required this.today});

  final List<ProjectModel> projects;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final total = projects.length;
    final active = projects.where((p) => p.isActive).length;
    final pending = projects.where((p) => p.hasPendingClosure).length;
    final completed = projects.where((p) => p.isCompleted).length;
    final delayed = projects.where((p) => _isDelayed(p, today)).length;
    final inProgressStages = projects
        .where((p) => !p.isCompleted && p.currentStage != null)
        .length;

    return SumouCard(
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          _MiniStat(value: '$total', label: 'الإجمالي', color: AppColors.projectTeal),
          _MiniStat(value: '$active', label: 'نشطة', color: AppColors.primaryTeal),
          _MiniStat(
            value: '$pending',
            label: 'بانتظار الإغلاق',
            color: AppColors.financeYellow,
          ),
          _MiniStat(
            value: '$completed',
            label: 'مكتملة',
            color: AppColors.accentGreen,
          ),
          _MiniStat(value: '$delayed', label: 'متأخرة', color: AppColors.error),
          _MiniStat(
            value: '$inProgressStages',
            label: 'مراحل قيد التنفيذ',
            color: AppColors.photographerPurple,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTextStyles.titleMedium.copyWith(color: color)),
        Text(label, style: AppTextStyles.label),
      ],
    );
  }
}

class _DelayedTag extends StatelessWidget {
  const _DelayedTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
          const SizedBox(width: 4),
          Text(
            'متأخر عن موعد التسليم',
            style: AppTextStyles.label.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

