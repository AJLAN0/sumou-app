import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../projects/providers/projects_providers.dart';
import '../projects/widgets/project_card.dart';

String _fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

enum _ProjFilter { all, active, completed, pendingClosure, field, social, wedding }

extension _ProjFilterView on _ProjFilter {
  String get label => switch (this) {
    _ProjFilter.all => 'الكل',
    _ProjFilter.active => 'نشط',
    _ProjFilter.completed => 'منتهي',
    _ProjFilter.pendingClosure => 'بانتظار الإغلاق',
    _ProjFilter.field => 'ميداني',
    _ProjFilter.social => 'سوشال',
    _ProjFilter.wedding => 'زواج',
  };

  bool matches(ProjectModel p) => switch (this) {
    _ProjFilter.all => true,
    _ProjFilter.active => p.isActive,
    _ProjFilter.completed => p.isCompleted,
    _ProjFilter.pendingClosure => p.hasPendingClosure,
    _ProjFilter.field => p.type == ProjectType.field,
    _ProjFilter.social => p.type == ProjectType.social,
    _ProjFilter.wedding => p.type == ProjectType.wedding,
  };
}

/// Admin "كل المشاريع": a system-wide, read-only view of every project,
/// regardless of manager/photographer. Mock-backed. No editing here.
class AdminAllProjectsScreen extends ConsumerStatefulWidget {
  const AdminAllProjectsScreen({super.key});

  @override
  ConsumerState<AdminAllProjectsScreen> createState() =>
      _AdminAllProjectsScreenState();
}

class _AdminAllProjectsScreenState
    extends ConsumerState<AdminAllProjectsScreen> {
  String _query = '';
  _ProjFilter _filter = _ProjFilter.all;
  String? _managerName; // null = all
  String? _photographerName; // null = all

  bool _matchesQuery(ProjectModel p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final inTeam = p.teamRoles.any(
      (r) => r.personName.toLowerCase().contains(q),
    );
    return p.name.toLowerCase().contains(q) ||
        p.clientName.toLowerCase().contains(q) ||
        p.serial.toLowerCase().contains(q) ||
        (p.managerName?.toLowerCase().contains(q) ?? false) ||
        inTeam;
  }

  bool _matches(ProjectModel p) {
    final managerOk = _managerName == null || p.managerName == _managerName;
    final photographerOk =
        _photographerName == null ||
        p.teamRoles.any((r) => r.personName == _photographerName);
    return _matchesQuery(p) && _filter.matches(p) && managerOk && photographerOk;
  }

  Future<void> _pick({
    required String title,
    required String allLabel,
    required List<String> options,
    required String? current,
    required ValueChanged<String?> onChanged,
  }) async {
    final result = await showModalBottomSheet<String>(
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
                _PickerRow(
                  label: allLabel,
                  selected: current == null,
                  onTap: () => Navigator.of(sheetContext).pop('__all__'),
                ),
                for (final o in options) ...[
                  const SizedBox(height: 8),
                  _PickerRow(
                    label: o,
                    selected: current == o,
                    onTap: () => Navigator.of(sheetContext).pop(o),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (result == null) return; // dismissed
    onChanged(result == '__all__' ? null : result);
  }

  void _openDetails(String id) => context.push(AppRoutes.projectDetailsPath(id));

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(allProjectsProvider);

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'كل المشاريع',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('تعذر تحميل المشاريع')),
        data: (projects) {
          final managers = <String>{
            for (final p in projects)
              if (p.managerName != null) p.managerName!,
          }.toList();
          final photographers = <String>{
            for (final p in projects)
              for (final r in p.teamRoles) r.personName,
          }.toList();
          final filtered = projects.where(_matches).toList();

          return Column(
            children: [
              _StatsStrip(projects: projects),
              const SizedBox(height: 12),
              SumouTextField(
                hint: 'بحث بالمشروع أو العميل أو الكود أو المدير أو المصور',
                prefixIcon: Icons.search,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _ProjFilter.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = _ProjFilter.values[i];
                    return _FilterChip(
                      label: f.label,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SelectorButton(
                      icon: Icons.badge_outlined,
                      label: _managerName ?? 'كل المدراء',
                      onTap: () => _pick(
                        title: 'تصفية حسب المدير',
                        allLabel: 'كل المدراء',
                        options: managers,
                        current: _managerName,
                        onChanged: (v) => setState(() => _managerName = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SelectorButton(
                      icon: Icons.camera_alt_outlined,
                      label: _photographerName ?? 'كل المصورين',
                      onTap: () => _pick(
                        title: 'تصفية حسب المصور',
                        allLabel: 'كل المصورين',
                        options: photographers,
                        current: _photographerName,
                        onChanged: (v) =>
                            setState(() => _photographerName = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: projects.isEmpty
                    ? const SumouEmptyState(
                        title: 'لا توجد مشاريع',
                        message: 'لم تتم إضافة أي مشروع بعد',
                        icon: Icons.work_outline,
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
                            itemBuilder: (_, i) => _AdminProjectCard(
                              project: filtered[i],
                              onTap: () => _openDetails(filtered[i].id),
                            ),
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
  const _StatsStrip({required this.projects});

  final List<ProjectModel> projects;

  @override
  Widget build(BuildContext context) {
    final total = projects.length;
    final active = projects.where((p) => p.isActive).length;
    final completed = projects.where((p) => p.isCompleted).length;
    final pending = projects.where((p) => p.hasPendingClosure).length;
    final field = projects.where((p) => p.type == ProjectType.field).length;
    final social = projects.where((p) => p.type == ProjectType.social).length;

    return SumouCard(
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          _MiniStat(value: '$total', label: 'الإجمالي', color: AppColors.projectTeal),
          _MiniStat(value: '$active', label: 'نشطة', color: AppColors.primaryTeal),
          _MiniStat(
            value: '$completed',
            label: 'منتهية',
            color: AppColors.accentGreen,
          ),
          _MiniStat(
            value: '$pending',
            label: 'بانتظار الإغلاق',
            color: AppColors.financeYellow,
          ),
          _MiniStat(value: '$field', label: 'ميدانية', color: AppColors.projectTeal),
          _MiniStat(value: '$social', label: 'سوشال', color: AppColors.photographerPurple),
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
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(color: color),
        ),
        Text(label, style: AppTextStyles.label),
      ],
    );
  }
}

// ---- project card -----------------------------------------------------------

class _AdminProjectCard extends StatelessWidget {
  const _AdminProjectCard({required this.project, required this.onTap});

  final ProjectModel project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final percent = p.stageProgressPercent;
    final stage = p.currentStage?.title;
    final photographers = p.teamRoles.length;

    return SumouCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.name, style: AppTextStyles.titleMedium),
              ),
              const SizedBox(width: 8),
              SumouStatusChip(sumouStatusForProject(p.status)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(p.clientName, style: AppTextStyles.bodyMuted),
              ),
              Text(
                p.serial,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.accentGreen,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Tag(label: p.type.nameAr),
              _MetaText(
                icon: Icons.calendar_today_outlined,
                text: '${_fmtDate(p.startDate)} ← ${_fmtDate(p.endDate)}',
              ),
              if (p.hasPendingClosure)
                _Tag(label: 'بانتظار الإغلاق', color: AppColors.financeYellow),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MetaText(
                icon: Icons.badge_outlined,
                text: 'المدير: ${p.managerName ?? '—'}',
              ),
              const SizedBox(width: 12),
              _MetaText(
                icon: Icons.camera_alt_outlined,
                text: 'المصورون: $photographers',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  stage == null ? 'لا توجد مراحل' : 'المرحلة: $stage',
                  style: AppTextStyles.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$percent%',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.accentGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 5,
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

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.projectTeal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: AppTextStyles.label.copyWith(color: c)),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(text, style: AppTextStyles.label),
      ],
    );
  }
}

// ---- controls ---------------------------------------------------------------

class _SelectorButton extends StatelessWidget {
  const _SelectorButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      borderColor: selected ? AppColors.accentGreen : null,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.body)),
          if (selected)
            const Icon(Icons.check_circle, color: AppColors.accentGreen),
        ],
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
