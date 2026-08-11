// Tests for the public client-tracking flow (no login required).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/client_tracking_model.dart';
import 'package:sumou_app/data/repositories/tracking_repository.dart';
import 'test_helpers.dart';

class _FailingTrackingRepository implements TrackingRepository {
  int calls = 0;

  @override
  Future<ClientTrackingModel?> trackBySerial(String serial) async {
    calls += 1;
    throw StateError('raw backend diagnostics token@example.test');
  }

  @override
  Future<void> submitReview({
    required String serial,
    required int rating,
    String? message,
  }) => throw UnimplementedError();
}

void main() {
  Future<void> bootToTrack(
    WidgetTester tester, {
    TrackingRepository? repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: mockAppOverrides(trackingRepository: repository),
        child: const SumouApp(),
      ),
    );
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

  testWidgets('malformed code uses the same neutral not-found state', (
    tester,
  ) async {
    await bootToTrack(tester);
    await enterCode(tester, 'ab');
    expect(find.text('لم يتم العثور على مشروع بهذا الرمز'), findsOneWidget);
    expect(find.textContaining('قصير'), findsNothing);
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
    expect(find.text('إرسال التقييم'), findsNothing);
  });

  testWidgets('delivered project shows the approved link', (tester) async {
    await bootToTrack(tester);
    await enterCode(tester, 'NAS-7K2M-9X');
    expect(find.text('تم التسليم'), findsWidgets);
    expect(find.text('الصور'), findsOneWidget);
    expect(find.text('https://example.test/photos'), findsOneWidget);
    expect(find.text('إرسال التقييم'), findsNothing);
  });

  testWidgets('network failure is safe and offers explicit retry', (
    tester,
  ) async {
    final repository = _FailingTrackingRepository();
    await bootToTrack(tester, repository: repository);

    await enterCode(tester, 'FLD-A1B2-C3');

    expect(find.text('تعذّر تتبع المشروع الآن، حاول مرة أخرى'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.textContaining('token@example.test'), findsNothing);
    expect(repository.calls, 1);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
  });
}
