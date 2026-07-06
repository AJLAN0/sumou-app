import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cross-screen request to move the authenticated shell to a bottom-nav tab.
///
/// A tab body (e.g. the manager home) sets this to the target index; the shell
/// consumes it, switches tabs, and resets it back to null. Kept intentionally
/// tiny so tab bodies can navigate the shell without a shared controller.
final shellJumpTabProvider = StateProvider<int?>((ref) => null);

/// When true, the manager projects tab opens pre-filtered to active projects.
/// The projects screen reads and clears it on entry.
final managerProjectsShowActiveProvider = StateProvider<bool>((ref) => false);
