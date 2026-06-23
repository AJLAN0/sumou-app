import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Visual variants for [SumouButton].
enum SumouButtonVariant { primary, secondary, danger }

/// Primary action button for the app.
///
/// One main CTA per screen should use [SumouButtonVariant.primary] (green).
/// [secondary] is an outlined neutral button; [danger] is used for
/// destructive/reject actions. Supports an optional leading [icon], a
/// [loading] spinner, and full-width layout.
class SumouButton extends StatelessWidget {
  const SumouButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SumouButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final SumouButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || loading;

    late final Color background;
    late final Color foreground;
    BorderSide side = BorderSide.none;

    switch (variant) {
      case SumouButtonVariant.primary:
        background = AppColors.accentGreen;
        foreground = AppColors.background;
      case SumouButtonVariant.secondary:
        background = AppColors.surfaceSecondary;
        foreground = AppColors.textWhite;
        side = const BorderSide(color: AppColors.border);
      case SumouButtonVariant.danger:
        background = AppColors.error;
        foreground = AppColors.textWhite;
    }

    final Widget child =
        loading
            ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            )
            : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppTextStyles.button.copyWith(color: foreground),
                ),
              ],
            );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled ? null : onPressed,
          child: Container(
            height: 50,
            width: fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.fromBorderSide(side),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
