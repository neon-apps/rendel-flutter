// A product card keeps its title's words whole at the largest accessibility
// text. On a rail card Flutter broke a word wherever the line ended: Tabak's
// "Ke / bapçısı" at the largest size (14 November).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

void main() {
  // Real Roboto, wherever this Flutter keeps it: the test font is about 1.9
  // times wider and would measure a different card.
  setUpAll(() async {
    for (var dir = File(Platform.resolvedExecutable).parent; dir.parent.path != dir.path; dir = dir.parent) {
      final roboto = File('${dir.path}/material_fonts/Roboto-Regular.ttf');
      if (roboto.existsSync()) {
        await (FontLoader('Roboto')..addFont(Future.value(roboto.readAsBytesSync().buffer.asByteData()))).load();
        return;
      }
    }
  });

  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  const titles = ['Halil Usta Kebapçısı', 'Lahmacun', 'Süt ürünü içerir'];

  Future<void> pump(WidgetTester tester, {required double width, required double scale, String? style}) async {
    tester.view.physicalSize = Size(width * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final theme = RendelTheme.paper();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 2400), textScaler: TextScaler.linear(scale)),
          child: RendelThemeScope(
            theme: theme,
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Builder(
                  builder: (context) => ComponentRegistry.build(
                    context,
                    WireBlock(
                      id: 'b_products',
                      type: 'product_cards',
                      fallbackText: 'Three dishes.',
                      props: {
                        if (style != null) 'style': style,
                        'items': [
                          for (final t in titles) {'id': t, 'title': t, 'price': '₺459,90'},
                        ],
                      },
                    )..ready = true,
                    dispatch,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Each word of [title] fits the line its paragraph was laid out in, at the
  /// scale it was drawn at: a word wider than that was broken inside itself.
  void expectWholeWords(WidgetTester tester, String title) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title).first);
    final style = paragraph.text.style!;
    for (final word in title.split(' ')) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
        maxLines: 1,
      )..layout();
      expect(painter.width, lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason: '"$word" of "$title" is ${painter.width.toStringAsFixed(1)} wide on a ${paragraph.size.width.toStringAsFixed(1)} line');
      painter.dispose();
    }
  }

  for (final env in [(width: 375.0, scale: 3.0), (width: 320.0, scale: 3.0), (width: 375.0, scale: 2.0)]) {
    testWidgets('rail cards at ${env.width.toInt()}@${env.scale}', (tester) async {
      await pump(tester, width: env.width, scale: env.scale);
      for (final t in titles) {
        expectWholeWords(tester, t);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the text is still larger than at the default size', (tester) async {
    await pump(tester, width: 375, scale: 3.0);
    final paragraph = tester.renderObject<RenderParagraph>(find.text('Halil Usta Kebapçısı').first);
    expect(paragraph.textScaler.scale(10), greaterThan(10), reason: 'the reader asked for large text');
  });
}
