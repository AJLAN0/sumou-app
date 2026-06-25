// Tests for the smart calendar / schedule view.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/projects/providers/projects_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';

void main() {
  Future<void> openCalendarAsPhotographer(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'photographer', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تقويمي'));
    await tester.pumpAndSettle();
  }

  testWidgets('photographer calendar shows controls and weekday labels', (
    tester,
  ) async {
    await openCalendarAsPhotographer(tester);
    expect(find.text('التقويم'), findsWidgets); // mode toggle
    expect(find.text('القائمة'), findsOneWidget);
    expect(find.text('سبت'), findsOneWidget); // Saturday-first header
    expect(find.text('الكل'), findsOneWidget); // filter
  });

  testWidgets('list mode renders project cards', (tester) async {
    await openCalendarAsPhotographer(tester);
    await tester.tap(find.text('القائمة'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('حملة انستقرام — رمضان'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('حملة انستقرام — رمضان'), findsWidgets);
  });

  testWidgets('completed filter narrows the list', (tester) async {
    await openCalendarAsPhotographer(tester);
    await tester.tap(find.text('منتهي').first); // filter chip
    await tester.pumpAndSettle();
    await tester.tap(find.text('القائمة'));
    await tester.pumpAndSettle();

    // The in-progress project is filtered out entirely.
    expect(find.text('حملة انستقرام — رمضان'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('تغطية مؤتمر — مكتمل'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('تغطية مؤتمر — مكتمل'), findsWidgets);
  });

  testWidgets('manager reaches the calendar from the More menu', (
    tester,
  ) async {
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

    await tester.tap(find.text('المزيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التقويم'));
    await tester.pumpAndSettle();

    // CalendarPage app bar + the calendar-mode toggle both read التقويم.
    expect(find.text('التقويم'), findsWidgets);
    expect(find.text('القائمة'), findsOneWidget);
  });

  test('calendarProjectsProvider is empty for roles without projects', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: MockUsers.devPassword);
    final list = await container.read(calendarProjectsProvider.future);
    expect(list, isEmpty);
  });
}
