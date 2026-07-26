import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/data/repositories/supabase/auth_identity.dart';

void main() {
  group('AuthIdentity.normalize', () {
    test('trims and lowercases', () {
      expect(AuthIdentity.normalize('  Admin.One '), 'admin.one');
      expect(AuthIdentity.normalize('USER_2'), 'user_2');
    });
  });

  group('AuthIdentity.isValid', () {
    test('accepts valid characters', () {
      expect(AuthIdentity.isValid('admin'), isTrue);
      expect(AuthIdentity.isValid('a.b-c_1'), isTrue);
      expect(AuthIdentity.isValid('user123'), isTrue);
    });

    test('rejects invalid characters', () {
      expect(AuthIdentity.isValid('Admin'), isFalse); // uppercase
      expect(AuthIdentity.isValid('has space'), isFalse);
      expect(AuthIdentity.isValid('bad@char'), isFalse);
      expect(AuthIdentity.isValid('emoji😀'), isFalse);
    });

    test('rejects too short / too long', () {
      expect(AuthIdentity.isValid('a'), isFalse); // 1 char
      expect(AuthIdentity.isValid('ab'), isTrue); // 2 chars ok
      expect(AuthIdentity.isValid('x' * 50), isTrue);
      expect(AuthIdentity.isValid('x' * 51), isFalse);
    });
  });

  group('AuthIdentity.internalEmailFor', () {
    test(
      'builds the correct hidden internal identity for a valid username',
      () {
        expect(
          AuthIdentity.internalEmailFor('  Admin.One '),
          'admin.one@users.sumou.internal',
        );
      },
    );

    test(
      'returns null for an invalid username (so login fails pre-network)',
      () {
        expect(AuthIdentity.internalEmailFor('a'), isNull);
        expect(AuthIdentity.internalEmailFor('bad char'), isNull);
        expect(AuthIdentity.internalEmailFor('x' * 51), isNull);
      },
    );
  });
}
