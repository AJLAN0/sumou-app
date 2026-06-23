import 'package:flutter/material.dart';

import '../core/widgets/widgets.dart';
import '../theme/app_text_styles.dart';

/// Temporary stand-in for routes whose real screens land in Step 7+.
///
/// Dev-only: shows the route title and path so the routing/redirect wiring can
/// be exercised before the real Entry/Login/Role-Select/dashboard/tracking
/// screens exist. Built on the design-system components to keep theme + RTL.
class RoutePlaceholder extends StatelessWidget {
  const RoutePlaceholder({super.key, required this.title, this.path});

  final String title;
  final String? path;

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      appBar: SumouAppBar(title: title),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTextStyles.titleLarge),
            if (path != null) ...[
              const SizedBox(height: 8),
              Text(path!, style: AppTextStyles.bodyMuted),
            ],
            const SizedBox(height: 12),
            Text('شاشة مؤقتة — قيد الإنشاء', style: AppTextStyles.bodyMuted),
          ],
        ),
      ),
    );
  }
}
