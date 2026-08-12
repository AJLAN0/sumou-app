import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _authSources = <String>[
  'lib/features/auth/screens/login_screen.dart',
  'lib/features/auth/providers/auth_controller.dart',
  'lib/features/profile/change_password_screen.dart',
  'lib/data/repositories/supabase/auth_gateway.dart',
  'lib/data/repositories/supabase/supabase_auth_repository.dart',
];

List<File> _productionDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList(growable: false)
  ..sort((left, right) => left.path.compareTo(right.path));

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

String _productionSource() => _productionDartFiles()
    .map((file) => _withoutComments(file.readAsStringSync()))
    .join('\n');

List<String> _productionLoggingCalls() {
  final loggingCall = RegExp(
    r'\b(?:print|debugPrint|developer\.log|log)\s*\(([\s\S]{0,2000}?)\)\s*;',
    multiLine: true,
  );
  return [
    for (final file in _productionDartFiles())
      ...loggingCall
          .allMatches(_withoutComments(file.readAsStringSync()))
          .map((match) => '${file.path}:${match.group(0)}'),
  ];
}

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

  test('production Flutter exposes no service-role initialization path', () {
    final configurableProductionSource = <String>[
      _productionSource(),
      File('pubspec.yaml').readAsStringSync(),
      File('config/dev.example.json').readAsStringSync(),
    ].join('\n');

    expect(
      RegExp(
        r'\b(?:service_role|SUPABASE_SERVICE_ROLE|serviceRole)\b',
        caseSensitive: false,
      ).allMatches(configurableProductionSource),
      isEmpty,
    );
  });

  test('production logging sinks do not receive password values', () {
    final calls = _productionLoggingCalls();
    expect(
      calls.where(
        (call) => RegExp(
          r'password|current_password|new_password',
          caseSensitive: false,
        ).hasMatch(call),
      ),
      isEmpty,
    );
  });

  test('production logging sinks do not receive temporary passwords', () {
    final calls = _productionLoggingCalls();
    expect(
      calls.where(
        (call) => RegExp(
          r'temp(?:orary)?_?password|oneTimePassword',
          caseSensitive: false,
        ).hasMatch(call),
      ),
      isEmpty,
    );
  });

  test('production logging sinks do not receive JWT or access tokens', () {
    final calls = _productionLoggingCalls();
    expect(
      calls.where(
        (call) => RegExp(
          r'\b(?:jwt|access_?token|refresh_?token)\b',
          caseSensitive: false,
        ).hasMatch(call),
      ),
      isEmpty,
    );
  });

  test('production logging sinks do not receive Authorization headers', () {
    final calls = _productionLoggingCalls();
    expect(
      calls.where(
        (call) => RegExp(
          r'authorization|bearer',
          caseSensitive: false,
        ).hasMatch(call),
      ),
      isEmpty,
    );
  });

  test(
    'production logging sinks do not receive sensitive request payloads',
    () {
      final calls = _productionLoggingCalls();
      expect(
        calls.where(
          (call) => RegExp(
            r'\b(?:body|payload|request)\b',
            caseSensitive: false,
          ).hasMatch(call),
        ),
        isEmpty,
      );
    },
  );

  test('Auth administrative actions use approved Edge Functions only', () {
    final gateway = _withoutComments(
      File(
        'lib/data/repositories/supabase/user_gateway.dart',
      ).readAsStringSync(),
    );
    final repository = _withoutComments(
      File(
        'lib/data/repositories/supabase/supabase_user_repository.dart',
      ).readAsStringSync(),
    );
    final production = _productionSource();

    expect(
      gateway,
      contains("_client.functions.invoke(functionName, body: body)"),
    );
    expect(gateway, contains("_invoke('admin-create-user', body)"));
    expect(gateway, contains("_invoke('admin-reset-password', body)"));
    expect(repository, contains('_gateway.invokeCreateUser(body)'));
    expect(repository, contains('_gateway.invokeResetPassword('));
    expect(RegExp(r'\.auth\s*\.\s*admin\b').allMatches(production), isEmpty);
  });

  test(
    'excluded notification, FCM, push, reminder, payment, and Rekaz integrations remain absent',
    () {
      final production = _productionSource();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final notificationRepository = _withoutComments(
        File(
          'lib/data/repositories/notification_repository.dart',
        ).readAsStringSync(),
      );

      for (final prohibitedDependency in <String>[
        'firebase_messaging:',
        'flutter_local_notifications:',
        'in_app_purchase:',
        'stripe:',
      ]) {
        expect(pubspec, isNot(contains(prohibitedDependency)));
      }
      expect(
        RegExp(
          r"package:(?:firebase|firebase_messaging|flutter_local_notifications|stripe|in_app_purchase)|"
          r'\b(?:FirebaseMessaging|FlutterLocalNotificationsPlugin|fcmToken|pushToken|scheduleReminder|RekazClient)\b|'
          r'''\.from\s*\(\s*['"]notifications['"]\s*\)|'''
          r'''\.rpc\s*\(\s*['"]send_notification['"]''',
          caseSensitive: false,
        ).allMatches(production),
        isEmpty,
      );
      expect(
        RegExp(
          r'\b(?:Future|Stream|void)\s+\w+\s*\(',
        ).allMatches(notificationRepository),
        isEmpty,
      );
    },
  );
}
