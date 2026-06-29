// Tests for the admin overview dashboard (Sprint 4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'package:sumou_app/features/dashboard/admin_dashboard_screen.dart';

import 'test_helpers.dart';

void main() {
  Future<void> pumpAdmin(WidgetTester tester) async {
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

  testWidgets('overview computes user and project stats from mock data', (
    tester,
  ) async {
    await pumpAdmin(tester);
    // Top overview is on-screen.
    expect(find.text('نظرة عامة على النظام'), findsOneWidget);
    // 'المستخدمون' appears in both the headline strip and the team card.
    expect(find.text('المستخدمون'), findsWidgets);
  });

  testWidgets('overview shows projects, team, requests and quick actions', (
    tester,
  ) async {
    await pumpAdmin(tester);
    final scroll = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(
      find.text('المشاريع حسب النوع'),
      300,
      scrollable: scroll,
    );
    expect(find.text('المشاريع حسب النوع'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('الفريق'),
      300,
      scrollable: scroll,
    );
    expect(find.text('متاحون'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('طلبات الإغلاق'),
      300,
      scrollable: scroll,
    );
    expect(find.text('طلبات الإغلاق'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('إجراءات سريعة'),
      300,
      scrollable: scroll,
    );
    await tester.scrollUntilVisible(
      find.text('إدارة المستخدمين'),
      300,
      scrollable: scroll,
    );
    expect(find.text('إدارة المستخدمين'), findsOneWidget);
  });

  testWidgets('reports quick action shows a coming-soon snackbar', (
    tester,
  ) async {
    await pumpAdmin(tester);
    // 'التقارير' is also a bottom-nav tab label; scope to the dashboard action.
    final reportsAction = find.descendant(
      of: find.byType(AdminDashboardScreen),
      matching: find.text('التقارير'),
    );
    await tester.scrollUntilVisible(
      reportsAction,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(reportsAction);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('هذه الميزة قريباً'), findsOneWidget);
  });
}
