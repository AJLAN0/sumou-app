import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/feature_permissions.dart';
import 'package:sumou_app/core/models/role_type.dart';
import 'package:sumou_app/data/repositories/auth_repository.dart';
import 'package:sumou_app/data/repositories/supabase/supabase_auth_repository.dart';

import 'fakes/fake_auth_gateway.dart';

SupabaseAuthRepository repoWith(FakeAuthGateway g) =>
    SupabaseAuthRepository.withGateway(g);

AuthFailure? failureOf(Object e) => e is AuthException ? e.reason : null;

void main() {
  // ---- Login ---------------------------------------------------------------
  group('login', () {
    test('valid login: signs in once with the hidden internal email', () async {
      final g = FakeAuthGateway(
        userId: 'u1',
        profile: profileRow(id: 'u1', username: 'manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      final user = await repoWith(
        g,
      ).login(username: '  Manager ', password: 'secret');
      expect(g.signInCalls, 1);
      expect(g.lastEmail, 'manager@users.sumou.internal');
      expect(user.username, 'manager');
      expect(user.defaultRole, RoleType.manager);
      // internal email never leaks into UserModel
      expect(user.email, isNull);
    });

    test('password is passed through untouched', () async {
      final g = FakeAuthGateway(
        profile: profileRow(),
        roles: [roleRow('r-manager', 'manager')],
      );
      await repoWith(g).login(username: 'manager', password: '  pA ss  ');
      expect(g.lastPassword, '  pA ss  ');
    });

    test('invalid username format → invalidCredentials, no network', () async {
      final g = FakeAuthGateway();
      final err = await repoWith(g)
          .login(username: 'a', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.invalidCredentials);
      expect(g.signInCalls, 0); // never called
    });

    test('wrong credentials → invalidCredentials (no leak)', () async {
      final g = FakeAuthGateway(signInError: true);
      final err = await repoWith(g)
          .login(username: 'manager', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.invalidCredentials);
    });

    test('profile-load failure after sign-in signs out', () async {
      final g = FakeAuthGateway(
        profile: profileRow(),
        errorOn: {'fetchProfile'},
      );
      final err = await repoWith(g)
          .login(username: 'manager', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.profileUnavailable);
      expect(g.signOutCalls, 1); // no orphan authenticated session
    });

    test('missing profile → profileUnavailable + sign out', () async {
      final g = FakeAuthGateway(profile: null);
      final err = await repoWith(g)
          .login(username: 'manager', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.profileUnavailable);
      expect(g.signOutCalls, 1);
    });

    test('inactive profile → accountDisabled + sign out', () async {
      final g = FakeAuthGateway(
        profile: profileRow(isActive: false),
        roles: [roleRow('r-manager', 'manager')],
      );
      final err = await repoWith(g)
          .login(username: 'manager', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.accountDisabled);
      expect(g.signOutCalls, 1);
    });

    test('soft-deleted profile → accountDisabled + sign out', () async {
      final g = FakeAuthGateway(
        profile: profileRow(deletedAt: '2020-01-01T00:00:00Z'),
        roles: [roleRow('r-manager', 'manager')],
      );
      final err = await repoWith(g)
          .login(username: 'manager', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.accountDisabled);
      expect(g.signOutCalls, 1);
    });

    test('mustChangePassword is loaded', () async {
      final g = FakeAuthGateway(
        profile: profileRow(mustChangePassword: true),
        roles: [roleRow('r-manager', 'manager')],
      );
      final user = await repoWith(g).login(username: 'manager', password: 'x');
      expect(user.mustChangePassword, isTrue);
    });
  });

  // ---- Roles ---------------------------------------------------------------
  group('roles', () {
    Future<Object?> loginErr(FakeAuthGateway g) => repoWith(g)
        .login(username: 'user', password: 'x')
        .then<Object?>((_) => null, onError: (e) => e);

    test('active roles load; inactive roles are excluded', () async {
      final g = FakeAuthGateway(
        profile: profileRow(defaultRoleId: 'r-manager'),
        roles: [
          roleRow('r-manager', 'manager'),
          roleRow('r-finance', 'finance', isActive: false), // excluded
          roleRow('r-photographer', 'photographer'),
        ],
      );
      final user = await repoWith(g).login(username: 'user', password: 'x');
      expect(
        user.roles,
        containsAll([RoleType.manager, RoleType.photographer]),
      );
      expect(user.roles, isNot(contains(RoleType.finance)));
    });

    test('marketing code maps to RoleType.marketing', () async {
      final g = FakeAuthGateway(
        profile: profileRow(defaultRoleId: 'r-mkt'),
        roles: [roleRow('r-mkt', 'marketing')],
      );
      final user = await repoWith(g).login(username: 'user', password: 'x');
      expect(user.roles, [RoleType.marketing]);
      expect(user.defaultRole, RoleType.marketing);
    });

    test('unknown active role code fails closed', () async {
      final g = FakeAuthGateway(
        profile: profileRow(defaultRoleId: 'r-x'),
        roles: [roleRow('r-x', 'super_wizard')],
      );
      expect(failureOf((await loginErr(g))!), AuthFailure.profileUnavailable);
    });

    test('no active roles fails closed', () async {
      final g = FakeAuthGateway(
        profile: profileRow(),
        roles: [roleRow('r-finance', 'finance', isActive: false)],
      );
      expect(failureOf((await loginErr(g))!), AuthFailure.profileUnavailable);
    });

    test('default role not among active roles fails closed', () async {
      final g = FakeAuthGateway(
        profile: profileRow(defaultRoleId: 'r-absent'),
        roles: [roleRow('r-manager', 'manager')],
      );
      expect(failureOf((await loginErr(g))!), AuthFailure.profileUnavailable);
    });

    test('finance/wedding_finance inactive roles are unusable', () async {
      final g = FakeAuthGateway(
        profile: profileRow(defaultRoleId: 'r-fin'),
        roles: [
          roleRow('r-fin', 'finance', isActive: false),
          roleRow('r-wfin', 'wedding_finance', isActive: false),
        ],
      );
      expect(failureOf((await loginErr(g))!), AuthFailure.profileUnavailable);
    });

    test('client_tracking is never loaded as a staff role', () async {
      final g = FakeAuthGateway(
        profile: profileRow(defaultRoleId: 'r-manager'),
        roles: [
          roleRow('r-manager', 'manager'),
          roleRow('r-ct', 'client_tracking'),
        ],
      );
      final user = await repoWith(g).login(username: 'user', password: 'x');
      expect(user.roles, [RoleType.manager]); // client_tracking skipped
    });

    test('multi-role: both roles present and default resolves', () async {
      final g = FakeAuthGateway(
        profile: profileRow(defaultRoleId: 'r-photographer'),
        roles: [
          roleRow('r-manager', 'manager'),
          roleRow('r-photographer', 'photographer'),
        ],
      );
      final user = await repoWith(g).login(username: 'user', password: 'x');
      expect(user.hasMultipleRoles, isTrue);
      expect(user.defaultRole, RoleType.photographer);
    });
  });

  // ---- Effective permissions ----------------------------------------------
  group('permissions', () {
    Future<FeaturePermissions> resolve(FakeAuthGateway g) async {
      final user = await repoWith(g).login(username: 'user', password: 'x');
      return user.permissions;
    }

    FakeAuthGateway base({
      List<Map<String, dynamic>> rolePerms = const [],
      List<Map<String, dynamic>> userPerms = const [],
    }) => FakeAuthGateway(
      profile: profileRow(defaultRoleId: 'r-manager'),
      roles: [roleRow('r-manager', 'manager')],
      rolePermissions: rolePerms,
      userPermissions: userPerms,
    );

    test('explicit true override wins over a false default', () async {
      final p = await resolve(
        base(
          rolePerms: [permRow('can_view_reports', false)],
          userPerms: [permRow('can_view_reports', true)],
        ),
      );
      expect(p.has(AppFeature.canViewReports), isTrue);
    });

    test('explicit false override wins over a true default', () async {
      final p = await resolve(
        base(
          rolePerms: [permRow('can_view_reports', true)],
          userPerms: [permRow('can_view_reports', false)],
        ),
      );
      expect(p.has(AppFeature.canViewReports), isFalse);
    });

    test('role default is used when there is no override', () async {
      final p = await resolve(
        base(rolePerms: [permRow('can_add_project', true)]),
      );
      expect(p.has(AppFeature.canAddProject), isTrue);
    });

    test(
      'role defaults are scoped to the caller OWN active role ids',
      () async {
        final g = FakeAuthGateway(
          profile: profileRow(defaultRoleId: 'r-manager'),
          roles: [
            roleRow('r-manager', 'manager'),
            roleRow('r-photographer', 'photographer'),
          ],
          rolePermissions: [permRow('can_add_project', true)],
        );
        await repoWith(g).login(username: 'user', password: 'x');
        // The role_permissions query is filtered by the caller's own role ids —
        // NEVER by permission code alone (which would leak an admin's oversight
        // read of unrelated roles).
        expect(
          g.lastRolePermissionIds,
          containsAll(['r-manager', 'r-photographer']),
        );
        expect(g.lastRolePermissionIds!.length, 2);
      },
    );

    test('inactive permission does not contribute', () async {
      final p = await resolve(
        base(rolePerms: [permRow('can_add_project', true, isActive: false)]),
      );
      expect(p.has(AppFeature.canAddProject), isFalse);
    });

    test('can_manage_finance is always false', () async {
      final p = await resolve(
        base(
          rolePerms: [permRow('can_manage_finance', true)],
          userPerms: [permRow('can_manage_finance', true)],
        ),
      );
      expect(p.has(AppFeature.canManageFinance), isFalse);
    });

    test('an unknown permission code never grants a capability', () async {
      final p = await resolve(
        base(rolePerms: [permRow('can_launch_rockets', true)]),
      );
      // nothing granted
      for (final f in AppFeature.values) {
        expect(p.has(f), isFalse, reason: f.name);
      }
    });

    test('a role_permissions query error fails closed', () async {
      final g = base()..errorOn = {'fetchRolePermissions'};
      final err = await repoWith(g)
          .login(username: 'user', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.profileUnavailable);
      expect(g.signOutCalls, 1);
    });
  });

  // ---- Photographer types --------------------------------------------------
  group('photographer types', () {
    test('active types map to name_ar; inactive excluded', () async {
      final g = FakeAuthGateway(
        profile: profileRow(defaultRoleId: 'r-photographer'),
        roles: [roleRow('r-photographer', 'photographer')],
        photoTypes: [
          photoTypeRow('مصور فوتوغرافي'),
          photoTypeRow('مصور فيديو', isActive: false),
        ],
      );
      final user = await repoWith(g).login(username: 'user', password: 'x');
      expect(user.photoTypes, ['مصور فوتوغرافي']);
    });
  });

  // ---- Session restoration (currentUser) -----------------------------------
  group('currentUser / restoration', () {
    test('no persisted session → null (signed out)', () async {
      final g = FakeAuthGateway(session: null);
      expect(await repoWith(g).currentUser(), isNull);
    });

    test('valid persisted session → complete user loaded', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      final user = await repoWith(g).currentUser();
      expect(user, isNotNull);
      expect(user!.defaultRole, RoleType.manager);
    });

    test('disabled persisted account → sign out + accountDisabled', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', isActive: false),
        roles: [roleRow('r-manager', 'manager')],
      );
      final err = await repoWith(
        g,
      ).currentUser().then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.accountDisabled);
      expect(g.signOutCalls, 1);
    });

    test(
      'restore query error propagates (valid session not signed out)',
      () async {
        final g = FakeAuthGateway(
          session: 'u1',
          profile: profileRow(id: 'u1'),
          errorOn: {'fetchProfile'},
        );
        final err = await repoWith(
          g,
        ).currentUser().then<Object?>((_) => null, onError: (e) => e);
        expect(err, isNotNull);
        expect(
          err is AuthException,
          isFalse,
        ); // non-typed → controller maps safely
        expect(g.signOutCalls, 0); // do NOT sign out on a transient failure
      },
    );
  });

  // ---- Logout + deferred changePassword ------------------------------------
  group('logout / changePassword', () {
    test('logout calls signOut and is idempotent', () async {
      final g = FakeAuthGateway();
      final repo = repoWith(g);
      await repo.logout();
      await repo.logout();
      expect(g.signOutCalls, 2);
    });

    test('changePassword is deferred to Step 10.6', () async {
      final g = FakeAuthGateway();
      final err = await repoWith(g)
          .changePassword(currentPassword: 'a', newPassword: 'b')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.passwordChangeUnavailable);
    });
  });
}
