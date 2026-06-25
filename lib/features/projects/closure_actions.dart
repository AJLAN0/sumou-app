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
        updated == null ? 'تعذّر تنفيذ العملية' : 'تم قبول الطلب وإنهاء المشروع',
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
Future<String?> _showRejectReasonSheet(BuildContext context) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      var showError = false;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
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
                  controller: controller,
                  hint: 'اذكر سبب رفض طلب الإغلاق',
                  maxLines: 3,
                ),
                if (showError) ...[
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
                    final reason = controller.text.trim();
                    if (reason.isEmpty) {
                      setSheetState(() => showError = true);
                      return;
                    }
                    Navigator.of(sheetContext).pop(reason);
                  },
                ),
                const SizedBox(height: 10),
                SumouButton(
                  label: 'إلغاء',
                  variant: SumouButtonVariant.secondary,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
