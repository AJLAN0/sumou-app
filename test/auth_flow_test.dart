// End-to-end auth flow test driving the real screens with mock auth.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';

void main() {
  Future<void> bootToEntry(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SumouApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('manager logs in and reaches the manager home', (tester) async {
    await bootToEntry(tester);

    await tester.tap(find.text('دخول سمو'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'manager');
    await tester.enterText(
        find.byType(TextField).at(1), MockUsers.devPassword);
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();

    expect(find.text('الرئيسية — مدير'), findsOneWidget);
  });

  testWidgets('disabled account is rejected with an error', (tester) async {
    await bootToEntry(tester);

    await tester.tap(find.text('دخول سمو'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'disabled');
    await tester.enterText(
        find.byType(TextField).at(1), MockUsers.devPassword);
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();

    // Still on the login screen with an error shown.
    expect(find.text('دخول'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
