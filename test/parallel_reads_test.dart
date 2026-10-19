import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';

/// Context providers and device reads run side by side (plan W7.2), up to
/// four at once, unless the server's `parallel_reads: false` puts them back
/// one after another; and a result too large for the server fails the action
/// rather than the turn.
class _Turns extends RendelApiClient {
  _Turns(this.turns)
      : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<List<RendelWireEvent>> turns;
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) async* {
    sent.add(body);
    for (final event in turns[sent.length - 1]) {
      yield event;
    }
  }
}

const _start = TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test');

List<RendelWireEvent> _reads(List<String> names) => [
      _start,
      for (var i = 0; i < names.length; i++)
        ActionExecute(invocationId: 'i$i', name: names[i], params: const {}, timeoutMs: 15000),
      const TurnEnd(status: 'awaiting_tool_results', pending: []),
    ];

final _answer = <RendelWireEvent>[
  _start,
  BlockReady(
    index: 0,
    block: WireBlock(id: 'b0', type: 'text', fallbackText: 'ok', props: const {'markdown': 'ok'})..ready = true,
  ),
  const TurnEnd(status: 'completed', pending: []),
];

RendelAction _read(String name, Future<RendelResult> Function() run) => RendelAction(
      name: name,
      description: 'A read.',
      params: RendelSchema.object({}),
      risk: RendelRisk.read,
      handler: (_) => run(),
    );

/// A handler that counts how many of its kind are running at once.
class _Gauge {
  int running = 0;
  int peak = 0;

  Future<RendelResult> call() async {
    peak = max(peak, ++running);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    running--;
    return RendelResult.ok({'ok': true});
  }
}

void main() {
  final logs = <RendelLogRecord>[];
  setUp(() {
    logs.clear();
    RendelLog.sink = logs.add;
  });
  tearDown(() => RendelLog.sink = null);

  ConversationController build(
    _Turns api,
    Map<String, RendelAction> actions, {
    Map<String, Future<Map<String, dynamic>> Function()> providers = const {},
    bool parallel = true,
  }) =>
      ConversationController(
        api: api,
        actions: actions,
        sdkVersion: 'flutter/test',
        contextProviders: providers,
        parallelReads: () => parallel,
      );

  test('two 300 ms reads finish in about 300 ms, each result under its own invocation', () async {
    final api = _Turns([_reads(['slow', 'slower']), _answer]);
    final c = build(api, {
      'slow': _read('slow', () async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return RendelResult.ok({'n': 1});
      }),
      // Finishes first; still listed second, where the server asked for it.
      'slower': _read('slower', () async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return RendelResult.ok({'n': 2});
      }),
    });
    final clock = Stopwatch()..start();
    await c.send('both').timeout(const Duration(seconds: 5));
    expect(clock.elapsedMilliseconds, lessThan(500));
    expect(api.sent[1]['tool_results'], [
      {'invocation_id': 'i0', 'status': 'success', 'data': {'n': 1}},
      {'invocation_id': 'i1', 'status': 'success', 'data': {'n': 2}},
    ]);
  });

  test('at most four reads run at once, and the list keeps the server order', () async {
    final gauge = _Gauge();
    final names = ['a', 'b', 'c', 'd', 'e', 'f'];
    final api = _Turns([_reads(names), _answer]);
    final c = build(api, {for (final n in names) n: _read(n, gauge.call)});
    await c.send('six').timeout(const Duration(seconds: 5));
    expect(gauge.peak, 4);
    expect(
      (api.sent[1]['tool_results'] as List).map((r) => (r as Map)['invocation_id']),
      ['i0', 'i1', 'i2', 'i3', 'i4', 'i5'],
    );
  });

  test('one at a time when the server turned parallel reads off', () async {
    final gauge = _Gauge();
    final api = _Turns([_reads(['a', 'b', 'c']), _answer]);
    final c = build(api, {for (final n in ['a', 'b', 'c']) n: _read(n, gauge.call)}, parallel: false);
    await c.send('in turn').timeout(const Duration(seconds: 5));
    expect(gauge.peak, 1);
    expect(
      (api.sent[1]['tool_results'] as List).map((r) => (r as Map)['invocation_id']),
      ['i0', 'i1', 'i2'],
    );
  });

  test('every context provider is asked at once, each within its own budget, in its own order', () async {
    final api = _Turns([_answer]);
    final c = build(api, const {}, providers: {
      'cart': () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return {'items': 2};
      },
      'stuck': () => Completer<Map<String, dynamic>>().future,
      'profile': () async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return {'tier': 'gold'};
      },
    });
    final clock = Stopwatch()..start();
    await c.send('my cart').timeout(const Duration(seconds: 5));
    // One 300 ms budget for all of them, not 300 + 200 + 150.
    expect(clock.elapsedMilliseconds, lessThan(550));
    final state = (api.sent[0]['context'] as Map)['app_state'] as Map;
    expect(state.keys.toList(), ['cart', 'profile']);
    expect(state, {
      'cart': {'items': 2},
      'profile': {'tier': 'gold'},
    });
    expect(logs.map((r) => r.code), contains('context_provider_timeout'));
  });

  test('a result over 16,384 characters fails the action, not the turn', () async {
    final api = _Turns([_reads(['huge', 'fits']), _answer]);
    final c = build(api, {
      'huge': _read('huge', () async => RendelResult.ok({'blob': 'x' * 20000})),
      // Exactly at the limit: {"blob":"…"} is 11 characters around the text.
      'fits': _read('fits', () async => RendelResult.ok({'blob': 'x' * (16384 - 11)})),
    });
    await c.send('big').timeout(const Duration(seconds: 5));
    final results = (api.sent[1]['tool_results'] as List).cast<Map<String, dynamic>>();
    expect(results[0]['status'], 'error');
    expect(results[0]['error'], contains('16384'));
    expect(results[0].containsKey('data'), isFalse);
    expect(results[1]['status'], 'success');
    expect(logs.map((r) => r.code), contains('result_too_large'));
  });

  group('the switch in the app config', () {
    test('is on unless the server says parallel_reads: false', () {
      expect(RendelRemoteConfig.tryParse('{"config": {}}')!.parallelReads, isTrue);
      expect(RendelRemoteConfig.tryParse('{"config": {}, "parallel_reads": true}')!.parallelReads, isTrue);
      expect(RendelRemoteConfig.tryParse('{"config": {}, "parallel_reads": false}')!.parallelReads, isFalse);
    });

    test('survives the cache, so a 304 on the next launch keeps it off', () {
      final off = RendelRemoteConfig.tryParse('{"config": {}, "parallel_reads": false}', etag: '"e"')!;
      expect(RendelRemoteConfig.tryParse(off.toCache())!.parallelReads, isFalse);
      final on = RendelRemoteConfig.tryParse('{"config": {}}', etag: '"e"')!;
      expect(on.toCache(), isNot(contains('parallel_reads')));
    });
  });
}
