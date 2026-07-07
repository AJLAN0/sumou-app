import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/projects_providers.dart';
import 'widgets/project_card.dart';

/// Manager "تعديل المشروع" hub.
///
/// One place to manage a project instead of scattered bottom actions: edit the
/// basics, update the stage, and manage the team — each opening its existing
/// focused flow.
class ManageProjectScreen extends ConsumerWidget {
  const ManageProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'تعديل المشروع',
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
          return ListView(
            children: [
              const SizedBox(height: 8),
              _Header(project: project),
              const SizedBox(height: 20),
              const SumouSectionHeader(title: 'ماذا تريد أن تعدّل؟'),
              const SizedBox(height: 12),
              // pushReplacement so finishing a sub-flow returns to the project
              // details (not back to this hub).
              _HubCard(
                icon: Icons.edit_outlined,
                title: 'تعديل بيانات المشروع',
                subtitle: 'الاسم، العميل، النوع، الحالة، والتواريخ',
                onTap:
                    () => context.pushReplacement(
                      AppRoutes.projectEditPath(project.id),
                    ),
              ),
              const SizedBox(height: 12),
              _HubCard(
                icon: Icons.update,
                title: 'تحديث المرحلة',
                subtitle: 'نقل المشروع إلى مرحلته الحالية',
                onTap:
                    () => context.pushReplacement(
                      AppRoutes.projectStagePath(project.id),
                    ),
              ),
              const SizedBox(height: 12),
              _HubCard(
                icon: Icons.group_outlined,
                title: 'إدارة الفريق',
                subtitle: 'إسناد المصورين وتعديل الفريق',
                onTap:
                    () => context.pushReplacement(
                      AppRoutes.projectAssignPath(project.id),
                    ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(project.name, style: AppTextStyles.titleMedium),
              ),
              const SizedBox(width: 8),
              SumouStatusChip(sumouStatusForProject(project.status)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.qr_code_2, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(
                project.serial,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.accentGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.accentGreen, size: 22),
          ),
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
          const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
