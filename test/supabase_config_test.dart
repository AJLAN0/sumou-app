import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/config/supabase_config.dart';

/// A realistic (but fake) DEV-shaped configuration. Not a real key.
SupabaseConfig _valid() => SupabaseConfig.from(
  rawUrl: 'https://abcdefghijklmnopqrst.supabase.co',
  rawAnonKey: 'sb_publishable_fake_value_for_tests_only',
);

void main() {
  group('SupabaseConfig.validate', () {
    test('valid DEV-like config passes', () {
      final c = _valid();
      expect(c.validate(), isNull);
      expect(c.isValid, isTrue);
      expect(c.isComplete, isTrue);
    });

    test('missing SUPABASE_URL', () {
      final c = SupabaseConfig.from(rawUrl: '', rawAnonKey: 'sb_publishable_x');
      expect(c.validate(), SupabaseConfigError.missingUrl);
      expect(c.isComplete, isFalse);
    });

    test('missing SUPABASE_ANON_KEY', () {
      final c = SupabaseConfig.from(
        rawUrl: 'https://abc.supabase.co',
        rawAnonKey: '',
      );
      expect(c.validate(), SupabaseConfigError.missingAnonKey);
      expect(c.isComplete, isFalse);
    });

    test('whitespace-only values are treated as missing (trimmed)', () {
      final url = SupabaseConfig.from(rawUrl: '   ', rawAnonKey: 'sb_x');
      expect(url.validate(), SupabaseConfigError.missingUrl);
      final key = SupabaseConfig.from(
        rawUrl: 'https://abc.supabase.co',
        rawAnonKey: '   ',
      );
      expect(key.validate(), SupabaseConfigError.missingAnonKey);
    });

    test('malformed URL is rejected', () {
      final c = SupabaseConfig.from(rawUrl: 'not a url', rawAnonKey: 'sb_x');
      expect(c.validate(), SupabaseConfigError.invalidUrl);
      expect(c.isValid, isFalse);
    });

    test('URL without a dotted host is rejected', () {
      final c = SupabaseConfig.from(
        rawUrl: 'https://localhost',
        rawAnonKey: 'sb_x',
      );
      expect(c.validate(), SupabaseConfigError.invalidUrl);
    });

    test('non-HTTPS URL is rejected', () {
      final c = SupabaseConfig.from(
        rawUrl: 'http://abc.supabase.co',
        rawAnonKey: 'sb_x',
      );
      expect(c.validate(), SupabaseConfigError.notHttps);
    });

    test('placeholder URL is rejected', () {
      final c = SupabaseConfig.from(
        rawUrl: 'https://your-project.supabase.co',
        rawAnonKey: 'sb_publishable_x',
      );
      expect(c.validate(), SupabaseConfigError.placeholderUrl);
    });

    test('placeholder anon key is rejected', () {
      for (final k in const [
        'your-anon-key',
        'your-publishable-key',
        'your-publishable-or-anon-key',
      ]) {
        final c = SupabaseConfig.from(
          rawUrl: 'https://abc.supabase.co',
          rawAnonKey: k,
        );
        expect(
          c.validate(),
          SupabaseConfigError.placeholderAnonKey,
          reason: 'expected "$k" rejected',
        );
      }
    });

    test('requireValid throws SupabaseConfigException when invalid', () {
      expect(
        () => SupabaseConfig.from(rawUrl: '', rawAnonKey: '').requireValid(),
        throwsA(isA<SupabaseConfigException>()),
      );
      expect(_valid().requireValid(), isA<SupabaseConfig>());
    });
  });

  group('anon key is never exposed', () {
    const secret = 'sb_publishable_super_secret_do_not_leak_123456';
    final c = SupabaseConfig.from(
      rawUrl: 'https://abc.supabase.co',
      rawAnonKey: secret,
    );

    test('toString does not contain the anon key', () {
      expect(c.toString().contains(secret), isFalse);
      expect(c.toString(), contains('<redacted>'));
      // the (public) URL may appear.
      expect(c.toString(), contains('abc.supabase.co'));
    });

    test('exception message does not contain the anon key', () {
      final ex = SupabaseConfigException(
        SupabaseConfigError.placeholderAnonKey,
      );
      expect(ex.message.contains(secret), isFalse);
      expect(ex.toString().contains(secret), isFalse);
    });
  });
}
