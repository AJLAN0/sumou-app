// Tests for the public client-tracking flow (no login required).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';

void main() {
  Future<void> bootToTrack(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SumouApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    // From the entry screen (unauthenticated), open the public tracking screen.
    await tester.tap(find.text('تتبع مشروع'));
    await tester.pumpAndSettle();
    expect(find.text('تتبع مشروعك'), findsOneWidget);
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('تتبع'));
    await tester.pumpAndSettle();
  }

  testWidgets('rejects a too-short code', (tester) async {
    await bootToTrack(tester);
    await enterCode(tester, 'ab');
    expect(find.text('الرمز قصير جداً، تحقق منه وحاول مجدداً'), findsOneWidget);
  });

  testWidgets('unknown code shows not-found error', (tester) async {
    await bootToTrack(tester);
    await enterCode(tester, 'NOPE9');
    expect(find.text('لم يتم العثور على مشروع بهذا الرمز'), findsOneWidget);
  });

  testWidgets('creating project shows جاري الإبداع', (tester) async {
    await bootToTrack(tester);
    await enterCode(tester, 'X7K-29QM-4R');
    expect(find.text('حملة انستقرام — رمضان'), findsOneWidget);
    expect(find.text('جاري الإبداع ⏳'), findsOneWidget);
  });

  testWidgets('delivered project shows the approved link', (tester) async {
    await bootToTrack(tester);
    await enterCode(tester, 'NAS-7K2M-9X');
    expect(find.text('تم التسليم'), findsWidgets);
    expect(find.text('الصور'), findsOneWidget);
    expect(find.text('https://example.test/photos'), findsOneWidget);
  });
}
