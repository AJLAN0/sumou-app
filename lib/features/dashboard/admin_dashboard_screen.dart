import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../admin/providers/admin_providers.dart';
import '../projects/providers/projects_providers.dart';
import '../projects/widgets/project_card.dart';

/// Admin overview dashboard (home tab of the admin shell).
///
/// A read-only control center computed from the mock repositories, grouped into
/// clear sections: a headline strip, projects, team, requests, and quick
/// actions. No user/permission editing, no finance/notifications.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('هذه الميزة قريباً')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersListProvider);
    final projectsAsync = ref.watch(allProjectsProvider);
    final closuresAsync = ref.watch(allClosureRequestsProvider);
    final counts =
        ref.watch(photographerActiveCountsProvider).valueOrNull ??
        const <String, int>{};

    if (usersAsync.hasError ||
        projectsAsync.hasError ||
        closuresAsync.hasError) {
      return const Center(child: Text('تعذّر تحميل بيانات النظام'));
    }
    final users = usersAsync.valueOrNull;
    final projects = projectsAsync.valueOrNull;
    final closures = closuresAsync.valueOrNull;
    if (users == null || projects == null || closures == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // ---- team stats ----
    final totalUsers = users.length;
    final activeUsers = users.where((u) => u.active).length;
    final inactiveUsers = totalUsers - activeUsers;
    final managers = users.where((u) => u.hasRole(RoleType.manager)).length;
    final photographers =
        users.where((u) => u.hasRole(RoleType.photographer)).length;
    final activePhotographers =
        users.where((u) => u.active && u.hasRole(RoleType.photographer));
    final highWorkload =
        activePhotographers.where((u) => (counts[u.id] ?? 0) >= 2).length;
    final available =
        activePhotographers.where((u) => (counts[u.id] ?? 0) < 2).length;

    // ---- project stats ----
    final totalProjects = projects.length;
    final activeProjects = projects.where((p) => p.isActive).length;
    final completedProjects = projects.where((p) => p.isCompleted).length;
    final pendingClosure = projects.where((p) => p.hasPendingClosure).length;
    final fieldCount =
        projects.where((p) => p.type == ProjectType.field).length;
    final socialCount =
        projects.where((p) => p.type == ProjectType.social).length;
    final weddingCount =
        projects.where((p) => p.type == ProjectType.wedding).length;
    final recent = projects.take(2).toList();

    // ---- request stats ----
    final pendingReq = closures
        .where((r) => r.status == ClosureRequestStatus.pending)
        .length;
    final approvedReq = closures
        .where((r) => r.status == ClosureRequestStatus.approved)
        .length;
    final rejectedReq = closures
        .where((r) => r.status == ClosureRequestStatus.rejected)
        .length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 4),
        Text('نظرة عامة على النظام', style: AppTextStyles.titleMedium),
        const SizedBox(height: 4),
        Text(
          'مراقبة المستخدمين والمشاريع والطلبات من مكان واحد',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 16),

        // ---- headline strip ----
        _Hero(
          tiles: [
            _Metric('$totalProjects', 'المشاريع', AppColors.projectTeal),
            _Metric('$activeProjects', 'نشطة', AppColors.primaryTeal),
            _Metric('$pendingClosure', 'بانتظار الإغلاق', AppColors.financeYellow),
            _Metric('$totalUsers', 'المستخدمون', AppColors.photographerPurple),
          ],
        ),
        const SizedBox(height: 16),

        // ---- projects ----
        _SectionCard(
          title: 'المشاريع',
          icon: Icons.work_outline,
          actionLabel: 'عرض الكل',
          onAction: () => context.push(AppRoutes.adminProjects),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetricRow(
                metrics: [
                  _Metric('$activeProjects', 'نشطة', AppColors.primaryTeal),
                  _Metric(
                    '$completedProjects',
                    'منتهية',
                    AppColors.accentGreen,
                  ),
                  _Metric(
                    '$pendingClosure',
                    'بانتظار الإغلاق',
                    AppColors.financeYellow,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _Divider(),
              const SizedBox(height: 12),
              Text('المشاريع حسب النوع', style: AppTextStyles.label),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TypeChip(label: 'ميداني', count: fieldCount),
                  _TypeChip(label: 'سوشال', count: socialCount),
                  _TypeChip(label: 'زواج', count: weddingCount),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- recent projects ----
        SumouSectionHeader(
          title: 'أحدث المشاريع',
          actionLabel: 'مراقبة المراحل',
          onAction: () => context.push(AppRoutes.adminStages),
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          const SumouEmptyState(
            title: 'لا توجد مشاريع',
            icon: Icons.work_outline,
          )
        else
          for (final p in recent) ...[
            ProjectCard(
              project: p,
              onTap: () => context.push(AppRoutes.projectDetailsPath(p.id)),
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 4),

        // ---- team ----
        _SectionCard(
          title: 'الفريق',
          icon: Icons.group_outlined,
          child: Column(
            children: [
              _MetricRow(
                metrics: [
                  _Metric('$totalUsers', 'المستخدمون', AppColors.projectTeal),
                  _Metric('$activeUsers', 'نشطون', AppColors.accentGreen),
                  _Metric('$inactiveUsers', 'معطّلون', AppColors.error),
                ],
              ),
              const SizedBox(height: 12),
              const _Divider(),
              const SizedBox(height: 12),
              _MetricRow(
                metrics: [
                  _Metric(
                    '$managers',
                    'المدراء',
                    AppColors.photographerPurple,
                  ),
                  _Metric('$photographers', 'المصورون', AppColors.projectTeal),
                  _Metric('$available', 'متاحون', AppColors.accentGreen),
                  _Metric('$highWorkload', 'مرتفعو الحِمل', AppColors.financeYellow),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- requests ----
        _SectionCard(
          title: 'طلبات الإغلاق',
          icon: Icons.inbox_outlined,
          child: _MetricRow(
            metrics: [
              _Metric('$pendingReq', 'معلقة', AppColors.financeYellow),
              _Metric('$approvedReq', 'مقبولة', AppColors.accentGreen),
              _Metric('$rejectedReq', 'مرفوضة', AppColors.error),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- quick actions ----
        const SumouSectionHeader(title: 'إجراءات سريعة'),
        const SizedBox(height: 12),
        _ActionGrid(
          actions: [
            _Action(
              icon: Icons.work_outline,
              label: 'كل المشاريع',
              onTap: () => context.push(AppRoutes.adminProjects),
            ),
            _Action(
              icon: Icons.timeline_outlined,
              label: 'مراقبة المراحل',
              onTap: () => context.push(AppRoutes.adminStages),
            ),
            _Action(
              icon: Icons.group_outlined,
              label: 'إدارة المستخدمين',
              onTap: () => context.push(AppRoutes.adminUsers),
            ),
            _Action(
              icon: Icons.shield_outlined,
              label: 'الأدوار والصلاحيات',
              onTap: () => context.push(AppRoutes.adminAccess),
            ),
            _Action(
              icon: Icons.bar_chart,
              label: 'التقارير',
              onTap: () => _comingSoon(context),
            ),
          ],
        ),
      ],
    );
  }
}

// ---- value objects ----------------------------------------------------------

class _Metric {
  const _Metric(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;
}

class _Action {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

// ---- headline strip ---------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.tiles});

  final List<_Metric> tiles;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: _MetricRow(metrics: tiles, large: true),
    );
  }
}

// ---- section card -----------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accentGreen),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppTextStyles.titleMedium)),
              if (actionLabel != null && onAction != null)
                GestureDetector(
                  onTap: onAction,
                  child: Text(
                    actionLabel!,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.accentGreen,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ---- metrics ----------------------------------------------------------------

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metrics, this.large = false});

  final List<_Metric> metrics;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0)
            Container(width: 1, height: 34, color: AppColors.border),
          Expanded(child: _MetricTile(metric: metrics[i], large: large)),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric, required this.large});

  final _Metric metric;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          metric.value,
          style: (large ? AppTextStyles.titleLarge : AppTextStyles.titleMedium)
              .copyWith(color: metric.color),
        ),
        const SizedBox(height: 2),
        Text(
          metric.label,
          style: AppTextStyles.label.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.border);
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.category_outlined, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.label),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: AppTextStyles.label.copyWith(
              color: AppColors.accentGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- quick actions ----------------------------------------------------------

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.actions});

  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += 2) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _ActionTile(action: actions[i])),
            const SizedBox(width: 12),
            if (i + 1 < actions.length)
              Expanded(child: _ActionTile(action: actions[i + 1]))
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < actions.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      onTap: action.onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(action.icon, color: AppColors.accentGreen, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              action.label,
              style: AppTextStyles.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
