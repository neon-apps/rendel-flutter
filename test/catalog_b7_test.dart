// Catalog wave 7 on the device: steps, offers, cart, journey and gauge, the
// catalog review of 2026-11-20 as Tuna picked them in /lab/catalog-next.
//
// Steps are numbered through their groups on a rail, with nothing to tick;
// an offer is a ticket whose code a tap copies; a cart totals its own lines,
// follows its steppers and sends its quantities as a form's submission; a
// journey is a card a leg with the wait between two; a gauge is a half dial
// read as its words. Every fixture is held to the protocol's own wire schema.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/numbers.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';

import 'wire_schema.dart';

/// A server that only records what it was sent.
class _Api extends RendelApiClient {
  _Api() : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) {
    sent.add(body);
    return const Stream.empty();
  }
}

Map<String, dynamic> _wire(String type, Map<String, dynamic> props) => {
      'id': 'b_$type',
      'type': type,
      'fallback_text': 'A $type block.',
      'props': props,
    };

WireBlock _block(Map<String, dynamic> wire) => WireBlock.tryParse(jsonDecode(jsonEncode(wire)))!;

final _layers = _wire('steps', {
  'title': 'Layers for a wet trail run',
  'groups': [
    {'label': 'Upper body'},
    {'label': 'Feet'},
  ],
  'items': [
    {'group_index': 0, 'title': 'Base layer', 'body': 'Wool next to the skin.', 'caption': 'Merino Crew · \$68'},
    {'group_index': 0, 'title': 'Shell'},
    {'group_index': 1, 'title': 'Socks', 'body': 'Merino blend.'},
  ],
  'cta': {
    'label': 'Add them all',
    'action': {'kind': 'reply', 'text': 'Add them all to my cart'},
  },
});

final _coupons = _wire('offers', {
  'items': [
    {
      'value': '15%',
      'unit': 'off',
      'title': 'Outerwear',
      'terms': 'Orders over \$120',
      'ends_label': 'Ends Sunday',
      'ending_soon': true,
      'code': 'RAIN15',
    },
    {'value': 'Free', 'unit': 'delivery', 'title': 'Express delivery', 'ends_label': 'Until 30 Nov', 'note': 'Applied at checkout'},
    {'value': '10%', 'unit': 'off', 'title': 'Welcome offer', 'spent_label': 'Used 12 Nov', 'code': 'WELCOME10'},
  ],
});

final _basket = _wire('cart', {
  'cart_id': 'cart',
  'title': 'Your cart',
  'lines': [
    {'id': 'trail-2', 'title': 'Trail 2', 'detail': 'Size 43 · Sand', 'unit_price': 149, 'quantity': 1},
    {'id': 'socks', 'title': 'Crew Socks', 'detail': '3-pack', 'unit_price': 18.5, 'quantity': 2, 'max': 3},
  ],
  'currency': 'USD',
  'note': 'Delivery is free over \$80.',
  'submit_label': 'Review order',
});

final _trip = _wire('journey', {
  'title': 'Istanbul to Lisbon',
  'legs': [
    {
      'carrier': 'AE 417 · Aerlune',
      'from': {'place': 'Istanbul', 'code': 'IST', 'time_label': '14:55', 'was_label': '14:20'},
      'to': {'place': 'Frankfurt', 'code': 'FRA', 'time_label': '16:05'},
      'duration_label': '3 h 10 min',
      'status': {'label': '35 min late', 'tone': 'warning'},
      'facts': [
        {'label': 'Gate', 'value': 'B14'},
        {'label': 'Seat', 'value': '14C'},
      ],
      'change_after': {'label': '40 min to change in Frankfurt', 'tone': 'warning'},
    },
    {
      'from': {'place': 'Frankfurt', 'code': 'FRA', 'time_label': '16:45'},
      'to': {'place': 'Lisbon', 'time_label': '18:50'},
      'change_after': {'label': 'never drawn'},
    },
  ],
});

final _uv = _wire('gauge', {
  'title': 'UV index now',
  'value': '7',
  'bands': [
    {'label': 'Low'},
    {'label': 'Moderate'},
    {'label': 'High'},
    {'label': 'Very high'},
    {'label': 'Extreme'},
  ],
  'band_index': 2,
  'position': 0.52,
  'note': 'SPF 50, and again every two hours.',
});

void main() {
  late List<String> copied;

  setUp(() {
    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  final theme = RendelTheme.paper();

  ConversationController controller(_Api api) => ConversationController(
        api: api,
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  /// [blocks] in a scrolling list on a phone, acting through the real controller.
  Future<_Api> pump(WidgetTester tester, List<Map<String, dynamic>> blocks, {double width = 390}) async {
    tester.view.physicalSize = Size(width * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = _Api();
    final c = controller(api);
    addTearDown(c.dispose);
    final dispatch = RendelDispatcher(onAction: c.tapAction, onSubmitForm: c.submitForm, canHandle: c.handles);
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: theme,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final block in blocks.map(_block))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return api;
  }

  test('the handshake declares the five, and each has a renderer', () async {
    final api = _Api();
    final c = controller(api);
    unawaited(c.send('hello'));
    await Future<void>.delayed(Duration.zero);
    final client = api.sent.single['client'] as Map<String, dynamic>;
    for (final type in ['steps', 'offers', 'cart', 'journey', 'gauge']) {
      expect(client['components'], contains(type));
      expect(supportedComponents, contains(type));
      expect(ComponentRegistry.registeredTypes, contains(type));
    }
    c.dispose();
  });

  group('steps', () {
    testWidgets('numbered through their groups, a heading over each run, nothing to tick', (tester) async {
      await pump(tester, [_layers]);
      expect(find.text('Layers for a wet trail run'), findsOneWidget);
      for (final n in ['1', '2', '3']) {
        expect(find.text(n), findsOneWidget);
      }
      // The headings in reading order, and the numbers running on under the second.
      expect(tester.getTopLeft(find.text('Upper body')).dy, lessThan(tester.getTopLeft(find.text('Base layer')).dy));
      expect(tester.getTopLeft(find.text('Feet')).dy, greaterThan(tester.getTopLeft(find.text('Shell')).dy));
      expect(tester.getTopLeft(find.text('3')).dy, greaterThan(tester.getTopLeft(find.text('Feet')).dy));
      expect(find.bySemanticsLabel('1, Base layer, Wool next to the skin., Merino Crew · \$68'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Add them all'), findsOneWidget);
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      await pump(tester, [_layers], width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('offers', () {
    testWidgets('a ticket an offer: its worth, what it is for, when it ends, its code', (tester) async {
      await pump(tester, [_coupons]);
      for (final words in ['15%', 'Outerwear', 'Orders over \$120', 'Ends Sunday', 'RAIN15', 'Free', 'Applied at checkout', 'Until 30 Nov']) {
        expect(find.text(words), findsOneWidget, reason: words);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap copies the code and says Copied for a moment', (tester) async {
      await pump(tester, [_coupons]);
      await tester.tap(find.bySemanticsLabel('Copy RAIN15'));
      await tester.pump();
      await tester.pump();
      expect(copied, ['RAIN15']);
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.text('RAIN15'), findsOneWidget);
    });

    testWidgets('one already used is struck through and says so in the code\'s place', (tester) async {
      await pump(tester, [_coupons]);
      expect(find.text('Used 12 Nov'), findsOneWidget);
      expect(find.text('WELCOME10'), findsNothing);
      expect(tester.widget<Text>(find.text('Welcome offer')).style!.decoration, TextDecoration.lineThrough);
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      await pump(tester, [_coupons], width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('cart', () {
    test('money is written as the language writes it, whole amounts without zeros', () {
      expect(rendelMoney(149, 'USD', 'en'), '\$149');
      expect(rendelMoney(204.5, 'USD', 'en'), '\$204.50');
      expect(rendelMoney(1299.9, 'TRY', 'tr'), '₺1.299,90');
      expect(rendelMoney(149, 'EUR', 'de'), '149 €');
      expect(rendelMoney(12, 'SEK', 'en'), '12 SEK');
    });

    testWidgets('totals its own lines and follows the steppers, within what a line may take', (tester) async {
      await pump(tester, [_basket]);
      expect(find.text('\$149'), findsOneWidget);
      expect(find.text('\$37'), findsOneWidget);
      expect(find.text('\$186'), findsOneWidget);
      expect(find.text('Review order · \$186'), findsOneWidget);
      expect(find.text('Delivery is free over \$80.'), findsOneWidget);

      const unsaved = 'Your cart has not changed yet. Press Review order to change it.';
      expect(find.text(unsaved), findsNothing);
      await tester.tap(find.bySemanticsLabel('More, Crew Socks'));
      await tester.pump();
      expect(find.text('\$204.50'), findsOneWidget);
      // On the card only, until the button sends it: the app's cart is as it was (F1082).
      expect(find.text(unsaved), findsOneWidget);
      // Three is the most of it: the fourth tap changes nothing.
      await tester.tap(find.bySemanticsLabel('More, Crew Socks'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('\$204.50'), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.bySemanticsLabel('Fewer, Crew Socks'));
        await tester.pump();
      }
      // A line at zero stays, struck through.
      expect(tester.widget<Text>(find.text('Crew Socks')).style!.decoration, TextDecoration.lineThrough);
      expect(find.text('Review order · \$149'), findsOneWidget);
    });

    testWidgets('sends the quantities as a form\'s submission, a value a line', (tester) async {
      final api = await pump(tester, [_basket]);
      await tester.tap(find.bySemanticsLabel('Fewer, Crew Socks'));
      await tester.pump();
      await tester.tap(find.text('Review order · \$167.50'));
      await tester.pump();
      await tester.pump();
      final sent = api.sent.single['form_submission'] as Map<String, dynamic>;
      expect(sent, {
        'form_id': 'cart',
        'values': {'trail-2': 1, 'socks': 1},
      });
      expect(schemaErrors({'form_submission': sent}, {'type': 'object', 'properties': {'form_submission': (chatRequestSchema['properties'] as Map)['form_submission']}}), isEmpty);
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      await pump(tester, [_basket], width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('journey', () {
    testWidgets('a card a leg: who runs it, how it stands, the two ends, its facts', (tester) async {
      await pump(tester, [_trip]);
      for (final words in ['AE 417 · Aerlune', '35 min late', 'IST', '14:55', '14:20', 'Istanbul', '3 h 10 min', 'B14', '14C', 'LIS'.replaceAll('LIS', 'Lisbon'), '18:50']) {
        expect(find.text(words), findsWidgets, reason: words);
      }
      // The planned time is struck through.
      expect(tester.widget<Text>(find.text('14:20')).style!.decoration, TextDecoration.lineThrough);
      // FRA ends the first leg and starts the second.
      expect(find.text('FRA'), findsNWidgets(2));
    });

    testWidgets('the wait between two legs is between their cards, and nothing follows the last', (tester) async {
      await pump(tester, [_trip]);
      final change = find.text('40 min to change in Frankfurt');
      expect(change, findsOneWidget);
      expect(find.text('never drawn'), findsNothing);
      expect(tester.getTopLeft(change).dy, greaterThan(tester.getTopLeft(find.text('B14')).dy));
      expect(tester.getTopLeft(change).dy, lessThan(tester.getTopLeft(find.text('16:45')).dy));
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      await pump(tester, [_trip], width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('gauge', () {
    testWidgets('a half dial with the reading and its band inside, read as its words', (tester) async {
      await pump(tester, [_uv]);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Extreme'), findsOneWidget);
      expect(find.text('SPF 50, and again every two hours.'), findsOneWidget);
      expect(find.bySemanticsLabel('UV index now: 7, High'), findsOneWidget);
      // The reading sits inside the dial, not under it.
      expect(tester.getRect(find.text('7')).bottom, lessThan(tester.getRect(find.text('Low')).top));
    });
  });

  group('the fixtures', () {
    test('parse against the protocol schema', () {
      for (final wire in [_layers, _coupons, _basket, _trip, _uv]) {
        expect(wireBlockErrors(wire), isEmpty, reason: '${wire['id']}');
      }
    });

    test('the schema check is a real one', () {
      expect(wireBlockErrors(_wire('steps', {'items': [{'title': 'only one'}]})), isNotEmpty, reason: 'two steps at least');
      expect(wireBlockErrors(_wire('cart', {'cart_id': 'c', 'lines': [{'id': 'a', 'title': 'A', 'unit_price': '1', 'quantity': 1}], 'currency': 'USD', 'submit_label': 'Go'})), isNotEmpty, reason: 'a price is a number');
    });
  });
}
