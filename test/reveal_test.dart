import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show BlockEnter;

/// An answer written at one pace, its blocks in step (Tuna 2026-10-23, after
/// Monogram; Özlem 2026-10-28: a paragraph at a time is "tak tak tak", not
/// a flow).
void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    canHandle: (_) => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
  );

  WireBlock text(String id, String markdown) =>
      WireBlock(id: id, type: 'text', fallbackText: markdown, props: {'markdown': markdown})..ready = true;

  /// [blocks] on one [page], each entering unless [seen] has its id.
  Future<void> pump(
    WidgetTester tester,
    List<WireBlock> blocks,
    Set<String> seen, {
    Object? page,
    bool still = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: still),
              // Scrolls: a long text is longer than the test's screen.
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final block in blocks)
                      BlockEnter(
                        key: ValueKey(block.id),
                        id: block.id,
                        seen: seen,
                        page: page,
                        child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  /// The alpha each word of [first]'s paragraph is drawn in, in order.
  List<double> alphas(WidgetTester tester, String first) {
    final paragraph = tester.widget<RichText>(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith(first)));
    final out = <double>[];
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false) && span.style?.color != null) out.add(span.style!.color!.a);
      return true;
    });
    return out;
  }

  /// How far in each block's entrance is, in order.
  List<double> entrances(WidgetTester tester) =>
      tester.widgetList<FadeTransition>(find.byType(FadeTransition)).map((fade) => fade.opacity.value).toList();

  /// The streaming caret, which is a widget of its own in the line.
  Finder caret() => find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Caret');

  testWidgets('a text arriving now has its words come in one after another, and all of them land', (tester) async {
    await pump(tester, [text('t', 'Your order is on its way.')], {}, page: Object());
    // Past the beat a block may wait for the one before it.
    await tester.pump(const Duration(milliseconds: 200));
    final early = alphas(tester, 'Your');
    expect(early, hasLength(6));
    expect(early.first, greaterThan(early.last), reason: 'the first word is ahead of the last');
    await tester.pump(const Duration(seconds: 2));
    expect(alphas(tester, 'Your').every((a) => a > 0.99), isTrue);
    expect(find.text('Your order is on its way.', findRichText: true), findsOneWidget);
  });

  testWidgets('a text that has been seen before is simply there', (tester) async {
    await pump(tester, [text('t', 'Your order is on its way.')], {'t'}, page: Object());
    expect(alphas(tester, 'Your'), isEmpty, reason: 'no word drawn apart from the others');
  });

  testWidgets('under reduced motion the words are simply there', (tester) async {
    await pump(tester, [text('t', 'Your order is on its way.')], {}, page: Object(), still: true);
    expect(alphas(tester, 'Your'), isEmpty);
    expect(find.text('Your order is on its way.', findRichText: true), findsOneWidget);
  });

  testWidgets('blocks arriving together enter in step, the second after the first', (tester) async {
    await pump(tester, [text('a', 'First.'), text('b', 'Second.')], {}, page: Object());
    await tester.pump(const Duration(milliseconds: 100));
    final fades = entrances(tester);
    expect(fades.first, greaterThan(0));
    expect(fades.last, 0, reason: 'its turn comes 150 ms after the first');
    await tester.pump(const Duration(seconds: 1));
    expect(entrances(tester).last, 1);
  });

  testWidgets('the page is written at one pace: the next paragraph waits for the one above it', (tester) async {
    // 99 characters: 0.9 s at 110 a second.
    final long = List.filled(20, 'word').join(' ');
    await pump(tester, [text('a', long), text('b', 'And then this.')], {}, page: Object());
    await tester.pump(const Duration(milliseconds: 500));
    final first = alphas(tester, 'word');
    expect(first.first, 1, reason: 'the first word is in');
    expect(first.last, 0, reason: 'the last is not due until 0.86 s');
    expect(alphas(tester, 'And').first, 0, reason: 'the next paragraph waits');
    expect(entrances(tester).last, 0, reason: 'and so does its block');
    await tester.pump(const Duration(milliseconds: 800));
    expect(alphas(tester, 'word').every((a) => a > 0.99), isTrue);
    expect(alphas(tester, 'And').first, greaterThan(0), reason: 'its turn, once the first is written');
    expect(entrances(tester).last, greaterThan(0));
    await tester.pump(const Duration(seconds: 2));
    expect(alphas(tester, 'And').every((a) => a > 0.99), isTrue);
    expect(entrances(tester).last, 1);
  });

  testWidgets('a card lands once the words above it are written', (tester) async {
    final long = List.filled(20, 'word').join(' ');
    final card = WireBlock(id: 'c', type: 'info_card', fallbackText: 'A card.', props: {'title': 'A card'})..ready = true;
    await pump(tester, [text('a', long), card], {}, page: Object());
    await tester.pump(const Duration(milliseconds: 500));
    expect(entrances(tester).last, 0, reason: 'the card waits for the paragraph');
    await tester.pump(const Duration(milliseconds: 800));
    expect(entrances(tester).last, greaterThan(0));
  });

  testWidgets('a long text is written faster, never longer than four seconds', (tester) async {
    // 2399 characters: 22 s at the page's pace, so the pace rises.
    final long = List.filled(400, 'words').join(' ');
    await pump(tester, [text('t', long)], {}, page: Object());
    await tester.pump(const Duration(seconds: 2));
    expect(alphas(tester, 'words').last, 0);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(alphas(tester, 'words').every((a) => a > 0.99), isTrue);
  });

  testWidgets('a stream keeps its pace as more arrives, and its caret waits at the end', (tester) async {
    final page = Object();
    final block = WireBlock(id: 's', type: 'text', fallbackText: '', props: {})..streamingText = 'Hello there';
    await pump(tester, [block], {}, page: page);
    await tester.pump(const Duration(milliseconds: 600));
    expect(alphas(tester, 'Hello').every((a) => a > 0.99), isTrue);
    expect(caret(), findsOneWidget, reason: 'the writer caught up with the stream');

    block.streamingText += ' and now more words.';
    await pump(tester, [block], {}, page: page);
    await tester.pump(const Duration(milliseconds: 50));
    final words = alphas(tester, 'Hello');
    expect(words.take(2).every((a) => a > 0.99), isTrue, reason: 'what was in stays in');
    expect(words[2], greaterThan(0), reason: 'the new words begin at once');
    expect(words[2], lessThan(1));
    expect(words.last, 0, reason: 'and come in at the page\'s pace');
    expect(caret(), findsNothing, reason: 'no caret while words are still coming in');
    await tester.pump(const Duration(seconds: 1));
    expect(alphas(tester, 'Hello').every((a) => a > 0.99), isTrue);
    expect(caret(), findsOneWidget);
  });
}
