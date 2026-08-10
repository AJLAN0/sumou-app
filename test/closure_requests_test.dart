// Tests for the manager approve/reject closure-request flow.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/core/widgets/widgets.dart';
import 'package:sumou_app/core/providers/repository_providers.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/data/repositories/project_repository.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';
import 'test_helpers.dart';

void main() {
  // Logs in as the manager, opens the "الطلبات" hub, then the closure inbox.
  Future<void> openRequests(
    WidgetTester tester, {
    ProjectRepository? repository,
  }) async {
    final container = makeMockContainer(
      extra: [
        if (repository != null)
          projectRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'manager', password: MockUsers.devPassword);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الطلبات'));
    await tester.pumpAndSettle();
    // The hub links to the closure inbox.
    await tester.tap(find.text('طلبات الإغلاق'));
    await tester.pumpAndSettle();
  }

  testWidgets('manager sees a pending closure request with actions', (
    tester,
  ) async {
    await openRequests(tester);
    expect(find.text('تصوير زواج — العليا'), findsOneWidget);
    expect(find.text('قبول'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);
  });

  testWidgets('approved request remains visible without review actions', (
    tester,
  ) async {
    await openRequests(tester);
    await tester.tap(find.text('قبول'));
    await tester.pumpAndSettle();
    // Confirm in the bottom sheet.
    await tester.tap(find.text('قبول وإنهاء'));
    await tester.pumpAndSettle();

    expect(find.text('مقبول'), findsOneWidget);
    expect(find.text('قبول'), findsNothing);
    expect(find.text('رفض'), findsNothing);
  });

  testWidgets('rejecting requires a reason and retains the decision', (
    tester,
  ) async {
    await openRequests(tester);
    await tester.tap(find.text('رفض'));
    await tester.pumpAndSettle();

    // Try to confirm with no reason.
    await tester.tap(find.widgetWithText(SumouButton, 'تأكيد الرفض'));
    await tester.pumpAndSettle();
    expect(find.text('الرجاء إدخال سبب الرفض'), findsOneWidget);

    // Enter a reason and confirm.
    await tester.enterText(find.byType(TextFormField), 'الجودة غير كافية');
    await tester.tap(find.widgetWithText(SumouButton, 'تأكيد الرفض'));
    await tester.pumpAndSettle();

    expect(find.text('مرفوض'), findsOneWidget);
    expect(find.textContaining('سبب الرفض: الجودة غير كافية'), findsOneWidget);
    expect(find.text('قبول'), findsNothing);
    expect(find.text('رفض'), findsNothing);
  });

  testWidgets('approve failure shows safe Arabic without diagnostics', (
    tester,
  ) async {
    await openRequests(tester, repository: _FailingApproveRepository());
    await tester.tap(find.text('قبول'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قبول وإنهاء'));
    await tester.pumpAndSettle();

    expect(find.text('الإجراء غير متاح حاليًا، حاول لاحقًا'), findsOneWidget);
    expect(find.textContaining('raw-backend-secret'), findsNothing);
  });

  testWidgets('approve loading prevents a duplicate mutation', (tester) async {
    final repository = _DelayedApproveRepository();
    await openRequests(tester, repository: repository);
    await tester.tap(find.text('قبول'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قبول وإنهاء'));
    await tester.pump();
    await tester.tap(find.text('رفض'));
    await tester.pump();

    expect(repository.calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.complete();
    await tester.pumpAndSettle();
  });

  test('approveClosureRequest completes the project', () async {
    final repo = MockProjectRepository();
    final updated = await repo.approveClosureRequest('cr-1');

    expect(updated, isNotNull);
    expect(updated!.status, ClosureRequestStatus.approved);

    final project = await repo.getProjectById('p-4');
    expect(project!.status, ProjectStatus.completed);
    expect(project.stages.every((s) => s.isDone), isTrue);

    // No longer pending → a second approval is rejected.
    expect(await repo.approveClosureRequest('cr-1'), isNull);
  });

  test('rejectClosureRequest returns the project to active', () async {
    final repo = MockProjectRepository();
    final updated = await repo.rejectClosureRequest('cr-1', 'تحتاج تعديلات');

    expect(updated, isNotNull);
    expect(updated!.status, ClosureRequestStatus.rejected);
    expect(updated.rejectReason, 'تحتاج تعديلات');

    final project = await repo.getProjectById('p-4');
    expect(project!.status, ProjectStatus.active);
  });

  test('approve/reject return null for unknown requests', () async {
    final repo = MockProjectRepository();
    expect(await repo.approveClosureRequest('nope'), isNull);
    expect(await repo.rejectClosureRequest('nope', 'x'), isNull);
  });
}

class _FailingApproveRepository extends MockProjectRepository {
  @override
  Future<ClosureRequestModel?> approveClosureRequest(String requestId) {
    throw const ProjectRepositoryException(
      ProjectRepositoryFailure.unavailable,
    );
  }
}

class _DelayedApproveRepository extends MockProjectRepository {
  final _completer = Completer<ClosureRequestModel?>();
  var calls = 0;

  @override
  Future<ClosureRequestModel?> approveClosureRequest(String requestId) {
    calls++;
    return _completer.future;
  }

  void complete() => _completer.complete(null);
}
