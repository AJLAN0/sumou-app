// Tests for the manager "إنهاء المشروع" flow: review + accept the photographer's
// closure request.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> openEnd(WidgetTester tester, String projectName) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'manager', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('المشاريع'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(projectName),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(projectName));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('إنهاء المشروع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('إنهاء المشروع'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the photographer closure request to review', (
    tester,
  ) async {
    await openEnd(tester, 'تصوير زواج — العليا');
    expect(find.textContaining('راجع طلب الإنهاء'), findsOneWidget);
    expect(find.textContaining('مقدّم الطلب'), findsOneWidget);
    expect(find.text('قبول'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);
  });

  testWidgets('accepting the request finishes the project', (tester) async {
    await openEnd(tester, 'تصوير زواج — العليا');
    await tester.tap(find.text('قبول'));
    await tester.pumpAndSettle();
    // Confirm in the Sumou bottom sheet.
    await tester.tap(find.text('قبول وإنهاء'));
    await tester.pumpAndSettle();

    expect(find.text('تم إنهاء المشروع'), findsOneWidget);
  });

  testWidgets('no request yet shows a waiting empty state', (tester) async {
    await openEnd(tester, 'تصوير ميداني — مهرجان الرياض');
    expect(find.text('لا يوجد طلب إنهاء'), findsOneWidget);
  });
}
