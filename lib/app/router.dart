import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/role_type.dart';
import '../features/auth/providers/auth_controller.dart';
import '../features/auth/screens/entry_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/role_selection_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/client_tracking/client_project_result_screen.dart';
import '../features/client_tracking/track_project_screen.dart';
import '../features/profile/change_password_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/projects/add_project_screen.dart';
import '../features/projects/assign_photographers_screen.dart';
import '../features/projects/project_details_screen.dart';
import '../features/shell/main_shell_screen.dart';

/// Centralized route paths. Use these constants instead of string literals.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String entry = '/entry';
  static const String login = '/login';
  static const String roleSelect = '/role-select';
  static const String track = '/track';
  static const String trackResult = '/track/result';
  static const String managerHome = '/manager/home';
  static const String addProject = '/manager/projects/add';
  static const String projectDetails = '/manager/projects/:id';
  static String projectDetailsPath(String id) => '/manager/projects/$id';
  static const String projectAssign = '/manager/projects/:id/assign';
  static String projectAssignPath(String id) => '/manager/projects/$id/assign';
  static const String photographerHome = '/photographer/home';
  static const String adminHome = '/admin/home';
  static const String profile = '/profile';
  static const String changePassword = '/settings/change-password';
}

/// Home path for the active role. Falls back to the manager home until the
/// other roles' homes are implemented in later steps.
String homePathFor(RoleType? role) => switch (role) {
  RoleType.manager => AppRoutes.managerHome,
  RoleType.photographer => AppRoutes.photographerHome,
  RoleType.admin => AppRoutes.adminHome,
  _ => AppRoutes.managerHome,
};

/// The app router. Watches auth/session state and redirects accordingly.
///
/// Built once per [ProviderScope]; auth changes trigger a refresh via the
/// [Listenable] below rather than rebuilding the router (which would drop
/// navigation history).
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      // Client tracking is public — accessible without employee login.
      if (loc == AppRoutes.track || loc == AppRoutes.trackResult) return null;

      // Splash routes itself after a brief auth check.
      if (loc == AppRoutes.splash) return null;

      const authFlow = {AppRoutes.entry, AppRoutes.login, AppRoutes.roleSelect};

      // Not signed in → allow entry/login, send everything else to entry.
      if (!auth.isAuthenticated) {
        if (loc == AppRoutes.entry || loc == AppRoutes.login) return null;
        return AppRoutes.entry;
      }

      // Signed in but a multi-role user hasn't chosen a role yet.
      if (auth.needsRoleSelection) {
        return loc == AppRoutes.roleSelect ? null : AppRoutes.roleSelect;
      }

      // Signed in with an active role: bounce auth-flow pages to the home.
      final home = homePathFor(auth.activeRole);
      if (authFlow.contains(loc)) return home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.entry,
        builder: (context, state) => const EntryScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.roleSelect,
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: AppRoutes.track,
        builder: (context, state) => const TrackProjectScreen(),
      ),
      GoRoute(
        path: AppRoutes.trackResult,
        builder: (context, state) => const ClientProjectResultScreen(),
      ),
      GoRoute(
        path: AppRoutes.managerHome,
        builder: (context, state) => const MainShellScreen(),
      ),
      GoRoute(
        path: AppRoutes.photographerHome,
        builder: (context, state) => const MainShellScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminHome,
        builder: (context, state) => const MainShellScreen(),
      ),
      // Declared before the `:id` route so the literal `add` segment isn't
      // captured as a project id.
      GoRoute(
        path: AppRoutes.addProject,
        builder: (context, state) => const AddProjectScreen(),
      ),
      // The `/:id/assign` segment is more specific than `/:id`, so no ordering
      // conflict with the details route.
      GoRoute(
        path: AppRoutes.projectAssign,
        builder: (context, state) =>
            AssignPhotographersScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.projectDetails,
        builder: (context, state) =>
            ProjectDetailsScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
    ],
  );
});
