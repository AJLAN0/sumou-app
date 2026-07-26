import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:sumou_app/core/models/feature_permissions.dart';
import 'package:sumou_app/core/models/role_type.dart';
import 'package:sumou_app/data/repositories/auth_repository.dart';
import 'package:sumou_app/data/repositories/supabase/auth_gateway.dart';
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

    test(
      'unreadable self-profile (RLS) → generic accountUnavailable + cleanup',
      () async {
        final g = FakeAuthGateway(profile: null);
        final err = await repoWith(g)
            .login(username: 'manager', password: 'x')
            .then<Object?>((_) => null, onError: (e) => e);
        expect(failureOf(err!), AuthFailure.accountUnavailable);
        expect(g.signOutCalls, 1); // best-effort cleanup ran
      },
    );

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

  // ---- (1) Expired token: wait for a refreshed session before querying -----
  group('expired session refresh', () {
    FakeAuthGateway expiredGateway() => FakeAuthGateway(
      session: 'u1',
      sessionExpired: true,
      profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
      roles: [roleRow('r-manager', 'manager')],
    );

    test(
      'refresh success → profile is queried only AFTER the refresh',
      () async {
        final g = expiredGateway();
        addTearDown(g.dispose);
        final future = repoWith(g).currentUser();

        // Let the repository subscribe, then assert it has NOT queried yet.
        await Future<void>.delayed(Duration.zero);
        expect(g.fetchProfileCalls, 0, reason: 'must wait for a valid token');

        g.authEvents.add(
          const AuthSessionEvent(AuthSessionEventKind.refreshed, userId: 'u1'),
        );
        final user = await future;
        expect(user, isNotNull);
        expect(g.fetchProfileCalls, 1);
        expect(g.allSubscriptionsCancelled, isTrue);
      },
    );

    test('signedOut during refresh → clean signed-out, no query', () async {
      final g = expiredGateway();
      addTearDown(g.dispose);
      final future = repoWith(g).currentUser();
      await Future<void>.delayed(Duration.zero);

      g.authEvents.add(const AuthSessionEvent(AuthSessionEventKind.signedOut));
      expect(await future, isNull); // signed out, not an error
      expect(g.fetchProfileCalls, 0);
      expect(g.allSubscriptionsCancelled, isTrue);
    });

    test(
      'stream error → sessionRestoreFailed, subscription cancelled',
      () async {
        final g = expiredGateway();
        addTearDown(g.dispose);
        final future = repoWith(
          g,
        ).currentUser().then<Object?>((_) => null, onError: (e) => e);
        await Future<void>.delayed(Duration.zero);

        g.authEvents.addError(StateError('refresh stream blew up'));
        expect(failureOf((await future)!), AuthFailure.sessionRestoreFailed);
        expect(g.fetchProfileCalls, 0);
        expect(g.allSubscriptionsCancelled, isTrue);
      },
    );

    test('timeout → sessionRestoreFailed, subscription cancelled', () async {
      final g = expiredGateway();
      addTearDown(g.dispose);
      final repo = SupabaseAuthRepository.withGateway(
        g,
        refreshTimeout: const Duration(milliseconds: 20),
      );
      final err = await repo.currentUser().then<Object?>(
        (_) => null,
        onError: (e) => e,
      );
      expect(failureOf(err!), AuthFailure.sessionRestoreFailed);
      expect(g.fetchProfileCalls, 0);
      expect(g.allSubscriptionsCancelled, isTrue);
    });

    test(
      'race re-check: already refreshed before subscribing → no hang',
      () async {
        // The SDK refreshed between the expiry check and the subscription, so NO
        // event will ever arrive; the re-check must resolve it immediately.
        final g =
            expiredGateway()
              ..sessionScript = [
                const AuthSessionInfo(
                  userId: 'u1',
                  isExpired: true,
                ), // 1st check
                const AuthSessionInfo(
                  userId: 'u1',
                  isExpired: false,
                ), // re-check
              ];
        addTearDown(g.dispose);
        final repo = SupabaseAuthRepository.withGateway(
          g,
          // Long timeout: this HANGS (and fails) without the re-check.
          refreshTimeout: const Duration(seconds: 30),
        );

        final user = await repo.currentUser().timeout(
          const Duration(seconds: 5),
        );
        expect(user, isNotNull);
        expect(g.fetchProfileCalls, 1);
        expect(g.allSubscriptionsCancelled, isTrue);
      },
    );

    test(
      'race re-check: session vanished before subscribing → signed out',
      () async {
        final g =
            expiredGateway()
              ..sessionScript = [
                const AuthSessionInfo(
                  userId: 'u1',
                  isExpired: true,
                ), // 1st check
                null, // session ended before we subscribed
              ];
        addTearDown(g.dispose);
        final repo = SupabaseAuthRepository.withGateway(
          g,
          refreshTimeout: const Duration(seconds: 30),
        );

        final user = await repo.currentUser().timeout(
          const Duration(seconds: 5),
        );
        expect(user, isNull);
        expect(g.fetchProfileCalls, 0);
        expect(g.allSubscriptionsCancelled, isTrue);
      },
    );

    test('a valid (unexpired) session never waits on the stream', () async {
      final g = FakeAuthGateway(
        session: 'u1',
        profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
        roles: [roleRow('r-manager', 'manager')],
      );
      addTearDown(g.dispose);
      expect(await repoWith(g).currentUser(), isNotNull);
      expect(g.authEventSubscriptions, 0);
    });
  });

  // ---- Auth event classification (expired events are non-decisive) --------
  group('auth event classification', () {
    test(
      'tokenRefreshed/signedIn/initialSession are usable only when unexpired',
      () {
        for (final event in [
          AuthChangeEvent.tokenRefreshed,
          AuthChangeEvent.signedIn,
          AuthChangeEvent.initialSession,
        ]) {
          final ok = classifyAuthEvent(
            event,
            sessionUserId: 'u1',
            sessionIsExpired: false,
          );
          expect(ok.kind, AuthSessionEventKind.refreshed, reason: '$event');
          expect(ok.userId, 'u1');

          // Expired → non-decisive, and NEVER carries a user id.
          final expired = classifyAuthEvent(
            event,
            sessionUserId: 'u1',
            sessionIsExpired: true,
          );
          expect(expired.kind, AuthSessionEventKind.other, reason: '$event');
          expect(expired.userId, isNull, reason: '$event must not leak an id');

          // No session at all → also non-decisive.
          final none = classifyAuthEvent(
            event,
            sessionUserId: null,
            sessionIsExpired: false,
          );
          expect(none.kind, AuthSessionEventKind.other);
          expect(none.userId, isNull);
        }
      },
    );

    test('signedOut/userDeleted stay terminal regardless of expiry', () {
      for (final expired in [true, false]) {
        expect(
          classifyAuthEvent(
            AuthChangeEvent.signedOut,
            sessionUserId: null,
            sessionIsExpired: expired,
          ).kind,
          AuthSessionEventKind.signedOut,
        );
        expect(
          classifyAuthEvent(
            // ignore: deprecated_member_use
            AuthChangeEvent.userDeleted,
            sessionUserId: 'u1',
            sessionIsExpired: expired,
          ).kind,
          AuthSessionEventKind.signedOut,
        );
      }
    });

    test('unrelated events are non-decisive', () {
      expect(
        classifyAuthEvent(
          AuthChangeEvent.userUpdated,
          sessionUserId: 'u1',
          sessionIsExpired: false,
        ).kind,
        AuthSessionEventKind.other,
      );
    });
  });

  group('expired events do not complete restoration', () {
    FakeAuthGateway expiredGw() => FakeAuthGateway(
      session: 'u1',
      sessionExpired: true,
      profile: profileRow(id: 'u1', defaultRoleId: 'r-manager'),
      roles: [roleRow('r-manager', 'manager')],
    );

    /// Emits the event exactly as the real gateway would classify it.
    void emit(
      FakeAuthGateway g,
      AuthChangeEvent event, {
      required bool expired,
    }) => g.authEvents.add(
      classifyAuthEvent(event, sessionUserId: 'u1', sessionIsExpired: expired),
    );

    test('an EXPIRED initialSession does not complete restoration', () async {
      final g = expiredGw();
      addTearDown(g.dispose);
      var settled = false;
      final future = SupabaseAuthRepository.withGateway(
        g,
        refreshTimeout: const Duration(milliseconds: 300),
      ).currentUser().whenComplete(() => settled = true);
      await Future<void>.delayed(Duration.zero);

      emit(g, AuthChangeEvent.initialSession, expired: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(settled, isFalse, reason: 'expired event must not be decisive');
      expect(g.fetchProfileCalls, 0);

      // A real refresh then completes it.
      emit(g, AuthChangeEvent.tokenRefreshed, expired: false);
      expect(await future, isNotNull);
      expect(g.allSubscriptionsCancelled, isTrue);
    });

    test('an EXPIRED signedIn does not complete restoration', () async {
      final g = expiredGw();
      addTearDown(g.dispose);
      var settled = false;
      final future = SupabaseAuthRepository.withGateway(
        g,
        refreshTimeout: const Duration(milliseconds: 300),
      ).currentUser().whenComplete(() => settled = true);
      await Future<void>.delayed(Duration.zero);

      emit(g, AuthChangeEvent.signedIn, expired: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(settled, isFalse);
      expect(g.fetchProfileCalls, 0);

      emit(g, AuthChangeEvent.signedIn, expired: false);
      expect(await future, isNotNull);
    });

    test('a NON-expired initialSession may complete restoration', () async {
      final g = expiredGw();
      addTearDown(g.dispose);
      final future =
          SupabaseAuthRepository.withGateway(
            g,
            refreshTimeout: const Duration(milliseconds: 300),
          ).currentUser();
      await Future<void>.delayed(Duration.zero);

      emit(g, AuthChangeEvent.initialSession, expired: false);
      final user = await future;
      expect(user, isNotNull);
      expect(user!.id, 'u1');
      expect(g.fetchProfileCalls, 1);
      expect(g.allSubscriptionsCancelled, isTrue);
    });
  });

  // ---- (2) Strict profile parsing (never a TypeError) ----------------------
  group('strict profile parsing', () {
    Future<Object?> loginErrWith(Map<String, dynamic> row) {
      final g = FakeAuthGateway(
        profile: row,
        roles: [roleRow('r-manager', 'manager')],
      );
      return repoWith(g)
          .login(username: 'manager', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
    }

    test('non-bool must_change_password is rejected (never coerced)', () async {
      for (final bad in <Object?>[null, 'true', 1, 'false', 0]) {
        final row = profileRow()..['must_change_password'] = bad;
        final err = await loginErrWith(row);
        expect(
          failureOf(err!),
          AuthFailure.profileUnavailable,
          reason: 'must_change_password=$bad must be rejected',
        );
        expect(err, isA<AuthException>()); // typed, never a TypeError
      }
    });

    test('non-bool is_active is rejected', () async {
      final row = profileRow()..['is_active'] = 'yes';
      final err = await loginErrWith(row);
      expect(failureOf(err!), AuthFailure.profileUnavailable);
    });

    test('missing / wrong-typed required strings are rejected', () async {
      for (final key in ['username', 'full_name', 'default_role_id']) {
        final missing = profileRow()..remove(key);
        expect(
          failureOf((await loginErrWith(missing))!),
          AuthFailure.profileUnavailable,
          reason: 'missing $key',
        );
        final wrongType = profileRow()..[key] = 42;
        expect(
          failureOf((await loginErrWith(wrongType))!),
          AuthFailure.profileUnavailable,
          reason: '$key wrong type',
        );
      }
    });

    test('non-string avatar_initials is rejected; null is allowed', () async {
      expect(
        failureOf((await loginErrWith(profileRow()..['avatar_initials'] = 7))!),
        AuthFailure.profileUnavailable,
      );
      final g = FakeAuthGateway(
        profile: profileRow(avatarInitials: null),
        roles: [roleRow('r-manager', 'manager')],
      );
      expect(
        await repoWith(g).login(username: 'manager', password: 'x'),
        isNotNull,
      );
    });

    test('whitespace-only full_name is rejected', () async {
      for (final blank in ['   ', '\t', '\n  ']) {
        final err = await loginErrWith(profileRow()..['full_name'] = blank);
        expect(
          failureOf(err!),
          AuthFailure.profileUnavailable,
          reason: 'blank full_name ${blank.codeUnits} must be rejected',
        );
      }
    });

    test(
      'malformed username is rejected (frozen ^[a-z0-9._-]{2,50}\$)',
      () async {
        for (final bad in [
          'A', // too short + uppercase
          'Manager', // uppercase
          'has space',
          'bad@char',
          'x', // too short
          'y' * 51, // too long
          '   ', // blank
        ]) {
          final err = await loginErrWith(profileRow()..['username'] = bad);
          expect(
            failureOf(err!),
            AuthFailure.profileUnavailable,
            reason: 'username "$bad" must be rejected',
          );
        }
      },
    );

    test(
      'malformed deleted_at is rejected (never read as "not deleted")',
      () async {
        for (final bad in <Object>[123, true, 'not-a-timestamp', '']) {
          final err = await loginErrWith(profileRow()..['deleted_at'] = bad);
          expect(
            failureOf(err!),
            AuthFailure.profileUnavailable,
            reason: 'deleted_at "$bad" must be rejected',
          );
        }
      },
    );

    test('a real PostgREST timestamp in deleted_at means disabled', () async {
      final g = FakeAuthGateway(
        profile: profileRow(deletedAt: '2024-05-01T12:34:56.789123+00:00'),
        roles: [roleRow('r-manager', 'manager')],
      );
      final err = await repoWith(g)
          .login(username: 'manager', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.accountDisabled);
    });

    test('blank id / default_role_id are rejected', () async {
      for (final key in ['id', 'default_role_id']) {
        final err = await loginErrWith(profileRow()..[key] = '   ');
        expect(
          failureOf(err!),
          AuthFailure.profileUnavailable,
          reason: 'blank $key must be rejected',
        );
      }
    });

    test('a well-formed profile still parses (bools preserved)', () async {
      final g = FakeAuthGateway(
        profile: profileRow(mustChangePassword: true),
        roles: [roleRow('r-manager', 'manager')],
      );
      final user = await repoWith(g).login(username: 'manager', password: 'x');
      expect(user.mustChangePassword, isTrue);
    });
  });

  // ---- (3)+(4) accountUnavailable + cleanup vs explicit logout -------------
  group('cleanup vs explicit logout', () {
    test('id mismatch also maps to the generic accountUnavailable', () async {
      final g = FakeAuthGateway(
        userId: 'u1',
        profile: profileRow(id: 'someone-else'),
        roles: [roleRow('r-manager', 'manager')],
      );
      final err = await repoWith(g)
          .login(username: 'manager', password: 'x')
          .then<Object?>((_) => null, onError: (e) => e);
      expect(failureOf(err!), AuthFailure.accountUnavailable);
      expect(g.signOutCalls, 1);
    });

    test(
      'best-effort cleanup swallows a signOut failure (real reason kept)',
      () async {
        final g = FakeAuthGateway(profile: null, signOutError: true);
        final err = await repoWith(g)
            .login(username: 'manager', password: 'x')
            .then<Object?>((_) => null, onError: (e) => e);
        // The cleanup error must NOT mask the reason we were failing for.
        expect(failureOf(err!), AuthFailure.accountUnavailable);
        expect(g.signOutCalls, 1);
      },
    );

    test(
      'EXPLICIT logout surfaces a signOut failure as logoutFailed',
      () async {
        final g = FakeAuthGateway(signOutError: true);
        final err = await repoWith(
          g,
        ).logout().then<Object?>((_) => null, onError: (e) => e);
        expect(failureOf(err!), AuthFailure.logoutFailed);
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
