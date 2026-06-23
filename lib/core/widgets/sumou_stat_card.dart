import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'sumou_card.dart';

/// Compact dashboard stat card (icon + value + label).
///
/// Designed to sit in a 2-column grid or a stacked list on dashboards. The
/// [accentColor] tints the icon badge so different metrics read distinctly.
class SumouStatCard extends StatelessWidget {
  const SumouStatCard({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.accentColor = AppColors.primaryTeal,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SumouCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
          if (icon != null) const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.titleLarge.copyWith(color: accentColor),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.bodyMuted),
        ],
      ),
    );
  }
}
