import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/followups.dart';
import 'package:rendel/src/ui/followup_card.dart';

/// The SDK's half of the demo persona test (2026-11-11): S-C and S-F.
void main() {
  group('a follow-up', () {
    test('reads its picture, https only', () {
      final card = {'id': 'a', 'title': 't', 'body': 'b', 'button': 'c'};
      expect(RendelFollowup.tryParse({...card, 'image_url': 'https://x/y.webp'})!.imageUrl, 'https://x/y.webp');
      expect(RendelFollowup.tryParse({...card, 'image_url': 'http://x/y.webp'})!.imageUrl, isNull);
      expect(RendelFollowup.tryParse(card)!.imageUrl, isNull);
    });

    testWidgets('draws the picture beside its words, and survives one that will not load', (tester) async {
      final theme = RendelTheme.fromTokens(
        surface: Colors.white,
        onSurface: Colors.black,
        accent: const Color(0xFF0E7C86),
        onAccent: Colors.white,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RendelFollowupCard(
            followup: const RendelFollowup(id: 'a', type: 'group_send', title: 'Court Mid', body: 'It is here', button: 'See', imageUrl: 'https://x/y.webp'),
            theme: theme,
            closeLabel: 'Close',
            onOpen: () {},
            onDismiss: () {},
          ),
        ),
      ));
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Court Mid'), findsOneWidget);
    });
  });

  test("the answer's highlight is made from the accent", () {
    final teal = RendelTheme.fromTokens(surface: Colors.white, onSurface: Colors.black, accent: const Color(0xFF0E7C86), onAccent: Colors.white);
    final red = RendelTheme.fromTokens(surface: Colors.white, onSurface: Colors.black, accent: const Color(0xFFAA0000), onAccent: Colors.white);
    expect(teal.mark, Color.lerp(Colors.white, const Color(0xFF0E7C86), 0.18));
    expect(teal.mark, isNot(red.mark));
  });
}
