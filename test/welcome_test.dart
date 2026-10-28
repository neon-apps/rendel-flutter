import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// The opening screen as the console's Appearance preview draws it (Tuna,
/// 2026-10-28, Grove on a phone beside the preview): the welcome at the top,
/// the suggestions on the raised surface, and the words at the panel's own
/// spacing inside a Material 3 host, whose text theme spaces body text wider.
void main() {
  Future<void> pump(WidgetTester tester, RendelTheme theme) async {
    final c = ConversationController(
      api: RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
        httpClient: MockClient((request) async => http.Response('{}', 200)),
      ),
      actions: const {},
      sdkVersion: 'flutter/test',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2E7D32), useMaterial3: true),
      home: RendelThemeScope(
        theme: theme,
        child: Scaffold(
          body: ThreadScreen(
            controller: c,
            headline: 'How can I help with your shop?',
            suggestions: const ['Where is my order?', 'Return an item'],
            onPickAttachment: (_) async => null,
            onDictate: (_) async => null,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the welcome opens at the top of the panel, not mid-screen', (tester) async {
    await pump(tester, RendelTheme.paper());
    final title = tester.getTopLeft(find.text('How can I help with your shop?'));
    // Only the panel's own padding above it; the panel's header and padding put it at 104; centred, it sat at 189.
    expect(title.dy, lessThan(140));
  });

  testWidgets('the suggestions card is the raised surface, as on the web', (tester) async {
    // Grove's own tokens: on paper the raised and high surfaces are one white.
    final theme = RendelTheme.fromTokens(
      surface: const Color(0xFFF7FBF1),
      onSurface: const Color(0xFF191D17),
      accent: const Color(0xFF3C6939),
      onAccent: const Color(0xFFFFFFFF),
      surfaceRaised: const Color(0xFFF1F5EB),
      surfaceHigh: const Color(0xFFE6E9E0),
    );
    await pump(tester, theme);
    final card = tester
        .widgetList<DecoratedBox>(find.ancestor(of: find.text('Where is my order?'), matching: find.byType(DecoratedBox)))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.border != null);
    expect(card.color, theme.colors.surfaceRaised);
  });

  testWidgets("a Material 3 host's letter spacing does not reach the panel's words", (tester) async {
    await pump(tester, RendelTheme.paper());
    for (final words in ['Where is my order?', 'How can I help with your shop?']) {
      final style = tester.renderObject<RenderParagraph>(find.text(words)).text.style;
      expect(style?.letterSpacing ?? 0, lessThanOrEqualTo(0), reason: words);
    }
  });
}
