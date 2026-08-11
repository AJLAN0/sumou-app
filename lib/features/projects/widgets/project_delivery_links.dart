import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/project_delivery_link.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../providers/projects_providers.dart';

/// Read-only management view of every project-link state returned by RLS.
class ProjectDeliveryLinksPanel extends ConsumerWidget {
  const ProjectDeliveryLinksPanel({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(projectLinksProvider(projectId));
    return links.when(
      loading:
          () => const SumouCard(
            child: Center(child: CircularProgressIndicator()),
          ),
      error:
          (_, __) => SumouCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'تعذّر تحميل روابط التسليم',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 10),
                SumouButton(
                  label: 'إعادة المحاولة',
                  variant: SumouButtonVariant.secondary,
                  onPressed:
                      () => ref.invalidate(projectLinksProvider(projectId)),
                ),
              ],
            ),
          ),
      data: (items) {
        if (items.isEmpty) {
          return const SumouCard(
            child: Text(
              'لا توجد روابط تسليم محفوظة',
              style: AppTextStyles.bodyMuted,
            ),
          );
        }
        return Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              _DeliveryLinkCard(link: items[index]),
              if (index != items.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _DeliveryLinkCard extends StatelessWidget {
  const _DeliveryLinkCard({required this.link});

  final ProjectDeliveryLink link;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(link.label, style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.link, size: 16, color: AppColors.accentGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  link.url,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.accentGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StateLabel(
                text: link.isApproved ? 'معتمد' : 'غير معتمد',
                color:
                    link.isApproved
                        ? AppColors.accentGreen
                        : AppColors.textMuted,
              ),
              _StateLabel(
                text: link.isClientVisible ? 'مرئي للعميل' : 'داخلي',
                color:
                    link.isClientVisible
                        ? AppColors.projectTeal
                        : AppColors.textMuted,
              ),
              _StateLabel(
                text: link.isRemoved ? 'غير نشط / محذوف' : 'نشط',
                color: link.isRemoved ? AppColors.error : AppColors.accentGreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppTextStyles.label.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
