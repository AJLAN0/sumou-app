import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/project_model.dart';
import '../../../core/models/role_type.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/repository_providers.dart';
import '../../auth/providers/auth_controller.dart';

/// Projects owned by the currently signed-in manager (mock-backed, read-only).
final managerProjectsProvider = FutureProvider<List<ProjectModel>>((ref) {
  final user = ref.watch(authControllerProvider).currentUser;
  if (user == null) return Future.value(const <ProjectModel>[]);
  return ref.read(projectRepositoryProvider).getProjectsForManager(user.id);
});

/// A single project by id (mock-backed, read-only). Null when not found.
final projectByIdProvider = FutureProvider.family<ProjectModel?, String>(
  (ref, id) => ref.read(projectRepositoryProvider).getProjectById(id),
);

/// Active staff that can be assigned to a project (managers + photographers).
/// Used by the create-project pickers. Excludes disabled accounts.
final assignableUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final users = await ref.read(userRepositoryProvider).getUsers();
  return users.where((u) => u.active).toList();
});

/// Active users that can act as a project manager.
final managerCandidatesProvider = FutureProvider<List<UserModel>>((ref) async {
  final users = await ref.watch(assignableUsersProvider.future);
  return users.where((u) => u.hasRole(RoleType.manager)).toList();
});

/// Active users that can be assigned as photographers/team members.
final photographerCandidatesProvider = FutureProvider<List<UserModel>>((
  ref,
) async {
  final users = await ref.watch(assignableUsersProvider.future);
  return users.where((u) => u.hasRole(RoleType.photographer)).toList();
});
