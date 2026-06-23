// Routing/redirect tests driven by the auth state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sumou_app/app/app.dart';
import 'package:sumou_app/app/router.dart';
import 'package:sumou_app/core/models/models.dart';
import 'package:sumou_app/data/repositories/mock/mock_repositories.dart';
import 'package:sumou_app/features/auth/providers/auth_controller.dart';

void main() {
  test('homePathFor maps the supported roles', () {
    expect(homePathFor(RoleType.manager), AppRoutes.managerHome);
    expect(homePathFor(RoleType.photographer), AppRoutes.photographerHome);
    expect(homePathFor(RoleType.admin), AppRoutes.adminHome);
  });

  testWidgets('authenticated single-role user lands on their role home', (
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

    expect(find.text('الرئيسية — مدير'), findsWidgets);
  });

  testWidgets('multi-role user is sent to role selection', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'multi', password: MockUsers.devPassword);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SumouApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('اختيار الدور'), findsWidgets);
  });
}
