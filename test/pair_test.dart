// Pairing a test build with the console.
//
// The device's half is one request and a reading of its answer, and the
// answer is what a developer's own pairing screen shows, so every way the
// server can say no is pinned here to the reason and sentence it becomes.
// Through the real client and a fake server, as `confirm_test.dart` does: the
// headers are the point of half of these.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rendel/rendel.dart';
import 'package:rendel/src/transport/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RendelApiClient client(_Server server) => RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd' * 32,
        config: const RendelConfig(
          apiBaseUrl: 'https://api.example',
          languages: ['tr'],
        ),
        httpClient: server,
      );

  group('answering the console\'s pairing code', () {
    test('sends the code with the key and the device, as every call does',
        () async {
      final server = _Server(200, {'paired': true, 'ends_at': '2026-10-08T14:00:00.000Z'});
      await client(server).pair('K7Q2-M9XD');

      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.example/v1/pairings/claim');
      expect(jsonDecode(request.body), {'code': 'K7Q2-M9XD'});
      expect(request.headers['X-Rendel-Key'], 'nc_pk_test_x');
      expect(request.headers['X-Rendel-Device'], 'd' * 32);
      expect(request.headers['Accept-Language'], 'tr');
      expect(request.headers['Content-Type'], startsWith('application/json'));
    });

    test('is paired until the time the server gives', () async {
      final result = await client(
        _Server(200, {'paired': true, 'ends_at': '2026-10-08T14:00:00.000Z'}),
      ).pair('K7Q2M9XD');
      expect(result.ok, isTrue);
      expect(result.endsAt, '2026-10-08T14:00:00.000Z');
      expect(result.reason, isNull);
      expect(result.message, isNull);
    });

    final refusals = <String, (int, Object?, RendelPairFailure, String)>{
      'a live key': (
        403,
        {
          'error': {'code': 'pairing_test_only', 'message': "Pairing works with the app's test key."}
        },
        RendelPairFailure.testOnly,
        "Pairing works with the app's test key.",
      ),
      'a wrong, used or old code': (
        404,
        {
          'error': {'code': 'pairing_not_found', 'message': 'That code is not valid any more.'}
        },
        RendelPairFailure.notFound,
        'That code is not valid any more.',
      ),
      'too many tries': (
        429,
        {
          'error': {'code': 'rate_limited'}
        },
        RendelPairFailure.rateLimited,
        'Too many tries. Wait a minute and try again.',
      ),
      'a malformed request': (
        400,
        {
          'error': {'code': 'invalid_request', 'message': 'Send { code } as the console shows it.'}
        },
        RendelPairFailure.failed,
        'Send { code } as the console shows it.',
      ),
      'an unknown key': (
        401,
        {
          'error': {'code': 'invalid_key'}
        },
        RendelPairFailure.failed,
        'Pairing failed (401, invalid_key).',
      ),
      'a suspended app, though it is a 403 like a live key': (
        403,
        {
          'error': {'code': 'quota_exceeded', 'message': 'This app is suspended.'}
        },
        RendelPairFailure.failed,
        'This app is suspended.',
      ),
      'a proxy\'s error page': (502, null, RendelPairFailure.failed, 'Pairing failed (502).'),
      'a 200 that is not a pairing': (
        200,
        {'ok': true},
        RendelPairFailure.failed,
        'Pairing failed (200).',
      ),
    };
    for (final MapEntry(key: name, value: (status, body, reason, message))
        in refusals.entries) {
      test('names $name', () async {
        final result = await client(_Server(status, body)).pair('K7Q2-M9XD');
        expect(result.ok, isFalse);
        expect(result.reason, reason);
        expect(result.message, message);
        expect(result.endsAt, isNull);
      });
    }

    test('answers a network that failed instead of throwing', () async {
      final result = await client(_Server.offline()).pair('K7Q2-M9XD');
      expect(result.ok, isFalse);
      expect(result.reason, RendelPairFailure.failed);
      expect(result.message, 'The server could not be reached.');
    });
  });

  group('Rendel.pair', () {
    late _Server server;
    late List<String> logs;

    setUp(() {
      server = _Server(200, {'paired': true, 'ends_at': '2026-10-08T14:00:00.000Z'});
      logs = [];
    });
    tearDown(Rendel.resetForTest);

    Future<void> init() => Rendel.init(
          appKey: 'nc_pk_test_x',
          config: RendelConfig(
            httpClient: server,
            remoteConfig: false,
            onLog: (record) => logs.add('${record.level.name}:${record.code}'),
          ),
        );

    test('made before init, waits for its client and goes out with the key',
        () async {
      final pairing = Rendel.pair('k7q2-m9xd');
      await Future<void>.delayed(Duration.zero);
      expect(server.requests, isEmpty);

      await init();
      final result = await pairing;

      expect(result.ok, isTrue);
      final claim = server.requests.singleWhere(
          (request) => request.url.path.endsWith('/v1/pairings/claim'));
      expect(claim.headers['X-Rendel-Key'], 'nc_pk_test_x');
      expect(claim.headers['X-Rendel-Device'], Rendel.deviceId);
    });

    test('reports each outcome on the log with a stable code', () async {
      await init();
      await Rendel.pair('K7Q2-M9XD');
      server.answer(404, {
        'error': {'code': 'pairing_not_found', 'message': 'That code is not valid any more.'}
      });
      await Rendel.pair('K7Q2-M9XD');
      server.answer(403, {
        'error': {'code': 'pairing_test_only', 'message': 'Test key only.'}
      });
      await Rendel.pair('K7Q2-M9XD');
      server.answer(429, {
        'error': {'code': 'rate_limited'}
      });
      await Rendel.pair('K7Q2-M9XD');

      expect(logs.where((l) => l.contains('pair')), [
        'debug:paired',
        'warning:pair_not_found',
        'warning:pair_test_only',
        'warning:pair_rate_limited',
      ]);
    });

    test('does not send a blank code', () async {
      await init();
      final result = await Rendel.pair('  ');
      expect(result.reason, RendelPairFailure.failed);
      // `init` sends its manifest, empty or not; nothing else goes out.
      expect(
        server.requests.where((r) => r.url.path.endsWith('/v1/pairings/claim')),
        isEmpty,
      );
    });

    // A widget test for its clock: the wait is ten seconds, and the test
    // should not take them.
    testWidgets('settles, saying why, when init never comes', (tester) async {
      RendelPairResult? result;
      unawaited(Rendel.pair('K7Q2-M9XD').then((r) => result = r));
      await tester.pump(const Duration(seconds: 9));
      expect(result, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(result?.reason, RendelPairFailure.failed);
      expect(server.requests, isEmpty);
    });
  });
}

/// One status and body for every request, and a record of what was sent.
class _Server extends http.BaseClient {
  _Server(this._status, this._body);

  _Server.offline()
      : _status = 0,
        _body = null,
        _offline = true;

  int _status;
  Object? _body;
  bool _offline = false;

  final List<http.Request> requests = [];

  void answer(int status, Object? body) {
    _status = status;
    _body = body;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_offline) throw const SocketLikeFailure();
    requests.add(request as http.Request);
    final text = _body == null ? '<html>Bad gateway</html>' : jsonEncode(_body);
    return http.StreamedResponse(Stream.value(utf8.encode(text)), _status);
  }
}

/// What a dropped connection looks like from above `package:http`.
class SocketLikeFailure implements Exception {
  const SocketLikeFailure();
}
