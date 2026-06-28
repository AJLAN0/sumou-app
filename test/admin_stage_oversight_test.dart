// Tests for the admin stage oversight screen (Sprint 5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> openStages(WidgetTester tester) async {
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

    await tester.scrollUntilVisible(
      find.text('كل المشاريع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('كل المشاريع'));
    await tester.pumpAndSettle();

    // Appbar timeline action opens stage oversight.
    await tester.tap(find.byIcon(Icons.timeline_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('opens stage oversight with summary and cards', (tester) async {
    await openStages(tester);
    expect(find.text('مراقبة المراحل'), findsWidgets); // app bar
    expect(find.text('الإجمالي'), findsOneWidget);
    expect(find.text('مراحل قيد التنفيذ'), findsWidgets);
  });

  testWidgets('completed filter narrows the list', (tester) async {
    await openStages(tester);
    await tester.tap(find.text('مكتمل').first);
    await tester.pumpAndSettle();

    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('تغطية مؤتمر — مكتمل'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('تغطية مؤتمر — مكتمل'), findsWidgets);
  });

  testWidgets('tapping a card opens admin project oversight', (tester) async {
    await openStages(tester);
    await tester.scrollUntilVisible(
      find.text('تصوير ميداني — مهرجان الرياض'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('تصوير ميداني — مهرجان الرياض'));
    await tester.pumpAndSettle();
    expect(find.text('مراقبة المشروع'), findsOneWidget); // admin details
  });
}
