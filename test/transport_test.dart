// The SSE parser, driven from bytes.
//
// Every other suite scripts `RendelApiClient.chat` wholesale, which means the code
// that turns a wire frame into an `RendelWireEvent` — the one piece of the SDK a
// server change can break without any Dart change at all — was never executed
// by a test.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rendel/rendel.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';

/// Replays a scripted SSE body, optionally with real time between frames.
class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.frames, {this.status = 200});

  final List<String> frames;
  final int status;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> body() async* {
      for (final frame in frames) {
        yield utf8.encode(frame);
      }
    }

    return http.StreamedResponse(body(), status);
  }
}

String frame(String event, Map<String, dynamic> data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

void main() {
  RendelApiClient client(_FakeHttp http) => RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
        httpClient: http,
      );

  test('a ping reaches the caller, so an idle timeout can see it', () async {
    // The server heartbeats every 15s precisely so a slow turn is not
    // mistaken for a dead one. Dropping pings inside the parser turned the
    // caller's idle timeout into a hard cap on how long the model may think
    // before its first block.
    final events = await client(_FakeHttp([
      frame('turn.start', {
        'v': 1,
        'seq': 0,
        'type': 'turn.start',
        'conversation_id': 'c1',
        'message_id': 'm1',
        'model': 'test',
      }),
      frame('ping', {'v': 1, 'seq': 1, 'type': 'ping'}),
      frame('turn.end', {
        'v': 1,
        'seq': 2,
        'type': 'turn.end',
        'status': 'completed',
        'pending': <String>[],
      }),
    ])).chat(const {}).toList();

    expect(events.whereType<Ping>(), hasLength(1));
    expect(events.first, isA<TurnStart>());
    expect(events.last, isA<TurnEnd>());
  });

  test('a frame the parser cannot read is skipped, not fatal', () async {
    // The forward-compatibility rule: a server that learns a new event type
    // must not break an old build.
    final events = await client(_FakeHttp([
      frame('turn.start', {
        'v': 1,
        'seq': 0,
        'type': 'turn.start',
        'conversation_id': 'c1',
        'message_id': 'm1',
        'model': 'test',
      }),
      'event: something.new\ndata: {"v":1,"seq":1,"type":"something.new"}\n\n',
      'event: block.ready\ndata: not json at all\n\n',
      frame('turn.end', {
        'v': 1,
        'seq': 3,
        'type': 'turn.end',
        'status': 'completed',
        'pending': <String>[],
      }),
    ])).chat(const {}).toList();

    expect(events, hasLength(2));
    expect(events.last, isA<TurnEnd>());
  });

  test('a non-200 yields one error and stops', () async {
    final events = await client(_FakeHttp(
      [jsonEncode({'error': {'code': 'invalid_key', 'message': 'Unknown key.'}})],
      status: 401,
    )).chat(const {}).toList();

    expect(events, hasLength(1));
    final error = events.single as RendelError;
    expect(error.code, 'invalid_key');
    expect(error.message, 'Unknown key.');
    expect(error.retryable, isFalse);
  });

  test('a 5xx is retryable; a 4xx is not', () async {
    final events = await client(_FakeHttp(['{}'], status: 503)).chat(const {}).toList();
    expect((events.single as RendelError).retryable, isTrue);
  });

  test('a body that is not the error envelope still reports the status',
      () async {
    final events = await client(_FakeHttp(['<html>gateway</html>'], status: 502))
        .chat(const {})
        .toList();
    final error = events.single as RendelError;
    expect(error.message, contains('502'));
  });

  group('the signed-in person\'s token', () {
    /// Records the request it was sent and answers an empty turn.
    http.BaseRequest? sent;
    final recorder = _Recording((request) => sent = request);
    RendelApiClient withToken(Future<String?> Function()? provider) => RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: RendelConfig(userToken: provider),
          httpClient: recorder,
        );

    test('goes with each question, asked for fresh', () async {
      var calls = 0;
      final api = withToken(() async => 'jwt-${++calls}');
      await api.chat(const {}).toList();
      expect(sent!.headers['X-Rendel-User-Token'], 'jwt-1');
      await api.chat(const {}).toList();
      expect(sent!.headers['X-Rendel-User-Token'], 'jwt-2');
    });

    test('is left out for someone not signed in', () async {
      await withToken(() async => null).chat(const {}).toList();
      expect(sent!.headers.containsKey('X-Rendel-User-Token'), isFalse);
    });

    test('a token call that throws costs the header, not the turn', () async {
      await withToken(() async => throw StateError('signed out')).chat(const {}).toList();
      expect(sent, isNotNull);
      expect(sent!.headers.containsKey('X-Rendel-User-Token'), isFalse);
    });
  });
}

/// Hands each request to [onSend] and answers with an empty stream.
class _Recording extends http.BaseClient {
  _Recording(this.onSend);

  final void Function(http.BaseRequest request) onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onSend(request);
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}
