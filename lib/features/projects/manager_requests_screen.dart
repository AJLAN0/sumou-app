import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/projects_providers.dart';

/// Manager "الطلبات" hub: request categories as cards. Closure requests use the
/// existing Sprint 2 logic (links to the closure inbox). Mock-backed only — no
/// finance/notification/Rekaz requests are created here.
class ManagerRequestsScreen extends ConsumerWidget {
  const ManagerRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(managerAllClosureRequestsProvider);

    return ListView(
      children: [
        const SizedBox(height: 4),
        const SumouSectionHeader(title: 'فئات الطلبات'),
        const SizedBox(height: 12),
        requestsAsync.when(
          loading:
              () => const SumouCard(
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (_, __) => const SumouCard(
                child: Text(
                  'تعذّر تحميل الطلبات',
                  style: AppTextStyles.bodyMuted,
                ),
              ),
          data: (views) {
            final pending =
                views
                    .where(
                      (v) => v.request.status == ClosureRequestStatus.pending,
                    )
                    .length;
            final approved =
                views
                    .where(
                      (v) => v.request.status == ClosureRequestStatus.approved,
                    )
                    .length;
            final rejected =
                views
                    .where(
                      (v) => v.request.status == ClosureRequestStatus.rejected,
                    )
                    .length;
            return _CategoryCard(
              icon: Icons.check_circle_outline,
              title: 'طلبات الإغلاق',
              subtitle:
                  'بانتظار: $pending · مقبول: $approved · مرفوض: $rejected',
              badge: pending,
              onTap: () => context.push(AppRoutes.managerClosures),
            );
          },
        ),
        const SizedBox(height: 12),
        // Photographer/assignment broadcast requests have no mock data yet, so
        // this category is an inert placeholder (its flow is a later sprint).
        const _CategoryCard(
          icon: Icons.camera_alt_outlined,
          title: 'طلبات التصوير',
          subtitle: 'قريباً',
          enabled: false,
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge = 0,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int badge;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tint = enabled ? AppColors.accentGreen : AppColors.textMuted;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: SumouCard(
        onTap: enabled ? onTap : null,
        child: Row(
          children: [
            Icon(icon, color: tint, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.bodyMuted),
                ],
              ),
            ),
            if (badge > 0) ...[
              _CountBadge(count: badge),
              const SizedBox(width: 8),
            ],
            if (enabled)
              const Icon(Icons.chevron_left, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.financeYellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: AppTextStyles.label.copyWith(
          color: AppColors.financeYellow,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
