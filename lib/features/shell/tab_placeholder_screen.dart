import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';

/// Lightweight placeholder body for a navigation tab.
///
/// Real dashboards / project / admin screens replace these in later steps.
class TabPlaceholderScreen extends StatelessWidget {
  const TabPlaceholderScreen({super.key, required this.title, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SumouEmptyState(
      title: title,
      message: 'هذه الشاشة قيد الإنشاء',
      icon: icon ?? Icons.widgets_outlined,
    );
  }
}
