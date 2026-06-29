// Tests for admin permissions control (Sprint 4).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/shell/role_based_bottom_nav.dart';

void main() {
  Future<void> openPermissions(WidgetTester tester) async {
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
