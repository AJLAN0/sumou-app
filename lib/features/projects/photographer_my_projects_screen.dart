import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'providers/projects_providers.dart';
import 'widgets/project_card.dart';

/// Filters available on the photographer's projects list.
enum _MyFilter { all, active, completed, pendingClosure, field, social }

extension _MyFilterView on _MyFilter {
  String get label => switch (this) {
    _MyFilter.all => 'الكل',
    _MyFilter.active => 'نشط',
    _MyFilter.completed => 'منتهي',
    _MyFilter.pendingClosure => 'بانتظار الإغلاق',
    _MyFilter.field => 'ميداني',
    _MyFilter.social => 'سوشال',
  };

  bool matches(ProjectModel p) => switch (this) {
    _MyFilter.all => true,
    _MyFilter.active => p.isActive,
    _MyFilter.completed => p.isCompleted,
    _MyFilter.pendingClosure => p.hasPendingClosure,
    _MyFilter.field => p.type == ProjectType.field,
    _MyFilter.social => p.type == ProjectType.social,
  };
}

/// Photographer "مشاريعي" tab: the projects the signed-in photographer is
/// assigned to. Read-only cards with search + filters. Mock-backed; no
/// stage/closure actions in this step.
class PhotographerMyProjectsScreen extends ConsumerStatefulWidget {
  const PhotographerMyProjectsScreen({super.key});

  @override
  ConsumerState<PhotographerMyProjectsScreen> createState() =>
      _PhotographerMyProjectsScreenState();
}

class _PhotographerMyProjectsScreenState
    extends ConsumerState<PhotographerMyProjectsScreen> {
  String _query = '';
  _MyFilter _filter = _MyFilter.all;

  bool _matchesQuery(ProjectModel p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return p.name.toLowerCase().contains(q) ||
        p.clientName.toLowerCase().contains(q);
  }

  /// The current photographer's own role/photo type on a project, if any.
  String? _myRole(ProjectModel p, String? userId) {
    if (userId == null) return null;
    for (final r in p.teamRoles) {
      if (r.userId == userId) return r.type;
    }
    return null;
  }

  void _openDetails(String id) {
    context.push(AppRoutes.projectDetailsPath(id));
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(
      authControllerProvider.select((s) => s.currentUser?.id),
    );
    final projectsAsync = ref.watch(photographerProjectsProvider);

    return Column(
      children: [
        SumouTextField(
          hint: 'بحث باسم المشروع أو العميل',
          prefixIcon: Icons.search,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _MyFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _MyFilter.values[i];
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
            error: (_, __) => const Center(child: Text('تعذّر تحميل مشاريعك')),
            data: (projects) {
              final filtered =
                  projects.where(_matchesQuery).where(_filter.matches).toList();
              if (projects.isEmpty) {
                return const SumouEmptyState(
                  title: 'لا توجد مشاريع مسندة إليك',
                  message: 'ستظهر هنا المشاريع التي يتم إسنادك إليها',
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
                itemBuilder:
                    (_, i) => ProjectCard(
                      project: filtered[i],
                      roleLabel: _myRole(filtered[i], userId),
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
