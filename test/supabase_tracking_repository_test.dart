import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sumou_app/data/repositories/supabase/supabase_tracking_repository.dart';
import 'package:sumou_app/data/repositories/supabase/tracking_gateway.dart';
import 'package:sumou_app/data/repositories/tracking_repository.dart';

class _FakeTrackingGateway implements TrackingGateway {
  Object? response;
  Object? error;
  int calls = 0;
  final List<String> serials = [];

  @override
  Future<Object?> trackProjectBySerial(String serial) async {
    calls += 1;
    serials.add(serial);
    if (error case final failure?) throw failure;
    return response;
  }
}

Map<String, dynamic> _validResponse({
  String serial = 'FLD-A1B2-C3',
  String status = 'active',
  Object? links,
}) => {
  'serial': serial,
  'project_name': 'مشروع تجريبي',
  'client_name': 'عميل تجريبي',
  'status': status,
  'links': links ?? <Object?>[],
};

Matcher _failure(TrackingRepositoryFailure reason) =>
    isA<TrackingRepositoryException>().having(
      (error) => error.reason,
      'reason',
      reason,
    );

void main() {
  group('SupabaseTrackingRepository input and RPC boundary', () {
    test('normalizes trim and uppercase before one gateway call', () async {
      final gateway =
          _FakeTrackingGateway()
            ..response = _validResponse(serial: 'SOC-9Z8Y-X7');
      final repository = SupabaseTrackingRepository.withGateway(gateway);

      final result = await repository.trackBySerial('  soc-9z8y-x7  ');

      expect(result?.serial, 'SOC-9Z8Y-X7');
      expect(gateway.serials, ['SOC-9Z8Y-X7']);
    });

    for (final serial in ['FLD-A1B2-C3', 'SOC-9Z8Y-X7', 'WED-0000-AA']) {
      test('accepts $serial', () async {
        final gateway =
            _FakeTrackingGateway()..response = _validResponse(serial: serial);
        final result = await SupabaseTrackingRepository.withGateway(
          gateway,
        ).trackBySerial(serial);

        expect(result?.serial, serial);
        expect(gateway.calls, 1);
      });
    }

    test(
      'malformed and blank inputs return neutral null without RPC',
      () async {
        final gateway = _FakeTrackingGateway()..response = _validResponse();
        final repository = SupabaseTrackingRepository.withGateway(gateway);

        for (final serial in ['', '   ', 'NOPE', 'FLD-123-AB', 'NAS-7K2M-9X']) {
          expect(await repository.trackBySerial(serial), isNull);
        }
        expect(gateway.calls, 0);
      },
    );

    test('null RPC response returns neutral null', () async {
      final gateway = _FakeTrackingGateway();

      expect(
        await SupabaseTrackingRepository.withGateway(
          gateway,
        ).trackBySerial('FLD-A1B2-C3'),
        isNull,
      );
      expect(gateway.calls, 1);
    });

    test('gateway uses exact RPC and argument only', () {
      final source =
          File(
            'lib/data/repositories/supabase/tracking_gateway.dart',
          ).readAsStringSync();

      expect(source, contains("'track_project_by_serial'"));
      expect(source, contains("params: {'project_serial': serial}"));
      expect('track_project_by_serial'.allMatches(source), hasLength(1));
      expect('project_serial'.allMatches(source), hasLength(1));
      expect(source, isNot(contains('.from(')));
    });
  });

  group('SupabaseTrackingRepository strict response parsing', () {
    test('hydrates the exact minimized active model', () async {
      final gateway =
          _FakeTrackingGateway()
            ..response = _validResponse(
              links: [
                {'label': 'الصور', 'url': 'https://client.test/photos'},
              ],
            );

      final result = await SupabaseTrackingRepository.withGateway(
        gateway,
      ).trackBySerial('FLD-A1B2-C3');

      expect(result, isNotNull);
      expect(result!.status, 'active');
      expect(result.projectName, 'مشروع تجريبي');
      expect(result.clientName, 'عميل تجريبي');
      expect(result.approvedLinks.single.label, 'الصور');
      expect(result.message, isNull);
      expect(result.rating, isNull);
      expect(
        () => result.approvedLinks.add(result.approvedLinks.single),
        throwsUnsupportedError,
      );
    });

    test('accepts done status and empty links', () async {
      final gateway =
          _FakeTrackingGateway()..response = _validResponse(status: 'done');

      final result = await SupabaseTrackingRepository.withGateway(
        gateway,
      ).trackBySerial('FLD-A1B2-C3');

      expect(result?.status, 'done');
      expect(result?.approvedLinks, isEmpty);
    });

    test('preserves multiple links in backend order', () async {
      final gateway =
          _FakeTrackingGateway()
            ..response = _validResponse(
              links: [
                {'label': 'الأول', 'url': 'https://client.test/1'},
                {'label': 'الثاني', 'url': 'http://client.test/2'},
              ],
            );

      final result = await SupabaseTrackingRepository.withGateway(
        gateway,
      ).trackBySerial('FLD-A1B2-C3');

      expect(result!.approvedLinks.map((link) => link.label), [
        'الأول',
        'الثاني',
      ]);
    });

    test('rejects a non-map outer response', () async {
      final gateway = _FakeTrackingGateway()..response = <Object?>[];
      await expectLater(
        SupabaseTrackingRepository.withGateway(
          gateway,
        ).trackBySerial('FLD-A1B2-C3'),
        throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
      );
    });

    test('rejects missing and extra outer keys', () async {
      for (final response in [
        _validResponse()..remove('client_name'),
        {..._validResponse(), 'project_id': 'secret'},
      ]) {
        final gateway = _FakeTrackingGateway()..response = response;
        await expectLater(
          SupabaseTrackingRepository.withGateway(
            gateway,
          ).trackBySerial('FLD-A1B2-C3'),
          throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
        );
      }
    });

    test('rejects unknown status instead of defaulting to active', () async {
      final gateway =
          _FakeTrackingGateway()
            ..response = _validResponse(status: 'pending_closure');
      await expectLater(
        SupabaseTrackingRepository.withGateway(
          gateway,
        ).trackBySerial('FLD-A1B2-C3'),
        throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
      );
    });

    test('rejects malformed or mismatched returned serial', () async {
      for (final serial in ['FLD-ABC-DE', 'SOC-A1B2-C3']) {
        final gateway =
            _FakeTrackingGateway()..response = _validResponse(serial: serial);
        await expectLater(
          SupabaseTrackingRepository.withGateway(
            gateway,
          ).trackBySerial('FLD-A1B2-C3'),
          throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
        );
      }
    });

    test('rejects blank project and client names', () async {
      for (final key in ['project_name', 'client_name']) {
        final response = _validResponse()..[key] = '   ';
        final gateway = _FakeTrackingGateway()..response = response;
        await expectLater(
          SupabaseTrackingRepository.withGateway(
            gateway,
          ).trackBySerial('FLD-A1B2-C3'),
          throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
        );
      }
    });

    test('rejects malformed links container and item', () async {
      for (final links in <Object?>[
        {'label': 'x'},
        ['not-a-map'],
      ]) {
        final gateway =
            _FakeTrackingGateway()..response = _validResponse(links: links);
        await expectLater(
          SupabaseTrackingRepository.withGateway(
            gateway,
          ).trackBySerial('FLD-A1B2-C3'),
          throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
        );
      }
    });

    test('rejects missing or extra link keys', () async {
      for (final link in <Map<String, dynamic>>[
        {'label': 'x'},
        {'label': 'x', 'url': 'https://client.test/x', 'project_id': 'secret'},
      ]) {
        final gateway =
            _FakeTrackingGateway()..response = _validResponse(links: [link]);
        await expectLater(
          SupabaseTrackingRepository.withGateway(
            gateway,
          ).trackBySerial('FLD-A1B2-C3'),
          throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
        );
      }
    });

    test('rejects blank labels and non-http URLs', () async {
      for (final link in <Map<String, dynamic>>[
        {'label': '   ', 'url': 'https://client.test/x'},
        {'label': 'ملفات', 'url': 'ftp://client.test/x'},
        {'label': 'ملفات', 'url': 'not-a-url'},
      ]) {
        final gateway =
            _FakeTrackingGateway()..response = _validResponse(links: [link]);
        await expectLater(
          SupabaseTrackingRepository.withGateway(
            gateway,
          ).trackBySerial('FLD-A1B2-C3'),
          throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
        );
      }
    });
  });

  group('SupabaseTrackingRepository safe failures', () {
    test('server or network failure maps safely without retry', () async {
      final gateway =
          _FakeTrackingGateway()
            ..error = StateError('raw token internal@example.test');

      await expectLater(
        SupabaseTrackingRepository.withGateway(
          gateway,
        ).trackBySerial('FLD-A1B2-C3'),
        throwsA(_failure(TrackingRepositoryFailure.loadFailed)),
      );
      expect(gateway.calls, 1);
    });

    test(
      'submitReview is unsupported and performs zero gateway calls',
      () async {
        final gateway = _FakeTrackingGateway()..response = _validResponse();
        final repository = SupabaseTrackingRepository.withGateway(gateway);

        await expectLater(
          repository.submitReview(
            serial: 'FLD-A1B2-C3',
            rating: 5,
            message: 'شكراً',
          ),
          throwsA(_failure(TrackingRepositoryFailure.unsupportedOperation)),
        );
        expect(gateway.calls, 0);
      },
    );

    test('tracking implementation has no tables, writes, or service role', () {
      final source = [
        File(
          'lib/data/repositories/supabase/tracking_gateway.dart',
        ).readAsStringSync(),
        File(
          'lib/data/repositories/supabase/supabase_tracking_repository.dart',
        ).readAsStringSync(),
      ].join('\n');

      expect(source, isNot(contains('service_role')));
      expect(source, isNot(contains('.from(')));
      expect(source, isNot(contains('.insert(')));
      expect(source, isNot(contains('.update(')));
      expect(source, isNot(contains('.upsert(')));
      expect(source, isNot(contains('.delete(')));
      expect(source, isNot(contains('project_id')));
      expect(source, isNot(contains('team_members')));
      expect(source, isNot(contains('assignment_value')));
      expect(source, isNot(contains('closure_request')));
      expect(source, isNot(contains('audit_logs')));
    });
  });
}
