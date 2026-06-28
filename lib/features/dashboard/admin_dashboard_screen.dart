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
/// A read-only control center computed from the mock repositories: user/team,
/// project-operations, and request stats. No user/permission editing, no
/// finance/notifications. Quick actions are placeholders until their screens
/// get routes.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('هذه الميزة قريباً')));
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

    // ---- user / team stats --------------------------------------------------
    final totalUsers = users.length;
    final activeUsers = users.where((u) => u.active).length;
    final inactiveUsers = totalUsers - activeUsers;
    final managers = users.where((u) => u.hasRole(RoleType.manager)).length;
    final photographers =
        users.where((u) => u.hasRole(RoleType.photographer)).length;
    final activeManagers =
        users.where((u) => u.active && u.hasRole(RoleType.manager)).length;
    final activePhotographers = users.where(
      (u) => u.active && u.hasRole(RoleType.photographer),
    );
    final highWorkload =
        activePhotographers.where((u) => (counts[u.id] ?? 0) >= 2).length;
    final available =
        activePhotographers.where((u) => (counts[u.id] ?? 0) < 2).length;

    // ---- project stats ------------------------------------------------------
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
    final recent = projects.take(3).toList();

    // ---- request stats ------------------------------------------------------
    final pendingReq =
        closures.where((r) => r.status == ClosureRequestStatus.pending).length;
    final approvedReq =
        closures.where((r) => r.status == ClosureRequestStatus.approved).length;
    final rejectedReq =
        closures.where((r) => r.status == ClosureRequestStatus.rejected).length;

    return ListView(
      children: [
        const SizedBox(height: 4),
        Text('نظرة عامة على النظام', style: AppTextStyles.titleMedium),
        const SizedBox(height: 4),
        Text(
          'مراقبة المستخدمين والمشاريع والطلبات من مكان واحد',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 16),

        // ---- overview ----
        _Grid(
          cards: [
            _Stat(
              '$totalUsers',
              'إجمالي المستخدمين',
              Icons.people_outline,
              AppColors.projectTeal,
            ),
            _Stat(
              '$activeUsers',
              'المستخدمون النشطون',
              Icons.verified_user_outlined,
              AppColors.accentGreen,
            ),
            _Stat(
              '$inactiveUsers',
              'غير النشطين',
              Icons.person_off_outlined,
              AppColors.error,
            ),
            _Stat(
              '$totalProjects',
              'إجمالي المشاريع',
              Icons.work_outline,
              AppColors.projectTeal,
            ),
            _Stat(
              '$activeProjects',
              'المشاريع النشطة',
              Icons.play_circle_outline,
              AppColors.primaryTeal,
            ),
            _Stat(
              '$completedProjects',
              'المشاريع المنتهية',
              Icons.check_circle_outline,
              AppColors.accentGreen,
            ),
            _Stat(
              '$pendingReq',
              'طلبات الإغلاق المعلقة',
              Icons.inbox_outlined,
              AppColors.financeYellow,
            ),
            _Stat(
              '$managers',
              'عدد المدراء',
              Icons.badge_outlined,
              AppColors.photographerPurple,
            ),
            _Stat(
              '$photographers',
              'عدد المصورين',
              Icons.camera_alt_outlined,
              AppColors.projectTeal,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ---- project operations ----
        const SumouSectionHeader(title: 'عمليات المشاريع'),
        const SizedBox(height: 12),
        _Grid(
          cards: [
            _Stat(
              '$activeProjects',
              'نشطة',
              Icons.play_circle_outline,
              AppColors.primaryTeal,
            ),
            _Stat(
              '$completedProjects',
              'منتهية',
              Icons.check_circle_outline,
              AppColors.accentGreen,
            ),
            _Stat(
              '$pendingClosure',
              'بانتظار الإغلاق',
              Icons.hourglass_top,
              AppColors.financeYellow,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SumouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المشاريع حسب النوع', style: AppTextStyles.label),
              const SizedBox(height: 10),
              _TypeRow(label: 'ميداني', count: fieldCount),
              _TypeRow(label: 'سوشال', count: socialCount),
              _TypeRow(label: 'زواج', count: weddingCount),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('أحدث المشاريع', style: AppTextStyles.label),
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
        const SizedBox(height: 12),

        // ---- team overview ----
        const SumouSectionHeader(title: 'نظرة على الفريق'),
        const SizedBox(height: 12),
        _Grid(
          cards: [
            _Stat(
              '$activeManagers',
              'مدراء نشطون',
              Icons.badge_outlined,
              AppColors.photographerPurple,
            ),
            _Stat(
              '${activePhotographers.length}',
              'مصورون نشطون',
              Icons.camera_alt_outlined,
              AppColors.projectTeal,
            ),
            _Stat(
              '$inactiveUsers',
              'مستخدمون معطّلون',
              Icons.person_off_outlined,
              AppColors.error,
            ),
            _Stat(
              '$highWorkload',
              'مصورون مرتفعو الحِمل',
              Icons.trending_up,
              AppColors.financeYellow,
            ),
            _Stat(
              '$available',
              'مصورون متاحون',
              Icons.event_available_outlined,
              AppColors.accentGreen,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ---- requests overview ----
        const SumouSectionHeader(title: 'الطلبات'),
        const SizedBox(height: 12),
        _Grid(
          cards: [
            _Stat(
              '$pendingReq',
              'معلقة',
              Icons.hourglass_top,
              AppColors.financeYellow,
            ),
            _Stat(
              '$approvedReq',
              'مقبولة',
              Icons.check_circle_outline,
              AppColors.accentGreen,
            ),
            _Stat(
              '$rejectedReq',
              'مرفوضة',
              Icons.cancel_outlined,
              AppColors.error,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ---- quick actions ----
        const SumouSectionHeader(title: 'إجراءات سريعة'),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.group_outlined,
          label: 'إدارة المستخدمين',
          onTap: () => _comingSoon(context),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.shield_outlined,
          label: 'الصلاحيات',
          onTap: () => _comingSoon(context),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.work_outline,
          label: 'كل المشاريع',
          onTap: () => context.push(AppRoutes.adminProjects),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.inbox_outlined,
          label: 'الطلبات',
          onTap: () => _comingSoon(context),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.bar_chart,
          label: 'التقارير',
          onTap: () => _comingSoon(context),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// A small value object describing one stat card.
class _Stat {
  const _Stat(this.value, this.label, this.icon, this.color);

  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

/// Lays out stat cards in a 2-column grid.
class _Grid extends StatelessWidget {
  const _Grid({required this.cards});

  final List<_Stat> cards;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _card(cards[i])),
              const SizedBox(width: 12),
              if (i + 1 < cards.length)
                Expanded(child: _card(cards[i + 1]))
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );
      if (i + 2 < cards.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  Widget _card(_Stat s) => SumouStatCard(
    value: s.value,
    label: s.label,
    icon: s.icon,
    accentColor: s.color,
  );
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(
            Icons.category_outlined,
            size: 16,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppTextStyles.body)),
          Text(
            '$count',
            style: AppTextStyles.label.copyWith(color: AppColors.accentGreen),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentGreen, size: 22),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: AppTextStyles.body)),
          const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
