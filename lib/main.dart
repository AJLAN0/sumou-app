import 'app/bootstrap.dart';

/// Entry point. All startup work (config validation + one-time Supabase
/// initialization) happens in [bootstrap], which then runs the app root.
Future<void> main() => bootstrap();
