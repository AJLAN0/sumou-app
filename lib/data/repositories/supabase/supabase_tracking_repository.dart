import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../../core/models/client_tracking_model.dart';
import '../tracking_repository.dart';
import 'tracking_gateway.dart';

/// Public tracking through the single minimized anonymous RPC contract.
class SupabaseTrackingRepository implements TrackingRepository {
  SupabaseTrackingRepository(SupabaseClient client)
    : _gateway = SupabaseTrackingGateway(client);

  SupabaseTrackingRepository.withGateway(this._gateway);

  final TrackingGateway _gateway;

  static final RegExp _serial = RegExp(
    r'^(FLD|SOC|WED)-[A-Z0-9]{4}-[A-Z0-9]{2}$',
  );
  static const Set<String> _outerKeys = {
    'serial',
    'project_name',
    'client_name',
    'status',
    'links',
  };
  static const Set<String> _linkKeys = {'label', 'url'};

  @override
  Future<ClientTrackingModel?> trackBySerial(String serial) async {
    final normalized = serial.trim().toUpperCase();
    // Malformed, unknown, inactive, and deleted projects share the same neutral
    // null result. Avoiding the RPC for malformed input creates no public oracle.
    if (!_serial.hasMatch(normalized)) return null;

    try {
      final response = await _gateway.trackProjectBySerial(normalized);
      if (response == null) return null;
      final row = _strictMap(response, _outerKeys);
      final returnedSerial = _requiredToken(row, 'serial');
      if (!_serial.hasMatch(returnedSerial) || returnedSerial != normalized) {
        _invalidData();
      }
      final status = _requiredToken(row, 'status');
      if (status != 'active' && status != 'done') _invalidData();

      final rawLinks = row['links'];
      if (rawLinks is! List) _invalidData();
      final links = <DeliveryLink>[];
      for (final rawLink in rawLinks) {
        final link = _strictMap(rawLink, _linkKeys);
        final url = _requiredToken(link, 'url');
        _validateHttpUrl(url);
        links.add(DeliveryLink(label: _requiredText(link, 'label'), url: url));
      }

      return ClientTrackingModel(
        serial: returnedSerial,
        projectName: _requiredText(row, 'project_name'),
        clientName: _requiredText(row, 'client_name'),
        status: status,
        approvedLinks: List.unmodifiable(links),
        message: null,
        rating: null,
      );
    } on TrackingRepositoryException {
      rethrow;
    } catch (_) {
      throw const TrackingRepositoryException(
        TrackingRepositoryFailure.loadFailed,
      );
    }
  }

  @override
  Future<void> submitReview({
    required String serial,
    required int rating,
    String? message,
  }) => Future<void>.error(
    const TrackingRepositoryException(
      TrackingRepositoryFailure.unsupportedOperation,
    ),
  );

  static Map<String, dynamic> _strictMap(
    Object? value,
    Set<String> expectedKeys,
  ) {
    if (value is! Map) _invalidData();
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) _invalidData();
      result[entry.key as String] = entry.value;
    }
    if (result.length != expectedKeys.length ||
        !result.keys.toSet().containsAll(expectedKeys)) {
      _invalidData();
    }
    return result;
  }

  static String _requiredToken(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.isEmpty || value != value.trim()) {
      _invalidData();
    }
    return value;
  }

  static String _requiredText(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) _invalidData();
    return value.trim();
  }

  static void _validateHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _invalidData();
    }
  }

  static Never _invalidData() =>
      throw const TrackingRepositoryException(
        TrackingRepositoryFailure.loadFailed,
      );
}
