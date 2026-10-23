import 'dart:async';

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
  _Api(this.script, {this.hold}) : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<RendelWireEvent> script;
  final sent = <Map<String, dynamic>>[];

  /// Held open before the turn's end, so a test can look while the cards are still coming.
  final Future<void>? hold;

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) async* {
    sent.add(body);
    for (final event in script) {
      if (event is TurnEnd && hold != null) await hold;
      yield event;
    }
  }
}

/// A voice that writes down what it was asked to say.
class _Voice extends RendelVoice {
  final said = <(String, String)>[];
  final urls = <String?>[];
  final parts = <List<String>>[];
  var stops = 0;

  @override
  Future<void> speak(String text, String locale, {String? url, List<String> parts = const []}) async {
    if (!on.value) return;
    said.add((text, locale));
    urls.add(url);
    this.parts.add(parts);
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

  group('read_aloud', () {
    Future<List<Object?>> capabilities(bool reads) async {
      final api = _Api(const [TurnEnd(status: 'completed', pending: [])]);
      final c = ConversationController(api: api, actions: const {}, sdkVersion: 'flutter/test', readsAloud: () => reads);
      await c.send('Hi');
      return (api.sent.single['client'] as Map)['capabilities'] as List<Object?>;
    }

    test('is declared only by a thread that will read, so the server begins no voice nobody plays', () async {
      expect(await capabilities(true), contains('read_aloud'));
      expect(await capabilities(false), isNot(contains('read_aloud')));
    });
  });

  group('the thread', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<(ConversationController, _Voice)> open(WidgetTester tester, List<RendelWireEvent> script,
        {String? locale, Future<void>? hold}) async {
      final c = ConversationController(
        api: _Api(script, hold: hold),
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

    List<RendelWireEvent> answer(String markdown, {String? lang, String? speech}) => [
          const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
          BlockReady(index: 0, block: _text(markdown)),
          TurnEnd(status: 'completed', pending: const [], lang: lang, speech: speech),
        ];

    testWidgets('starts reading the moment the opening is written, while the cards are still coming', (tester) async {
      final end = Completer<void>();
      final (c, voice) = await open(
        tester,
        [
          const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
          const BlockStart(index: 0, id: 't', blockType: 'text'),
          const BlockDelta(index: 0, textDelta: 'C vitamini için bir doktora danışın. İşte mağazadakiler.'),
          const TurnSpeech(
            token: 'tok9',
            text: 'C vitamini için bir doktora danışın. İşte mağazadakiler.',
            lang: 'tr',
            parts: ['p1', 'p2'],
          ),
          const BlockStart(index: 1, id: 'p', blockType: 'product_cards'),
          const TurnEnd(status: 'completed', pending: [], lang: 'tr', speech: 'tok9'),
        ],
        hold: end.future,
      );
      late Future<bool> sent;
      await tester.runAsync(() async {
        sent = c.send('C vitamini önerir misin');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(c.busy, isTrue, reason: 'the turn has not ended');
      expect(voice.said, [('C vitamini için bir doktora danışın. İşte mağazadakiler.', 'tr')]);
      expect(voice.urls.single, endsWith('/v1/speech/tok9'));
      // A sentence at a time, so the first is heard soonest.
      expect(voice.parts.single.map((u) => u.split('/').last), ['p1', 'p2']);
      end.complete();
      await tester.runAsync(() => sent);
      await tester.pump();
      expect(voice.said, hasLength(1), reason: 'read once, not again at the end');
    });

    testWidgets("plays the server's natural voice when it sent a token", (tester) async {
      final (c, voice) = await open(tester, answer('Yarın hava açık.', lang: 'tr', speech: 'tok123'));
      await tester.runAsync(() => c.send('Hava nasıl?'));
      await tester.pump();
      expect(voice.urls.single, '${c.api.config.apiBaseUrl}/v1/speech/tok123');
    });

    testWidgets('and leaves it to the phone when it did not', (tester) async {
      final (c, voice) = await open(tester, answer('Yarın hava açık.', lang: 'tr'));
      await tester.runAsync(() => c.send('Hava nasıl?'));
      await tester.pump();
      expect(voice.urls.single, isNull);
    });

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

    testWidgets('reads nothing that lands with the app in the background, and stops when it goes there',
        (tester) async {
      final (c, voice) = await open(tester, answer('Tomorrow is clear.', lang: 'en'));
      // The order the platform reports them in; the binding refuses a skipped step.
      void go(List<AppLifecycleState> states) => states.forEach(tester.binding.handleAppLifecycleStateChanged);
      final stops = voice.stops;
      go([AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      expect(voice.stops, greaterThan(stops), reason: 'put away, the voice stops');
      await tester.runAsync(() => c.send('Weather?'));
      await tester.pump();
      expect(voice.said, isEmpty);
      go([AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
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
