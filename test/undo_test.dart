// A write that ran with no card (`action_done`): one line in the answer with
// its Undo, which runs the inverse the server hands back once, however many
// times it is tapped, and says how it went. The web SDK's test/undo.test.ts
// holds the same line to the same behaviour.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

const _line = 'Added INNER GOODNESS Oat Milk 1L to your cart';

String _turn({required DateTime until}) {
  final events = [
    {'type': 'turn.start', 'conversation_id': 'c1', 'message_id': 'm1'},
    {
      'type': 'block.ready',
      'index': 0,
      'block': {
        'id': 'b0',
        'type': 'action_done',
        'fallback_text': _line,
        'props': {
          'invocation_id': 'inv-1',
          'action_name': 'add_to_cart',
          'text': _line,
          'undo_until': until.toUtc().toIso8601String(),
        },
      },
    },
    {'type': 'turn.end', 'status': 'completed', 'pending': <String>[]},
  ];
  return [
    for (final (seq, event) in events.indexed)
      'event: ${event['type']}\ndata: ${jsonEncode({'v': 1, 'seq': seq, ...event})}\n\n',
  ].join();
}

/// `/v1/chat` answers with the line; each `/v1/invocations/:id/undo` with the next of [undos].
class _Server {
  _Server(this.turn, this.undos);

  final String turn;
  final List<Map<String, dynamic>> undos;
  final List<Map<String, dynamic>> asked = [];

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/v1/chat')) {
      return http.Response(turn, 200, headers: {'content-type': 'text/event-stream'});
    }
    if (path == '/v1/invocations/inv-1/undo') {
      asked.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode(undos.removeAt(0)), 200, headers: {'content-type': 'application/json'});
    }
    return http.Response('{}', 200);
  });

  RendelApiClient api() => RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'device-1',
        config: const RendelConfig(),
        httpClient: client,
      );
}

Widget _app(Widget child) => MaterialApp(
      home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: child)),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  final ran = <Map<String, dynamic>>[];
  var fails = false;

  ConversationController controller(_Server server) {
    final remove = RendelAction(
      name: 'remove_from_cart',
      description: 'Take it out.',
      params: RendelSchema.object({'product_id': RendelSchema.string()}),
      risk: RendelRisk.write,
      handler: (params) async {
        ran.add(params);
        return fails ? RendelResult.fail('cart service down') : RendelResult.ok({'ok': true});
      },
    );
    final c = ConversationController(
      api: server.api(),
      actions: {'remove_from_cart': remove},
      sdkVersion: 'flutter/test',
      user: () => null,
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    ran.clear();
    fails = false;
  });

  test('the build declares the line', () {
    expect(supportedComponents, contains('action_done'));
  });

  testWidgets('says what happened, runs the inverse once, then says Undone', (tester) async {
    final server = _Server(_turn(until: DateTime.now().add(const Duration(minutes: 10))), [
      {'state': 'run', 'undo_id': 'u1', 'name': 'remove_from_cart', 'params': {'product_id': 'P001'}, 'timeout_ms': 15000},
      {'state': 'undone'},
    ]);
    final c = controller(server);
    await tester.runAsync(() => c.send('Add oat milk'));
    await tester.pumpWidget(_app(ThreadScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(_line), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    // A second tap while it runs does nothing: the button is gone.
    expect(find.text('Undo'), findsNothing);
    await _settle(tester);

    expect(ran, [
      {'product_id': 'P001'}
    ]);
    expect(server.asked, hasLength(2));
    expect(server.asked[1]['report'], {'undo_id': 'u1', 'status': 'success', 'data': {'ok': true}});
    expect(find.text('Undone'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    final block = c.messages.last.blocks.single;
    expect(await tester.runAsync(() => c.undoAction(block)), 'undone');
    expect(server.asked, hasLength(2));
  });

  testWidgets('puts Undo under the words at the largest text size, so they are not broken a few letters a line', (tester) async {
    tester.view.physicalSize = const Size(375, 667) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final server = _Server(_turn(until: DateTime.now().add(const Duration(minutes: 10))), []);
    final c = controller(server);
    await tester.runAsync(() => c.send('Add oat milk'));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(375, 667), textScaler: TextScaler.linear(3.1)),
      child: _app(ThreadScreen(controller: c)),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final words = tester.getRect(find.text(_line));
    final undo = tester.getRect(find.text('Undo'));
    expect(undo.top, greaterThanOrEqualTo(words.bottom));
    // The words keep the line's width: "INNER GOODNESS" is not cut into pieces.
    expect(words.width, greaterThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('says plainly when it failed, and offers it again', (tester) async {
    fails = true;
    final server = _Server(_turn(until: DateTime.now().add(const Duration(minutes: 10))), [
      {'state': 'run', 'undo_id': 'u1', 'name': 'remove_from_cart', 'params': <String, dynamic>{}, 'timeout_ms': 15000},
      {'state': 'failed', 'error': 'down'},
    ]);
    final c = controller(server);
    await tester.runAsync(() => c.send('Add oat milk'));
    await tester.pumpWidget(_app(ThreadScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(find.text("Couldn't undo this. Try again."), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('offers no Undo once the window has closed', (tester) async {
    final server = _Server(_turn(until: DateTime.now().subtract(const Duration(seconds: 1))), []);
    final c = controller(server);
    await tester.runAsync(() => c.send('Add oat milk'));
    await tester.pumpWidget(_app(ThreadScreen(controller: c)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(_line), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  test('an action names its inverse in the manifest', () {
    final add = RendelAction(
      name: 'add_to_cart',
      description: 'Put it in.',
      params: RendelSchema.object({'product_id': RendelSchema.string()}),
      risk: RendelRisk.write,
      handler: (_) async => RendelResult.ok(null),
      undo: const RendelUndo('remove_from_cart'),
    );
    final manifest = buildManifest([add]);
    final nc = ((manifest['actions'] as List).single as Map)['nc'] as Map;
    expect(nc['undo'], {'action': 'remove_from_cart'});
    expect(nc.containsKey('confirm'), isFalse);
  });
}
