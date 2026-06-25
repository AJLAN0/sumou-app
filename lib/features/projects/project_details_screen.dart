import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'closure_actions.dart';
import 'providers/projects_providers.dart';
import 'widgets/closure_request_card.dart';
import 'widgets/project_card.dart';
import 'widgets/stage_timeline.dart';

String _date(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// Full-screen project details (read-only). Loads the project by id; actions
/// are UI-only placeholders gated by the signed-in user's permissions.
class ProjectDetailsScreen extends ConsumerWidget {
  const ProjectDetailsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'تفاصيل المشروع',
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
          return _Details(project: project);
        },
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.project});

  final ProjectModel project;

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('هذه الميزة قريباً')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).currentUser;
    // Stage updates: needs the permission, and for a photographer also requires
    // being assigned to this project (a manager can update any project).
    final isManager = user?.hasRole(RoleType.manager) ?? false;
    final isAssigned = project.isAssignedTo(user?.id ?? '');
    final canUpdateStages =
        (user?.hasPermission(AppFeature.canUpdateStages) ?? false) &&
        (isManager || isAssigned);
    // Closure requests: needs the permission and being assigned to the project.
    final canRequestClosure =
        (user?.hasPermission(AppFeature.canRequestClosure) ?? false) &&
        isAssigned;
    final canAssign =
        user?.hasPermission(AppFeature.canAssignPhotographers) ?? false;
    // Closure review (approve/reject) for managers with the permission.
    final canApproveClosure =
        user?.hasPermission(AppFeature.canApproveClosure) ?? false;
    final pendingClosureAsync = ref.watch(
      pendingClosureForProjectProvider(project.id),
    );

    return ListView(
      children: [
        const SizedBox(height: 8),
        _Summary(project: project),
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'مراحل المشروع'),
        const SizedBox(height: 12),
        StageTimeline(stages: project.stages),
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'الفريق'),
        const SizedBox(height: 12),
        if (project.teamRoles.isEmpty)
          const SumouEmptyState(
            title: 'لا يوجد فريق',
            message: 'لم يتم إسناد أعضاء بعد',
            icon: Icons.group_outlined,
          )
        else
          for (final role in project.teamRoles) ...[
            _TeamMemberCard(role: role),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 14),
        const SumouSectionHeader(title: 'الملاحظات'),
        const SizedBox(height: 12),
        if (project.notes != null && project.notes!.trim().isNotEmpty)
          SumouCard(child: Text(project.notes!, style: AppTextStyles.body))
        else
          const SumouCard(
            child: Text('لا توجد ملاحظات', style: AppTextStyles.bodyMuted),
          ),
        if (canApproveClosure && project.hasPendingClosure) ...[
          const SizedBox(height: 24),
          const SumouSectionHeader(title: 'طلب الإغلاق'),
          const SizedBox(height: 12),
          pendingClosureAsync.when(
            loading:
                () => const SumouCard(
                  child: Center(child: CircularProgressIndicator()),
                ),
            error:
                (_, __) => const SumouCard(
                  child: Text(
                    'تعذّر تحميل الطلب',
                    style: AppTextStyles.bodyMuted,
                  ),
                ),
            data:
                (request) =>
                    request == null
                        ? const SumouCard(
                          child: Text(
                            'لا يوجد طلب إغلاق',
                            style: AppTextStyles.bodyMuted,
                          ),
                        )
                        : ClosureRequestCard(
                          request: request,
                          clientName: project.clientName,
                          onApprove:
                              () => approveClosureFlow(context, ref, request),
                          onReject:
                              () => rejectClosureFlow(context, ref, request),
                        ),
          ),
        ],
        const SizedBox(height: 24),
        const SumouSectionHeader(title: 'الإجراءات'),
        const SizedBox(height: 12),
        if (canUpdateStages) ...[
          SumouButton(
            label: 'تحديث المرحلة',
            icon: Icons.update,
            onPressed:
                () => context.push(AppRoutes.projectStagePath(project.id)),
          ),
          const SizedBox(height: 10),
        ],
        if (canRequestClosure) ...[
          SumouButton(
            label: 'طلب إغلاق',
            variant: SumouButtonVariant.secondary,
            icon: Icons.check_circle_outline,
            onPressed:
                () => context.push(AppRoutes.projectClosurePath(project.id)),
          ),
          const SizedBox(height: 10),
        ],
        if (canAssign) ...[
          SumouButton(
            label: 'إسناد مصور',
            variant: SumouButtonVariant.secondary,
            icon: Icons.person_add_alt,
            onPressed:
                () => context.push(AppRoutes.projectAssignPath(project.id)),
          ),
          const SizedBox(height: 10),
        ],
        if (project.isCompleted)
          SumouButton(
            label: 'رابط التسليم',
            variant: SumouButtonVariant.secondary,
            icon: Icons.link,
            onPressed: () => _comingSoon(context),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(project.name, style: AppTextStyles.titleLarge),
              ),
              const SizedBox(width: 8),
              SumouStatusChip(sumouStatusForProject(project.status)),
            ],
          ),
          const SizedBox(height: 12),
          _Line(icon: Icons.person_outline, text: project.clientName),
          _Line(
            icon: Icons.qr_code_2,
            text: project.serial,
            valueColor: AppColors.accentGreen,
          ),
          _Line(icon: Icons.category_outlined, text: project.type.nameAr),
          _Line(
            icon: Icons.calendar_today_outlined,
            text: '${_date(project.startDate)} ← ${_date(project.endDate)}',
          ),
          if (project.managerName != null)
            _Line(
              icon: Icons.badge_outlined,
              text: 'المدير: ${project.managerName}',
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

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({required this.role});

  final ProjectTeamRole role;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.surfaceSecondary,
              shape: BoxShape.circle,
            ),
            child: Text(
              UserModel.initialsFrom(role.personName),
              style: AppTextStyles.label.copyWith(color: AppColors.textWhite),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.personName, style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(role.type, style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
          if (role.value > 0)
            Text(
              '${role.value} ر.س',
              style: AppTextStyles.label.copyWith(
                color: AppColors.financeYellow,
              ),
            ),
        ],
      ),
    );
  }
}
