import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/project_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'providers/projects_providers.dart';
import 'widgets/closure_request_card.dart';

/// Refresh everything that reflects a closure decision.
void _invalidateClosure(WidgetRef ref, String projectId) {
  ref.invalidate(managerClosureRequestsProvider);
  ref.invalidate(managerAllClosureRequestsProvider);
  ref.invalidate(photographerClosureRequestsProvider);
  ref.invalidate(pendingClosureForProjectProvider(projectId));
  ref.invalidate(closureRequestsForProjectProvider(projectId));
  ref.invalidate(managerProjectsProvider);
  ref.invalidate(photographerProjectsProvider);
  ref.invalidate(projectByIdProvider(projectId));
}

String _safeFailureMessage(Object error) =>
    error is ProjectRepositoryException
        ? error.messageAr
        : 'تعذّر تنفيذ العملية بأمان، حاول مرة أخرى';

/// Confirm + approve a closure request. The repository and backend remain
/// authoritative; failures are reduced to safe Arabic messages.
Future<void> approveClosureFlow(
  BuildContext context,
  WidgetRef ref,
  ClosureRequestModel request, {
  ValueChanged<bool>? onSaving,
}) async {
  final ok = await showSumouConfirmSheet(
    context,
    title: 'قبول طلب الإغلاق',
    message: 'سيتم إنهاء المشروع «${request.projectName}» واعتماد التسليم.',
    confirmLabel: 'قبول وإنهاء',
  );
  if (!ok) return;
  onSaving?.call(true);
  final repo = ref.read(projectRepositoryProvider);
  String message;
  try {
    final updated = await repo.approveClosureRequest(request.id);
    if (updated == null) {
      message = 'تعذّر تنفيذ العملية';
    } else {
      _invalidateClosure(ref, request.projectId);
      message = 'تم قبول الطلب وإنهاء المشروع';
    }
  } catch (error) {
    message = _safeFailureMessage(error);
  } finally {
    onSaving?.call(false);
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Capture a reason + reject a closure request with safe failure handling.
Future<void> rejectClosureFlow(
  BuildContext context,
  WidgetRef ref,
  ClosureRequestModel request, {
  ValueChanged<bool>? onSaving,
}) async {
  final reason = await _showRejectReasonSheet(context);
  if (reason == null) return; // cancelled
  onSaving?.call(true);
  final repo = ref.read(projectRepositoryProvider);
  String message;
  try {
    final updated = await repo.rejectClosureRequest(request.id, reason);
    if (updated == null) {
      message = 'تعذّر تنفيذ العملية';
    } else {
      _invalidateClosure(ref, request.projectId);
      message = 'تم رفض الطلب';
    }
  } catch (error) {
    message = _safeFailureMessage(error);
  } finally {
    onSaving?.call(false);
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Closure card that exposes review actions only for the exact local
/// authorization/state preconditions and blocks concurrent submissions.
class ClosureRequestReviewCard extends ConsumerStatefulWidget {
  const ClosureRequestReviewCard({
    super.key,
    required this.request,
    required this.project,
    this.clientName,
  });

  final ClosureRequestModel request;
  final ProjectModel project;
  final String? clientName;

  @override
  ConsumerState<ClosureRequestReviewCard> createState() =>
      _ClosureRequestReviewCardState();
}

class _ClosureRequestReviewCardState
    extends ConsumerState<ClosureRequestReviewCard> {
  var _busy = false;
  var _flowOpen = false;

  bool get _canReview {
    final user = ref.watch(authControllerProvider).currentUser;
    if (user == null ||
        !widget.request.isPending ||
        widget.project.status != ProjectStatus.pendingClosure) {
      return false;
    }
    if (user.hasRole(RoleType.admin)) return true;
    return widget.project.managerId == user.id &&
        user.hasPermission(AppFeature.canApproveClosure);
  }

  Future<void> _approve() async {
    if (_flowOpen) return;
    _flowOpen = true;
    try {
      await approveClosureFlow(
        context,
        ref,
        widget.request,
        onSaving: _setBusy,
      );
    } finally {
      _flowOpen = false;
      _setBusy(false);
    }
  }

  Future<void> _reject() async {
    if (_flowOpen) return;
    _flowOpen = true;
    try {
      await rejectClosureFlow(context, ref, widget.request, onSaving: _setBusy);
    } finally {
      _flowOpen = false;
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    if (mounted && _busy != value) setState(() => _busy = value);
  }

  @override
  Widget build(BuildContext context) {
    final canReview = _canReview;
    return ClosureRequestCard(
      request: widget.request,
      clientName: widget.clientName,
      busy: _busy,
      onApprove: canReview ? _approve : null,
      onReject: canReview ? _reject : null,
    );
  }
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
