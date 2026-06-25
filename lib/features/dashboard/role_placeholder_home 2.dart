import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_text_styles.dart';

/// Coming-soon home for roles whose modules aren't built yet
/// (designer, finance, wedding admin/finance, attendance, personal photo).
///
/// Uses the role's accent color and Arabic name for consistency.
class RolePlaceholderHome extends StatelessWidget {
  const RolePlaceholderHome({super.key, required this.role});

  final RoleType role;

  @override
  Widget build(BuildContext context) {
    final model = RoleModel.of(role);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: model.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(model.icon, color: model.color, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              model.nameAr,
              style: AppTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'وحدة "${model.nameAr}" قيد الإنشاء وستتوفر في تحديث قادم',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SumouStatusChip(SumouStatus.creating),
          ],
        ),
      ),
    );
  }
}
