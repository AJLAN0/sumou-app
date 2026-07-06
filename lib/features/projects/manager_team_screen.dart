import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/projects_providers.dart';

/// Manager "الفريق" tab: a read-only availability view of photographers, with a
/// simple متاح/مشغول signal from their active-project load. Mock-backed.
class ManagerTeamScreen extends ConsumerWidget {
  const ManagerTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photographersAsync = ref.watch(photographerCandidatesProvider);
    final counts =
        ref.watch(photographerActiveCountsProvider).valueOrNull ??
        const <String, int>{};

    return photographersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('تعذّر تحميل الفريق')),
      data: (photographers) {
        if (photographers.isEmpty) {
          return const SumouEmptyState(
            title: 'لا يوجد فريق',
            message: 'لم تتم إضافة مصورين بعد',
            icon: Icons.group_outlined,
          );
        }
        final available = photographers
            .where((u) => (counts[u.id] ?? 0) < 2)
            .length;
        return ListView(
          children: [
            const SizedBox(height: 4),
            _AvailabilityStrip(
              available: available,
              total: photographers.length,
            ),
            const SizedBox(height: 12),
            const SumouSectionHeader(title: 'المصورون'),
            const SizedBox(height: 12),
            for (final u in photographers) ...[
              _TeamMemberCard(user: u, activeCount: counts[u.id] ?? 0),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

class _AvailabilityStrip extends StatelessWidget {
  const _AvailabilityStrip({required this.available, required this.total});

  final int available;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Row(
        children: [
          const Icon(Icons.group_outlined, color: AppColors.accentGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الفريق المتاح', style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(
                  '$available من $total متاحون حالياً',
                  style: AppTextStyles.bodyMuted,
                ),
              ],
            ),
          ),
          Text(
            '$available / $total',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.accentGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({required this.user, required this.activeCount});

  final UserModel user;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final available = activeCount < 2;
    final statusColor = available ? AppColors.accentGreen : AppColors.financeYellow;
    final statusLabel = available ? 'متاح' : 'مشغول';

    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceSecondary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  user.avatarInitials,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textWhite,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName, style: AppTextStyles.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '$activeCount مشاريع نشطة',
                      style: AppTextStyles.bodyMuted,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: AppTextStyles.label.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (user.photoTypes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in user.photoTypes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      t,
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.primaryTeal,
                      ),
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
