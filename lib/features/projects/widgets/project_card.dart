import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

/// Maps a [ProjectStatus] onto the shared [SumouStatus] chip vocabulary.
SumouStatus sumouStatusForProject(ProjectStatus status) => switch (status) {
  ProjectStatus.active => SumouStatus.active,
  ProjectStatus.inProgress => SumouStatus.inProgress,
  ProjectStatus.completed => SumouStatus.ended,
  ProjectStatus.pendingClosure => SumouStatus.pendingApproval,
  ProjectStatus.rejected => SumouStatus.rejected,
  ProjectStatus.approved => SumouStatus.accepted,
  ProjectStatus.delivered => SumouStatus.delivered,
};

String _date(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// Mobile project card used in project lists (no desktop tables).
class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project, this.onTap});

  final ProjectModel project;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final percent = project.stageProgressPercent;
    final stage = project.currentStage?.title;

    return SumouCard(
      onTap: onTap,
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
                child: Text(project.clientName, style: AppTextStyles.bodyMuted),
              ),
              Text(
                project.serial,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.accentGreen,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Tag(label: project.type.nameAr),
              const SizedBox(width: 8),
              const Icon(
                Icons.calendar_today_outlined,
                size: 13,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                '${_date(project.startDate)} ← ${_date(project.endDate)}',
                style: AppTextStyles.label,
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
          if (project.teamRoles.isNotEmpty) ...[
            const SizedBox(height: 12),
            _TeamSummary(roles: project.teamRoles),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.projectTeal.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(color: AppColors.projectTeal),
      ),
    );
  }
}

class _TeamSummary extends StatelessWidget {
  const _TeamSummary({required this.roles});

  final List<ProjectTeamRole> roles;

  @override
  Widget build(BuildContext context) {
    final shown = roles.take(3).toList();
    final extra = roles.length - shown.length;

    return Row(
      children: [
        for (final role in shown) ...[
          _Avatar(initials: UserModel.initialsFrom(role.personName)),
          const SizedBox(width: 6),
        ],
        if (extra > 0)
          Text('+$extra', style: AppTextStyles.label)
        else
          Expanded(
            child: Text(
              shown.length == 1 ? shown.first.personName : 'الفريق',
              style: AppTextStyles.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.surfaceSecondary,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: AppTextStyles.label.copyWith(color: AppColors.textWhite),
      ),
    );
  }
}
