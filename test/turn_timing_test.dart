import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';

/// Each request as the device lived it (optimisation 6.1): the moments from
/// the question, or from the device's reads ready, sent for the server to
/// keep beside its own numbers, as the web SDK sends them.
class _Turns extends RendelApiClient {
  _Turns(this.turns) : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<List<RendelWireEvent>> turns;
  final List<Map<String, dynamic>> sent = [];
  final List<Map<String, dynamic>> events = [];

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) async* {
    sent.add(body);
    for (final event in turns[sent.length - 1]) {
      yield event;
    }
  }

  @override
  Future<void> sendEvent(Map<String, dynamic> event) async => events.add(event);
}

TurnStart _start(String? requestId) => TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test', requestId: requestId);

List<RendelWireEvent> _answer(String? requestId) => [
      _start(requestId),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      const BlockDelta(index: 0, textDelta: 'Kargoda'),
      BlockReady(
        index: 0,
        block: WireBlock(id: 'b0', type: 'text', fallbackText: 'Kargoda', props: const {'markdown': 'Kargoda'})..ready = true,
      ),
      const TurnEnd(status: 'completed', pending: []),
    ];

void main() {
  ConversationController build(_Turns api, [Map<String, RendelAction> actions = const {}]) =>
      ConversationController(api: api, actions: actions, sdkVersion: 'flutter/test');

  test('a question sends its moments once its request ends, in order', () async {
    final api = _Turns([_answer('r1')]);
    await build(api).send('Siparişim nerede?');
    expect(api.events, hasLength(1));
    final timing = api.events.single;
    expect(timing['type'], 'turn_timing');
    expect(timing['request_id'], 'r1');
    expect(timing.keys.toSet(), {'type', 'request_id', 'prep_ms', 'first_event_ms', 'first_block_ms', 'first_ready_ms', 'end_ms'});
    final moments = [for (final k in ['prep_ms', 'first_event_ms', 'first_block_ms', 'first_ready_ms', 'end_ms']) timing[k] as int];
    for (var i = 1; i < moments.length; i++) {
      expect(moments[i], greaterThanOrEqualTo(moments[i - 1]));
    }
  });

  test("the request that asked for the device's reads carries how long they took", () async {
    final api = _Turns([
      [
        _start('r1'),
        const ActionExecute(invocationId: 'i1', name: 'track_order', params: {}, timeoutMs: 15000),
        const TurnEnd(status: 'awaiting_tool_results', pending: []),
      ],
      _answer('r2'),
    ]);
    final read = RendelAction(
      name: 'track_order',
      description: 'A read.',
      params: RendelSchema.object({}),
      risk: RendelRisk.read,
      handler: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return RendelResult.ok({'status': 'shipped'});
      },
    );
    await build(api, {'track_order': read}).send('Siparişim nerede?');
    expect([for (final e in api.events) e['request_id']], ['r2', 'r1']);
    expect(api.events[1]['reads_ms'] as int, greaterThanOrEqualTo(60));
    expect(api.events[0].containsKey('reads_ms'), isFalse);
  });

  test('a request the server gave no id sends nothing', () async {
    final api = _Turns([_answer(null)]);
    await build(api).send('Siparişim nerede?');
    expect(api.events, isEmpty);
  });
}
