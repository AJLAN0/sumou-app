// Tests for admin role management, now part of the merged access-control
// screen (roles and permissions live together under the الصلاحيات tab).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/shell/role_based_bottom_nav.dart';

void main() {
  Future<void> openAccessControl(WidgetTester tester) async {
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
        matching: find.text('الصلاحيات'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('admin opens access control from the nav', (tester) async {
    await openAccessControl(tester);
    expect(find.text('بحث بالاسم أو اسم المستخدم'), findsOneWidget);
    expect(find.text('سعد المطيري'), findsOneWidget);
  });

  testWidgets('editing a user\'s roles shows a success snackbar', (
    tester,
  ) async {
    await openAccessControl(tester);

    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('حفظ التغييرات'));
    await tester.tap(find.text('حفظ التغييرات'));
    await tester.pumpAndSettle();
    // Confirm in the Sumou bottom sheet.
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('تم تحديث الأدوار والصلاحيات'), findsOneWidget);
  });

  test('updateUserRoles updates default and roles', () async {
    final repo = MockUserRepository();
    final updated = await repo.updateUserRoles(
      'u-photographer',
      defaultRole: RoleType.manager,
      roles: const [RoleType.photographer, RoleType.manager],
    );
    expect(updated, isNotNull);
    expect(updated!.defaultRole, RoleType.manager);
    expect(
      updated.roles,
      containsAll(<RoleType>[RoleType.manager, RoleType.photographer]),
    );

    final reloaded = await repo.getUserById('u-photographer');
    expect(reloaded!.defaultRole, RoleType.manager);
  });

  test('updateUserRoles rejects a default not in roles', () async {
    final repo = MockUserRepository();
    final result = await repo.updateUserRoles(
      'u-manager',
      defaultRole: RoleType.photographer,
      roles: const [RoleType.manager],
    );
    expect(result, isNull);
  });

  test('updateUserRoles returns null for an unknown user', () async {
    final repo = MockUserRepository();
    final result = await repo.updateUserRoles(
      'nope',
      defaultRole: RoleType.manager,
      roles: const [RoleType.manager],
    );
    expect(result, isNull);
  });
}
