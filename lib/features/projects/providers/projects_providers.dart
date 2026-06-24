import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/project_model.dart';
import '../../../core/providers/repository_providers.dart';
import '../../auth/providers/auth_controller.dart';

/// Projects owned by the currently signed-in manager (mock-backed, read-only).
final managerProjectsProvider = FutureProvider<List<ProjectModel>>((ref) {
  final user = ref.watch(authControllerProvider).currentUser;
  if (user == null) return Future.value(const <ProjectModel>[]);
  return ref.read(projectRepositoryProvider).getProjectsForManager(user.id);
});
