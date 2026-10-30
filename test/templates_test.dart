// Card templates: kinds of card drawn from the customer's own layout
// (`packages/protocol/src/templates.ts`). The same failure modes as remote
// config: a template out of shape is drawn the built-in way, never a crash,
// and one that draws nothing for a block gives the block back to the catalog.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/templates.dart';

const _productList = {
  'layout': 'list',
  'node': {
    'type': 'box',
    'direction': 'row',
    'gap': 8,
    'children': [
      {'type': 'text', 'bind': 'price', 'weight': 'bold', 'color': 'accent'},
      {'type': 'text', 'bind': 'title', 'grow': true},
      {'type': 'text', 'bind': 'badge', 'when': {'bind': 'badge'}},
    ],
  },
};

const _infoCard = {
  'node': {
    'type': 'box',
    'padding': 16,
    'fill': 'raised',
    'radius': 16,
    'children': [
      {'type': 'text', 'bind': 'title', 'size': 18, 'weight': 'bold'},
      {'type': 'button', 'bind': 'cta', 'when': {'bind': 'cta'}},
    ],
  },
};

const _tracker = {
  'node': {
    'type': 'each',
    'bind': 'steps',
    'gap': 6,
    'child': {
      'type': 'box',
      'direction': 'row',
      'children': [
        {'type': 'text', 'bind': 'label'},
        {'type': 'text', 'value': 'now', 'when': {'bind': 'status', 'equals': 'current'}},
      ],
    },
  },
};

void main() {
  group('reading templates', () {
    test('keeps every kind that is in shape', () {
      final kept = RendelCardTemplate.parseAll({
        'product_cards': _productList,
        'info_card': _infoCard,
        'order_tracker': _tracker,
      });
      expect(kept.keys, containsAll(['product_cards', 'info_card', 'order_tracker']));
      expect(kept['product_cards']!.layout, 'list');
      expect(kept['product_cards']!.node.children, hasLength(3));
    });

    test('drops a template whole when any value in it could be more than a value', () {
      final kept = RendelCardTemplate.parseAll({
        'product_cards': {
          'node': {'type': 'text', 'bind': 'title', 'color': 'red; background:url(https://evil.example/p.gif)'},
        },
        'item_list': {
          'node': {'type': 'image', 'bind': 'image_url', 'src': 'https://evil.example/p.gif'},
        },
        'info_card': {
          'layout': 'grid',
          'node': {'type': 'text', 'bind': 'title'},
        },
        'order_tracker': {
          'node': {'type': 'text', 'bind': 'title', 'value': 'both'},
        },
        'confirm_card': {
          'node': {'type': 'text', 'value': 'Yes'},
        },
      });
      expect(kept, isEmpty);
    });

    test('bounds the tree', () {
      Map<String, dynamic> deep = {'type': 'text', 'bind': 'title'};
      for (var i = 0; i < 8; i++) {
        deep = {
          'type': 'box',
          'children': [deep],
        };
      }
      expect(RendelCardTemplate.tryParse('info_card', {'node': deep}), isNull);
    });

    test('rides along with the published config, and through the cache', () {
      final remote = RendelRemoteConfig.tryParse(jsonEncode({
        'channel': 'published',
        'version': 4,
        'config': {
          'templates': {'info_card': _infoCard},
        },
      }))!;
      expect(remote.isEmpty, isFalse);
      expect(remote.cardTemplates.keys, ['info_card']);
      final cached = RendelRemoteConfig.tryParse(remote.toCache())!;
      expect(cached.cardTemplates.keys, ['info_card']);
    });

    test('an older payload carries none', () {
      final remote = RendelRemoteConfig.tryParse('{"config":{"theme":{"radius":{"card":8}}}}')!;
      expect(remote.cardTemplates, isEmpty);
    });
  });

  group('drawing a templated card', () {
    final tapped = <UIAction>[];
    final dispatch = RendelDispatcher(
      onAction: (action) async {
        tapped.add(action);
        return true;
      },
      onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
      canHandle: (_) => true,
    );

    setUp(tapped.clear);
    tearDown(() => rendelCardTemplates = const {});

    Future<void> pump(WidgetTester tester, String type, Map<String, dynamic> props) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final b = WireBlock(id: 'b_$type', type: type, fallbackText: 'A $type block.', props: props)..ready = true;
      await tester.pumpWidget(MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Builder(builder: (context) => ComponentRegistry.build(context, b, dispatch)),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('draws each product in the customer\'s own order, and taps it as the built-in card does', (tester) async {
      rendelCardTemplates = RendelCardTemplate.parseAll({'product_cards': _productList});
      await pump(tester, 'product_cards', {
        'items': [
          {
            'title': 'Aero Glide 2',
            'price': r'$129',
            'badge': 'New',
            'action': {'kind': 'reply', 'text': 'Aero'},
          },
          {'title': 'Court Low', 'price': r'$95'},
        ],
      });
      expect(tester.takeException(), isNull);
      expect(find.text(r'$129'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      expect(tester.getTopLeft(find.text(r'$129')).dx, lessThan(tester.getTopLeft(find.text('Aero Glide 2')).dx));
      await tester.tap(find.text('Aero Glide 2'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tapped, hasLength(1));
    });

    testWidgets('binds a button to the one the model sent, and draws none it did not', (tester) async {
      rendelCardTemplates = RendelCardTemplate.parseAll({'info_card': _infoCard});
      await pump(tester, 'info_card', {
        'title': 'Free returns',
        'cta': {
          'label': 'Start a return',
          'action': {'kind': 'reply', 'text': 'return'},
        },
      });
      expect(tester.takeException(), isNull);
      expect(find.text('Start a return'), findsOneWidget);
      await tester.tap(find.text('Start a return'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tapped, hasLength(1));
    });

    testWidgets('repeats an each over the steps, and shows a node only when its condition holds', (tester) async {
      rendelCardTemplates = RendelCardTemplate.parseAll({'order_tracker': _tracker});
      await pump(tester, 'order_tracker', {
        'title': 'Order 1042',
        'steps': [
          {'label': 'Packed', 'status': 'done'},
          {'label': 'On its way', 'status': 'current'},
          {'label': 'Delivered', 'status': 'pending'},
        ],
      });
      expect(tester.takeException(), isNull);
      expect(find.text('Packed'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
    });

    testWidgets('draws the built-in card when the template draws nothing for the block', (tester) async {
      rendelCardTemplates = RendelCardTemplate.parseAll({
        'info_card': {
          'node': {'type': 'text', 'bind': 'body'},
        },
      });
      await pump(tester, 'info_card', {'title': 'Free returns'});
      expect(tester.takeException(), isNull);
      expect(find.text('Free returns'), findsOneWidget);
    });

    for (final kind in rendelTemplateKinds) {
      testWidgets('$kind survives hostile props under a template', (tester) async {
        rendelCardTemplates = RendelCardTemplate.parseAll({
          'product_cards': _productList,
          'item_list': {
            'node': {'type': 'text', 'bind': 'title'},
          },
          'info_card': _infoCard,
          'order_tracker': _tracker,
        });
        await pump(tester, kind, {
          'items': 'not a list',
          'title': 7,
          'steps': [null, 3, {'label': null}],
          'cta': 'not a button',
        });
        expect(tester.takeException(), isNull);
      });
    }
  });
}
