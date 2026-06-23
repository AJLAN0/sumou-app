// Tests for the mock repository implementations.

import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/repositories.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';

void main() {
  group('MockAuthRepository', () {
    test('logs in an active user with the dev password', () async {
      final auth = MockAuthRepository();
      final user = await auth.login(
        username: 'manager',
        password: MockUsers.devPassword,
      );
      expect(user.username, 'manager');
      expect(await auth.currentUser(), isNotNull);
    });

    test('rejects a wrong password', () async {
      final auth = MockAuthRepository();
      await expectLater(
        auth.login(username: 'manager', password: 'wrong'),
        throwsA(isA<AuthException>().having(
            (e) => e.reason, 'reason', AuthFailure.invalidCredentials)),
      );
    });

    test('rejects a disabled account', () async {
      final auth = MockAuthRepository();
      await expectLater(
        auth.login(username: 'disabled', password: MockUsers.devPassword),
        throwsA(isA<AuthException>()
            .having((e) => e.reason, 'reason', AuthFailure.accountDisabled)),
      );
    });

    test('logout clears the session', () async {
      final auth = MockAuthRepository();
      await auth.login(username: 'admin', password: MockUsers.devPassword);
      await auth.logout();
      expect(await auth.currentUser(), isNull);
    });

    test('changePassword updates the dev password', () async {
      final auth = MockAuthRepository();
      await auth.login(username: 'admin', password: MockUsers.devPassword);
      await auth.changePassword(
        currentPassword: MockUsers.devPassword,
        newPassword: 'new-dev-pass',
      );
      await auth.logout();
      final user =
          await auth.login(username: 'admin', password: 'new-dev-pass');
      expect(user.username, 'admin');
    });
  });

  group('MockUserRepository', () {
    test('exposes the mock users and lookups', () async {
      final repo = MockUserRepository();
      expect((await repo.getUsers()).length, MockUsers.users.length);
      expect((await repo.getUserById('u-admin'))?.username, 'admin');
      expect((await repo.getUserByUsername('photographer'))?.id,
          'u-photographer');
      expect(await repo.getUserById('missing'), isNull);
    });
  });

  group('MockPermissionRepository', () {
    test('derives permission records from users', () async {
      final repo = MockPermissionRepository();
      final perm = await repo.getPermissions('u-manager');
      expect(perm, isNotNull);
      expect(perm!.hasPermission(AppFeature.canAddProject), isTrue);
    });
  });

  group('MockTrackingRepository', () {
    test('returns a delivered project with links', () async {
      final repo = MockTrackingRepository();
      final result = await repo.trackBySerial('nas-7k2m-9x');
      expect(result, isNotNull);
      expect(result!.hasApprovedLinks, isTrue);
    });

    test('returns a creating project with no links', () async {
      final repo = MockTrackingRepository();
      final result = await repo.trackBySerial('X7K-29QM-4R');
      expect(result!.isCreating, isTrue);
    });

    test('unknown serial returns null', () async {
      final repo = MockTrackingRepository();
      expect(await repo.trackBySerial('NOPE'), isNull);
    });
  });
}
