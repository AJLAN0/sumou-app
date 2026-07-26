import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/feature_permissions.dart';
import 'package:sumou_app/core/models/role_type.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/data/repositories/supabase/supabase_auth_repository.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

import 'fakes/fake_auth_gateway.dart';

/// A container whose auth repository is the REAL SupabaseAuthRepository backed by
/// a fake gateway (no network) — so we exercise controller + repository together.
ProviderContainer containerWith(FakeAuthGateway g) {
  final c = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith(
        (ref) => SupabaseAuthRepository.withGateway(g),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('AuthController.initializeSession', () {
    test('starts in the initializing state', () {
      final c = containerWith(FakeAuthGateway());
      expect(c.read(authControllerProvider).isInitializing, isTrue);
      expect(c.read(authControllerProvider).isAuthenticated, isFalse);
    });

    test('no persisted session → initialized + signed out', () async {
      final c = containerWith(FakeAuthGateway(session: null));
      await c.read(authControllerProvider.notifier).initializeSession();
      final s = c.read(authControllerProvider);
      expect(s.isInitializing, isFalse);
      expect(s.isAuthenticated, isFalse);
      expect(s.errorMessage, isNull);
    });

    test('valid persisted session → initialized + authenticated', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      final c = containerWith(g);
      await c.read(authControllerProvider.notifier).initializeSession();
      final s = c.read(authControllerProvider);
      expect(s.isInitializing, isFalse);
      expect(s.isAuthenticated, isTrue);
      expect(s.activeRole, RoleType.manager);
    });

    test('disabled persisted account → signed out (safe)', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', isActive: false),
        roles: [roleRow('r-manager', 'manager')],
      );
      final c = containerWith(g);
      await c.read(authControllerProvider.notifier).initializeSession();
      final s = c.read(authControllerProvider);
      expect(s.isAuthenticated, isFalse);
      expect(s.isInitializing, isFalse);
      expect(g.signOutCalls, 1);
    });

    test('restore failure → signed out with a safe Arabic message', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1'),
        errorOn: {'fetchProfile'},
      );
      final c = containerWith(g);
      await c.read(authControllerProvider.notifier).initializeSession();
      final s = c.read(authControllerProvider);
      expect(s.isAuthenticated, isFalse);
      expect(s.isInitializing, isFalse);
      expect(s.errorMessage, isNotNull);
    });

    test(
      'concurrent callers await the SAME restoration (no early routing)',
      () async {
        final g = FakeAuthGateway(
          session: 'u1',
          profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
          roles: [roleRow('r-manager', 'manager')],
        );
        final c = containerWith(g);
        final ctrl = c.read(authControllerProvider.notifier);

        // Start restoration, then call again while it is still in flight.
        final first = ctrl.initializeSession();
        final second = ctrl.initializeSession();
        // The second caller gets the in-flight future — NOT an immediately
        // completed one that would let it route on a still-initializing state.
        expect(identical(first, second), isTrue);

        await second;
        final s = c.read(authControllerProvider);
        expect(s.isInitializing, isFalse);
        expect(s.isAuthenticated, isTrue);
      },
    );

    test('a TRANSIENT restore failure can be retried', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
        errorOn: {'fetchProfile'},
      );
      final c = containerWith(g);
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.initializeSession();
      expect(c.read(authControllerProvider).isAuthenticated, isFalse);
      expect(c.read(authControllerProvider).errorMessage, isNotNull);

      // Outage clears → a retry must be possible (not latched signed-out).
      g.errorOn = {};
      await ctrl.initializeSession();
      final s = c.read(authControllerProvider);
      expect(s.isAuthenticated, isTrue);
      expect(s.isInitializing, isFalse);
      expect(s.errorMessage, isNull);
    });

    test('a TERMINAL disabled-account result is not retried', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', isActive: false),
        roles: [roleRow('r-manager', 'manager')],
      );
      final c = containerWith(g);
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.initializeSession();
      expect(c.read(authControllerProvider).isAuthenticated, isFalse);

      // Even if the account were re-enabled, restoration stays settled — the
      // repository already cleared the bad session; the user must log in again.
      g.profile = profileRow(id: 'u1', defaultRoleId: 'r-manager');
      await ctrl.initializeSession();
      expect(c.read(authControllerProvider).isAuthenticated, isFalse);
    });

    test('is idempotent (second call is a no-op)', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      final c = containerWith(g);
      final ctrl = c.read(authControllerProvider.notifier);
      await ctrl.initializeSession();
      expect(c.read(authControllerProvider).isAuthenticated, isTrue);
      // Change the backend so a re-run WOULD produce a different result…
      g.session = null;
      await ctrl.initializeSession();
      // …but the second call is a no-op, so the user is still loaded.
      expect(c.read(authControllerProvider).isAuthenticated, isTrue);
    });
  });

  group('login clears the initializing state', () {
    test(
      'a failed login while initializing does not leave isInitializing',
      () async {
        // Fresh controller → isInitializing is true; a login attempt must settle it
        // on every path, or the router would hold Splash and hide the error.
        final g = FakeAuthGateway(signInError: true);
        final c = containerWith(g);
        expect(c.read(authControllerProvider).isInitializing, isTrue);

        await c
            .read(authControllerProvider.notifier)
            .login(username: 'manager', password: 'wrong');
        final s = c.read(authControllerProvider);
        expect(s.isInitializing, isFalse);
        expect(s.isAuthenticated, isFalse);
        expect(s.errorMessage, isNotNull);
      },
    );

    test('a successful login settles initialization', () async {
      final g = FakeAuthGateway(
        userId: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      final c = containerWith(g);
      await c
          .read(authControllerProvider.notifier)
          .login(username: 'manager', password: 'x');
      final s = c.read(authControllerProvider);
      expect(s.isInitializing, isFalse);
      expect(s.isAuthenticated, isTrue);
    });
  });

  group('logout resets the session', () {
    test('clears the user and the selected role', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [
          roleRow('r-manager', 'manager'),
          roleRow('r-photographer', 'photographer'),
        ],
      );
      final c = containerWith(g);
      final ctrl = c.read(authControllerProvider.notifier);
      await ctrl.initializeSession();
      ctrl.selectRole(RoleType.manager);
      expect(c.read(authControllerProvider).selectedRole, RoleType.manager);

      await ctrl.logout();
      final s = c.read(authControllerProvider);
      expect(s.currentUser, isNull);
      expect(s.selectedRole, isNull);
      expect(g.signOutCalls, 1);
    });
  });

  group('admin permission oversight does not leak', () {
    test('role defaults are scoped to the admin OWN role id', () async {
      final g = FakeAuthGateway(
        session: 'admin-1',
        profile: profileRow(id: 'admin-1', defaultRoleId: 'r-admin'),
        roles: [roleRow('r-admin', 'admin')],
        // Scoped to the admin's own role, the gateway returns only admin grants.
        rolePermissions: [permRow('can_manage_users', true)],
      );
      final c = containerWith(g);
      await c.read(authControllerProvider.notifier).initializeSession();
      final perms = c.read(authControllerProvider).currentUser!.permissions;
      // The admin gets its own grant…
      expect(perms.has(AppFeature.canManageUsers), isTrue);
      // …but NOT a manager-only capability (it never queried other roles).
      expect(perms.has(AppFeature.canAddProject), isFalse);
      // Proof of own-role scoping: the query used the admin's role id only.
      expect(g.lastRolePermissionIds, ['r-admin']);
    });
  });
}
