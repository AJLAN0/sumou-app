import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/widgets.dart';
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
    // Size the mark to the screen so it reads big on any device.
    final logoWidth = (MediaQuery.sizeOf(context).width * 0.62).clamp(
      220.0,
      340.0,
    );
    return SumouScaffold(
      // The brand mark fills with liquid white as the loading indicator.
      body: Center(child: LiquidLogoLoader(width: logoWidth)),
    );
  }
}
