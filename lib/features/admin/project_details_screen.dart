import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../projects/providers/projects_providers.dart';
import '../projects/widgets/closure_request_card.dart';
import '../projects/widgets/project_card.dart';
import '../projects/widgets/stage_timeline.dart';
import 'providers/admin_providers.dart';

String _fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// Admin project oversight (read-only). Opens any project regardless of
/// manager/photographer. No editing here — actions are placeholders.
class AdminProjectDetailsScreen extends ConsumerWidget {
  const AdminProjectDetailsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'مراقبة المشروع',
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
          return _Body(project: project);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersById = {
      for (final u
          in ref.watch(usersListProvider).valueOrNull ?? const <UserModel>[])
        u.id: u,
    };
    final closureAsync = ref.watch(
      closureRequestForProjectProvider(project.id),
    );
    final photographers = project.teamRoles;

    return ListView(
      children: [
        const SizedBox(height: 8),
        _Summary(project: project),
        const SizedBox(height: 24),

        // ---- team ----
        const SumouSectionHeader(title: 'الفريق'),
        const SizedBox(height: 12),
        _TeamRow(
          name: project.managerName ?? '—',
          type: 'مدير المشروع',
          active: usersById[project.managerId]?.active,
          color: AppColors.primaryTeal,
        ),
        const SizedBox(height: 10),
        if (photographers.isEmpty)
          const SumouEmptyState(
            title: 'لا يوجد مصورون',
            message: 'لم يتم إسناد أعضاء بعد',
            icon: Icons.group_outlined,
          )
        else
          for (final role in photographers) ...[
            _TeamRow(
              name: role.personName,
              type: role.type,
              active: role.userId == null
                  ? null
                  : usersById[role.userId]?.active,
              color: AppColors.photographerPurple,
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 14),

        // ---- stages ----
        const SumouSectionHeader(title: 'مراحل المشروع'),
        const SizedBox(height: 12),
        StageTimeline(stages: project.stages),
        const SizedBox(height: 24),

        // ---- closure request ----
        const SumouSectionHeader(title: 'طلب الإغلاق'),
        const SizedBox(height: 12),
        closureAsync.when(
          loading: () => const SumouCard(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const SumouCard(
            child: Text('تعذّر تحميل الطلب', style: AppTextStyles.bodyMuted),
          ),
          data: (request) => request == null
              ? const SumouCard(
                  child: Text(
                    'لا يوجد طلب إغلاق لهذا المشروع',
                    style: AppTextStyles.bodyMuted,
                  ),
                )
              // Read-only: no approve/reject callbacks for the admin here.
              : ClosureRequestCard(
                  request: request,
                  clientName: project.clientName,
                ),
        ),
        const SizedBox(height: 24),

        // ---- client delivery links ----
        const SumouSectionHeader(title: 'روابط التسليم للعميل'),
        const SizedBox(height: 12),
        closureAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (request) => _ClientLinks(request: request),
        ),
        const SizedBox(height: 24),

        // ---- notes ----
        const SumouSectionHeader(title: 'الملاحظات'),
        const SizedBox(height: 12),
        if (project.notes != null && project.notes!.trim().isNotEmpty)
          SumouCard(child: Text(project.notes!, style: AppTextStyles.body))
        else
          const SumouCard(
            child: Text('لا توجد ملاحظات', style: AppTextStyles.bodyMuted),
          ),
        const SizedBox(height: 24),

        // ---- admin actions (placeholders) ----
        const SumouSectionHeader(title: 'إجراءات الإدارة'),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.edit_outlined,
          label: 'تعديل بيانات المشروع',
          onTap: () =>
              context.push(AppRoutes.adminProjectEditPath(project.id)),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.swap_horiz,
          label: 'تغيير المدير',
          onTap: () =>
              context.push(AppRoutes.adminProjectTeamPath(project.id)),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.group_outlined,
          label: 'تعديل الفريق',
          onTap: () =>
              context.push(AppRoutes.adminProjectTeamPath(project.id)),
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.timeline_outlined,
          label: 'مراقبة المراحل',
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('المراحل معروضة في الأعلى')),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---- summary ----------------------------------------------------------------

class _Summary extends StatelessWidget {
  const _Summary({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final stage = p.currentStage?.title;
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.name, style: AppTextStyles.titleLarge),
              ),
              const SizedBox(width: 8),
              SumouStatusChip(sumouStatusForProject(p.status)),
            ],
          ),
          const SizedBox(height: 12),
          _Line(icon: Icons.person_outline, text: p.clientName),
          _Line(
            icon: Icons.qr_code_2,
            text: p.serial,
            valueColor: AppColors.accentGreen,
          ),
          _Line(icon: Icons.category_outlined, text: p.type.nameAr),
          _Line(
            icon: Icons.badge_outlined,
            text: 'المدير: ${p.managerName ?? '—'}',
          ),
          _Line(
            icon: Icons.camera_alt_outlined,
            text: 'المصورون: ${p.teamRoles.length}',
          ),
          _Line(
            icon: Icons.event_outlined,
            text: 'البداية: ${_fmtDate(p.startDate)}',
          ),
          _Line(
            icon: Icons.event_available_outlined,
            text: 'التسليم: ${_fmtDate(p.endDate)}',
          ),
          _Line(
            icon: Icons.timeline_outlined,
            text: stage == null ? 'لا توجد مراحل' : 'المرحلة الحالية: $stage',
          ),
          if (p.hasPendingClosure)
            _Line(
              icon: Icons.hourglass_top,
              text: 'بانتظار اعتماد الإغلاق',
              valueColor: AppColors.financeYellow,
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.stageProgressPercent / 100,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceSecondary,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.accentGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${p.stageProgressPercent}%',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.accentGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.valueColor});

  final IconData icon;
  final String text;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- team -------------------------------------------------------------------

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.name,
    required this.type,
    required this.color,
    this.active,
  });

  final String name;
  final String type;
  final Color color;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              UserModel.initialsFrom(name),
              style: AppTextStyles.label.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(type, style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
          if (active != null) _StatusPill(active: active!),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentGreen : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? 'نشط' : 'غير نشط',
        style: AppTextStyles.label.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---- client links -----------------------------------------------------------

class _ClientLinks extends StatelessWidget {
  const _ClientLinks({required this.request});

  final ClosureRequestModel? request;

  @override
  Widget build(BuildContext context) {
    final link = request?.deliveryLink;
    final approved = request?.isApproved ?? false;
    final hasApprovedLink =
        approved && link != null && link.trim().isNotEmpty;

    if (!hasApprovedLink) {
      return const SumouCard(
        child: Text(
          'لا توجد روابط معتمدة بعد — يظهر للعميل «جاري الإبداع ⏳»',
          style: AppTextStyles.bodyMuted,
        ),
      );
    }
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, size: 16, color: AppColors.accentGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  link!,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.accentGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'رابط معتمد ومرئي للعميل عبر صفحة التتبع.',
            style: AppTextStyles.label.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ---- actions ----------------------------------------------------------------

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
