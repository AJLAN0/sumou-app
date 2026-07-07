import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';
import 'sumou_logo.dart';

/// Reusable app bar that follows the Sumou theme.
///
/// Thin wrapper over [AppBar] so screens get a consistent title style and
/// optional actions/leading without re-specifying theme details. Implements
/// [PreferredSizeWidget] so it can be passed to `Scaffold.appBar`.
///
/// When [showBrand] is enabled and a screen doesn't provide its own [leading]
/// (i.e. the main app pages, which have no back button), the icon-only Sumou
/// logo is shown as a small brand mark. It is off by default.
class SumouAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SumouAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
    this.showBrand = false,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final bool brandLeading = leading == null && showBrand;
    final Widget? resolvedLeading =
        leading ??
        (showBrand
            ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Center(child: SumouLogo.icon(height: 40)),
            )
            : null);
    return AppBar(
      title: Text(title, style: AppTextStyles.titleMedium),
      centerTitle: centerTitle,
      actions: actions,
      leading: resolvedLeading,
      // The brand mark is wider than a default icon, so widen the leading slot
      // to prevent clipping.
      leadingWidth: brandLeading ? 96 : null,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
