import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';

/// Reusable app bar that follows the Sumou theme.
///
/// Thin wrapper over [AppBar] so screens get a consistent title style and
/// optional actions/leading without re-specifying theme details. Implements
/// [PreferredSizeWidget] so it can be passed to `Scaffold.appBar`.
class SumouAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SumouAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, style: AppTextStyles.titleMedium),
      centerTitle: centerTitle,
      actions: actions,
      leading: leading,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
