import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_model.dart';
import '../../../core/providers/repository_providers.dart';

/// Loads the users list for the admin screens (mock-backed). Read-only.
final usersListProvider = FutureProvider<List<UserModel>>(
  (ref) => ref.read(userRepositoryProvider).getUsers(),
);
