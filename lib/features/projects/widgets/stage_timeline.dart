import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

String _fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// Reusable, mobile-first vertical stage timeline.
///
/// Works for any workflow length (the 3-stage and 7-stage flows alike) since it
/// simply renders the [stages] it is given. Shows each stage's order, title,
/// status, last-updated date, and notes. RTL is inherited from the app root.
class StageTimeline extends StatelessWidget {
  const StageTimeline({
    super.key,
    required this.stages,
    this.showHeader = true,
  });

  final List<ProjectStageModel> stages;

  /// Whether to show the progress header (current stage + percentage + bar).
  final bool showHeader;

  int get _percent {
    if (stages.isEmpty) return 0;
    final done = stages.where((s) => s.isDone).length;
    return ((done / stages.length) * 100).round();
  }

  ProjectStageModel? get _current {
    for (final s in stages) {
      if (s.isCurrent) return s;
    }
    for (final s in stages) {
      if (!s.isDone) return s;
    }
    return stages.isEmpty ? null : stages.last;
  }

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) {
      return const SumouCard(
        child: Text('لا توجد مراحل', style: AppTextStyles.bodyMuted),
      );
    }

    final ordered = [...stages]..sort((a, b) => a.order.compareTo(b.order));

    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _current == null
                        ? 'لا توجد مراحل'
                        : 'المرحلة الحالية: ${_current!.title}',
                    style: AppTextStyles.body,
                  ),
                ),
                Text(
                  '$_percent%',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.accentGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _percent / 100,
                minHeight: 5,
                backgroundColor: AppColors.surfaceSecondary,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.accentGreen,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          for (var i = 0; i < ordered.length; i++)
            _TimelineRow(stage: ordered[i], isLast: i == ordered.length - 1),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.stage, required this.isLast});

  final ProjectStageModel stage;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (stage.status) {
      ProjectStageStatus.done => (AppColors.accentGreen, Icons.check_circle),
      ProjectStageStatus.current => (
        AppColors.projectTeal,
        Icons.radio_button_checked,
      ),
      ProjectStageStatus.pending => (
        AppColors.textMuted,
        Icons.radio_button_unchecked,
      ),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(icon, size: 22, color: color),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.border,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${stage.order}. ${stage.title}',
                          style: AppTextStyles.body.copyWith(
                            color: stage.isPending ? AppColors.textMuted : null,
                          ),
                        ),
                      ),
                      Text(
                        stage.status.nameAr,
                        style: AppTextStyles.label.copyWith(color: color),
                      ),
                    ],
                  ),
                  if (stage.updatedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'آخر تحديث: ${_fmtDate(stage.updatedAt!)}',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  if (stage.notes != null && stage.notes!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(stage.notes!, style: AppTextStyles.bodyMuted),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
