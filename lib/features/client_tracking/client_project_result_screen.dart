import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/client_tracking_model.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/tracking_providers.dart';

/// Public result screen for client tracking. Shows only client-safe data:
/// project/client name, status, progress, and approved delivery links. When no
/// links are approved it shows «جاري الإبداع ⏳». No staff-only data, no rating.
class ClientProjectResultScreen extends ConsumerWidget {
  const ClientProjectResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(trackingResultProvider);

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'حالة المشروع',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body:
          result == null
              ? SumouEmptyState(
                title: 'لا توجد نتيجة',
                message: 'أدخل الرمز السري لمتابعة مشروعك',
                icon: Icons.search_off,
                actionLabel: 'العودة للتتبع',
                onAction: () => context.go(AppRoutes.track),
              )
              : _Result(result: result),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.result});

  final ClientTrackingModel result;

  SumouStatus _statusFor(String status) => switch (status) {
    'active' => SumouStatus.active,
    'done' => SumouStatus.delivered,
    _ => SumouStatus.inProgress,
  };

  double _progressFor(String status) => switch (status) {
    'done' => 1.0,
    'active' => 0.5,
    _ => 0.25,
  };

  @override
  Widget build(BuildContext context) {
    final progress = _progressFor(result.status);

    return ListView(
      children: [
        const SizedBox(height: 8),
        // Header
        Center(
          child: Column(
            children: [
              Text(
                result.projectName,
                style: AppTextStyles.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(result.clientName, style: AppTextStyles.bodyMuted),
              const SizedBox(height: 8),
              Text(
                result.serial,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.accentGreen,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              SumouStatusChip(_statusFor(result.status)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Progress
        SumouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('مرحلة التنفيذ', style: AppTextStyles.body),
                  Text(
                    '${(progress * 100).round()}%',
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
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceSecondary,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.accentGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Delivery
        const SumouSectionHeader(title: 'التسليم'),
        const SizedBox(height: 12),
        if (!result.hasApprovedLinks) const _CreatingCard(),
        if (result.hasApprovedLinks)
          for (final link in result.approvedLinks) ...[
            _LinkCard(link: link),
            const SizedBox(height: 12),
          ],
        if (result.message != null) ...[
          const SizedBox(height: 12),
          const SumouSectionHeader(title: 'رسالة'),
          const SizedBox(height: 12),
          SumouCard(child: Text(result.message!, style: AppTextStyles.body)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link});

  final DeliveryLink link;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check,
              color: AppColors.accentGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(link.label, style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(
                  link.url,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.projectTeal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatingCard extends StatelessWidget {
  const _CreatingCard();

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.projectTeal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.brush_outlined,
              color: AppColors.projectTeal,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ClientTrackingModel.creatingLabel,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.projectTeal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'سيتوفر رابط التسليم عند اكتمال العمل',
                  style: AppTextStyles.bodyMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
