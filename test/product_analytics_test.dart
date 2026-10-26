// Product analytics (design/plans/product-analytics.md §2): masking, events
// and their properties, sessions, super properties, the switch, and what
// waits for init.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/analytics.dart';
import 'package:rendel/src/core/screens.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';

class _Server {
  final batches = <Map<String, dynamic>>[];

  late final client = MockClient((request) async {
    if (request.url.path.endsWith('/v1/events')) {
      batches.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
      return http.Response('', 204);
    }
    return http.Response('{"ok":true}', 200);
  });

  List<Map<String, dynamic>> get events => [
        for (final batch in batches) ...(batch['events'] as List).cast<Map<String, dynamic>>(),
      ];

  List<Map<String, dynamic>> of(String type) => events.where((e) => e['type'] == type).toList();
}

RendelScreens get _screens => RendelScreens.instance;
RendelAnalytics get _analytics => RendelAnalytics.instance;

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

void main() {
  late List<Map<String, dynamic>> sent;
  late List<RendelLogRecord> logs;
  late DateTime now;

  setUp(() {
    sent = [];
    logs = [];
    RendelLog.sink = logs.add;
    now = DateTime.utc(2026, 10, 26, 12);
    _analytics.clock = () => now;
  });
  tearDown(() {
    Rendel.resetForTest();
    RendelLog.sink = null;
  });

  /// Counting without a server: what leaves is in [sent].
  void capture() => _screens.send = sent.addAll;

  List<Map<String, dynamic>> flushed() {
    _screens.flush();
    final out = List.of(sent);
    sent.clear();
    return out;
  }

  Future<_Server> init(WidgetTester tester) async {
    final server = _Server();
    await tester.runAsync(() => Rendel.init(
          appKey: _key,
          config: RendelConfig(remoteConfig: false, httpClient: server.client, onLog: logs.add),
        ));
    return server;
  }

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
        _screens.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

  group('masking', () {
    test('replaces what looks personal, the protocol\'s patterns in its order', () {
      expect(maskText('write to ada@example.com today'), 'write to [masked] today');
      expect(maskText('call +90 555 123 45 67'), 'call [masked]');
      expect(maskText('card 4111 1111 1111 1111'), 'card [masked]');
      expect(maskText('IBAN TR33 0006 1005 1978 6457 8413 26'), 'IBAN [masked]');
      expect(maskText('TCKN 12345678901'), 'TCKN [masked]');
      expect(maskText('Balance 1200'), 'Balance [masked]');
      expect(maskText('Buy 2 for 150'), 'Buy 2 for 150');
      expect(maskText('Size 42, row 7'), 'Size 42, row 7');
    });

    test('properties: names checked, values scalar, strings masked and cut, 20 at most', () {
      final dropped = <String>[];
      final clean = cleanProps({
        'plan': 'pro',
        'price': 3.5,
        'beta': true,
        'coupon': null,
        'email': 'ada@example.com',
        'note': 'x' * 300,
        'Bad Name': 1,
        'nested': {'a': 1},
        'list': [1],
        'nan': double.nan,
        for (var i = 0; i < 20; i++) 'k$i': i,
      }, dropped: dropped);
      expect(clean.length, 20);
      expect(clean['plan'], 'pro');
      expect(clean['price'], 3.5);
      expect(clean['beta'], true);
      expect(clean.containsKey('coupon'), isTrue);
      expect(clean['email'], '[masked]');
      expect((clean['note'] as String).length, 255);
      expect(dropped, containsAll(['Bad Name', 'nested', 'list', 'nan', 'k14']));
    });
  });

  group('track', () {
    testWidgets('sends flat, masked properties; a bad one is dropped and named, the event kept', (tester) async {
      final server = await init(tester);
      Rendel.track('add_to_cart', {
        'product': 'Espresso',
        'qty': 2,
        'gift': false,
        'email': 'ada@example.com',
        'meta': {'nested': true},
        'value': 7,
        'currency': 'usd',
      });
      await settle(tester);
      expect(server.of('event').single, {
        'type': 'event',
        'name': 'add_to_cart',
        'props': {'product': 'Espresso', 'qty': 2, 'gift': false, 'email': '[masked]'},
        'value': 7,
        'currency': 'USD',
        'at': isA<String>(),
        'session': matches(_uuid),
      });
      expect(logs.where((r) => r.code == 'invalid_prop').single.message, contains('"meta"'));
    });

    testWidgets('carries who is signed in on the batch, only when someone is', (tester) async {
      final server = await init(tester);
      Rendel.track('opened_app');
      await settle(tester);
      await tester.runAsync(() => Rendel.identify(userId: 'u_1', userHmac: 'h'));
      Rendel.track('signed_in');
      await settle(tester);
      final withEvents = server.batches.where((b) => (b['events'] as List).any((e) => e['type'] == 'event')).toList();
      expect(withEvents.first.containsKey('user'), isFalse);
      expect(withEvents.last['user'], {'id': 'u_1', 'hmac': 'h'});
    });
  });

  group('sessions', () {
    testWidgets('one starts with the first item, and every item carries it', (tester) async {
      capture();
      Rendel.setScreen('Home');
      await tester.pump();
      Rendel.track('opened');
      final items = flushed();
      expect(items.map((i) => i['type']), ['session', 'screen_view', 'event']);
      final session = items.first['session'] as String;
      expect(session, matches(_uuid));
      expect(items.first['started_at'], '2026-10-26T12:00:00.000Z');
      expect(items.skip(1).map((i) => i['session']), everyElement(session));
    });

    testWidgets('a new one after 30 minutes with nothing counted', (tester) async {
      capture();
      Rendel.track('a');
      now = now.add(const Duration(minutes: 29));
      Rendel.track('b');
      now = now.add(const Duration(minutes: 30));
      Rendel.track('c');
      final items = flushed();
      expect(items.map((i) => i['type']), ['session', 'event', 'event', 'session', 'event']);
      expect(items[1]['session'], items[2]['session']);
      expect(items[4]['session'], isNot(items[1]['session']));
    });

    testWidgets('a new one after 30 minutes in the background, whatever was counted there', (tester) async {
      capture();
      await tester.pumpWidget(const SizedBox());
      Rendel.track('a');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = now.add(const Duration(minutes: 20));
      Rendel.track('in_background');
      now = now.add(const Duration(minutes: 11));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      Rendel.track('back');
      final items = flushed().where((i) => i['type'] == 'event').toList();
      expect(items[0]['session'], items[1]['session']);
      expect(items[2]['session'], isNot(items[1]['session']));
    });

    testWidgets('identify of someone else starts one, what waited going as who it was', (tester) async {
      final server = await init(tester);
      Rendel.track('anonymous');
      await tester.runAsync(() => Rendel.identify(userId: 'u_1'));
      Rendel.track('signed_in');
      await tester.runAsync(() => Rendel.identify(userId: 'u_1'));
      Rendel.track('same_person');
      await settle(tester);
      final events = server.of('event');
      expect(events.map((e) => e['name']), ['anonymous', 'signed_in', 'same_person']);
      expect(events[1]['session'], isNot(events[0]['session']));
      expect(events[2]['session'], events[1]['session']);
      // The anonymous event left without a user, before the sign-in.
      final first = server.batches.firstWhere((b) => (b['events'] as List).any((e) => e['name'] == 'anonymous'));
      expect(first.containsKey('user'), isFalse);
    });

    testWidgets('reset starts one when somebody was signed in, not otherwise', (tester) async {
      capture();
      Rendel.track('a');
      Rendel.reset();
      Rendel.track('b');
      await tester.runAsync(() => Rendel.identify(userId: 'u_1'));
      Rendel.track('c');
      Rendel.reset();
      Rendel.track('d');
      final events = flushed().where((i) => i['type'] == 'event').toList();
      expect(events[0]['session'], events[1]['session']);
      expect(events[2]['session'], isNot(events[1]['session']));
      expect(events[3]['session'], isNot(events[2]['session']));
    });
  });

  group('super properties', () {
    testWidgets('go on the session; a change in it replaces the row still waiting', (tester) async {
      capture();
      Rendel.register({'plan': 'free'});
      Rendel.track('a');
      Rendel.register({'plan': 'pro', 'beta': true});
      Rendel.register({'Bad Key': 1});
      var items = flushed();
      expect(items.where((i) => i['type'] == 'session').toList(), [
        {
          'type': 'session',
          'session': items.last['session'],
          'started_at': isA<String>(),
          'super_props': {'plan': 'pro', 'beta': true},
        },
      ]);
      expect(logs.map((r) => r.code), contains('invalid_prop'));
      // Sent already: changed again, the session's row goes again.
      Rendel.unregister('beta');
      items = flushed();
      expect(items.single['super_props'], {'plan': 'pro'});
      expect(_analytics.superProps, {'plan': 'pro'});
    });

    testWidgets('20 at most', (tester) async {
      Rendel.register({for (var i = 0; i < 25; i++) 'k$i': i});
      expect(_analytics.superProps.length, 20);
    });

    testWidgets('and the switch are kept across launches', (tester) async {
      await init(tester);
      Rendel.register({'plan': 'pro'});
      Rendel.setAnalyticsEnabled(false);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      Rendel.resetForTest(relaunch: true);
      expect(_analytics.superProps, isEmpty);
      await init(tester);
      expect(_analytics.superProps, {'plan': 'pro'});
      expect(Rendel.analyticsEnabled, isFalse);
    });
  });

  group('setAnalyticsEnabled(false)', () {
    testWidgets('stops views, events, sessions and purchases, and drops what waited', (tester) async {
      final server = await init(tester);
      await tester.pumpWidget(MaterialApp(navigatorObservers: [Rendel.navigatorObserver], home: const Text('home')));
      Rendel.track('waiting');
      Rendel.setAnalyticsEnabled(false);
      Rendel.setScreen('Cart');
      await tester.pump();
      Rendel.track('add_to_cart');
      Rendel.track('purchase', {'value': 10, 'currency': 'TRY'});
      Rendel.register({'plan': 'pro'});
      await settle(tester);
      expect(server.events, isEmpty);
      // Turns still carry the screen.
      expect(_screens.current, 'Cart');

      Rendel.setAnalyticsEnabled(true);
      Rendel.track('back_on');
      await settle(tester);
      expect(server.events.map((e) => e['type']), ['session', 'event']);
      expect(server.of('session').single['super_props'], {'plan': 'pro'});
    });

    testWidgets('said before init, drops what waited from launch', (tester) async {
      Rendel.setScreen('Splash');
      await tester.pump();
      Rendel.setAnalyticsEnabled(false);
      final server = await init(tester);
      await settle(tester);
      expect(server.events, isEmpty);
    });
  });

  group('before init', () {
    testWidgets('track, register and the switch are held, then sent', (tester) async {
      Rendel.register({'plan': 'pro'});
      Rendel.track('launched', {'cold': true});
      final server = await init(tester);
      await settle(tester);
      expect(server.of('session').single['super_props'], {'plan': 'pro'});
      expect(server.of('event').single['props'], {'cold': true});
    });
  });

  group('remote config', () {
    test('reads capture, keeps it in the cache, and defaults what is missing or wrong', () {
      final parsed = RendelRemoteConfig.tryParse(jsonEncode({
        'channel': 'published',
        'config': {},
        'capture': {
          'taps': 'no_text',
          'sample': 0.25,
          'mask': ['Wallet'],
        },
      }))!;
      expect(parsed.capture, const RendelCapture(taps: 'no_text', sample: 0.25, mask: ['Wallet']));
      expect(RendelRemoteConfig.tryParse(parsed.toCache())!.capture, parsed.capture);
      expect(RendelRemoteConfig.tryParse('{"config":{}}')!.capture, RendelCapture.defaults);
      expect(RendelCapture.parse({'taps': 'sometimes', 'sample': 3, 'mask': 'x'}), RendelCapture.defaults);
    });

    test('the sample is by device, the same every time', () {
      expect(sampleOf('0123456789abcdef0123456789abcdef'), sampleOf('0123456789abcdef0123456789abcdef'));
      final shares = [for (var i = 0; i < 1000; i++) sampleOf('device-$i')];
      expect(shares.every((s) => s >= 0 && s < 1), isTrue);
      final under = shares.where((s) => s < 0.5).length;
      expect(under, inInclusiveRange(400, 600));
    });
  });
}
