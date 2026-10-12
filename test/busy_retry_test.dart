import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';

/// A busy model's turn is tried again once, by itself, with the same turn id
/// (design/plans/resilience.md §4.3). A second busy answer is shown as usual,
/// with its Retry, and other errors are never retried by themselves.
void main() {
  String sse(List<(String, Map<String, dynamic>)> frames) =>
      frames.map((f) => 'event: ${f.$1}\ndata: ${jsonEncode({'v': 1, 'seq': 0, 'type': f.$1, ...f.$2})}\n\n').join();

  final start = ('turn.start', <String, dynamic>{'conversation_id': 'c1', 'message_id': 'm1', 'request_id': 'r1'});
  final busy = ('error', <String, dynamic>{'code': 'model_busy', 'message': 'Busy.', 'retryable': true});
  final internal = ('error', <String, dynamic>{'code': 'internal', 'message': 'Oops.', 'retryable': true});
  (String, Map<String, dynamic>) end(String status) => ('turn.end', {'status': status, 'pending': <String>[]});
  final answer = [
    ('block.start', <String, dynamic>{'index': 0, 'id': 'b0', 'block_type': 'text'}),
    ('block.ready', <String, dynamic>{
      'index': 0,
      'block': {'id': 'b0', 'type': 'text', 'fallback_text': 'tamam', 'props': {'markdown': 'tamam'}},
    }),
  ];

  (ConversationController, List<Map<String, dynamic>>) setup(List<String> turns) {
    final bodies = <Map<String, dynamic>>[];
    final controller = ConversationController(
      api: RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
        httpClient: MockClient((request) async {
          if (!request.url.path.endsWith('/v1/chat')) return http.Response('{}', 200);
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(turns.removeAt(0), 200, headers: {'content-type': 'text/event-stream'});
        }),
      ),
      actions: const {},
      sdkVersion: 'flutter/test',
      autoRetryDelay: Duration.zero,
    );
    return (controller, bodies);
  }

  test('a busy model is tried once more by itself, with the same turn id', () async {
    final (controller, bodies) = setup([
      sse([start, busy, end('error')]),
      sse([start, ...answer, end('completed')]),
    ]);
    await controller.send('selam');
    expect(bodies, hasLength(2));
    expect(bodies[1]['turn_id'], bodies[0]['turn_id']);
    expect(controller.errorCode, isNull);
  });

  test('a second busy answer is shown, with its Retry', () async {
    final (controller, bodies) = setup([
      sse([start, busy, end('error')]),
      sse([start, busy, end('error')]),
    ]);
    await controller.send('selam');
    expect(bodies, hasLength(2));
    expect(controller.errorCode, 'model_busy');
    expect(controller.canRetry, isTrue);
  });

  test('other errors are not tried again by themselves', () async {
    final (controller, bodies) = setup([sse([start, internal, end('error')])]);
    await controller.send('selam');
    expect(bodies, hasLength(1));
    expect(controller.errorCode, 'internal');
  });
}
