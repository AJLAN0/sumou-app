import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'nav_item.dart';

/// Custom bottom navigation bar styled for Sumou.
///
/// Renders the given [items] with large tap targets; the active item uses the
/// role [accentColor], inactive items use muted text. RTL ordering is inherited
/// from the app root (first item appears on the right).
class RoleBasedBottomNav extends StatelessWidget {
  const RoleBasedBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.accentColor,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavCell(
                    item: items[i],
                    selected: i == currentIndex,
                    accentColor: accentColor,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accentColor : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: AppTextStyles.label.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
