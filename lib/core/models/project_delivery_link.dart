/// Internal, read-only delivery-link state visible to an owning manager or
/// administrator through the existing `project_links` SELECT policy.
class ProjectDeliveryLink {
  const ProjectDeliveryLink({
    required this.id,
    required this.projectId,
    required this.label,
    required this.url,
    required this.isApproved,
    required this.isClientVisible,
    required this.isActive,
    required this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String projectId;
  final String label;
  final String url;
  final bool isApproved;
  final bool isClientVisible;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? deletedAt;

  bool get isRemoved => !isActive || deletedAt != null;
}
