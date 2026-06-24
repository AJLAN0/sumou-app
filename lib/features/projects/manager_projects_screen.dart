import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/projects_providers.dart';
import 'widgets/project_card.dart';

enum _ProjectFilter { all, active, completed, pendingClosure, field, social }

extension _FilterView on _ProjectFilter {
  String get label => switch (this) {
    _ProjectFilter.all => 'الكل',
    _ProjectFilter.active => 'نشط',
    _ProjectFilter.completed => 'منتهي',
    _ProjectFilter.pendingClosure => 'بانتظار الإغلاق',
    _ProjectFilter.field => 'ميداني',
    _ProjectFilter.social => 'سوشال',
  };

  bool matches(ProjectModel p) => switch (this) {
    _ProjectFilter.all => true,
    _ProjectFilter.active => p.isActive,
    _ProjectFilter.completed => p.isCompleted,
    _ProjectFilter.pendingClosure => p.hasPendingClosure,
    _ProjectFilter.field => p.type == ProjectType.field,
    _ProjectFilter.social => p.type == ProjectType.social,
  };
}

/// Manager projects list (المشاريع tab). Read-only cards with search + filters.
class ManagerProjectsScreen extends ConsumerStatefulWidget {
  const ManagerProjectsScreen({super.key});

  @override
  ConsumerState<ManagerProjectsScreen> createState() =>
      _ManagerProjectsScreenState();
}

class _ManagerProjectsScreenState extends ConsumerState<ManagerProjectsScreen> {
  String _query = '';
  _ProjectFilter _filter = _ProjectFilter.all;

  bool _matchesQuery(ProjectModel p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final inTeam = p.teamRoles.any(
      (r) => r.personName.toLowerCase().contains(q),
    );
    return p.name.toLowerCase().contains(q) ||
        p.clientName.toLowerCase().contains(q) ||
        inTeam;
  }

  void _openDetails(String id) {
    context.push(AppRoutes.projectDetailsPath(id));
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(managerProjectsProvider);

    return Column(
      children: [
        SumouTextField(
          hint: 'بحث باسم المشروع أو العميل أو المصور',
          prefixIcon: Icons.search,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _ProjectFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _ProjectFilter.values[i];
              return _FilterChip(
                label: f.label,
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: projectsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('تعذّر تحميل المشاريع')),
            data: (projects) {
              final filtered =
                  projects.where(_matchesQuery).where(_filter.matches).toList();
              if (projects.isEmpty) {
                return const SumouEmptyState(
                  title: 'لا توجد مشاريع',
                  message: 'ستظهر مشاريعك هنا عند إضافتها',
                  icon: Icons.work_outline,
                );
              }
              if (filtered.isEmpty) {
                return const SumouEmptyState(
                  title: 'لا توجد نتائج',
                  message: 'جرّب تعديل البحث أو الفلاتر',
                  icon: Icons.search_off,
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => ProjectCard(
                  project: filtered[i],
                  onTap: () => _openDetails(filtered[i].id),
                ),
              );
            },
          ),
        ),
      ],
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
