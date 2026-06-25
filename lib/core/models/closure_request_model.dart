/// Status of a project closure request.
enum ClosureRequestStatus {
  pending,
  approved,
  rejected;

  String get nameAr => switch (this) {
    ClosureRequestStatus.pending => 'بانتظار الموافقة',
    ClosureRequestStatus.approved => 'مقبول',
    ClosureRequestStatus.rejected => 'مرفوض',
  };
}

/// A request (from a photographer) to close/deliver a project, reviewed by the
/// manager.
class ClosureRequestModel {
  const ClosureRequestModel({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.submittedBy,
    required this.submittedByName,
    required this.createdAt,
    this.reportFileUrl,
    this.deliveryLink,
    this.notes,
    this.status = ClosureRequestStatus.pending,
    this.rejectReason,
    this.reviewedAt,
  });

  final String id;
  final String projectId;
  final String projectName;

  /// User id of the submitter.
  final String submittedBy;
  final String submittedByName;
  final DateTime createdAt;

  final String? reportFileUrl;
  final String? deliveryLink;

  /// Optional free-text note from the submitter.
  final String? notes;
  final ClosureRequestStatus status;
  final String? rejectReason;
  final DateTime? reviewedAt;

  bool get isPending => status == ClosureRequestStatus.pending;
  bool get isApproved => status == ClosureRequestStatus.approved;
  bool get isRejected => status == ClosureRequestStatus.rejected;

  ClosureRequestModel copyWith({
    ClosureRequestStatus? status,
    String? rejectReason,
    DateTime? reviewedAt,
  }) {
    return ClosureRequestModel(
      id: id,
      projectId: projectId,
      projectName: projectName,
      submittedBy: submittedBy,
      submittedByName: submittedByName,
      createdAt: createdAt,
      reportFileUrl: reportFileUrl,
      deliveryLink: deliveryLink,
      notes: notes,
      status: status ?? this.status,
      rejectReason: rejectReason ?? this.rejectReason,
      reviewedAt: reviewedAt ?? this.reviewedAt,
    );
  }
}
