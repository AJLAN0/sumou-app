import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/core/config/supabase_config.dart';

/// A standard-shaped (but fake) hosted DEV URL — 20-char ref. Never real.
const _fakeUrl = 'https://abcdefghijklmnopqrst.supabase.co';

/// A realistic (but fake) key value. Never a real key.
const _fakeKey = 'sb_publishable_fake_value_for_tests_only';

SupabaseConfig _cfg(String url, String key) =>
    SupabaseConfig.from(rawUrl: url, rawAnonKey: key);

void main() {
  group('SupabaseConfig.validate — happy path', () {
    test('valid standard hosted URL passes', () {
      final c = _cfg(_fakeUrl, _fakeKey);
      expect(c.validate(), isNull);
      expect(c.isValid, isTrue);
      expect(c.isComplete, isTrue);
    });

    test('a single trailing slash is accepted', () {
      expect(_cfg('$_fakeUrl/', _fakeKey).validate(), isNull);
    });
  });

  group('SupabaseConfig.validate — missing / whitespace / key', () {
    test('missing SUPABASE_URL', () {
      final c = _cfg('', _fakeKey);
      expect(c.validate(), SupabaseConfigError.missingUrl);
      expect(c.isComplete, isFalse);
    });

    test('missing SUPABASE_ANON_KEY', () {
      final c = _cfg(_fakeUrl, '');
      expect(c.validate(), SupabaseConfigError.missingAnonKey);
      expect(c.isComplete, isFalse);
    });

    test('whitespace-only values are treated as missing (trimmed)', () {
      expect(_cfg('   ', _fakeKey).validate(), SupabaseConfigError.missingUrl);
      expect(
        _cfg(_fakeUrl, '   ').validate(),
        SupabaseConfigError.missingAnonKey,
      );
    });

    test('placeholder anon key is rejected', () {
      for (final k in const [
        'your-anon-key',
        'your-publishable-key',
        'your-publishable-or-anon-key',
      ]) {
        expect(
          _cfg(_fakeUrl, k).validate(),
          SupabaseConfigError.placeholderAnonKey,
          reason: 'expected "$k" rejected',
        );
      }
    });
  });

  group('SupabaseConfig.validate — URL shape (hosted Supabase only)', () {
    test('malformed URL is rejected', () {
      expect(_cfg('not a url', _fakeKey).validate(), isNotNull);
      expect(_cfg('not a url', _fakeKey).isValid, isFalse);
    });

    test('non-HTTPS URL is rejected as notHttps', () {
      expect(
        _cfg('http://abcdefghijklmnopqrst.supabase.co', _fakeKey).validate(),
        SupabaseConfigError.notHttps,
      );
    });

    test('placeholder URL is rejected as placeholderUrl', () {
      expect(
        _cfg('https://your-project.supabase.co', _fakeKey).validate(),
        SupabaseConfigError.placeholderUrl,
      );
    });

    test('rejects non-Supabase and non-standard hosted URLs', () {
      const rejected = <String>[
        'https://example.com',
        'https://abc.supabase.co', // ref too short
        'https://ABCDEFGHIJKLMNOPQRST.supabase.co', // uppercase ref
        'https://abcdefghijklmnopqrst.supabase.co/path', // path
        'https://abcdefghijklmnopqrst.supabase.co?x=1', // query
        'https://abcdefghijklmnopqrst.supabase.co#fragment', // fragment
        'https://user@abcdefghijklmnopqrst.supabase.co', // userInfo
        'https://abcdefghijklmnopqrst.supabase.co:8443', // explicit port
      ];
      for (final u in rejected) {
        expect(
          _cfg(u, _fakeKey).validate(),
          SupabaseConfigError.invalidUrl,
          reason: 'expected "$u" rejected as invalidUrl',
        );
      }
    });
  });

  group('requireValid', () {
    test('throws SupabaseConfigException when invalid', () {
      expect(
        () => _cfg('', '').requireValid(),
        throwsA(isA<SupabaseConfigException>()),
      );
    });

    test('returns the config when valid', () {
      expect(_cfg(_fakeUrl, _fakeKey).requireValid(), isA<SupabaseConfig>());
    });
  });

  group('anon key is never exposed', () {
    const secret = 'sb_publishable_super_secret_do_not_leak_123456';
    final c = _cfg(_fakeUrl, secret);

    test('toString does not contain the anon key', () {
      expect(c.toString().contains(secret), isFalse);
      expect(c.toString(), contains('<redacted>'));
      // the (public) URL may appear.
      expect(c.toString(), contains('abcdefghijklmnopqrst.supabase.co'));
    });

    test('exception message/toString do not contain the anon key', () {
      final ex = SupabaseConfigException(
        SupabaseConfigError.placeholderAnonKey,
      );
      expect(ex.message.contains(secret), isFalse);
      expect(ex.toString().contains(secret), isFalse);
    });
  });
}
