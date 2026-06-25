import 'dart:math';

import 'project_enums.dart';

/// Generates client-facing project serials (e.g. `FLD-1A2B-3C`).
///
/// The format is owned here so the UI (review preview) and the repository agree
/// on it. A real backend will own serial allocation later; this is mock-safe
/// and contains no secrets.
class ProjectSerial {
  ProjectSerial._();

  static final Random _random = Random();

  static String prefixFor(ProjectType type) => switch (type) {
    ProjectType.field => 'FLD',
    ProjectType.social => 'SOC',
    ProjectType.wedding => 'WED',
  };

  static String generate(ProjectType type) {
    String block(int length) {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      return String.fromCharCodes([
        for (var i = 0; i < length; i++)
          chars.codeUnitAt(_random.nextInt(chars.length)),
      ]);
    }

    return '${prefixFor(type)}-${block(4)}-${block(2)}';
  }
}
