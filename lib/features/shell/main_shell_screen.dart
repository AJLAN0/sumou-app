import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../auth/providers/auth_controller.dart';
import '../dashboard/admin_dashboard_screen.dart';
import '../dashboard/manager_home_screen.dart';
import '../dashboard/photographer_home_screen.dart';
import '../dashboard/role_placeholder_home.dart';
import '../profile/profile_view.dart';
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

    final Widget body;
    if (current.label == RoleNavConfig.moreLabel) {
      body = const MoreMenuScreen();
    } else if (current.label == RoleNavConfig.profileLabel) {
      body = const ProfileView();
    } else if (index == 0) {
      // The first tab is each role's home / dashboard.
      body = _homeFor(role);
    } else {
      body = TabPlaceholderScreen(title: current.label, icon: current.icon);
    }

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

  Widget _homeFor(RoleType role) => switch (role) {
        RoleType.manager => const ManagerHomeScreen(),
        RoleType.photographer => const PhotographerHomeScreen(),
        RoleType.admin => const AdminDashboardScreen(),
        _ => RolePlaceholderHome(role: role),
      };
}
