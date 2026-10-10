import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

/// The Grove report's section 4, the parts the SDK draws: a booked-out slot,
/// a day said twice, a card number broken over two lines, a highlight nobody
/// explained, and product names cut after two lines.
void main() {
  final picked = <String>[];

  Future<void> pump(WidgetTester tester, String type, Map<String, dynamic> props) async {
    picked.clear();
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: (context) => ComponentRegistry.build(
                context,
                WireBlock(id: 'b', type: type, fallbackText: 'A block.', props: props)..ready = true,
                RendelDispatcher(
                  onAction: (_) async => true,
                  canHandle: (_) => true,
                  onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
                  onSelect: (block, id, label) async {
                    picked.add(id);
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a booked-out window is shown and cannot be picked', (tester) async {
    await pump(tester, 'datetime_slots', {
      'title': 'Tomorrow morning',
      'slots': [
        {'id': 'S-8', 'label': '08:00–10:00', 'available': false},
        {'id': 'S-10', 'label': '10:00–12:00'},
      ],
    });
    expect(find.text('08:00–10:00'), findsOneWidget);
    await tester.tap(find.text('08:00–10:00'));
    await tester.tap(find.text('10:00–12:00'));
    await tester.pump();
    expect(picked, ['S-10']);
  });

  testWidgets('a long pass value takes its own row', (tester) async {
    await pump(tester, 'pass', {
      'kind': 'membership',
      'title': 'Grove Rewards',
      'fields': [
        {'label': 'Card number', 'value': '6018 2900 4471 0038'},
        {'label': 'Points', 'value': '3,710'},
        {'label': 'Member since', 'value': '2 Nov 2024'},
      ],
    });
    final number = tester.renderObject<RenderParagraph>(find.text('6018 2900 4471 0038'));
    // One line: its height is a single line of the 17pt value style.
    expect(number.size.height, lessThan(30));
  });

  testWidgets('a comparison that marks a best value says what the mark means', (tester) async {
    final rows = [
      {'label': 'Protein', 'values': ['3.8 g', '3.0 g'], 'best_index': 0},
    ];
    await pump(tester, 'comparison', {
      'items': [
        {'title': 'Oat Milk 1L'},
        {'title': 'Soy Milk 1L'},
      ],
      'rows': rows,
    });
    expect(find.text(const RendelStrings().comparisonBest), findsOneWidget);

    await pump(tester, 'comparison', {
      'items': [
        {'title': 'Oat Milk 1L'},
        {'title': 'Soy Milk 1L'},
      ],
      'rows': [
        {'label': 'Size', 'values': ['1 L', '1 L']},
      ],
    });
    expect(find.text(const RendelStrings().comparisonBest), findsNothing);
  });

  testWidgets('a product name gets three lines', (tester) async {
    await pump(tester, 'product_cards', {
      'items': [
        {'title': 'INNER GOODNESS Regular Soy Milk 1L', 'price': r'A$1.59'},
        {'title': 'INNER GOODNESS Soy Light Milk 1L', 'price': r'A$1.59'},
      ],
    });
    final title = tester.widget<Text>(find.text('INNER GOODNESS Regular Soy Milk 1L'));
    expect(title.maxLines, 3);
  });

  testWidgets('a bar chart reads out the bar that was tapped (Grove report)', (tester) async {
    await pump(tester, 'chart', {
      'kind': 'bar',
      'labels': ['Sep', 'Oct'],
      'unit': r'A$',
      'series': [
        {
          'data': [67.5, 119.04],
        },
      ],
    });
    expect(find.text(r'A$119.04'), findsOneWidget);
    await tester.tap(find.text('Sep'));
    await tester.pump();
    expect(find.text(r'A$67.50'), findsOneWidget);
    await tester.tap(find.text('Sep'));
    await tester.pump();
    expect(find.text(r'A$119.04'), findsOneWidget);
  });
}
