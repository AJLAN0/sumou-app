import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../auth/providers/auth_controller.dart';
import 'more_menu_screen.dart';
import 'nav_item.dart';
import 'role_based_bottom_nav.dart';
import 'tab_placeholder_screen.dart';

/// Authenticated app shell: a Sumou-styled header, a body that switches with
/// the role-based bottom navigation, and the [RoleBasedBottomNav] itself.
///
/// The active role comes from the auth/session state; tab content is
/// placeholder-only in this step.
class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(
      authControllerProvider.select((s) => s.activeRole),
    );

    // Should not happen on a role-home route (redirect guards it), but stay
    // safe if the session is cleared while the shell is mounted.
    if (role == null) {
      return const SumouScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final items = RoleNavConfig.forRole(role);
    final index = _index.clamp(0, items.length - 1);
    final current = items[index];
    final accent = RoleModel.of(role).color;

    final Widget body = current.label == RoleNavConfig.moreLabel
        ? const MoreMenuScreen()
        : TabPlaceholderScreen(title: current.label, icon: current.icon);

    return SumouScaffold(
      appBar: SumouAppBar(title: current.label),
      body: body,
      bottomNavigationBar: RoleBasedBottomNav(
        items: items,
        currentIndex: index,
        accentColor: accent,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
