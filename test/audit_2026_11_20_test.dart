// What the component audit of 2026-11-20 found, each held: every block in
// every app theme, light and dark, against Flutter's accessibility
// guidelines and the web SDK's renderer.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show chartScale;

void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  Future<void> pump(WidgetTester tester, String type, Map<String, dynamic> props, {RendelStrings? strings}) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Widget child = Builder(
      builder: (c) => ComponentRegistry.build(
        c,
        WireBlock(id: 'b', type: type, fallbackText: 'A $type block.', props: props)..ready = true,
        dispatch,
      ),
    );
    if (strings != null) child = RendelStringsScope(strings: strings, child: child);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a signed amount carries one sign, in front, wherever the model wrote its own', (tester) async {
    await pump(tester, 'item_list', {
      'items': [
        {'title': 'Refund', 'amount': {'value': '€-4.20', 'tone': 'negative'}},
        {'title': 'Salary', 'amount': {'value': 'US\$ +2,450', 'tone': 'positive'}},
        {'title': 'Coffee', 'amount': {'value': '-3.10', 'tone': 'negative'}},
        {'title': 'Rent', 'amount': {'value': '£900', 'tone': 'neutral'}},
      ],
    });
    for (final shown in ['−€4.20', '+US\$ 2,450', '−3.10', '£900']) {
      expect(find.textContaining(shown), findsOneWidget, reason: shown);
    }
  });

  testWidgets('a gallery picture with no alt and no caption is named by which picture it is', (tester) async {
    final handle = tester.ensureSemantics();
    final images = [
      {'url': 'https://rendel.ai/a.jpg'},
      {'url': 'https://rendel.ai/b.jpg'},
    ];
    await pump(tester, 'media_gallery', {'images': images});
    expect(find.bySemanticsLabel(RegExp('Picture 2 of 2')), findsWidgets);
    await pump(tester, 'media_gallery', {'images': images}, strings: RendelStrings.forLocale('tr'));
    expect(find.bySemanticsLabel(RegExp('Resim 2, toplam 2')), findsWidgets);
    handle.dispose();
  });

  test('the picture name is written in every language the SDK speaks', () {
    for (final tag in ['en', 'tr', 'de', 'fr', 'es', 'ar']) {
      final s = RendelStrings.forLocale(tag);
      expect(s.pictureNumber(3, 12), allOf(contains('3'), contains('12')), reason: tag);
      if (tag != 'en') expect(s.pictureOf, isNot(const RendelStrings().pictureOf), reason: tag);
    }
  });

  test("the primary's lit fill keeps its words at 4.5:1 a quarter of the way down", () {
    // Klinik's teal and Derma's rose pass flat and read 4.42 and 4.17 under Flutter's guideline at 82%.
    for (final accent in ['#0e7c7b', '#9C5766', '#1E3A2B']) {
      final theme = RendelRemoteConfig.tryParse(jsonEncode({
        'config': {
          'theme': {'accent': accent, 'onAccent': '#FFFFFF', 'surfaceRaised': '#FFFFFF'},
        },
      }))!
          .applyTo(RendelTheme.paper());
      final c = theme.colors;
      final top = Color.lerp(c.surfaceRaised, c.accent, theme.litMix)!;
      expect(contrastRatio(c.onAccent, Color.lerp(top, c.accent, 0.25)!), greaterThanOrEqualTo(4.5), reason: accent);
    }
    expect(RendelTheme.paper().litMix, 0.82);
  });

  testWidgets("a form's text row is one named field to a screen reader, not a nameless button beside it", (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, 'form', {
      'form_id': 'f',
      'submit_label': 'Send',
      'fields': [
        {'name': 'note', 'label': 'Note', 'kind': 'text'},
      ],
    });
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  test("a chart's scale is round, as the web SDK's niceScale", () {
    for (final (min, max, lo, hi, step) in const [
      (0.0, 424.0, 0.0, 500.0, 250.0),
      (0.0, 62.0, 0.0, 75.0, 25.0),
      (0.0, 0.0, 0.0, 1.0, 0.5),
      (-120.0, 340.0, -200.0, 400.0, 200.0),
      (-5.0, 0.0, -5.0, 0.0, 2.5),
      (0.0, 1980.0, 0.0, 2000.0, 1000.0),
    ]) {
      final s = chartScale(min, max);
      expect((s.lo, s.hi, s.step), (lo, hi, step), reason: '$min..$max');
      expect(s.hi.isNegative, isFalse, reason: 'no -0 at the top of $min..$max');
    }
  });

  testWidgets('a line chart names its round top, not the peak', (tester) async {
    await pump(tester, 'chart', {
      'kind': 'line',
      'labels': ['Mar', 'Apr', 'May'],
      'series': [
        {'name': 'This year', 'data': [120, 424, 300]},
        {'name': 'Last year', 'data': [80, 200, 260]},
      ],
    });
    expect(find.text('500'), findsOneWidget);
    expect(find.text('424'), findsNothing);
  });

  // The second pass the same day: the boundary that says a control is one
  // (WCAG 1.4.11). On the rail, an empty box, an unpicked star and an off
  // switch read 1.3 to 1.4:1.
  final faint = RendelTheme.paper().colors.onSurfaceFaint;

  Iterable<BoxDecoration> decorations(WidgetTester tester) => tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>();

  testWidgets("a checklist's empty box is ringed in the faint ink", (tester) async {
    await pump(tester, 'checklist', {
      'items': [
        {'id': 'a', 'title': 'Unplug the modem', 'done': true},
        {'id': 'b', 'title': 'Check the light'},
      ],
    });
    final rings = decorations(tester).map((d) => d.border).whereType<Border>().map((b) => b.top.color).toSet();
    expect(rings, contains(faint));
  });

  testWidgets("a rating's unpicked stars are outlines in the faint ink", (tester) async {
    await pump(tester, 'rating', {'question': 'How was it?', 'scale': 'stars_5'});
    final stars = tester.widgetList<Icon>(find.byIcon(Icons.star_outline_rounded));
    expect(stars, hasLength(5));
    expect(stars.map((i) => i.color).toSet(), {faint});
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets("a form's switch is ringed in the faint ink when off, and its knob stays where it was", (tester) async {
    await pump(tester, 'form', {
      'form_id': 'f',
      'fields': [
        {'kind': 'toggle', 'name': 'news', 'label': 'News'},
      ],
      'submit_label': 'Send',
    });
    final track = decorations(tester).firstWhere((d) => d.borderRadius == BorderRadius.circular(999));
    expect((track.border! as Border).top.color, faint);
    final knob = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle);
    expect(tester.getSize(knob.first), const Size(20, 20));
  });

  // Under reduced motion a streaming answer's caret is held solid and a block
  // on its way does not breathe; their clocks ran on regardless, asking for a
  // frame sixty times a second for nothing.
  for (final still in [true, false]) {
    testWidgets('a streaming answer and a block on its way ${still ? 'ask for no frames under' : 'move without'} reduced motion', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Widget part(String type, Map<String, dynamic> props) => Builder(
            builder: (c) => ComponentRegistry.build(c, WireBlock(id: type, type: type, fallbackText: 'A $type block.', props: props)..ready = false, dispatch),
          );
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: const Size(390, 1600), devicePixelRatio: 3, disableAnimations: still),
        child: MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(body: Column(children: [part('text', {'markdown': 'Your order left'}), part('item_list', {'items': []})])),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, !still);
    });
  }
}
