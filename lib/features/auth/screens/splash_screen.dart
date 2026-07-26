import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/widgets.dart';
import '../providers/auth_controller.dart';

/// Opening screen. Shows branding while the app restores a persisted Supabase
/// session, then routes based on the restored auth state: unauthenticated →
/// entry, multi-role w/o selection → role select, otherwise the role home.
///
/// It waits for BOTH a small minimum branding duration AND completion of
/// [AuthController.initializeSession] before routing — the app never routes to
/// Entry before restoration has finished.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const Duration _minBranding = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    // Run after the first frame so restoration (which mutates the auth provider)
    // never modifies a provider during the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _boot();
    });
  }

  Future<void> _boot() async {
    final controller = ref.read(authControllerProvider.notifier);
    // Both must finish: branding minimum + session restoration.
    await Future.wait<void>([
      Future<void>.delayed(_minBranding),
      controller.initializeSession(),
    ]);
    if (!mounted) return;
    _route();
  }

  void _route() {
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
  Widget build(BuildContext context) {
    // Size the mark to the screen so it reads big on any device.
    final logoWidth = (MediaQuery.sizeOf(context).width * 0.432).clamp(
      153.0,
      225.0,
    );
    return SumouScaffold(
      // The brand mark fills with liquid white as the loading indicator.
      body: Center(child: LiquidLogoLoader(width: logoWidth)),
    );
  }
}
