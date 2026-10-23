import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/read_aloud.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each answer's opening read aloud, in the answer's own language (Tuna
/// 2026-10-23, after Monogram).
class _Api extends RendelApiClient {
  _Api(this.script) : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<RendelWireEvent> script;

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) => Stream.fromIterable(script);
}

/// A voice that writes down what it was asked to say.
class _Voice extends RendelVoice {
  final said = <(String, String)>[];
  var stops = 0;

  @override
  Future<void> speak(String text, String locale) async {
    if (on.value) said.add((text, locale));
  }

  @override
  Future<void> stop() async => stops++;
}

WireBlock _text(String markdown) =>
    WireBlock(id: 't', type: 'text', fallbackText: '', props: {'markdown': markdown})..ready = true;

void main() {
  group('spokenLead', () {
    test("says the answer's opening paragraph, as words", () {
      expect(
        spokenLead([
          _text('Bugün hava ılık ama akşama doğru ==yağmur %75== görünüyor; yarın ise **18°** civarında.\n\n'
              '## Sıcaklıklar\nTüm değerler Celsius.'),
        ]),
        'Bugün hava ılık ama akşama doğru yağmur %75 görünüyor; yarın ise 18° civarında.',
      );
    });

    test('two sentences at most, and a link by its words', () {
      expect(
        spokenLead([_text('One. Two, see [the guide](https://x.io/a). Three. Four.')]),
        'One. Two, see the guide.',
      );
    });

    test('skips what is not prose, and says nothing when there is none', () {
      final card = WireBlock(id: 'c', type: 'info_card', fallbackText: 'A card', props: {})..ready = true;
      expect(spokenLead([card, _text('# \n\nYour order is on its way.')]), 'Your order is on its way.');
      expect(spokenLead([card]), isNull);
    });
  });

  group('the thread', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<(ConversationController, _Voice)> open(WidgetTester tester, List<RendelWireEvent> script,
        {String? locale}) async {
      final c = ConversationController(
        api: _Api(script),
        actions: const {},
        sdkVersion: 'flutter/test',
        locale: locale,
      );
      final voice = _Voice();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ThreadScreen(controller: c, voice: voice)),
      ));
      return (c, voice);
    }

    List<RendelWireEvent> answer(String markdown, {String? lang}) => [
          const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
          BlockReady(index: 0, block: _text(markdown)),
          TurnEnd(status: 'completed', pending: const [], lang: lang),
        ];

    testWidgets("reads a finished answer in the answer's language", (tester) async {
      final (c, voice) = await open(tester, answer('Yarın hava açık. Detaylar aşağıda.', lang: 'tr'), locale: 'en');
      await tester.runAsync(() => c.send('Hava nasıl?'));
      await tester.pump();
      expect(voice.said, [('Yarın hava açık. Detaylar aşağıda.', 'tr')]);
    });

    testWidgets("falls back to the app's language when the server does not say", (tester) async {
      final (c, voice) = await open(tester, answer('Tomorrow is clear.'), locale: 'en-GB');
      await tester.runAsync(() => c.send('Weather?'));
      await tester.pump();
      expect(voice.said.single.$2, 'en-GB');
    });

    testWidgets('reads nothing of a turn that did not finish', (tester) async {
      final (c, voice) = await open(tester, [
        const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
        BlockReady(index: 0, block: _text('Half an answer.')),
        const TurnEnd(status: 'error', pending: []),
      ]);
      await tester.runAsync(() => c.send('Hi'));
      await tester.pump();
      expect(voice.said, isEmpty);
    });

    testWidgets('the speaker turns it off, and a new question stops the voice', (tester) async {
      final (c, voice) = await open(tester, answer('Tomorrow is clear.', lang: 'en'));
      await tester.runAsync(() => c.send('Weather?'));
      await tester.pump();
      expect(voice.said, hasLength(1));

      await tester.tap(find.bySemanticsLabel('Read answers aloud'));
      await tester.pump();
      expect(voice.on.value, isFalse);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

      final stopsBefore = voice.stops;
      await tester.enterText(find.byType(TextField), 'And Friday?');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send message'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(voice.stops, greaterThan(stopsBefore));
      expect(voice.said, hasLength(1), reason: 'off stays off');
    });
  });
}
