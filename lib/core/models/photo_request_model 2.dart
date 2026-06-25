/// Status of a broadcast photographer request.
enum PhotoRequestStatus {
  pending,
  accepted,
  missed;

  String get nameAr => switch (this) {
    PhotoRequestStatus.pending => 'بانتظار القبول',
    PhotoRequestStatus.accepted => 'مقبول',
    PhotoRequestStatus.missed => 'خيرها بغيرها',
  };
}

/// A request broadcast to photographers of a given type. Clean model only —
/// the realtime fan-out flow is a later sprint.
class PhotoRequestModel {
  const PhotoRequestModel({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.requestedBy,
    required this.type,
    this.date,
    this.value = 0,
    this.status = PhotoRequestStatus.pending,
    this.candidates = const [],
    this.acceptedBy,
    this.notes,
  });

  final String id;
  final String projectId;
  final String projectName;

  /// User id of the requester (usually a manager).
  final String requestedBy;

  /// Photography type requested, e.g. «مصور منتجات».
  final String type;
  final DateTime? date;
  final num value;
  final PhotoRequestStatus status;

  /// User ids the request was sent to.
  final List<String> candidates;

  /// User id of whoever accepted, if any.
  final String? acceptedBy;
  final String? notes;

  bool get isPending => status == PhotoRequestStatus.pending;
  bool get isAccepted => status == PhotoRequestStatus.accepted;
}
