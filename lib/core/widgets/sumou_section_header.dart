import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Section title with an optional trailing action (e.g. «عرض الكل»).
///
/// Gives list/dashboard sections a consistent header and a single, clear
/// secondary action when needed.
class SumouSectionHeader extends StatelessWidget {
  const SumouSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(title, style: AppTextStyles.titleMedium)),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel!,
              style: AppTextStyles.label.copyWith(color: AppColors.accentGreen),
            ),
          ),
      ],
    );
  }
}
