import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../projects/widgets/project_card.dart' show sumouStatusForProject;

String _fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// Admin project card (read-only): title, status, client, serial, type, dates,
/// manager, photographer count, current stage, and progress. Shared by the
/// admin all-projects and stage-oversight lists.
class AdminProjectCard extends StatelessWidget {
  const AdminProjectCard({
    super.key,
    required this.project,
    required this.onTap,
  });

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
