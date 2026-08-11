import '../../core/models/client_tracking_model.dart';

/// Safe public-tracking failures. Backend diagnostics are never retained.
enum TrackingRepositoryFailure { loadFailed, unsupportedOperation }

class TrackingRepositoryException implements Exception {
  const TrackingRepositoryException(this.reason);

  final TrackingRepositoryFailure reason;

  String get messageAr => switch (reason) {
    TrackingRepositoryFailure.loadFailed =>
      'تعذّر تتبع المشروع الآن، حاول مرة أخرى',
    TrackingRepositoryFailure.unsupportedOperation =>
      'إرسال التقييم غير متاح حالياً',
  };

  @override
  String toString() => 'TrackingRepositoryException(${reason.name})';
}

/// Client project tracking by secret serial code.
///
/// Returns null when the serial is unknown. Only approved links are ever
/// exposed by implementations.
abstract interface class TrackingRepository {
  Future<ClientTrackingModel?> trackBySerial(String serial);

  /// Submit a client rating (1–5) and optional thank-you message. Real
  /// implementations fail closed until a trusted retained-review contract
  /// exists; mocks may retain legacy in-memory behavior for isolated tests.
  Future<void> submitReview({
    required String serial,
    required int rating,
    String? message,
  });
}
