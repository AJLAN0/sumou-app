import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('pubspec version 1.4.0+5 is wired to iOS bundle values', () {
    final pubspec = _read('pubspec.yaml');
    final infoPlist = _read('ios/Runner/Info.plist');

    expect(
      RegExp(r'^version:\s*1\.4\.0\+5\s*$', multiLine: true).hasMatch(pubspec),
      isTrue,
    );
    expect(
      infoPlist,
      contains(
        '<key>CFBundleShortVersionString</key>\n\t<string>\$(FLUTTER_BUILD_NAME)</string>',
      ),
    );
    expect(
      infoPlist,
      contains(
        '<key>CFBundleVersion</key>\n\t<string>\$(FLUTTER_BUILD_NUMBER)</string>',
      ),
    );
  });

  test('Git ignores the local DEV config but tracks its example', () {
    final ignored = Process.runSync('git', [
      'check-ignore',
      '--quiet',
      'config/dev.json',
    ]);
    final example = Process.runSync('git', [
      'check-ignore',
      '--quiet',
      'config/dev.example.json',
    ]);

    expect(ignored.exitCode, 0);
    expect(example.exitCode, isNot(0));
    expect(File('config/dev.example.json').existsSync(), isTrue);
  });

  test(
    'production configuration accepts only URL and publishable key inputs',
    () {
      final config = _read('lib/core/config/supabase_config.dart');
      final bootstrap = _read('lib/app/bootstrap.dart');
      final example = _read('config/dev.example.json');
      final executable = '$config\n$bootstrap\n$example'.replaceAll(
        RegExp(r'^\s*///?.*$', multiLine: true),
        '',
      );

      expect(executable, contains("String.fromEnvironment('SUPABASE_URL')"));
      expect(
        executable,
        contains("String.fromEnvironment('SUPABASE_ANON_KEY')"),
      );
      expect(bootstrap, contains('publishableKey: resolved.anonKey'));
      expect(
        RegExp(
          r'\b(?:service_role|SUPABASE_SERVICE_ROLE|serviceRole)\b',
          caseSensitive: false,
        ).allMatches(executable),
        isEmpty,
      );
    },
  );

  test('iOS release wiring imports Flutter-generated DART_DEFINES', () {
    final releaseConfig = _read('ios/Flutter/Release.xcconfig');
    final xcodeProject = _read('ios/Runner.xcodeproj/project.pbxproj');

    expect(releaseConfig, contains('#include "Generated.xcconfig"'));
    expect(
      xcodeProject,
      contains('flutter_tools/bin/xcode_backend.sh\\" build'),
    );
  });

  test('iOS minimum deployment target is consistently 13.0', () {
    final podfile = _read('ios/Podfile');
    final frameworkPlist = _read('ios/Flutter/AppFrameworkInfo.plist');
    final xcodeProject = _read('ios/Runner.xcodeproj/project.pbxproj');
    final xcodeTargets =
        RegExp(
          r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
        ).allMatches(xcodeProject).map((match) => match.group(1)).toSet();

    expect(podfile, contains("platform :ios, '13.0'"));
    expect(
      frameworkPlist,
      contains('<key>MinimumOSVersion</key>\n  <string>13.0</string>'),
    );
    expect(xcodeTargets, {'13.0'});
  });
}
