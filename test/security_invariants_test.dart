import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _authSources = <String>[
  'lib/features/auth/screens/login_screen.dart',
  'lib/features/auth/providers/auth_controller.dart',
  'lib/features/profile/change_password_screen.dart',
  'lib/data/repositories/supabase/auth_gateway.dart',
  'lib/data/repositories/supabase/supabase_auth_repository.dart',
];

List<String> _loggingStatements() {
  final loggingCall = RegExp(r'\b(?:print|debugPrint|developer\.log|log)\s*\(');
  return [
    for (final path in _authSources)
      for (final line in File(path).readAsLinesSync())
        if (loggingCall.hasMatch(line)) line,
  ];
}

void main() {
  test('login code contains no password logging statement', () {
    final lines = _loggingStatements();
    expect(
      lines.where((line) => line.toLowerCase().contains('password')),
      isEmpty,
    );
  });

  test('password-change code contains no password logging statement', () {
    final lines = _loggingStatements();
    expect(
      lines.where((line) => line.toLowerCase().contains('password')),
      isEmpty,
    );
  });

  test('password-change code contains no token logging statement', () {
    final lines = _loggingStatements();
    expect(
      lines.where((line) {
        final lower = line.toLowerCase();
        return lower.contains('token') || lower.contains('authorization');
      }),
      isEmpty,
    );
  });

  test('password-change code contains no internal email logging statement', () {
    final lines = _loggingStatements();
    expect(
      lines.where((line) {
        final lower = line.toLowerCase();
        return lower.contains('email') || lower.contains('@');
      }),
      isEmpty,
    );
  });
}
