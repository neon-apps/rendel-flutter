import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/theme.dart' show voiceGlow;
import 'package:rendel/src/ui/ring_voice_mode.dart' show RingVoiceMode;
import 'package:rendel/src/ui/thread_screen.dart';

/// Voice mode, Tuna 2026-10-21: on a dark theme its words were white on a
/// near-white glow (Corvo), and a sent question showed twice for a moment,
/// the words heard fading out under the question written over them. The ring
/// that listens (2026-11-23) keeps both: its own ground, and words that go
/// the moment the question is written.
void main() {
  final corvo = RendelTheme.fromTokens(
    surface: const Color(0xFF0B0C0E),
    onSurface: const Color(0xFFF1F0EC),
    accent: const Color(0xFFF1F0EC),
    onAccent: const Color(0xFF0B0C0E),
  );

  group('the glow', () {
    // What `voiceGlow` in derive.ts gives for the same grounds, to the byte.
    void same(Color surface, Color ink, int web) {
      final glow = voiceGlow(surface, ink).toARGB32();
      for (final shift in [16, 8, 0]) {
        expect(((glow >> shift) & 0xFF) - ((web >> shift) & 0xFF), inInclusiveRange(-1, 1));
      }
    }

    test("is the web SDK's", () {
      same(const Color(0xFF0B0C0E), const Color(0xFFF1F0EC), 0xFF313133);
      same(const Color(0xFFF2F2EF), const Color(0xFF121413), 0xFFFEFEFE);
      same(const Color(0xFF3B5BDB), const Color(0xFFFFFFFF), 0xFF4967DE);
    });

    test('reads under the words on any ground', () {
      for (final (surface, ink) in [
        (const Color(0xFF0B0C0E), const Color(0xFFF1F0EC)),
        (const Color(0xFF3B5BDB), const Color(0xFFFFFFFF)),
        (const Color(0xFFF2F2EF), const Color(0xFF121413)),
      ]) {
        expect(contrastRatio(ink, voiceGlow(surface, ink)), greaterThanOrEqualTo(4.5));
      }
    });
  });

  ConversationController held() => ConversationController(
        // A request that never answers: the question stays over the page.
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          httpClient: MockClient((_) => Completer<http.Response>().future),
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  Future<(Completer<String?>, void Function(String))> speak(
    WidgetTester tester,
    ConversationController c,
    RendelTheme theme,
  ) async {
    final done = Completer<String?>();
    late void Function(String) say;
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: theme,
          child: Scaffold(
            body: ThreadScreen(
              controller: c,
              onDictate: (onPartial) {
                say = onPartial;
                return done.future;
              },
              onStopDictating: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Held, as a finger holds it while it speaks.
    await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Speak instead of typing')));
    await tester.pump();
    return (done, say);
  }

  testWidgets('listens on the app\'s own ground, so its words read on a dark one', (tester) async {
    final c = held();
    addTearDown(c.dispose);
    final (_, say) = await speak(tester, c, corvo);
    say('Why is my balance lower');
    await tester.pump(const Duration(milliseconds: 400));

    // The ring's ground is the theme's own surface, nearly opaque over the page.
    final ground = tester
        .widgetList<ColoredBox>(find.descendant(of: find.byType(RingVoiceMode), matching: find.byType(ColoredBox)))
        .map((box) => box.color)
        .firstWhere((colour) => colour.withValues(alpha: 1) == corvo.colors.surface);
    expect(ground.a, greaterThan(0.95));
    // The newest word in the page's ink, which reads on it.
    final word = tester.widget<DefaultTextStyle>(
      find.ancestor(of: find.text('lower'), matching: find.byType(DefaultTextStyle)).first,
    );
    expect(word.style.color, corvo.colors.onSurface);
    expect(contrastRatio(corvo.colors.onSurface, corvo.colors.surface), greaterThanOrEqualTo(4.5));
  });

  testWidgets('a spoken question is written once, in the place it was heard in',
      (tester) async {
    final c = held();
    addTearDown(c.dispose);
    final (done, say) = await speak(tester, c, RendelTheme.paper());
    const words = 'Find white sneakers under 130 in size 42';
    say(words);
    await tester.pump();
    // The ring writes it word by word as it is heard.
    expect(find.text('sneakers'), findsOneWidget);

    done.complete(words);
    await tester.pump();
    // The ring is still landing, and only the question shows the words: the
    // heard ones go in the frame it is written.
    for (final ms in [0, 60, 120]) {
      await tester.pump(Duration(milliseconds: ms));
      expect(find.text(words), findsOneWidget);
      expect(find.text('sneakers'), findsNothing);
    }
    // Past the copilot's own time limit, which ends the turn it is holding.
    await tester.pump(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
  });
}
