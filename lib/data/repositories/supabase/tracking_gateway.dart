import 'package:supabase_flutter/supabase_flutter.dart';

class TrackingGatewayException implements Exception {
  const TrackingGatewayException();

  @override
  String toString() => 'TrackingGatewayException';
}

/// Narrow, fakeable boundary for the sole anonymous tracking RPC.
abstract interface class TrackingGateway {
  Future<Object?> trackProjectBySerial(String serial);
}

class SupabaseTrackingGateway implements TrackingGateway {
  const SupabaseTrackingGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> trackProjectBySerial(String serial) async {
    try {
      return await _client.rpc(
        'track_project_by_serial',
        params: {'project_serial': serial},
      );
    } on PostgrestException {
      throw const TrackingGatewayException();
    }
  }
}
