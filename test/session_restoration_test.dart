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

  // ---- (5) A stale in-flight restore must never overwrite a newer result ---
  group('operation generation guard', () {
    test('a slow restore cannot overwrite a NEWER login', () async {
      // Restore is waiting on an expired-token refresh that never completes in
      // time; meanwhile the user logs in explicitly.
      final g = FakeAuthGateway(
        session: 'old-user',
        sessionExpired: true,
        profile: profileRow(id: 'old-user', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      addTearDown(g.dispose);
      final c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith(
            (ref) => SupabaseAuthRepository.withGateway(
              g,
              refreshTimeout: const Duration(milliseconds: 30),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(authControllerProvider.notifier);

      final restore = ctrl.initializeSession(); // starts, will fail on timeout

      // A newer explicit login lands first and succeeds.
      g.sessionExpired = false;
      g.profile = profileRow(id: 'new-user', defaultRoleId: 'r-admin');
      g.roles = [roleRow('r-admin', 'admin')];
      g.userId = 'new-user';
      await ctrl.login(username: 'admin', password: 'x');
      expect(c.read(authControllerProvider).isAuthenticated, isTrue);

      // The older restore now finishes (with a timeout failure) — it must NOT
      // clobber the login result with a signed-out/error state.
      await restore;
      final s = c.read(authControllerProvider);
      expect(
        s.isAuthenticated,
        isTrue,
        reason: 'stale restore overwrote login',
      );
      expect(s.currentUser!.id, 'new-user');
      expect(s.errorMessage, isNull);
      expect(s.isInitializing, isFalse);
    });

    test('a slow restore cannot resurrect a session after logout', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        sessionExpired: true,
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      addTearDown(g.dispose);
      final c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith(
            (ref) => SupabaseAuthRepository.withGateway(
              g,
              refreshTimeout: const Duration(milliseconds: 30),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(authControllerProvider.notifier);

      final restore = ctrl.initializeSession();
      await ctrl.logout(); // newer operation
      expect(c.read(authControllerProvider).isAuthenticated, isFalse);

      // Even if the restore would have produced a user, it is inert now.
      g.sessionExpired = false;
      await restore;
      final s = c.read(authControllerProvider);
      expect(
        s.isAuthenticated,
        isFalse,
        reason: 'stale restore resurrected it',
      );
      expect(s.currentUser, isNull);
    });
  });

  // ---- (4) Explicit logout failure keeps authenticated state ---------------
  group('explicit logout failure', () {
    test('logoutFailed keeps the user signed in and shows a message', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      addTearDown(g.dispose);
      final c = containerWith(g);
      final ctrl = c.read(authControllerProvider.notifier);
      await ctrl.initializeSession();
      expect(c.read(authControllerProvider).isAuthenticated, isTrue);

      g.signOutError = true;
      await ctrl.logout();

      final s = c.read(authControllerProvider);
      // The session still exists → do NOT strand the app showing signed-out.
      expect(s.isAuthenticated, isTrue);
      expect(s.currentUser!.id, 'u1');
      expect(s.errorMessage, isNotNull);
      expect(s.isInitializing, isFalse);
    });

    test('a later successful logout clears the session', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
        signOutError: true,
      );
      addTearDown(g.dispose);
      final c = containerWith(g);
      final ctrl = c.read(authControllerProvider.notifier);
      await ctrl.initializeSession();
      await ctrl.logout(); // fails
      expect(c.read(authControllerProvider).isAuthenticated, isTrue);

      g.signOutError = false;
      await ctrl.logout(); // retry succeeds
      final s = c.read(authControllerProvider);
      expect(s.isAuthenticated, isFalse);
      expect(s.selectedRole, isNull);
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
