import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';

/// Branded placeholder for the admin التقارير tab. Advanced reports come later.
class ReportsPlaceholderScreen extends StatelessWidget {
  const ReportsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SumouEmptyState(
      title: 'التقارير',
      message: 'التقارير المتقدمة ستتوفر في تحديث قادم',
      icon: Icons.bar_chart,
    );
  }
}
