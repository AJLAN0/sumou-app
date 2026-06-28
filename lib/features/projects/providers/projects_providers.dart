import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/closure_request_model.dart';
import '../../../core/models/project_model.dart';
import '../../../core/models/role_type.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/repository_providers.dart';
import '../../auth/providers/auth_controller.dart';

/// A pending closure request paired with its project (for the manager review
/// list). Records keep the join lightweight without a dedicated view model.
typedef ClosureRequestView =
    ({ClosureRequestModel request, ProjectModel project});

/// Projects owned by the currently signed-in manager (mock-backed, read-only).
final managerProjectsProvider = FutureProvider<List<ProjectModel>>((ref) {
  final user = ref.watch(authControllerProvider).currentUser;
  if (user == null) return Future.value(const <ProjectModel>[]);
  return ref.read(projectRepositoryProvider).getProjectsForManager(user.id);
});

/// Projects the currently signed-in photographer is assigned to (mock-backed,
/// read-only). Empty when signed out.
final photographerProjectsProvider = FutureProvider<List<ProjectModel>>((ref) {
  final user = ref.watch(authControllerProvider).currentUser;
  if (user == null) return Future.value(const <ProjectModel>[]);
  return ref
      .read(projectRepositoryProvider)
      .getProjectsForPhotographer(user.id);
});

/// Role-scoped projects for the smart calendar / schedule view: the manager's
/// projects, the photographer's assigned projects, or empty for other roles.
final calendarProjectsProvider = FutureProvider<List<ProjectModel>>((
  ref,
) async {
  final role = ref.watch(authControllerProvider).activeRole;
  if (role == RoleType.manager) {
    return ref.watch(managerProjectsProvider.future);
  }
  if (role == RoleType.photographer) {
    return ref.watch(photographerProjectsProvider.future);
  }
  return const <ProjectModel>[];
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

/// Active-project count per assigned user id (UI-only capacity signal).
///
/// Used to show a simple متاح/مشغول/ممتلئ status on the assign screen. This is
/// not an enforcement gate — assignment is never blocked in Sprint 2.
final photographerActiveCountsProvider = FutureProvider<Map<String, int>>((
  ref,
) async {
  final projects = await ref.watch(projectRepositoryProvider).getProjects();
  final counts = <String, int>{};
  for (final p in projects) {
    if (!p.isActive) continue;
    for (final id in p.assignedPhotographers) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
});

/// Pending closure requests for the signed-in manager's projects, each joined
/// with its project (mock-backed). Empty when signed out or not a manager.
final managerClosureRequestsProvider = FutureProvider<List<ClosureRequestView>>(
  (ref) async {
    final user = ref.watch(authControllerProvider).currentUser;
    if (user == null) return const <ClosureRequestView>[];
    final repo = ref.read(projectRepositoryProvider);
    final requests = await repo.getClosureRequests();
    final myProjects = await repo.getProjectsForManager(user.id);
    final byId = {for (final p in myProjects) p.id: p};
    final result = <ClosureRequestView>[];
    for (final r in requests) {
      if (!r.isPending) continue;
      final project = byId[r.projectId];
      if (project != null) result.add((request: r, project: project));
    }
    return result;
  },
);

/// The pending closure request for a single project, or null when none.
final pendingClosureForProjectProvider =
    FutureProvider.family<ClosureRequestModel?, String>((ref, projectId) async {
      final requests =
          await ref.read(projectRepositoryProvider).getClosureRequests();
      for (final r in requests) {
        if (r.projectId == projectId && r.isPending) return r;
      }
      return null;
    });

/// All closure requests (any status) for the signed-in manager's projects,
/// joined with the project — used by the manager requests hub for counts.
final managerAllClosureRequestsProvider =
    FutureProvider<List<ClosureRequestView>>((ref) async {
      final user = ref.watch(authControllerProvider).currentUser;
      if (user == null) return const <ClosureRequestView>[];
      final repo = ref.read(projectRepositoryProvider);
      final requests = await repo.getClosureRequests();
      final myProjects = await repo.getProjectsForManager(user.id);
      final byId = {for (final p in myProjects) p.id: p};
      final result = <ClosureRequestView>[];
      for (final r in requests) {
        final project = byId[r.projectId];
        if (project != null) result.add((request: r, project: project));
      }
      return result;
    });

/// All projects in the system (mock-backed, read-only). Used by the admin
/// overview dashboard, which is not scoped to a single role.
final allProjectsProvider = FutureProvider<List<ProjectModel>>(
  (ref) => ref.read(projectRepositoryProvider).getProjects(),
);

/// The closure request for a project (any status), most recent first, or null.
/// Used by the admin read-only project details.
final closureRequestForProjectProvider =
    FutureProvider.family<ClosureRequestModel?, String>((ref, projectId) async {
  final requests =
      await ref.read(projectRepositoryProvider).getClosureRequests();
  final matching = requests.where((r) => r.projectId == projectId).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return matching.isEmpty ? null : matching.first;
});

/// All closure requests in the system (any status). Used by the admin overview.
final allClosureRequestsProvider = FutureProvider<List<ClosureRequestModel>>(
  (ref) => ref.read(projectRepositoryProvider).getClosureRequests(),
);

/// Closure requests submitted by the signed-in photographer (any status),
/// joined with the project — used by the photographer requests screen.
final photographerClosureRequestsProvider =
    FutureProvider<List<ClosureRequestView>>((ref) async {
      final user = ref.watch(authControllerProvider).currentUser;
      if (user == null) return const <ClosureRequestView>[];
      final repo = ref.read(projectRepositoryProvider);
      final requests = await repo.getClosureRequests();
      final projects = await repo.getProjects();
      final byId = {for (final p in projects) p.id: p};
      final result = <ClosureRequestView>[];
      for (final r in requests) {
        if (r.submittedBy != user.id) continue;
        final project = byId[r.projectId];
        if (project != null) result.add((request: r, project: project));
      }
      return result;
    });
