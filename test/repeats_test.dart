import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

/// The Grove report's "same thing twice" findings: a courier's vehicle line
/// drawn twice on one card (P2-3), and "Cart" over "Cart" on a screen card.
void main() {
  Future<void> pump(WidgetTester tester, String type, Map<String, dynamic> props) async {
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: Builder(
            builder: (context) => ComponentRegistry.build(
              context,
              WireBlock(id: 'b', type: type, fallbackText: 'A block.', props: props)..ready = true,
              RendelDispatcher(
                onAction: (_) async => true,
                canHandle: (_) => true,
                onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
                routeTitle: (route) => route == 'cart' ? 'Cart' : 'My orders',
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('an info card draws a line once when meta and body say it alike', (tester) async {
    await pump(tester, 'info_card', {
      'title': 'Priya Nair',
      'meta': 'Red scooter · 7HG 21',
      'body': 'Red scooter · 7HG 21',
    });
    expect(find.text('Red scooter · 7HG 21'), findsOneWidget);
  });

  testWidgets("a screen card leaves out the route's title when it is the item's", (tester) async {
    await pump(tester, 'screens', {
      'items': [
        {'title': 'Cart', 'action': {'kind': 'navigate', 'route': 'cart', 'params': <String, Object?>{}}},
        {'title': 'Order M-3019', 'action': {'kind': 'navigate', 'route': 'orders', 'params': <String, Object?>{}}},
      ],
    });
    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('My orders'), findsOneWidget);
  });
}
