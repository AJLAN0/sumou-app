// Tests for the admin "all projects" screen (Sprint 5).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  Future<void> openAllProjects(WidgetTester tester) async {
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

    // The dashboard quick action opens the screen.
    await tester.scrollUntilVisible(
      find.text('كل المشاريع'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('كل المشاريع'));
    await tester.pumpAndSettle();
  }

  testWidgets('admin opens all projects with stats and cards', (tester) async {
    await openAllProjects(tester);
    expect(find.text('كل المشاريع'), findsWidgets); // app bar
    expect(find.text('الإجمالي'), findsOneWidget); // summary strip

    await tester.scrollUntilVisible(
      find.text('تصوير ميداني — مهرجان الرياض'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsWidgets);
  });

  testWidgets('completed filter narrows the list', (tester) async {
    await openAllProjects(tester);

    await tester.tap(find.text('منتهي').first); // status filter chip
    await tester.pumpAndSettle();

    expect(find.text('تصوير ميداني — مهرجان الرياض'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('تغطية مؤتمر — مكتمل'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('تغطية مؤتمر — مكتمل'), findsWidgets);
  });

  testWidgets('manager filter is available', (tester) async {
    await openAllProjects(tester);
    // Manager/photographer selector buttons render with their default labels.
    expect(find.text('كل المدراء'), findsOneWidget);
    expect(find.text('كل المصورين'), findsOneWidget);
  });
}
