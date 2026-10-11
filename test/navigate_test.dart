import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/route.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// A server that records what it was sent and never answers.
class _Silent extends RendelApiClient {
  _Silent() : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) {
    sent.add(body);
    return const Stream.empty();
  }
}

/// A server that records the screen opens it is told about.
class _Opens extends _Silent {
  final List<Map<String, String>> opens = [];

  @override
  Future<void> sendScreenOpen(Map<String, String> open) async => opens.add(open);
}

WireBlock _block(String id, String type, Map<String, dynamic> props) =>
    WireBlock(id: id, type: type, fallbackText: 'A $type block.', props: props)..ready = true;

Map<String, dynamic> _go(String route, [Map<String, Object?> params = const {}]) =>
    {'kind': 'navigate', 'route': route, 'params': params};

final _screens = _block('screens', 'screens', {
  'items': [
    {'title': 'Order #4821', 'icon': 'package', 'action': _go('order_detail', {'order_id': '4821'})},
    {'title': 'Somewhere else', 'action': _go('not_registered')},
  ],
});

final _lit = find.byWidgetPredicate((w) => '${w.runtimeType}' == '_LitAction');
final _bubble = find.bySemanticsLabel('Back to the assistant');

/// The design brief's tests for `navigate` (`design/NAVIGATE.md`).
void main() {
  group('the wire', () {
    test('the handshake declares navigate and screens', () async {
      final api = _Silent();
      final c = ConversationController(api: api, actions: const {}, sdkVersion: 'flutter/test');
      unawaited(c.send('hello'));
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      final client = api.sent.single['client'] as Map<String, dynamic>;
      expect(client['actions'], contains('navigate'));
      expect(client['components'], contains('screens'));
    });

    /// The web SDK logs the same code, so one log pipeline reads both.
    test('a route that throws while opening logs route_open_failed', () async {
      final logged = <RendelLogRecord>[];
      RendelLog.sink = logged.add;
      addTearDown(() => RendelLog.sink = null);
      final c = ConversationController(
        api: _Silent(),
        actions: const {},
        routes: {
          'order_detail': RendelRoute(
            name: 'order_detail',
            title: 'Orders › Order',
            description: 'One order.',
            open: (_) => throw StateError('no navigator'),
          ),
        },
        sdkVersion: 'flutter/test',
      );
      addTearDown(c.dispose);

      final opened = await c.tapAction(
        UIAction.tryParse(_go('order_detail', {'order_id': '4821'}))!,
      );

      expect(opened, isFalse);
      expect(logged.map((r) => r.code), ['route_open_failed']);
    });

    test('an open is reported with the reply and block it came from, and only an open', () async {
      final api = _Opens();
      final opened = <Map<String, Object?>>[];
      final c = ConversationController(
        api: api,
        actions: const {},
        routes: {
          'order_detail': RendelRoute(
            name: 'order_detail',
            title: 'Orders › Order',
            description: 'One order.',
            open: opened.add,
          ),
          'broken': RendelRoute(
            name: 'broken',
            title: 'Broken',
            description: 'Throws.',
            open: (_) => throw StateError('no navigator'),
          ),
        },
        sdkVersion: 'flutter/test',
      );
      addTearDown(c.dispose);
      c.messages.add(RendelMessage.assistant()
        ..serverId = 'm1'
        ..blocks.add(_screens));

      expect(await c.tapAction(UIAction.tryParse(_go('order_detail', {'order_id': '4821'}))!), isTrue);
      expect(opened, [
        {'order_id': '4821'},
      ]);
      expect(api.opens, [
        {'message_id': 'm1', 'block_id': 'screens', 'route': 'order_detail'},
      ]);

      // The same route with values no reply offered opens, but is not counted as an open of that card.
      expect(await c.tapAction(UIAction.tryParse(_go('order_detail', {'order_id': '9999'}))!), isTrue);
      expect(api.opens, hasLength(1));

      // A route that throws opened nothing, so nothing is reported.
      expect(await c.tapAction(UIAction.tryParse(_go('broken'))!), isFalse);
      expect(api.opens, hasLength(1));
    });

    test('a navigate parses with the primitive params the wire allows', () {
      final action = UIAction.tryParse({
        'kind': 'navigate',
        'route': 'order_detail',
        'params': {'order_id': '4821', 'count': 2, 'gift': true, 'nested': {'a': 1}},
      });
      expect(action, isA<NavigateAction>());
      action as NavigateAction;
      expect(action.route, 'order_detail');
      expect(action.params, {'order_id': '4821', 'count': 2, 'gift': true});
      expect(UIAction.tryParse({'kind': 'navigate'}), isNull);
    });

    test('a manifest with routes hashes as the TypeScript implementation does', () {
      final manifest = buildManifest(
        [
          RendelAction(
            name: 'get_order_status',
            description: 'Fetch the delivery status of an order by id.',
            params: RendelSchema.object({'order_id': RendelSchema.string()}),
            risk: RendelRisk.read,
            handler: (_) async => RendelResult.ok(),
          ),
        ],
        // Out of order on purpose: the manifest sorts them.
        routes: [
          RendelRoute(
            name: 'order_detail',
            title: 'Orders › Order',
            description: 'One order: its items, delivery and payment.',
            params: const {'order_id': RendelRouteParam.string(required: true, fromActions: true)},
            open: (_) {},
          ),
          RendelRoute(
            name: 'delivery',
            title: 'Orders › Delivery',
            description: 'Change when and where an order arrives.',
            params: const {
              'order_id': RendelRouteParam.string(required: true, fromActions: true),
              'day': RendelRouteParam.string(description: 'The day picked, e.g. Friday'),
            },
            open: (_) {},
          ),
          RendelRoute(name: 'cart', title: 'Cart', description: 'What is in the cart now.', open: (_) {}),
        ],
      );
      expect((manifest['routes'] as List).map((r) => (r as Map)['name']), ['cart', 'delivery', 'order_detail']);
      // From `packages/protocol`'s own `hashManifest`, over the same manifest
      // after `actionManifest.parse`.
      expect(hashManifest(manifest), 'e5d991d5176acd4e8674960fdd878c9768569f30bf33b8a749788a2787bd2130');
    });

    test('an app without routes has no routes key', () {
      final manifest = buildManifest([
        RendelAction(
          name: 'cancel_order',
          description: 'Cancel an order.',
          params: RendelSchema.object({}),
          risk: RendelRisk.destructive,
          handler: (_) async => RendelResult.ok(),
        ),
      ]);
      expect(manifest.containsKey('routes'), isFalse);
      expect(canonicalize(manifest), isNot(contains('routes')));
    });

    test('a registered route goes into the manifest with its title, description and params',
        () async {
      Map<String, dynamic>? sent;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/v1/apps/manifest')) {
          sent = (jsonDecode(request.body) as Map<String, dynamic>)['manifest'] as Map<String, dynamic>;
        }
        return http.Response('{"ok":true}', 200);
      });
      addTearDown(Rendel.resetForTest);
      // Before init, as a host registering its routes at startup would.
      Rendel.registerRoute(
        'order_detail',
        title: 'Orders › Order',
        description: 'One order: its items, delivery and payment.',
        params: const {
          'order_id': RendelRouteParam.string(description: 'The order', required: true, fromActions: true),
          'gift': RendelRouteParam.boolean(),
        },
        open: (_) {},
      );
      await Rendel.init(
        appKey: 'nc_pk_test_example_000000000000000000000000',
        config: RendelConfig(httpClient: client, remoteConfig: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(sent, isNotNull, reason: 'an app with routes and no actions still has a manifest');
      expect(sent!['actions'], isEmpty);
      expect(sent!['routes'], [
        {
          'name': 'order_detail',
          'title': 'Orders › Order',
          'description': 'One order: its items, delivery and payment.',
          'params': {
            'order_id': {'type': 'string', 'description': 'The order', 'required': true, 'fromActions': true},
            'gift': {'type': 'boolean'},
          },
        },
      ]);
    });
  });

  group('drawing screens', () {
    late List<Map<String, Object?>> opened;

    ConversationController controller() {
      final c = ConversationController(
        api: _Silent(),
        actions: const {},
        routes: {
          'order_detail': RendelRoute(
            name: 'order_detail',
            title: 'Orders › Order',
            description: 'One order.',
            open: opened.add,
          ),
        },
        sdkVersion: 'flutter/test',
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> pump(WidgetTester tester, ConversationController c, List<WireBlock> blocks) async {
      c.messages.add(RendelMessage.assistant()..blocks.addAll(blocks));
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                // A recogniser, so the microphone is drawn.
                onDictate: (_) => Completer<String?>().future,
                onStopDictating: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() => opened = []);

    testWidgets("draws the route's own title under the item's, and an unknown route inert",
        (tester) async {
      await pump(tester, controller(), [
        _block('lede', 'text', {'markdown': 'It arrives today.'}),
        _screens,
      ]);

      expect(find.text('Order #4821'), findsWidgets);
      final path = find.text('Orders › Order');
      expect(path, findsOneWidget);
      expect(tester.getTopLeft(path).dy, greaterThan(tester.getTopLeft(find.text('Order #4821').first).dy));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Order #4821, Orders › Order')),
        isSemantics(isButton: true, hasTapAction: true),
      );

      // Drawn, and not a control: no button, no press, no line under it.
      expect(find.text('Somewhere else'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Somewhere else')),
        isNot(isSemantics(isButton: true)),
      );
      await tester.tap(find.text('Somewhere else'), warnIfMissed: false);
      await tester.pump();
      expect(opened, isEmpty);
    });

    testWidgets('a tap calls the route with its params', (tester) async {
      await pump(tester, controller(), [_screens]);
      await tester.tap(find.bySemanticsLabel('Order #4821, Orders › Order'));
      await tester.pump();
      expect(opened, [
        {'order_id': '4821'},
      ]);
    });

    testWidgets('the first item is lit beside the microphone, which narrows to a circle',
        (tester) async {
      await pump(tester, controller(), [
        _block('lede', 'text', {'markdown': 'It arrives today.'}),
        _screens,
      ]);

      expect(_lit, findsOneWidget);
      expect(find.descendant(of: _lit, matching: find.text('Order #4821')), findsOneWidget);
      expect(find.descendant(of: _lit, matching: find.byIcon(Icons.north_east_rounded)), findsOneWidget);
      final mic = tester.getRect(find.bySemanticsLabel('Speak instead of typing'));
      final lit = tester.getRect(_lit);
      expect(mic.width, 52);
      expect(lit.left, greaterThan(mic.right));
      expect(lit.center.dy, closeTo(mic.center.dy, 1));

      await tester.tap(_lit);
      await tester.pump();
      expect(opened, [
        {'order_id': '4821'},
      ]);
    });

    testWidgets('a page whose first screen is unknown lights nothing', (tester) async {
      await pump(tester, controller(), [
        _block('s', 'screens', {
          'items': [
            {'title': 'Somewhere else', 'action': _go('not_registered')},
          ],
        }),
      ]);
      expect(_lit, findsNothing);
    });
  });

  group('the bubble', () {
    String sse(String event, Map<String, Object?> data) => 'event: $event\ndata: ${jsonEncode(data)}\n\n';

    /// An answer long enough to scroll, with its screens at the foot.
    String answer() {
      final blocks = [
        {'id': 'lede', 'type': 'text', 'props': {'markdown': 'It arrives today by 18:00.'}},
        for (var i = 0; i < 6; i++)
          {'id': 'p$i', 'type': 'text', 'props': {'markdown': 'Paragraph $i. ' * 14}},
        {
          'id': 'screens',
          'type': 'screens',
          'props': {
            'items': [
              {'title': 'Order #4821', 'action': _go('order_detail', {'order_id': '4821'})},
            ],
          },
        },
      ];
      return sse('turn.start', {'conversation_id': 'c', 'message_id': 'm'}) +
          [
            for (var i = 0; i < blocks.length; i++) ...[
              sse('block.start', {'index': i, 'id': blocks[i]['id'], 'block_type': blocks[i]['type']}),
              sse('block.ready', {
                'index': i,
                'block': {...blocks[i], 'fallback_text': 'A block.'},
              }),
            ],
          ].join() +
          sse('turn.end', {'status': 'completed', 'pending': <String>[]});
    }

    late List<Map<String, Object?>> opened;

    /// The app, with the copilot open on the answer.
    Future<void> host(WidgetTester tester, {bool still = false}) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      addTearDown(Rendel.resetForTest);
      opened = [];
      final navigator = GlobalKey<NavigatorState>();
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/v1/chat')) {
          return http.Response(answer(), 200, headers: {'content-type': 'text/event-stream'});
        }
        return http.Response('{"ok":true}', 200);
      });
      Rendel.registerRoute(
        'order_detail',
        title: 'Orders › Order',
        description: 'One order.',
        params: const {'order_id': RendelRouteParam.string(required: true)},
        open: (params) {
          opened.add(params);
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Order ${params['order_id']}'),
                      // The app's own launcher, on the screen it opened.
                      TextButton(onPressed: () => Rendel.open(context), child: const Text('Ask')),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
      await Rendel.init(
        appKey: 'nc_pk_test_example_000000000000000000000000',
        config: RendelConfig(
          httpClient: client,
          remoteConfig: false,
          suggestions: const ['Where is my order?'],
          onDictate: (_) => Completer<String?>().future,
          onStopDictating: () {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: still
              ? (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(disableAnimations: true),
                    child: child!,
                  )
              : null,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () => Rendel.open(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Where is my order?'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('It arrives today by 18:00.'), findsOneWidget);
    }

    Finder page() => find.descendant(of: find.byType(ThreadScreen), matching: find.byType(Scrollable)).first;

    Finder card() => find.bySemanticsLabel('Order #4821, Orders › Order');

    Future<void> scrollToCard(WidgetTester tester) async {
      await tester.scrollUntilVisible(card(), 200, scrollable: page());
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Opens the order from [from]: its card, or by default the button lit
    /// beside the microphone, which is on screen wherever the page is.
    Future<void> go(WidgetTester tester, [Finder? from]) async {
      await tester.tap(from ?? _lit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    }

    testWidgets('a tap calls open with the params and shows the bubble', (tester) async {
      await host(tester);
      await scrollToCard(tester);
      await go(tester, card());

      expect(opened, [
        {'order_id': '4821'},
      ]);
      // The app's screen is in front, the answer out of sight, the bubble up.
      expect(find.text('Order 4821'), findsOneWidget);
      expect(find.text('It arrives today by 18:00.'), findsNothing);
      expect(find.text('It arrives today by 18:00.', skipOffstage: false), findsOneWidget);
      expect(_bubble, findsOneWidget);
      final bubble = tester.getRect(_bubble);
      expect(bubble.size, const Size(56, 56));
      expect(bubble.right, 390 - 14);
      expect(bubble.bottom, 844 - 104);
    });

    testWidgets('tapping the bubble restores the panel with the same page and scroll',
        (tester) async {
      await host(tester);
      await scrollToCard(tester);
      final scroll = tester.state<ScrollableState>(page());
      final before = scroll.position.pixels;
      expect(before, greaterThan(0));

      await go(tester, card());
      await tester.tap(_bubble);
      await settle(tester);

      expect(_bubble, findsNothing);
      expect(find.text('Order #4821'), findsWidgets);
      // The same list, not one rebuilt to look like it.
      expect(tester.state<ScrollableState>(page()), same(scroll));
      expect(scroll.position.pixels, before);

      // And it is the sheet again: closing it leaves the app's screen, and no
      // bubble.
      await tester.tap(find.bySemanticsLabel('Close the assistant'));
      await settle(tester);
      expect(find.byType(ThreadScreen, skipOffstage: false), findsNothing);
      expect(_bubble, findsNothing);
      expect(find.text('Order 4821'), findsOneWidget);
    });

    testWidgets('a drag moves the bubble to the nearer edge, and a short press restores',
        (tester) async {
      await host(tester);
      await go(tester);

      await tester.drag(_bubble, const Offset(-260, -200));
      await settle(tester);
      final moved = tester.getRect(_bubble);
      expect(moved.left, 14, reason: 'let go on the left half, it settles on the left edge');
      expect(moved.top, closeTo(844 - 104 - 56 - 200, 1));
      expect(find.text('It arrives today by 18:00.'), findsNothing, reason: 'a drag is not a tap');

      await tester.tap(_bubble);
      await settle(tester);
      expect(find.text('It arrives today by 18:00.'), findsOneWidget);
    });

    testWidgets("the app's own launcher while the bubble is up is a tap on the bubble",
        (tester) async {
      await host(tester);
      await go(tester);
      await tester.tap(find.text('Ask'));
      await settle(tester);
      expect(_bubble, findsNothing);
      expect(find.text('It arrives today by 18:00.'), findsOneWidget);
    });

    testWidgets('the reset arrow shows once there is a conversation, and starts over', (tester) async {
      // `host` has already asked and been answered. On the opening screen
      // there is nothing to start over from (Tuna, 2026-10-10).
      await host(tester);
      final reset = find.bySemanticsLabel('Start a new conversation');
      expect(reset, findsOneWidget);
      await tester.tap(reset);
      await settle(tester);
      expect(find.text('Where is my order?'), findsOneWidget);
      expect(reset, findsNothing);
    });

    testWidgets('closing the panel makes no bubble', (tester) async {
      await host(tester);
      await tester.tap(find.bySemanticsLabel('Close the assistant'));
      await settle(tester);
      expect(find.byType(ThreadScreen, skipOffstage: false), findsNothing);
      expect(_bubble, findsNothing);
    });

    testWidgets('under reduced motion the bubble simply appears', (tester) async {
      await host(tester, still: true);
      await tester.tap(_lit);
      await tester.pump();
      await tester.pump();
      expect(_bubble, findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: _bubble, matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, 1);

      await tester.tap(_bubble);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(_bubble, findsNothing);
      expect(find.text('It arrives today by 18:00.'), findsOneWidget);
    });
  });

  test('the string is in all six languages', () {
    const english = RendelStrings();
    expect(english.backToAssistant, 'Back to the assistant');
    expect(RendelStrings.forLocale('tr').backToAssistant, 'Asistana dön');
    for (final language in ['tr', 'de', 'fr', 'es', 'ar']) {
      final said = RendelStrings.forLocale(language).backToAssistant;
      expect(said, isNotEmpty, reason: language);
      expect(said, isNot(english.backToAssistant), reason: '$language is still English');
    }
  });
}
