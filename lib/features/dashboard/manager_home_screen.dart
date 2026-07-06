import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../projects/providers/projects_providers.dart';
import '../shell/shell_providers.dart';

/// Manager home dashboard (home tab of the manager shell).
///
/// A clean, operational monthly summary computed from the mock repositories.
/// Cards and quick actions switch the shell to the matching bottom-nav tab.
class ManagerHomeScreen extends ConsumerWidget {
  const ManagerHomeScreen({super.key});

  // Manager bottom-nav indices: 0 home, 1 projects, 2 requests, 3 team.
  static const int _projectsTab = 1;
  static const int _requestsTab = 2;
  static const int _teamTab = 3;

  void _jump(WidgetRef ref, int index) =>
      ref.read(shellJumpTabProvider.notifier).state = index;

  void _openActiveProjects(WidgetRef ref) {
    ref.read(managerProjectsShowActiveProvider.notifier).state = true;
    _jump(ref, _projectsTab);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(managerProjectsProvider).valueOrNull;
    final closures = ref.watch(managerAllClosureRequestsProvider).valueOrNull;
    final photographers = ref.watch(photographerCandidatesProvider).valueOrNull;
    final counts =
        ref.watch(photographerActiveCountsProvider).valueOrNull ??
        const <String, int>{};

    final activeCount = projects?.where((p) => p.isActive).length;
    final pendingClosures = closures
        ?.where((v) => v.request.status == ClosureRequestStatus.pending)
        .length;
    final totalPhotographers = photographers?.length;
    final availablePhotographers = photographers
        ?.where((u) => (counts[u.id] ?? 0) < 2)
        .length;

    String n(int? value) => value?.toString() ?? '—';

    return ListView(
      children: [
        const SizedBox(height: 4),
        Text('ملخص الشهر', style: AppTextStyles.titleMedium),
        const SizedBox(height: 4),
        Text(
          'نظرة سريعة على مشاريع هذا الشهر وفريقك',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SumouStatCard(
                value: n(activeCount),
                label: 'مشاريع نشطة',
                icon: Icons.work_outline,
                accentColor: AppColors.projectTeal,
                onTap: () => _openActiveProjects(ref),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SumouStatCard(
                value: n(pendingClosures),
                label: 'طلبات إنهاء',
                icon: Icons.inbox_outlined,
                accentColor: AppColors.financeYellow,
                onTap: () => _jump(ref, _requestsTab),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SumouStatCard(
          value: '${n(availablePhotographers)} / ${n(totalPhotographers)}',
          label: 'الفريق المتاح',
          icon: Icons.group_outlined,
          accentColor: AppColors.accentGreen,
          onTap: () => _jump(ref, _teamTab),
        ),
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'إجراءات سريعة'),
        const SizedBox(height: 12),
        SumouButton(
          label: 'إضافة مشروع',
          icon: Icons.add,
          onPressed: () => context.push(AppRoutes.addProject),
        ),
        const SizedBox(height: 10),
        SumouButton(
          label: 'عرض الطلبات',
          variant: SumouButtonVariant.secondary,
          icon: Icons.inbox_outlined,
          onPressed: () => _jump(ref, _requestsTab),
        ),
        const SizedBox(height: 10),
        SumouButton(
          label: 'عرض الفريق',
          variant: SumouButtonVariant.secondary,
          icon: Icons.group_outlined,
          onPressed: () => _jump(ref, _teamTab),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
