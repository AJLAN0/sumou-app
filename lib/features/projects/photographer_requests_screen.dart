import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/widgets.dart';
import 'providers/projects_providers.dart';
import 'widgets/closure_request_card.dart';

/// Photographer "الطلبات" screen: the closure requests the current photographer
/// submitted, with their status. Read-only — mock-backed. Empty state when the
/// photographer has no requests. No accept/decline workflow, no notifications.
class PhotographerRequestsScreen extends ConsumerWidget {
  const PhotographerRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(photographerClosureRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('تعذّر تحميل الطلبات')),
      data: (views) {
        if (views.isEmpty) {
          return const SumouEmptyState(
            title: 'لا توجد طلبات حالياً',
            message: 'ستظهر هنا طلبات الإغلاق التي ترسلها',
            icon: Icons.inbox_outlined,
          );
        }
        return ListView(
          children: [
            const SizedBox(height: 4),
            const SumouSectionHeader(title: 'طلبات الإغلاق'),
            const SizedBox(height: 12),
            for (final v in views) ...[
              ClosureRequestCard(
                request: v.request,
                clientName: v.project.clientName,
                // Read-only: the photographer cannot approve/reject.
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
