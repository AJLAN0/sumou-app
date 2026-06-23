import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/client_tracking_model.dart';

/// Holds the most recent client-tracking lookup so the result screen can render
/// it. Public/unauthenticated — no staff data flows through here.
final trackingResultProvider = StateProvider<ClientTrackingModel?>(
  (ref) => null,
);
