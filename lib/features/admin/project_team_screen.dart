import 'package:flutter/widgets.dart';

import '../projects/assign_photographers_screen.dart';

/// Admin uses the same trusted, catalog-driven team assignment flow.
/// Manager reassignment remains unavailable until a trusted contract exists.
class AdminProjectTeamScreen extends StatelessWidget {
  const AdminProjectTeamScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) =>
      AssignPhotographersScreen(projectId: projectId, title: 'إدارة الفريق');
}
