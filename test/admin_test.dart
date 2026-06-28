// Tests for the admin users / permissions / reports tabs.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/shell/role_based_bottom_nav.dart';

void main() {
  Future<void> pumpAsAdmin(WidgetTester tester) async {
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
  }

  // Tap a bottom-nav tab by its label. Scoped to the nav so it isn't confused
  // with same-named labels elsewhere (e.g. dashboard stat cards).
  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(RoleBasedBottomNav),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('users tab lists users as cards', (tester) async {
    // Use a tall viewport so all user cards (incl. the last, disabled one)
    // render without scrolling.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpAsAdmin(tester);
    await tapNav(tester, 'المستخدمين');

    expect(find.text('سعد المطيري'), findsOneWidget);
    expect(find.text('@admin'), findsOneWidget);
    // The disabled mock user renders a غير نشط pill.
    expect(find.text('غير نشط'), findsWidgets);
  });

  testWidgets('inactive filter narrows the list', (tester) async {
    await pumpAsAdmin(tester);
    await tapNav(tester, 'المستخدمين');

    await tester.tap(find.text('غير نشط').first); // filter chip
    await tester.pumpAndSettle();

    expect(find.text('فهد القحطاني'), findsOneWidget);
    expect(find.text('سعد المطيري'), findsNothing);
  });

  testWidgets('tapping a user opens the details sheet', (tester) async {
    await pumpAsAdmin(tester);
    await tapNav(tester, 'المستخدمين');

    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();

    expect(find.text('الأدوار'), findsOneWidget);
    expect(find.text('تعطيل المستخدم'), findsOneWidget); // active user
  });

  testWidgets('deactivating a user shows a success snackbar', (tester) async {
    await pumpAsAdmin(tester);
    await tapNav(tester, 'المستخدمين');

    await tester.tap(find.text('سعد المطيري'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعطيل المستخدم'));
    await tester.pumpAndSettle();
    // Confirm in the Sumou bottom sheet.
    await tester.tap(find.text('تعطيل'));
    // Pump (not settle) so the success snackbar isn't auto-dismissed.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('تم تعطيل المستخدم'), findsOneWidget);
  });

  testWidgets('permissions tab shows feature chips', (tester) async {
    await pumpAsAdmin(tester);
    await tapNav(tester, 'الصلاحيات');

    expect(find.text('إضافة مشروع'), findsWidgets);
  });

  testWidgets('reports tab shows the placeholder', (tester) async {
    await pumpAsAdmin(tester);
    await tapNav(tester, 'التقارير');

    expect(find.text('التقارير المتقدمة ستتوفر في تحديث قادم'), findsOneWidget);
  });
}
