import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

String _fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// Maps a [ClosureRequestStatus] onto the shared [SumouStatus] chip vocabulary.
SumouStatus _statusFor(ClosureRequestStatus status) => switch (status) {
  ClosureRequestStatus.pending => SumouStatus.pendingApproval,
  ClosureRequestStatus.approved => SumouStatus.accepted,
  ClosureRequestStatus.rejected => SumouStatus.rejected,
};

/// Mobile card for a closure request (no tables). Shows the request details and,
/// when [onApprove]/[onReject] are provided, the manager's review actions.
class ClosureRequestCard extends StatelessWidget {
  const ClosureRequestCard({
    super.key,
    required this.request,
    this.clientName,
    this.onApprove,
    this.onReject,
    this.busy = false,
  });

  final ClosureRequestModel request;
  final String? clientName;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final showActions = onApprove != null || onReject != null;
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.projectName,
                  style: AppTextStyles.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              SumouStatusChip(_statusFor(request.status)),
            ],
          ),
          const SizedBox(height: 10),
          if (clientName != null)
            _Line(icon: Icons.business_outlined, text: clientName!),
          _Line(
            icon: Icons.person_outline,
            text: 'مقدّم الطلب: ${request.submittedByName}',
          ),
          _Line(
            icon: Icons.calendar_today_outlined,
            text: 'بتاريخ: ${_fmtDate(request.createdAt)}',
          ),
          if (request.deliveryLink != null &&
              request.deliveryLink!.trim().isNotEmpty)
            _Line(
              icon: Icons.link,
              text: request.deliveryLink!,
              valueColor: AppColors.accentGreen,
            ),
          if (request.reportFileUrl != null &&
              request.reportFileUrl!.trim().isNotEmpty)
            _Line(
              icon: Icons.description_outlined,
              text: request.reportFileUrl!,
            ),
          if (request.notes != null && request.notes!.trim().isNotEmpty)
            _Line(icon: Icons.sticky_note_2_outlined, text: request.notes!),
          if (request.isRejected &&
              request.rejectReason != null &&
              request.rejectReason!.trim().isNotEmpty)
            _Line(
              icon: Icons.cancel_outlined,
              text: 'سبب الرفض: ${request.rejectReason}',
              valueColor: AppColors.error,
            ),
          if (showActions) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (onReject != null)
                  Expanded(
                    child: SumouButton(
                      label: 'رفض',
                      variant: SumouButtonVariant.danger,
                      onPressed: busy ? null : onReject,
                    ),
                  ),
                if (onReject != null && onApprove != null)
                  const SizedBox(width: 12),
                if (onApprove != null)
                  Expanded(
                    child: SumouButton(
                      label: 'قبول',
                      loading: busy,
                      onPressed: busy ? null : onApprove,
                    ),
                  ),
              ],
            ),
          ],
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
