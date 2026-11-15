import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';
import 'package:rendel/src/ui/lab/lab.dart' show LabGlass;

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

  testWidgets('the welcome is centred, a little above the middle (sdk-look-a §4)', (tester) async {
    await pump(tester, RendelTheme.paper());
    final screen = tester.getSize(find.byType(Scaffold));
    final title = tester.getCenter(find.text('How can I help with your shop?'));
    expect(title.dx, closeTo(screen.width / 2, 1));
    expect(title.dy, lessThan(screen.height / 2));
  });

  testWidgets('each suggestion is a glass card, in the theme\'s own colours', (tester) async {
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
        .widgetList<Container>(find.ancestor(of: find.text('Where is my order?'), matching: find.byType(Container)))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.border != null);
    expect(card.border, Border.all(color: LabGlass.lineOf(theme), width: 0.8));
    expect(card.gradient, isNotNull, reason: 'the glass tint');
  });

  testWidgets("a Material 3 host's letter spacing does not reach the panel's words", (tester) async {
    await pump(tester, RendelTheme.paper());
    for (final words in ['Where is my order?', 'How can I help with your shop?']) {
      final style = tester.renderObject<RenderParagraph>(find.text(words)).text.style;
      expect(style?.letterSpacing ?? 0, lessThanOrEqualTo(0), reason: words);
    }
  });
}
