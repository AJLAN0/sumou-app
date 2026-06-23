// Tests for the admin users / permissions / reports tabs.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

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

  testWidgets('users tab lists users as cards', (tester) async {
    await pumpAsAdmin(tester);
    await tester.tap(find.text('المستخدمين'));
    await tester.pumpAndSettle();

    expect(find.text('سعد المطيري'), findsOneWidget);
    expect(find.text('@admin'), findsOneWidget);
    // Disabled mock user renders a موقوف pill.
    expect(find.text('موقوف'), findsWidgets);
  });

  testWidgets('inactive filter narrows the list', (tester) async {
    await pumpAsAdmin(tester);
    await tester.tap(find.text('المستخدمين'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الموقوفون'));
    await tester.pumpAndSettle();

    expect(find.text('فهد القحطاني'), findsOneWidget);
    expect(find.text('سعد المطيري'), findsNothing);
  });

  testWidgets('permissions tab shows feature chips', (tester) async {
    await pumpAsAdmin(tester);
    await tester.tap(find.text('الصلاحيات'));
    await tester.pumpAndSettle();

    expect(find.text('إضافة مشروع'), findsWidgets);
  });

  testWidgets('reports tab shows the placeholder', (tester) async {
    await pumpAsAdmin(tester);
    await tester.tap(find.text('التقارير'));
    await tester.pumpAndSettle();

    expect(find.text('التقارير المتقدمة ستتوفر في تحديث قادم'), findsOneWidget);
  });
}
