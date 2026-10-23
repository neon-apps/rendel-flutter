import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show BlockEnter;

/// An answer's words at a steady pace, and its blocks in step (Tuna
/// 2026-10-23, after Monogram).
void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    canHandle: (_) => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
  );

  WireBlock text(String id, String markdown) =>
      WireBlock(id: id, type: 'text', fallbackText: markdown, props: {'markdown': markdown})..ready = true;

  Future<void> pump(WidgetTester tester, List<WireBlock> blocks, Set<String> seen) async {
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: Column(
            children: [
              for (final block in blocks)
                BlockEnter(
                  key: ValueKey(block.id),
                  id: block.id,
                  seen: seen,
                  child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
                ),
            ],
          ),
        ),
      ),
    ));
  }

  /// The alpha each word of [words]' paragraph is drawn in, in order.
  List<double> alphas(WidgetTester tester, String first) {
    final paragraph = tester.widget<RichText>(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith(first)));
    final out = <double>[];
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false) && span.style?.color != null) out.add(span.style!.color!.a);
      return true;
    });
    return out;
  }

  testWidgets('a text arriving now has its words come in one after another, and all of them land', (tester) async {
    await pump(tester, [text('t', 'Your order is on its way.')], {});
    await tester.pump(const Duration(milliseconds: 40));
    final early = alphas(tester, 'Your');
    expect(early, hasLength(6));
    expect(early.first, greaterThan(early.last), reason: 'the first word is ahead of the last');
    await tester.pump(const Duration(seconds: 2));
    expect(alphas(tester, 'Your').every((a) => a > 0.99), isTrue);
    expect(find.text('Your order is on its way.', findRichText: true), findsOneWidget);
  });

  testWidgets('a text that has been seen before is simply there', (tester) async {
    await pump(tester, [text('t', 'Your order is on its way.')], {'t'});
    expect(alphas(tester, 'Your'), isEmpty, reason: 'no word drawn apart from the others');
  });

  testWidgets('blocks arriving together enter in step, the second after the first', (tester) async {
    await pump(tester, [text('a', 'First.'), text('b', 'Second.')], {});
    await tester.pump(const Duration(milliseconds: 100));
    final fades = tester.widgetList<FadeTransition>(find.byType(FadeTransition)).toList();
    expect(fades.first.opacity.value, greaterThan(0));
    expect(fades.last.opacity.value, 0, reason: 'its turn comes 150 ms after the first');
    await tester.pump(const Duration(seconds: 1));
    expect(fades.last.opacity.value, 1);
  });
}
