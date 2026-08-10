import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/widgets.dart';
import 'closure_actions.dart';
import 'providers/projects_providers.dart';

/// Full-page wrapper (own scaffold) so the closure inbox can be pushed as a
/// route from the manager requests hub. The manager shell tab embeds the
/// requests hub instead.
class ClosureRequestsPage extends StatelessWidget {
  const ClosureRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'طلبات الإغلاق',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const ClosureRequestsScreen(),
    );
  }
}

/// Manager closure history. Pending requests expose guarded review actions;
/// processed requests remain visible without mutation controls.
class ClosureRequestsScreen extends ConsumerWidget {
  const ClosureRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(managerAllClosureRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('تعذّر تحميل الطلبات')),
      data: (views) {
        if (views.isEmpty) {
          return const SumouEmptyState(
            title: 'لا توجد طلبات إغلاق',
            message: 'ستظهر هنا طلبات إغلاق المشاريع وسجل قراراتها',
            icon: Icons.inbox_outlined,
          );
        }
        return ListView.separated(
          itemCount: views.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final view = views[i];
            return ClosureRequestReviewCard(
              request: view.request,
              project: view.project,
              clientName: view.project.clientName,
            );
          },
        );
      },
    );
  }
}
