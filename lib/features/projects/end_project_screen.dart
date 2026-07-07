import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'closure_actions.dart';
import 'providers/projects_providers.dart';
import 'widgets/closure_request_card.dart';

/// Manager "إنهاء المشروع" screen.
///
/// The manager doesn't submit a closure — the photographer does. Here the
/// manager reviews the photographer's pending closure request and accepts it to
/// finish the project (or rejects it). If no request exists yet, an empty state
/// explains that the photographer must request closure first.
class EndProjectScreen extends ConsumerWidget {
  const EndProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'إنهاء المشروع',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: projectAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('تعذّر تحميل المشروع')),
        data: (project) {
          if (project == null) {
            return const SumouEmptyState(
              title: 'المشروع غير موجود',
              icon: Icons.search_off,
            );
          }
          if (project.isCompleted) {
            return const SumouEmptyState(
              title: 'تم إنهاء المشروع',
              message: 'تم اعتماد التسليم وإغلاق المشروع.',
              icon: Icons.check_circle_outline,
            );
          }
          final pendingAsync = ref.watch(
            pendingClosureForProjectProvider(projectId),
          );
          return pendingAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('تعذّر تحميل الطلب')),
            data: (request) {
              if (request == null) {
                return const SumouEmptyState(
                  title: 'لا يوجد طلب إنهاء',
                  message:
                      'سيصبح بإمكانك إنهاء المشروع بعد أن يرسل المصور طلب الإغلاق.',
                  icon: Icons.hourglass_empty,
                );
              }
              return ListView(
                children: [
                  const SizedBox(height: 8),
                  SumouCard(
                    color: AppColors.surfaceSecondary,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.projectTeal,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'راجع طلب الإنهاء المقدّم من المصور ثم اقبله لإنهاء المشروع.',
                            style: AppTextStyles.bodyMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClosureRequestCard(
                    request: request,
                    clientName: project.clientName,
                    onApprove: () => approveClosureFlow(context, ref, request),
                    onReject: () => rejectClosureFlow(context, ref, request),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
