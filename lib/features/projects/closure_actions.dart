import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/projects_providers.dart';

/// Refresh everything that reflects a closure decision.
void _invalidateClosure(WidgetRef ref, String projectId) {
  ref.invalidate(managerClosureRequestsProvider);
  ref.invalidate(managerAllClosureRequestsProvider);
  ref.invalidate(photographerClosureRequestsProvider);
  ref.invalidate(pendingClosureForProjectProvider(projectId));
  ref.invalidate(managerProjectsProvider);
  ref.invalidate(photographerProjectsProvider);
  ref.invalidate(projectByIdProvider(projectId));
}

/// Confirm + approve a closure request (manager). Shows a success/error
/// snackbar. Mock-only.
Future<void> approveClosureFlow(
  BuildContext context,
  WidgetRef ref,
  ClosureRequestModel request,
) async {
  final ok = await showSumouConfirmSheet(
    context,
    title: 'قبول طلب الإغلاق',
    message: 'سيتم إنهاء المشروع «${request.projectName}» واعتماد التسليم.',
    confirmLabel: 'قبول وإنهاء',
  );
  if (!ok) return;
  final repo = ref.read(projectRepositoryProvider);
  final updated = await repo.approveClosureRequest(request.id);
  _invalidateClosure(ref, request.projectId);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        updated == null
            ? 'تعذّر تنفيذ العملية'
            : 'تم قبول الطلب وإنهاء المشروع',
      ),
    ),
  );
}

/// Capture a reason + reject a closure request (manager). Shows a success/error
/// snackbar. Mock-only.
Future<void> rejectClosureFlow(
  BuildContext context,
  WidgetRef ref,
  ClosureRequestModel request,
) async {
  final reason = await _showRejectReasonSheet(context);
  if (reason == null) return; // cancelled
  final repo = ref.read(projectRepositoryProvider);
  final updated = await repo.rejectClosureRequest(request.id, reason);
  _invalidateClosure(ref, request.projectId);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(updated == null ? 'تعذّر تنفيذ العملية' : 'تم رفض الطلب'),
    ),
  );
}

/// Bottom sheet collecting a required rejection reason. Returns the reason, or
/// null when cancelled/dismissed.
Future<String?> _showRejectReasonSheet(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: _RejectReasonSheet(
            onConfirm: (reason) => Navigator.of(sheetContext).pop(reason),
            onCancel: () => Navigator.of(sheetContext).pop(),
          ),
        ),
  );
}

class _RejectReasonSheet extends StatefulWidget {
  const _RejectReasonSheet({required this.onConfirm, required this.onCancel});

  final ValueChanged<String> onConfirm;
  final VoidCallback onCancel;

  @override
  State<_RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<_RejectReasonSheet> {
  final _controller = TextEditingController();
  var _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'سبب الرفض',
            style: AppTextStyles.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SumouTextField(
            controller: _controller,
            hint: 'اذكر سبب رفض طلب الإغلاق',
            maxLines: 3,
          ),
          if (_showError) ...[
            const SizedBox(height: 6),
            Text(
              'الرجاء إدخال سبب الرفض',
              style: AppTextStyles.label.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 16),
          SumouButton(
            label: 'تأكيد الرفض',
            variant: SumouButtonVariant.danger,
            onPressed: () {
              final reason = _controller.text.trim();
              if (reason.isEmpty) {
                setState(() => _showError = true);
                return;
              }
              widget.onConfirm(reason);
            },
          ),
          const SizedBox(height: 10),
          SumouButton(
            label: 'إلغاء',
            variant: SumouButtonVariant.secondary,
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }
}
