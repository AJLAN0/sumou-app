import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/role_type.dart';
import '../dev/route_placeholder.dart';
import '../features/auth/providers/auth_controller.dart';

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

      const authFlow = {
        AppRoutes.splash,
        AppRoutes.entry,
        AppRoutes.login,
        AppRoutes.roleSelect,
      };

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
        builder:
            (context, state) =>
                const RoutePlaceholder(title: 'سمو', path: AppRoutes.splash),
      ),
      GoRoute(
        path: AppRoutes.entry,
        builder:
            (context, state) =>
                const RoutePlaceholder(title: 'الدخول', path: AppRoutes.entry),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder:
            (context, state) => const RoutePlaceholder(
              title: 'تسجيل الدخول',
              path: AppRoutes.login,
            ),
      ),
      GoRoute(
        path: AppRoutes.roleSelect,
        builder:
            (context, state) => const RoutePlaceholder(
              title: 'اختيار الدور',
              path: AppRoutes.roleSelect,
            ),
      ),
      GoRoute(
        path: AppRoutes.track,
        builder:
            (context, state) => const RoutePlaceholder(
              title: 'تتبع مشروع',
              path: AppRoutes.track,
            ),
      ),
      GoRoute(
        path: AppRoutes.trackResult,
        builder:
            (context, state) => const RoutePlaceholder(
              title: 'حالة المشروع',
              path: AppRoutes.trackResult,
            ),
      ),
      GoRoute(
        path: AppRoutes.managerHome,
        builder:
            (context, state) => const RoutePlaceholder(
              title: 'الرئيسية — مدير',
              path: AppRoutes.managerHome,
            ),
      ),
      GoRoute(
        path: AppRoutes.photographerHome,
        builder:
            (context, state) => const RoutePlaceholder(
              title: 'الرئيسية — مصور',
              path: AppRoutes.photographerHome,
            ),
      ),
      GoRoute(
        path: AppRoutes.adminHome,
        builder:
            (context, state) => const RoutePlaceholder(
              title: 'لوحة التحكم — الإدارة',
              path: AppRoutes.adminHome,
            ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder:
            (context, state) =>
                const RoutePlaceholder(title: 'صفحتي', path: AppRoutes.profile),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder:
            (context, state) => const RoutePlaceholder(
              title: 'تغيير كلمة المرور',
              path: AppRoutes.changePassword,
            ),
      ),
    ],
  );
});
