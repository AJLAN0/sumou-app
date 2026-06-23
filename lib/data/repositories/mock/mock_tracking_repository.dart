import '../../../core/models/client_tracking_model.dart';
import '../tracking_repository.dart';

/// In-memory [TrackingRepository] with a couple of sample projects:
/// one delivered (has approved links) and one still in progress.
class MockTrackingRepository implements TrackingRepository {
  final Map<String, ClientTrackingModel> _bySerial = {
    'NAS-7K2M-9X': const ClientTrackingModel(
      serial: 'NAS-7K2M-9X',
      projectName: 'تصوير حفل زفاف — العليا',
      clientName: 'عائلة الراشد',
      status: 'done',
      approvedLinks: [
        DeliveryLink(label: 'الصور', url: 'https://example.test/photos'),
      ],
    ),
    'X7K-29QM-4R': const ClientTrackingModel(
      serial: 'X7K-29QM-4R',
      projectName: 'حملة انستقرام — رمضان',
      clientName: 'شركة النخيل',
      status: 'active',
      // No approved links yet → client sees "جاري الإبداع ⏳".
    ),
  };

  @override
  Future<ClientTrackingModel?> trackBySerial(String serial) async =>
      _bySerial[serial.trim().toUpperCase()];

  @override
  Future<void> submitReview({
    required String serial,
    required int rating,
    String? message,
  }) async {
    final key = serial.trim().toUpperCase();
    final existing = _bySerial[key];
    if (existing == null) return;
    _bySerial[key] = ClientTrackingModel(
      serial: existing.serial,
      projectName: existing.projectName,
      clientName: existing.clientName,
      status: existing.status,
      approvedLinks: existing.approvedLinks,
      rating: rating,
      message: message,
    );
  }
}
