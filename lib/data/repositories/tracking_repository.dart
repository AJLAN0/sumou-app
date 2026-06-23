import '../../core/models/client_tracking_model.dart';

/// Client project tracking by secret serial code.
///
/// Returns null when the serial is unknown. Only approved links are ever
/// exposed by implementations.
abstract interface class TrackingRepository {
  Future<ClientTrackingModel?> trackBySerial(String serial);

  /// Submit a client rating (1–5) and optional thank-you message.
  Future<void> submitReview({
    required String serial,
    required int rating,
    String? message,
  });
}
