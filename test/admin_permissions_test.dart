// Tests for admin permissions control (Sprint 4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/data/repositories/user_repository.dart';
import 'package:sumou_app/features/admin/access_control_screen.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/shell/role_based_bottom_nav.dart';
import 'test_helpers.dart';

void main() {
  Future<void> openPermissions(WidgetTester tester) async {
    final container = makeMockContainer();
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

  testWidgets('permissions screen shows summary and opens the editor', (
    tester,
  ) async {
    await openPermissions(tester);
    expect(find.textContaining('الصلاحيات المفعّلة:'), findsWidgets);

    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    expect(find.text('إدارة المشاريع'), findsOneWidget);
    expect(find.text('الأدوار تتحكم في التنقل العام.'), findsOneWidget);
  });

  testWidgets('saving permissions shows a success snackbar', (tester) async {
    await openPermissions(tester);
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

  testWidgets('real flow disables access editing without a trusted contract', (
    tester,
  ) async {
    final container = makeMockContainer(
      extra: [
        userRepositoryProvider.overrideWith((_) => _ReadOnlyUserRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: AccessControlScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'تعديل الأدوار والصلاحيات غير متاح حتى يجهز مسار الخادم الآمن.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    expect(find.text('تطبيق صلاحيات الدور'), findsNothing);
  });

  test('setFeature toggles a permission flag', () {
    const p = FeaturePermissions(canAddProject: true);
    expect(p.has(AppFeature.canAddProject), isTrue);
    final off = p.setFeature(AppFeature.canAddProject, false);
    expect(off.has(AppFeature.canAddProject), isFalse);
    final on = off.setFeature(AppFeature.canViewReports, true);
    expect(on.has(AppFeature.canViewReports), isTrue);
  });

  test('updateUserPermissions persists the new flags', () async {
    final repo = MockUserRepository();
    final updated = await repo.updateUserPermissions(
      'u-photographer',
      const FeaturePermissions(canViewReports: true),
    );
    expect(updated, isNotNull);
    expect(updated!.permissions.has(AppFeature.canViewReports), isTrue);
    // The record was replaced, not merged.
    expect(updated.permissions.has(AppFeature.canUpdateStages), isFalse);

    final reloaded = await repo.getUserById('u-photographer');
    expect(reloaded!.permissions.has(AppFeature.canViewReports), isTrue);
  });

  test('updateUserPermissions returns null for an unknown user', () async {
    final repo = MockUserRepository();
    final result = await repo.updateUserPermissions(
      'nope',
      const FeaturePermissions(),
    );
    expect(result, isNull);
  });
}

class _ReadOnlyUserRepository extends MockUserRepository {
  @override
  UserRepositoryCapabilities get capabilities =>
      const UserRepositoryCapabilities.supabaseStep10_7();
}
