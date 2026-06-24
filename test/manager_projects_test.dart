// Tests for the manager projects list tab.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> openProjects(WidgetTester tester) async {
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
  }

  testWidgets('lists the manager projects as cards', (tester) async {
    await openProjects(tester);
    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsOneWidget);
    expect(find.text('حملة انستقرام — رمضان'), findsOneWidget);
  });

  testWidgets('search narrows the list', (tester) async {
    await openProjects(tester);
    await tester.enterText(find.byType(TextField), 'رمضان');
    await tester.pumpAndSettle();
    expect(find.text('حملة انستقرام — رمضان'), findsOneWidget);
    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsNothing);
  });

  testWidgets('completed filter shows only completed projects', (tester) async {
    await openProjects(tester);
    // The completed card also shows a «منتهي» status chip; the filter chip
    // comes first in the tree.
    await tester.tap(find.text('منتهي').first);
    await tester.pumpAndSettle();
    expect(find.text('تغطية مؤتمر — مكتمل'), findsOneWidget);
    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsNothing);
  });

  testWidgets('tapping a card shows the coming-soon snackbar', (tester) async {
    await openProjects(tester);
    await tester.tap(find.text('تصوير ميداني — مهرجان الرياض'));
    await tester.pump(); // start snackbar animation
    expect(find.text('تفاصيل المشروع قريباً'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // flush snackbar timer
  });
}
