/// A single approved deliverable link shown to a client.
class DeliveryLink {
  const DeliveryLink({required this.label, required this.url});

  /// What the link is for (e.g. role/photographer or deliverable type).
  final String label;
  final String url;
}

/// Read-only view a client sees after entering a project's secret code.
///
/// Only approved links are exposed. When none are approved yet, the client
/// should see [creatingLabel] («جاري الإبداع ⏳») instead of links.
class ClientTrackingModel {
  const ClientTrackingModel({
    required this.serial,
    required this.projectName,
    required this.clientName,
    required this.status,
    this.approvedLinks = const [],
    this.message,
    this.rating,
  });

  /// Shown to the client while no deliverable link is approved yet.
  static const String creatingLabel = 'جاري الإبداع ⏳';

  final String serial;
  final String projectName;
  final String clientName;
  final String status;
  final List<DeliveryLink> approvedLinks;

  /// Optional client thank-you message.
  final String? message;

  /// Optional client rating (1–5).
  final int? rating;

  bool get hasApprovedLinks => approvedLinks.isNotEmpty;

  /// True when nothing is delivered yet (client sees [creatingLabel]).
  bool get isCreating => approvedLinks.isEmpty;
}
