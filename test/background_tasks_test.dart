// Background tasks, phase 1b (Flutter 0.73.0): a yes carries the person and
// their token, so the server can run a write it makes as them at the tap; the
// app says when the person left the conversation (the sheet closed, the app
// put away) and when they are back; recover() asks for a cut answer until the
// server has it, and again when the app comes back to the front; and the
// launcher shows a dot while the sheet is closed and an answer finished
// unseen, or a card waits for the person. `support` is declared only once the
// app's config has Support on.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';

String _sse(List<Map<String, Object?>> events) => [
      for (final (seq, event) in events.indexed) 'event: ${event['type']}\ndata: ${jsonEncode({'v': 1, 'seq': seq, ...event})}\n\n',
    ].join();

const _answer = <Map<String, Object?>>[
  {'type': 'turn.start', 'conversation_id': 'c1', 'message_id': 'm1'},
  {'type': 'block.start', 'index': 0, 'id': 'b1', 'block_type': 'text'},
  {
    'type': 'block.ready',
    'index': 0,
    'block': {'id': 'b1', 'type': 'text', 'fallback_text': 'Your return has started.', 'props': {'markdown': 'Your return has started.'}},
  },
  {'type': 'turn.end', 'status': 'completed', 'pending': <String>[]},
];

const _card = <Map<String, Object?>>[
  {'type': 'turn.start', 'conversation_id': 'c1', 'message_id': 'm1'},
  {'type': 'block.start', 'index': 0, 'id': 'b1', 'block_type': 'confirm_card'},
  {
    'type': 'block.ready',
    'index': 0,
    'block': {
      'id': 'b1',
      'type': 'confirm_card',
      'fallback_text': 'Start the return?',
      'props': {
        'invocation_id': 'i1',
        'action_name': 'start_return',
        'summary': 'Start a return for order O-1?',
        'params': <String, Object>{},
        'params_display': <Object>[],
        'risk': 'write',
        'executes': 'server',
        'confirm': {'kind': 'confirm', 'invocation_id': 'i1'},
        'cancel': {'kind': 'cancel', 'invocation_id': 'i1'},
      },
    },
  },
  {'type': 'turn.end', 'status': 'awaiting_confirmation', 'pending': ['i1']},
];

/// The API: what each request was, and a turn that can be held open.
class _Server {
  final List<({String path, Map<String, String> headers, Object? body})> requests = [];
  List<Map<String, Object?>> turn = _answer;

  /// Set: the turn's stream holds after its first event until this is completed.
  Completer<void>? hold;

  /// What `/v1/conversations/c1/messages` answers, one list per fetch; the last repeats.
  List<List<Map<String, Object?>>> stored = [const []];
  int fetches = 0;

  List<Object?> away() => [for (final r in requests) if (r.path == '/v1/conversations/c1/away') r.body];

  late final client = MockClient.streaming((request, body) async {
    final path = request.url.path;
    final text = await utf8.decodeStream(body);
    requests.add((path: path, headers: request.headers, body: text.isEmpty ? null : jsonDecode(text)));
    http.StreamedResponse json(Object value) =>
        http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), 200, headers: {'content-type': 'application/json'});
    if (path == '/v1/apps/config') {
      return json({
        'channel': 'published',
        'version': null,
        'updated_at': null,
        'config': <String, Object>{},
      });
    }
    if (path == '/v1/chat') {
      final held = hold;
      if (held == null) {
        return http.StreamedResponse(Stream.value(utf8.encode(_sse(turn))), 200, headers: {'content-type': 'text/event-stream'});
      }
      final stream = StreamController<List<int>>();
      stream.add(utf8.encode(_sse(turn.sublist(0, 1))));
      unawaited(held.future.then((_) async {
        stream.add(utf8.encode(_sse(turn).split('\n\n').skip(1).join('\n\n')));
        await stream.close();
      }));
      return http.StreamedResponse(stream.stream, 200, headers: {'content-type': 'text/event-stream'});
    }
    if (path == '/v1/conversations/c1/messages') {
      final list = stored[fetches < stored.length ? fetches : stored.length - 1];
      fetches++;
      return json({'conversation_id': 'c1', 'messages': list});
    }
    if (path.endsWith('/confirm')) return json({'status': 'succeeded'});
    if (path.endsWith('/away')) return http.StreamedResponse(const Stream.empty(), 204);
    return json({'ok': true});
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The app with Rendel's launcher, and a way to ask from the open sheet.
Future<({BuildContext Function() context, Future<void> Function(String) ask, Future<void> Function() close})> _app(
  WidgetTester tester,
  _Server server,
) async {
  await tester.runAsync(() async {
    await Rendel.init(appKey: _key, config: RendelConfig(httpClient: server.client));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      context = c;
      return const Scaffold(floatingActionButton: RendelLauncher());
    }),
  ));
  await _settle(tester);
  Future<void> ask(String text) async {
    if (find.byType(TextField).evaluate().isEmpty) {
      await tester.tap(find.bySemanticsLabel('Type a message'));
      await _settle(tester);
    }
    await tester.enterText(find.byType(TextField).last, text);
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _settle(tester);
  }

  Future<void> close() async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _settle(tester);
  }

  return (context: () => context, ask: ask, close: close);
}

void _lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

const _away = [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];
const _back = [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed];

void main() {
  tearDown(Rendel.resetForTest);

  group('the confirm request', () {
    test('carries the person and their token on a yes, in headers only, and neither on a no', () async {
      final server = _Server();
      final api = RendelApiClient(
        appKey: _key,
        deviceId: 'd1',
        config: RendelConfig(httpClient: server.client, userToken: () async => 'tok-ayse'),
        httpClient: server.client,
      );
      expect(await api.recordDecision('i1', confirm: true, user: {'id': 'ayse', 'hmac': 'h'}), 'succeeded');
      await api.recordDecision('i1', confirm: false, user: {'id': 'ayse', 'hmac': 'h'});
      final yes = server.requests[0];
      expect(yes.headers, containsPair('X-Rendel-User-Token', 'tok-ayse'));
      expect(yes.headers, containsPair('X-Rendel-User', 'ayse'));
      expect(yes.headers, containsPair('X-Rendel-User-Hmac', 'h'));
      expect(yes.body, {'decision': 'confirm'});
      final no = server.requests[1];
      expect(no.headers.containsKey('X-Rendel-User-Token'), isFalse);
      expect(no.headers.containsKey('X-Rendel-User'), isFalse);
    });
  });

  group('the support capability', () {
    Future<List<Object?>> declared(bool on) async {
      final server = _Server();
      final c = ConversationController(
        api: RendelApiClient(appKey: _key, deviceId: 'd1', config: RendelConfig(httpClient: server.client), httpClient: server.client),
        actions: const {},
        sdkVersion: 'flutter/0.73.0',
        supportOn: () => on,
      );
      await c.send('hello');
      c.dispose();
      final chat = server.requests.firstWhere((r) => r.path == '/v1/chat').body! as Map;
      return (chat['client'] as Map)['capabilities'] as List<Object?>;
    }

    test('is declared only while the config has Support on', () async {
      expect(await declared(false), isNot(contains('support')));
      expect(await declared(true), contains('support'));
    });
  });

  group('recover()', () {
    setUp(() => ConversationController.recoverEvery = Duration.zero);
    tearDown(() => ConversationController.recoverEvery = const Duration(seconds: 2));

    test('asks again until the server has the cut answer whole', () async {
      final server = _Server()
        ..turn = _answer.sublist(0, 2)
        ..stored = [
          const [],
          const [],
          [
            {'id': 'u1', 'role': 'user', 'blocks': [{'id': 'q', 'type': 'text', 'fallback_text': 'Start a return', 'props': {'markdown': 'Start a return'}}]},
            {'id': 'm1', 'role': 'assistant', 'blocks': [_answer[2]['block']]},
          ],
        ];
      final c = ConversationController(
        api: RendelApiClient(appKey: _key, deviceId: 'd1', config: RendelConfig(httpClient: server.client), httpClient: server.client),
        actions: const {},
        sdkVersion: 'flutter/0.73.0',
      );
      await c.send('Start a return');
      expect(c.errorCode, 'stream_dropped');
      expect(await c.recover(), isTrue);
      expect(server.fetches, 3);
      expect(c.messages.last.blocks.single.props['markdown'], 'Your return has started.');
      c.dispose();
    });
  });

  group('on the phone', () {
    testWidgets('says the person left when the sheet closes or the app is put away, and that they are back', (tester) async {
      final server = _Server();
      final app = await _app(tester, server);
      unawaited(Rendel.open(app.context()));
      await _settle(tester);
      await app.close();
      // No conversation yet: nothing to leave.
      expect(server.away(), isEmpty);

      unawaited(Rendel.open(app.context()));
      await _settle(tester);
      await app.ask('Start a return for my last order');
      await app.close();
      unawaited(Rendel.open(app.context()));
      await _settle(tester);
      _lifecycle(tester, _away);
      await _settle(tester);
      _lifecycle(tester, _back);
      await _settle(tester);
      expect(server.away(), [
        {'away': true},
        {'away': false},
        {'away': true},
        {'away': false},
      ]);

      // Put away with the sheet closed: already away, nothing more to say.
      await app.close();
      _lifecycle(tester, _away);
      _lifecycle(tester, _back);
      await _settle(tester);
      expect(server.away(), hasLength(5));
    });

    testWidgets('a dot on the launcher for an answer that finished with the sheet closed, until it is opened', (tester) async {
      final server = _Server()..hold = Completer<void>();
      final app = await _app(tester, server);
      final dot = find.byKey(const ValueKey('rendel-launcher-dot'));
      unawaited(Rendel.open(app.context()));
      await _settle(tester);
      await app.ask('Start a return for my last order');
      await app.close();
      expect(dot, findsNothing);

      server.hold!.complete();
      await _settle(tester);
      expect(Rendel.waiting.value, RendelWaiting.answer);
      expect(dot, findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Your answer is ready')), findsOneWidget);

      unawaited(Rendel.open(app.context()));
      await _settle(tester);
      expect(Rendel.waiting.value, RendelWaiting.none);
      await app.close();
      expect(dot, findsNothing);
    });

    testWidgets('a dot on the launcher while a card waits for the person with the sheet closed', (tester) async {
      final server = _Server()..turn = _card;
      final app = await _app(tester, server);
      unawaited(Rendel.open(app.context()));
      await _settle(tester);
      await app.ask('Start a return for my last order');
      expect(Rendel.waiting.value, RendelWaiting.none);
      await app.close();
      expect(Rendel.waiting.value, RendelWaiting.approval);
      expect(find.byKey(const ValueKey('rendel-launcher-dot')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Something is waiting for your approval')), findsOneWidget);
    });

    testWidgets('a cut answer is asked for again when the app comes back, and shows as a dot', (tester) async {
      ConversationController.recoverEvery = Duration.zero;
      addTearDown(() => ConversationController.recoverEvery = const Duration(seconds: 2));
      final server = _Server()..turn = _answer.sublist(0, 2);
      final app = await _app(tester, server);
      unawaited(Rendel.open(app.context()));
      await _settle(tester);
      await app.ask('Start a return for my last order');
      await app.close();
      server.stored = [
        [
          {'id': 'm1', 'role': 'assistant', 'blocks': [_answer[2]['block']]},
        ],
      ];
      final before = server.fetches;
      _lifecycle(tester, _away);
      _lifecycle(tester, _back);
      await _settle(tester);
      expect(server.fetches, greaterThan(before));
      expect(Rendel.waiting.value, RendelWaiting.answer);
    });
  });
}
