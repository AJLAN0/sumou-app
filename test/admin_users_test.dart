// Tests for admin users CRUD (add / edit / delete).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/shell/role_based_bottom_nav.dart';

void main() {
  Future<void> openUsers(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(RoleBasedBottomNav),
        matching: find.text('المستخدمين'),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ---- widget flows ----

  testWidgets('add button opens the user form', (tester) async {
    await openUsers(tester);
    await tester.tap(find.text('إضافة مستخدم'));
    await tester.pumpAndSettle();

    // The form fields and the create CTA are present.
    expect(find.text('الاسم الكامل'), findsOneWidget);
    expect(find.text('إضافة المستخدم'), findsOneWidget);
  });

  testWidgets('deleting a user shows a success snackbar', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openUsers(tester);
    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('حذف المستخدم'));
    await tester.tap(find.text('حذف المستخدم'));
    await tester.pumpAndSettle();
    // Confirm in the Sumou bottom sheet.
    await tester.tap(find.text('حذف'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('تم حذف المستخدم'), findsOneWidget);
  });

  // ---- repository ----

  test('createUser adds a user and rejects bad input', () async {
    final repo = MockUserRepository();
    final created = await repo.createUser(
      fullName: 'مستخدم جديد',
      username: 'newuser',
      defaultRole: RoleType.manager,
      roles: const [RoleType.manager],
    );
    expect(created, isNotNull);
    expect(created!.id, isNotEmpty);

    final all = await repo.getUsers();
    expect(all.any((u) => u.username == 'newuser'), isTrue);

    // Duplicate username (case-insensitive) is rejected.
    final dup = await repo.createUser(
      fullName: 'x',
      username: 'NewUser',
      defaultRole: RoleType.manager,
      roles: const [RoleType.manager],
    );
    expect(dup, isNull);

    // The default role must be within the roles list.
    final bad = await repo.createUser(
      fullName: 'y',
      username: 'yy',
      defaultRole: RoleType.admin,
      roles: const [RoleType.manager],
    );
    expect(bad, isNull);
  });

  test('updateUser changes fields and guards collisions', () async {
    final repo = MockUserRepository();
    final updated = await repo.updateUser(
      'u-photographer',
      fullName: 'نورة المحدثة',
      username: 'noura2',
      defaultRole: RoleType.photographer,
      roles: const [RoleType.photographer],
    );
    expect(updated, isNotNull);
    expect(updated!.fullName, 'نورة المحدثة');
    expect(updated.username, 'noura2');
    // Permissions are preserved (managed elsewhere).
    expect(updated.permissions.has(AppFeature.canUpdateStages), isTrue);

    // Colliding with another user's username is rejected.
    final collide = await repo.updateUser(
      'u-photographer',
      fullName: 'x',
      username: 'admin',
      defaultRole: RoleType.photographer,
      roles: const [RoleType.photographer],
    );
    expect(collide, isNull);

    // Unknown id → null.
    final unknown = await repo.updateUser(
      'nope',
      fullName: 'x',
      username: 'zz',
      defaultRole: RoleType.manager,
      roles: const [RoleType.manager],
    );
    expect(unknown, isNull);
  });

  test('deleteUser removes a user once', () async {
    final repo = MockUserRepository();
    expect(await repo.deleteUser('u-disabled'), isTrue);
    final all = await repo.getUsers();
    expect(all.any((u) => u.id == 'u-disabled'), isFalse);
    // Deleting again does nothing.
    expect(await repo.deleteUser('u-disabled'), isFalse);
  });
}
