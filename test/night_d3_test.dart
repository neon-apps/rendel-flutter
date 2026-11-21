// What the night of 20 November's people found in the SDK's look (T02, T24,
// T30, T38), each held. The web SDK's `night-d3.test.ts` holds the same.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show shownOnPage;

var _n = 0;
WireBlock _b(String type, [Map<String, dynamic> props = const {}, bool ready = true]) =>
    WireBlock(id: '$type-${_n++}', type: type, fallbackText: 'A $type.', props: props)..ready = ready;

final _dispatch = RendelDispatcher(
  onAction: (_) async => true,
  onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
  canHandle: (_) => true,
);

Future<void> _pump(WidgetTester tester, WireBlock block) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: SingleChildScrollView(
          child: Builder(builder: (c) => ComponentRegistry.build(c, block, _dispatch)),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));
}

String _words(WidgetTester tester) =>
    tester.widgetList<RichText>(find.byType(RichText)).map((t) => t.text.toPlainText()).join('\n');

void main() {
  testWidgets('answer text drops a mark with no partner, and the backslash before a quote', (tester) async {
    Future<String> words(String markdown) async {
      await _pump(tester, _b('text', {'markdown': markdown}));
      return _words(tester);
    }

    // Derya's product page.
    expect(await words(r'Fırında ısıtılarak servis yapılan ==\"satır arası bir çörek gibi** bir ekmek ürünüdür.'),
        contains('servis yapılan "satır arası bir çörek gibi bir ekmek ürünüdür.'));
    expect(await words('**Önemli'), contains('Önemli'));
    expect(await words('**Önemli'), isNot(contains('*')));
    // What is not a stray mark stays.
    expect(await words('a == b, and 2**3'), contains('a == b, and 2**3'));
  });

  testWidgets('a figure is set smaller in its third, never cut', (tester) async {
    // Derya's month: "A$130,..." beside a whole "5" and "A$26,14".
    await _pump(
        tester,
        _b('stat_group', {
          'items': [
            {'label': 'Bu ay toplam', 'value': r'A$130,69'},
            {'label': 'Sipariş sayısı', 'value': '5'},
            {'label': 'Ortalama sipariş', 'value': r'A$26,14'},
          ]
        }));
    final total = find.text(r'A$130,69');
    expect(total, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(total).didExceedMaxLines, isFalse);
    // Its drawn width ends before the next figure starts.
    final fitted = find.ancestor(of: total, matching: find.byType(FittedBox));
    expect(tester.getRect(fitted).right, lessThanOrEqualTo(tester.getRect(find.text('5')).left));
  });

  testWidgets('a table draws no column that no row fills', (tester) async {
    // Laura's "Savings by plan": the last column ran off the plate, empty.
    await _pump(
        tester,
        _b('table', {
          'columns': ['Plan', 'Monthly', 'Annual', 'You save per seat per year'],
          'rows': [
            ['Starter', r'$15', r'$12'],
            ['Team', r'$39', r'$31.20', ''],
          ]
        }));
    expect(find.text('Annual'), findsOneWidget);
    expect(find.textContaining('You save'), findsNothing);
  });

  testWidgets("Undo's next words rise in where the button was, and not on a line read back (H4)", (tester) async {
    String? phase;
    final dispatch = RendelDispatcher(
      onAction: (_) async => true,
      onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
      canHandle: (_) => true,
      onUndo: (_) async {
        phase = 'undoing';
        return 'undone';
      },
      undoPhase: (_) => phase,
    );
    Future<void> show(WireBlock line) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: RendelThemeScope(
              theme: RendelTheme.paper(),
              child: Builder(builder: (c) => ComponentRegistry.build(c, line, dispatch)),
            ),
          ),
        ));
    double opacityOver(String words) => tester
        .widget<Opacity>(find.ancestor(of: find.text(words), matching: find.byType(Opacity)).first)
        .opacity;

    final until = DateTime.now().add(const Duration(minutes: 1)).toIso8601String();
    await show(_b('action_done', {'text': 'Added to your cart.', 'invocation_id': 'inv-u', 'undo_until': until}));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOver('Undoing…'), lessThan(1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacityOver('Undoing…'), 1);

    // A line read back already undone stands still from its first frame.
    await tester.pumpWidget(const SizedBox());
    await show(_b('action_done', {'text': 'Added to your cart.', 'invocation_id': 'inv-r', 'undone': true}));
    expect(opacityOver('Undone'), 1);
  });

  testWidgets("the way on does not write a question's emoji again when its round draws it (F0041)", (tester) async {
    await _pump(
        tester,
        _b('quick_replies', {
          'title': 'What next?',
          'items': [
            {'label': 'Show me a workout 💪', 'icon': '💪', 'action': {'kind': 'reply', 'text': 'Show me a workout'}},
            {'label': 'Add to cart', 'icon': 'cart', 'action': {'kind': 'reply', 'text': 'Add to cart'}},
          ]
        }));
    expect(find.text('Show me a workout'), findsOneWidget);
    expect(find.text('Show me a workout 💪'), findsNothing);
    expect(find.text('💪'), findsOneWidget);
    expect(find.text('Add to cart'), findsOneWidget);
  });

  testWidgets('a list row does not open its line on the status its pill says (F1013)', (tester) async {
    await _pump(
        tester,
        _b('item_list', {
          'items': [
            {'title': 'Sipariş M-2018', 'subtitle': 'Yolda · 4 ürün · 14:00–16:00', 'status': {'label': 'Yolda', 'tone': 'info'}},
            {'title': 'Sipariş M-2017', 'subtitle': 'Teslim edildi', 'status': {'label': 'Teslim edildi', 'tone': 'success'}},
          ]
        }));
    expect(find.text('4 ürün · 14:00–16:00'), findsOneWidget);
    expect(find.text('Yolda'), findsOneWidget, reason: 'the pill');
    expect(find.text('Teslim edildi'), findsOneWidget, reason: 'the pill, not the line as well');
  });

  test('a page leaves out a block with nothing in it, and a heading with nothing of its own under it', () {
    // Derya's product page: "Beslenme bilgileri" over a key_value with no
    // rows, and "Stok ve fiyat" over another; Elif's "Kısa yorumum" over the way on.
    final lede = _b('text', {'markdown': 'Çok lezzetli.'});
    final nutrition = _b('section', {'title': 'Beslenme bilgileri'});
    final noRows = _b('key_value', {'title': 'Beslenme değerleri', 'rows': <Object>[]});
    final allergens = _b('section', {'title': 'Alerjenler'});
    final tags = _b('tags', {
      'items': [
        {'label': 'Gluten'}
      ]
    });
    final stock = _b('section', {'title': 'Stok ve fiyat'});
    final noStock = _b('key_value', {'rows': <Object>[]});
    final comment = _b('section', {'title': 'Kısa yorumum'});
    final wayOn = _b('quick_replies', {
      'replies': [
        {'label': 'Akşam rutini'}
      ]
    });
    expect(shownOnPage([lede, nutrition, noRows, allergens, tags, stock, noStock, comment, wayOn]),
        [lede, allergens, tags, wayOn]);
    // Two headings in a row: the first has nothing of its own (Kargo ve Teslimat).
    final shipping = _b('section', {'title': 'Kargo ve Teslimat'});
    final returns = _b('section', {'title': 'İade ve Değişim'});
    final article = _b('article_card', {'title': 'İade ve Değişim'});
    expect(shownOnPage([shipping, returns, article]), [returns, article]);
    // A heading last stays out; one over a card still arriving stays in.
    expect(shownOnPage([lede, nutrition]), [lede]);
    final coming = _b('key_value', const {}, false);
    expect(shownOnPage([nutrition, coming]), [nutrition, coming]);
  });
}
