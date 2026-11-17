import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/lab/lab.dart' show LabGlass, LabWash;
import 'package:rendel/src/ui/thread_screen.dart';

/// The panel's look (design/plans/sdk-look-a.md, Tuna 2026-11-15): what it
/// promises beyond what the older tests already hold it to.
void main() {
  tearDown(() {
    RendelLook.groundLight = null;
    RendelLook.suggestionCards = const {};
  });

  Future<ConversationController> pump(WidgetTester tester, RendelTheme theme, {double keyboard = 0}) async {
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
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: RendelThemeScope(
            theme: theme,
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                headline: 'What can I do for you?',
                suggestions: const ['Where is my order?', 'Return an item'],
                onDictate: (_) async => null,
                onPickAttachment: (_) async => null,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return c;
  }

  testWidgets('the glass takes the dark column on a dark theme (§1)', (tester) async {
    final light = RendelTheme.paper();
    final dark = RendelTheme.fromTokens(
      surface: const Color(0xFF121413),
      onSurface: const Color(0xFFF2F2EF),
      accent: const Color(0xFF7FC8A0),
      onAccent: const Color(0xFF0B1A12),
    );
    expect(LabGlass.fillOf(light), const Color(0x9EFFFFFF));
    expect(LabGlass.lineOf(light), const Color(0x14000000));
    expect(LabGlass.fillOf(dark), const Color(0x1AFFFFFF));
    expect(LabGlass.lineOf(dark), const Color(0x1FFFFFFF));
    await pump(tester, dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('+ opens the sources over the card, and nothing above it moves (§6)', (tester) async {
    await pump(tester, RendelTheme.paper());
    final title = tester.getRect(find.text('What can I do for you?'));
    final card = tester.getRect(find.text('Where is my order?'));
    await tester.tap(find.bySemanticsLabel('Attach a file'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Photos'), findsOneWidget);
    expect(tester.getRect(find.text('What can I do for you?')), title);
    expect(tester.getRect(find.text('Where is my order?')), card);
    // A tap anywhere else closes it, and still nothing has moved.
    await tester.tapAt(const Offset(400, 120));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Photos'), findsNothing);
    expect(tester.getRect(find.text('What can I do for you?')), title);
  });

  testWidgets('a suggestion the app gives a card for is drawn with its title and line (§5)', (tester) async {
    RendelLook.suggestionCards = const {
      'Where is my order?': RendelSuggestionCard(title: 'Track my order', line: 'Where it is right now'),
    };
    await pump(tester, RendelTheme.paper());
    expect(find.text('Track my order'), findsOneWidget);
    expect(find.text('Where it is right now'), findsOneWidget);
    // One without a card keeps its own words.
    expect(find.text('Return an item'), findsOneWidget);
  });

  testWidgets('suggestions with no picture are a list under the greeting, an arrow on each row (Tuna, 2026-11-17, B5)', (tester) async {
    await pump(tester, RendelTheme.paper());
    final words = find.text('Return an item');
    expect(words, findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    // One glass card for the two, under the greeting, a round arrow at each row's end.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
    final list = find.ancestor(of: words, matching: find.byType(LabGlass)).first;
    expect(find.descendant(of: list, matching: find.text('Where is my order?')), findsOneWidget);
    expect(tester.getRect(list).top, greaterThan(tester.getRect(find.text('What can I do for you?')).bottom));
    // The words start after the row's padding (20), with no picture's place.
    expect(tester.getRect(words).left - tester.getRect(list).left, closeTo(20, 1.5));
  });

  testWidgets("the ground's light takes the app's two colours when it names them (§2)", (tester) async {
    RendelLook.groundLight = (const Color(0xFFD9A43A), const Color(0xFF1E3B2F));
    await pump(tester, RendelTheme.paper());
    final wash = find.byType(LabWash);
    expect(wash, findsOneWidget);
    final gradient = tester
        .widgetList<DecoratedBox>(find.descendant(of: wash, matching: find.byType(DecoratedBox)))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .firstWhere((g) => g.begin == Alignment.centerLeft);
    // Gold on the left: warmer than it is blue. Spruce on the right: greener than red.
    final left = gradient.colors.first, right = gradient.colors.last;
    expect(left.r, greaterThan(left.b));
    expect(right.g, greaterThan(right.r));
  });
}
