import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/user_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';

/// Shows a server-generated temporary password exactly once for the current UI
/// operation. The holder is cleared whether the dialog is closed normally or
/// the route is otherwise dismissed.
Future<void> showTemporaryPasswordDialog(
  BuildContext context, {
  required OneTimePassword password,
  required String title,
}) async {
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => _TemporaryPasswordDialog(password: password, title: title),
    );
  } finally {
    password.clear();
  }
}

class _TemporaryPasswordDialog extends StatelessWidget {
  const _TemporaryPasswordDialog({required this.password, required this.title});

  final OneTimePassword password;
  final String title;

  @override
  Widget build(BuildContext context) {
    final value = password.value;
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ستظهر كلمة المرور المؤقتة هذه مرة واحدة فقط. انسخها وسلّمها للمستخدم بطريقة آمنة.',
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              value ?? '',
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium,
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed:
              value == null
                  ? null
                  : () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم نسخ كلمة المرور المؤقتة'),
                      ),
                    );
                  },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('نسخ'),
        ),
        SumouButton(
          label: 'تم',
          fullWidth: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
