// Screens and goals (design/plans/screens-goals.md): the screen each page is
// counted under, when views go, the screen a turn carries, and goals.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/screens.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';

class _Turns extends RendelApiClient {
  _Turns() : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) async* {
    sent.add(body);
    yield const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test');
    yield BlockReady(
      index: 0,
      block: WireBlock(id: 'b0', type: 'text', fallbackText: 'ok', props: const {'markdown': 'ok'})..ready = true,
    );
    yield const TurnEnd(status: 'completed', pending: []);
  }
}

class _Server {
  final events = <Map<String, dynamic>>[];
  final devices = <String?>[];

  late final client = MockClient((request) async {
    if (request.url.path.endsWith('/v1/events')) {
      devices.add(request.headers['X-Rendel-Device']);
      events.addAll(((jsonDecode(request.body) as Map)['events'] as List).cast<Map<String, dynamic>>());
      return http.Response('', 204);
    }
    return http.Response('{"ok":true}', 200);
  });

  List<Map<String, dynamic>> of(String type) => events.where((e) => e['type'] == type).toList();
}

final _navigator = GlobalKey<NavigatorState>();

/// Every route the app pushes by name is a page called by that name.
Widget _app({Widget home = const Text('home')}) => MaterialApp(
      navigatorKey: _navigator,
      navigatorObservers: [Rendel.navigatorObserver],
      home: home,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Text('${settings.name}'),
      ),
    );

/// A page that names itself as it is first built.
class _Named extends StatefulWidget {
  const _Named(this.name);

  final String name;

  @override
  State<_Named> createState() => _NamedState();
}

class _NamedState extends State<_Named> {
  @override
  void initState() {
    super.initState();
    Rendel.setScreen(widget.name);
  }

  @override
  Widget build(BuildContext context) => Text(widget.name);
}

NavigatorState get _nav => _navigator.currentState!;
RendelScreens get _screens => RendelScreens.instance;

void main() {
  late List<Map<String, dynamic>> sent;
  late List<RendelLogRecord> logs;

  setUp(() {
    sent = [];
    logs = [];
    RendelLog.sink = logs.add;
  });
  tearDown(() {
    Rendel.resetForTest();
    RendelLog.sink = null;
  });

  void capture() => _screens.send = sent.addAll;

  /// What has been counted so far, sent now.
  List<String> viewed() {
    _screens.flush();
    return [for (final view in sent) view['screen'] as String];
  }

  group('a screen\'s name', () {
    test('has its ids replaced, its query and fragment dropped', () {
      expect(screenName('/orders/8812'), '/orders/:id');
      expect(screenName('/orders/8812/?tab=2#top'), '/orders/:id');
      expect(screenName('/u/0B8D3C1E-5f6a-4b7c-8d9e-0f1a2b3c4d5e/edit'), '/u/:id/edit');
      expect(screenName('/carts/5f6a4b7c8d9e0f1a'), '/carts/:id');
      expect(screenName('/people/ada@example.com'), '/people/:id');
      expect(screenName('/people/ada%40example.com'), '/people/:id');
      expect(screenName('/share/V1StGXR8_Z5jdHi6B-myT'), '/share/:id');
      expect(screenName('/orders/8812/items/3'), '/orders/:id/items/:id');
    });

    test('keeps words, short codes and names that are not paths', () {
      expect(screenName('/sale/summer-sale-2026-collection'), '/sale/summer-sale-2026-collection');
      expect(screenName('/checkout/step2'), '/checkout/step2');
      expect(screenName('/cafe'), '/cafe');
      expect(screenName('/'), '/');
      expect(screenName('/orders/'), '/orders');
      expect(screenName('orderDetail'), 'orderDetail');
      expect(screenName(' Checkout › Payment '), 'Checkout › Payment');
    });

    test('is at most 120 characters, and null when there is none', () {
      expect(screenName('/${'x' * 200}'), hasLength(120));
      expect(screenName('x' * 200), hasLength(120));
      expect(screenName('   '), isNull);
      expect(screenName(null), isNull);
    });
  });

  group('the observer', () {
    testWidgets('counts each page as it comes and goes, the same one twice in a row once', (tester) async {
      capture();
      await tester.pumpWidget(_app());
      _nav.pushNamed('/orders/8812?tab=2');
      await tester.pumpAndSettle();
      _nav.pushNamed('/orders/9913');
      await tester.pumpAndSettle();
      expect(_screens.current, '/orders/:id');
      _nav.pop();
      await tester.pumpAndSettle();
      _nav.pop();
      await tester.pumpAndSettle();
      expect(_screens.current, '/');
      _nav.pushNamed('/profile');
      await tester.pumpAndSettle();
      _nav.pushReplacementNamed('/settings');
      await tester.pumpAndSettle();
      _nav.pushNamedAndRemoveUntil('/home', (_) => false);
      await tester.pumpAndSettle();
      expect(viewed(), ['/', '/orders/:id', '/', '/profile', '/settings', '/home']);
      expect(sent.first, {'type': 'screen_view', 'screen': '/', 'at': isA<String>()});
      expect(DateTime.parse(sent.first['at'] as String).isUtc, isTrue);
    });

    testWidgets('a dialog or a sheet is not a screen: the page under it still is', (tester) async {
      capture();
      await tester.pumpWidget(_app());
      _nav.pushNamed('/orders/1');
      await tester.pumpAndSettle();
      showDialog<void>(context: _navigator.currentContext!, builder: (_) => const Text('sure?'));
      await tester.pumpAndSettle();
      expect(_screens.current, '/orders/:id');
      _nav.pop();
      await tester.pumpAndSettle();
      showModalBottomSheet<void>(context: _navigator.currentContext!, builder: (_) => const Text('sheet'));
      await tester.pumpAndSettle();
      // A page pushed over the sheet, and popped: the page under the sheet again.
      _nav.push(MaterialPageRoute<void>(builder: (_) => const Text('full screen')));
      await tester.pumpAndSettle();
      expect(_screens.current, isNull);
      _nav.pop();
      await tester.pumpAndSettle();
      expect(_screens.current, '/orders/:id');
      expect(viewed(), ['/', '/orders/:id']);
    });

    testWidgets('a page Rendel opened is called by its registered title, then and later', (tester) async {
      capture();
      await tester.pumpWidget(_app());
      _screens.opening('Orders › Order');
      _nav.pushNamed('/orders/8812');
      await tester.pumpAndSettle();
      _nav.pushNamed('/cart');
      await tester.pumpAndSettle();
      _nav.pushNamed('/orders/9913');
      await tester.pumpAndSettle();
      _screens.opening('Help');
      _nav.push(MaterialPageRoute<void>(builder: (_) => const Text('help')));
      await tester.pumpAndSettle();
      expect(viewed(), ['/', 'Orders › Order', '/cart', 'Orders › Order', 'Help']);
    });
  });

  group('setScreen', () {
    testWidgets('a push and the name its page gives itself are one view', (tester) async {
      capture();
      await tester.pumpWidget(_app());
      _nav.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/checkout'),
        builder: (_) => const _Named('Checkout › Payment'),
      ));
      await tester.pumpAndSettle();
      expect(viewed(), ['/', 'Checkout › Payment']);
    });

    testWidgets('holds for its page, back to it included, until the app says otherwise', (tester) async {
      capture();
      await tester.pumpWidget(_app(home: const _Named('Home')));
      _nav.pushNamed('/orders/1');
      await tester.pumpAndSettle();
      _nav.pop();
      await tester.pumpAndSettle();
      expect(_screens.current, 'Home');
      Rendel.setScreen('Home › Deals');
      await tester.pump();
      Rendel.setScreen(null);
      await tester.pump();
      // Handed back to the route's own name.
      expect(_screens.current, '/');
      Rendel.setScreen('  ');
      expect(logs.map((r) => r.code), ['invalid_screen']);
      Rendel.setScreen('x' * 200);
      await tester.pump();
      expect(viewed(), ['Home', '/orders/:id', 'Home', 'Home › Deals', '/', 'x' * 120]);
    });
  });

  group('views go', () {
    testWidgets('not before init, and then the ones that waited', (tester) async {
      await tester.pumpWidget(_app());
      for (var i = 0; i < 55; i++) {
        Rendel.setScreen('s$i');
        await tester.pump();
      }
      _screens.flush();
      // At most one batch waits; the oldest go first.
      capture();
      expect(viewed(), [for (var i = 5; i < 55; i++) 's$i']);
    });

    testWidgets('at 40', (tester) async {
      capture();
      await tester.pumpWidget(_app());
      // '/' and 38 more.
      for (var i = 0; i < 38; i++) {
        Rendel.setScreen('s$i');
        await tester.pump();
      }
      expect(sent, isEmpty);
      Rendel.setScreen('s38');
      await tester.pump();
      expect(sent, hasLength(40));
    });

    testWidgets('every 15 seconds', (tester) async {
      _screens.timed = true;
      capture();
      await tester.pumpWidget(_app());
      Rendel.setScreen('Cart');
      await tester.pump();
      await tester.pump(const Duration(seconds: 14));
      expect(sent, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(sent.map((v) => v['screen']), ['/', 'Cart']);
    });

    testWidgets('when the app goes to the background', (tester) async {
      capture();
      await tester.pumpWidget(_app());
      Rendel.setScreen('Cart');
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(sent, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(sent.map((v) => v['screen']), ['/', 'Cart']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('to /v1/events, from this device, once init has run', (tester) async {
      final server = _Server();
      Rendel.setScreen('Before init');
      await tester.pump();
      await tester.runAsync(() async {
        await Rendel.init(appKey: _key, config: RendelConfig(remoteConfig: false, httpClient: server.client));
        _screens.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(server.of('screen_view'), [
        {'type': 'screen_view', 'screen': 'Before init', 'at': isA<String>()},
      ]);
      expect(server.devices.last, Rendel.deviceId);
    });
  });

  group('a turn', () {
    ConversationController build(_Turns api, {Map<String, Future<Map<String, dynamic>> Function()> providers = const {}}) {
      final c = ConversationController(
        api: api,
        actions: const {},
        sdkVersion: 'flutter/test',
        contextProviders: providers,
        onOpenUrl: (_) async => true,
      );
      addTearDown(c.dispose);
      return c;
    }

    test('carries the screen it was asked on, beside the app state', () async {
      final api = _Turns();
      final c = build(api, providers: {'cart': () async => {'items': 2}});
      Rendel.setScreen('Checkout › Payment');
      await c.send('What is this fee?').timeout(const Duration(seconds: 5));
      expect(api.sent.single['context'], {
        'app_state': {
          'cart': {'items': 2},
        },
        'current_screen': 'Checkout › Payment',
      });
    });

    test('carries no context when there is neither', () async {
      final api = _Turns();
      await build(api).send('Hi').timeout(const Duration(seconds: 5));
      expect(api.sent.single.containsKey('context'), isFalse);
    });
  });

  group('track', () {
    testWidgets('sends a goal by name, with a value when it has its currency', (tester) async {
      final server = _Server();
      await tester.runAsync(() async {
        await Rendel.init(
          appKey: _key,
          config: RendelConfig(remoteConfig: false, httpClient: server.client, onLog: logs.add),
        );
        Rendel.track('signup');
        Rendel.track('booking_made', {'value': 120, 'currency': ' try '});
        Rendel.track('Sign Up');
        Rendel.track('a' * 41);
        Rendel.track('booking', {'value': 5});
        Rendel.track('booking', {'value': -1, 'currency': 'TRY'});
        Rendel.track('booking', {'value': 2e9, 'currency': 'TRY'});
        Rendel.track('purchase', {'value': 549.9, 'currency': 'TRY'});
        Rendel.track('purchase');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(server.of('goal'), [
        {'type': 'goal', 'name': 'signup'},
        {'type': 'goal', 'name': 'booking_made', 'value': 120, 'currency': 'TRY'},
      ]);
      expect(server.of('purchase'), [
        {'type': 'purchase', 'value': 549.9, 'currency': 'TRY'},
      ]);
      expect(logs.map((r) => r.code).where((code) => code.startsWith('invalid_')), [
        'invalid_goal',
        'invalid_goal',
        'invalid_goal',
        'invalid_goal',
        'invalid_goal',
        'invalid_purchase',
      ]);
    });
  });
}
