import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../data/repositories/mock/mock_repositories.dart';

/// Repository dependency-injection providers.
///
/// These currently return the in-memory mock implementations. When Supabase
/// implementations exist, swap them here (or override in a [ProviderScope]) —
/// nothing else in the app needs to change because callers depend on the
/// abstract interfaces.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => MockAuthRepository(),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => MockUserRepository(),
);

final permissionRepositoryProvider = Provider<PermissionRepository>(
  (ref) => MockPermissionRepository(),
);

final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => MockTrackingRepository(),
);

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => MockProjectRepository(),
);
