import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

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

  Future<WireBlock> pump(WidgetTester tester) async {
    sent = [];
    tapped = [];
    final block = WireBlock(id: 'b', type: 'confirm_card', fallbackText: 'Add?', props: card())..ready = true;
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
}
