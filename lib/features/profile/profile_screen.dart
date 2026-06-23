import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/widgets.dart';
import 'profile_view.dart';

/// Full-screen host for [ProfileView], used by the `/profile` route (reached
/// from the manager/admin "More" menu). Auth-route shells embed [ProfileView]
/// directly via the صفحتي tab instead.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'صفحتي',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const ProfileView(),
    );
  }
}
