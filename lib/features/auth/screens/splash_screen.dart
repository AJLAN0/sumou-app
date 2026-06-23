import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../providers/auth_controller.dart';

/// Opening screen. Shows branding briefly, then routes based on auth state:
/// unauthenticated → entry, multi-role w/o selection → role select, otherwise
/// the active role's home.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const Duration _delay = Duration(milliseconds: 1400);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_delay, _route);
  }

  void _route() {
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    final String target;
    if (!auth.isAuthenticated) {
      target = AppRoutes.entry;
    } else if (auth.needsRoleSelection) {
      target = AppRoutes.roleSelect;
    } else {
      target = homePathFor(auth.activeRole);
    }
    context.go(target);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryTeal,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.accentGreen,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text('سمو الإبداع', style: AppTextStyles.titleLarge),
            const SizedBox(height: 6),
            Text('للإنتاج المرئي', style: AppTextStyles.bodyMuted),
            const SizedBox(height: 28),
            const CircularProgressIndicator(strokeWidth: 2.4),
          ],
        ),
      ),
    );
  }
}
