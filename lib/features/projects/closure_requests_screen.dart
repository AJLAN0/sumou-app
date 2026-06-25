import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../auth/providers/auth_controller.dart';
import 'closure_actions.dart';
import 'providers/projects_providers.dart';
import 'widgets/closure_request_card.dart';

/// Manager "الطلبات" tab: pending closure requests to review (approve/reject).
/// Cards, not tables. Mock-backed; actions gated by canApproveClosure.
class ClosureRequestsScreen extends ConsumerWidget {
  const ClosureRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canApprove =
        ref.watch(authControllerProvider).currentUser?.hasPermission(
              AppFeature.canApproveClosure,
            ) ??
        false;
    final requestsAsync = ref.watch(managerClosureRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('تعذّر تحميل الطلبات')),
      data: (views) {
        if (views.isEmpty) {
          return const SumouEmptyState(
            title: 'لا توجد طلبات إغلاق',
            message: 'ستظهر هنا طلبات إغلاق المشاريع بانتظار مراجعتك',
            icon: Icons.inbox_outlined,
          );
        }
        return ListView.separated(
          itemCount: views.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final view = views[i];
            return ClosureRequestCard(
              request: view.request,
              clientName: view.project.clientName,
              onApprove: canApprove
                  ? () => approveClosureFlow(context, ref, view.request)
                  : null,
              onReject: canApprove
                  ? () => rejectClosureFlow(context, ref, view.request)
                  : null,
            );
          },
        );
      },
    );
  }
}
