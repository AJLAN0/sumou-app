import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Temporary landing screen for Step 1.
///
/// Exists only to verify the theme, colors, and RTL setup render correctly.
/// It will be replaced by the Splash/Entry flow in a later Sprint 1 step.
class AppPlaceholderHome extends StatelessWidget {
  const AppPlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سمو')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.accentGreen,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                Text('سمو الإبداع', style: AppTextStyles.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'تهيئة المظهر والاتجاه (RTL) مكتملة',
                  style: AppTextStyles.bodyMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
