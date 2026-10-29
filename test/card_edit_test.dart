import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';

/// Values the user may change on a confirmation card (Tuna, 2026-10-11): each
/// takes its control, the change goes to the server, and the card confirmed
/// is the one the server drew last.
void main() {
  late List<Map<String, dynamic>> sent;
  late List<UIAction> tapped;
  Map<String, String>? answer;

  Map<String, dynamic> card() => {
        'invocation_id': 'inv_1',
        'action_name': 'add_to_cart',
        'summary': 'Add 1 of Oat Milk 1L to your cart?',
        'risk': 'write',
        'params': {'product_id': 'P003', 'quantity': 1, 'refund_to': 'card'},
        'params_display': [
          {'label': 'Product', 'value': 'Oat Milk 1L', 'param': 'product_id'},
          {'label': 'Quantity', 'value': '1', 'param': 'quantity'},
          {'label': 'Refund to', 'value': 'Card', 'param': 'refund_to'},
        ],
        'editable': [
          {'param': 'quantity', 'label': 'Quantity', 'kind': 'stepper', 'min': 1, 'max': 20},
          {
            'param': 'refund_to',
            'label': 'Refund to',
            'kind': 'choice',
            'options': [
              {'value': 'card', 'label': 'Card'},
              {'value': 'store_credit', 'label': 'Store credit'},
            ],
          },
        ],
        'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
        'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
      };

  Future<WireBlock> pump(WidgetTester tester, [Map<String, dynamic>? props]) async {
    sent = [];
    tapped = [];
    final block = WireBlock(id: 'b', type: 'confirm_card', fallbackText: 'Add?', props: props ?? card())..ready = true;
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ComponentRegistry.build(
                context,
                block,
                RendelDispatcher(
                  onAction: (action) async {
                    tapped.add(action);
                    return true;
                  },
                  onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
                  canHandle: (_) => true,
                  onEditCard: (block, edits) async {
                    sent.add(edits);
                    if (answer == null) {
                      // The server's redraw.
                      final params = Map<String, dynamic>.from(block.props['params'] as Map)..addAll(edits);
                      setState(() {
                        block.props['params'] = params;
                        block.props['summary'] = 'Add ${params['quantity']} of Oat Milk 1L to your cart?';
                      });
                    }
                    return answer;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    return block;
  }

  setUp(() => answer = null);

  testWidgets('a stepper sends the new count, and confirm waits for the redraw', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    // Pressed while the change waits: nothing is confirmed.
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(tapped, isEmpty);

    await tester.pump(const Duration(milliseconds: 500));
    expect(sent, [
      {'quantity': 2}
    ]);
    await tester.pump();
    expect(find.text('Add 2 of Oat Milk 1L to your cart?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(tapped, hasLength(1));
  });

  testWidgets('a choice sends at once', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Store credit'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(sent, [
      {'refund_to': 'store_credit'}
    ]);
  });

  testWidgets('a refused change says so and keeps the card from being confirmed', (tester) async {
    answer = {'quantity': '"quantity" must be <= 20'};
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text(const RendelStrings().cardEditInvalid), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(tapped, isEmpty);
  });

  testWidgets('without a way to send a change, the values are text', (tester) async {
    final block = WireBlock(id: 'b', type: 'confirm_card', fallbackText: 'Add?', props: card())..ready = true;
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: Builder(
            builder: (context) => ComponentRegistry.build(
              context,
              block,
              RendelDispatcher(
                onAction: (_) async => true,
                onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
                canHandle: (_) => true,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.bySemanticsLabel('More'), findsNothing);
    expect(find.text('Card'), findsOneWidget);
  });

  /// Values the person fills in on the card (`card_fill`, Tuna 2026-10-29):
  /// the server leaves them out of `params` and marks their control
  /// `required`, rather than asking for each in a turn of its own.
  group('a value filled in on the card', () {
    Map<String, dynamic> unfilled() => card()
      ..['params'] = {'product_id': 'P003', 'quantity': 1}
      ..['params_display'] = [
        {'label': 'Product', 'value': 'Oat Milk 1L', 'param': 'product_id'},
        {'label': 'Quantity', 'value': '1', 'param': 'quantity'},
      ]
      ..['editable'] = [
        {'param': 'quantity', 'label': 'Quantity', 'kind': 'stepper', 'min': 1, 'max': 20},
        {
          'param': 'refund_to',
          'label': 'Refund to',
          'kind': 'choice',
          'required': true,
          'options': [
            {'value': 'card', 'label': 'Card'},
            {'value': 'store_credit', 'label': 'Store credit'},
          ],
        },
        {'param': 'reason', 'label': 'Reason', 'kind': 'text', 'required': true, 'max_length': 200},
      ];

    test('is declared with each chat request', () async {
      final bodies = <Map<String, dynamic>>[];
      final c = ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/v1/chat')) bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response('', 200, headers: {'content-type': 'text/event-stream'});
          }),
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );
      await c.send('return my order');
      expect((bodies.single['client'] as Map)['capabilities'], contains('card_fill'));
      c.dispose();
    });

    testWidgets('its control is drawn empty, with its label', (tester) async {
      await pump(tester, unfilled());
      expect(find.text('Refund to · Required'), findsOneWidget);
      expect(find.text('Reason · Required'), findsOneWidget);
      // A choice with nothing chosen.
      for (final option in ['Card', 'Store credit']) {
        expect(tester.widget<RendelChip>(find.widgetWithText(RendelChip, option)).selected, isNot(true));
      }
      // An empty text field.
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('confirm waits until the redrawn card has every value', (tester) async {
      await pump(tester, unfilled());
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(tapped, isEmpty, reason: 'nothing filled in yet');

      await tester.tap(find.text('Store credit'));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(sent, [
        {'refund_to': 'store_credit'}
      ]);
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(tapped, isEmpty, reason: 'the reason is still missing');

      await tester.enterText(find.byType(TextField), 'Too small');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(sent.last, {'reason': 'Too small'});
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(tapped, hasLength(1));
    });

    /// QA on 2026-10-29 (R3-9, Grove): "Add the address …" above a
    /// greyed-out button, and nothing said which field the card waited for.
    testWidgets('an empty one says it is required, until it is filled in', (tester) async {
      await pump(tester, unfilled());
      // The field shows the "…" the card's sentence holds for it.
      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.hintText, '…');
      // A value that is not required carries no mark.
      expect(find.text('Quantity'), findsOneWidget);

      await tester.tap(find.text('Store credit'));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Refund to'), findsOneWidget);
      expect(find.text('Reason · Required'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Too small');
      await tester.pump();
      expect(find.text('Reason'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('the mark is in the reader\'s language', (tester) async {
      final block = WireBlock(id: 'b', type: 'confirm_card', fallbackText: 'Add?', props: unfilled())..ready = true;
      await tester.pumpWidget(MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: RendelStringsScope(
            strings: RendelStrings.forLocale('tr'),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) => ComponentRegistry.build(
                    context,
                    block,
                    RendelDispatcher(
                      onAction: (_) async => true,
                      onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
                      canHandle: (_) => true,
                      onEditCard: (_, __) async => null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(find.text('Reason · Zorunlu'), findsOneWidget);
    });

    testWidgets('a blank text is no value', (tester) async {
      final props = unfilled()..['params'] = {'product_id': 'P003', 'quantity': 1, 'refund_to': 'card', 'reason': '  '};
      await pump(tester, props);
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(tapped, isEmpty);
    });
  });

  testWidgets('a number beside its label has a width, so the card draws', (tester) async {
    // QA R3: unbounded in its row, the field's layout failed and the page was blank.
    await pump(tester, {
      ...card(),
      'editable': [
        {'param': 'quantity', 'label': 'Quantity', 'kind': 'number'},
      ],
    });
    expect(tester.takeException(), isNull);
    expect(find.text('Add 1 of Oat Milk 1L to your cart?'), findsOneWidget);
  });
}
