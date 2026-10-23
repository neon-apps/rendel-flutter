import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  var stops = 0;

  /// What [elapsed] says: how long the answer being read has been heard.
  Duration heard = Duration.zero;

  @override
  Duration get elapsed => playing.value == null ? Duration.zero : heard;

  @override
  Future<void> speak(String text, String locale, {String? url, String? key}) async {
    said.add((text, locale));
    urls.add(url);
    playing.value = key ?? text;
  }

  @override
  Future<void> stop() async {
    stops++;
    playing.value = null;
  }
}

/// The speaker, as a list of what it was given.
class _Out implements RendelPcmOut {
  final opened = <int>[];
  final fed = <int>[];
  var closes = 0;

  @override
  Future<void> open(int sampleRate) async => opened.add(sampleRate);

  @override
  Future<void> feed(Uint8List s16le) async => fed.add(s16le.length);

  @override
  Future<void> drained() async {}

  @override
  Future<void> close() async => closes++;
}

/// A server that sends a fifth of a second of the voice and then nothing, as
/// api.rendel.ai did for 18 seconds (2026-10-23); closing the client ends it.
class _Stalls extends http.BaseClient {
  final _body = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _body.add(Uint8List(9600));
    return http.StreamedResponse(_body.stream, 200,
        headers: {'content-type': 'audio/pcm; rate=24000; channels=1; encoding=s16le'});
  }

  @override
  void close() {
    if (_body.isClosed) return;
    _body.addError(http.ClientException('closed'));
    _body.close();
  }
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

  group('sentences', () {
    test('are cut as the server cuts them: not inside a number, after Dr. or before a lower-case ordinal', () {
      expect(sentences('Whey Protein 2.270 g şu an 1.299,90 TL. Stokta var.'),
          ['Whey Protein 2.270 g şu an 1.299,90 TL.', 'Stokta var.']);
      expect(sentences('Dr. Ayşe yarın 3. katta. Geç kalma.'), ['Dr. Ayşe yarın 3. katta.', 'Geç kalma.']);
    });
  });

  group('the natural voice', () {
    late List<Uri> asked;
    late _Out out;
    late http.Client Function() client;

    /// A server that answers [respond] for each request.
    void serve(http.StreamedResponse Function(Uri url) respond) {
      asked = [];
      client = () => MockClient.streaming((request, _) async {
            asked.add(request.url);
            return respond(request.url);
          });
    }

    http.StreamedResponse pcm(List<int> pieces) => http.StreamedResponse(
          Stream.fromIterable([for (final bytes in pieces) Uint8List(bytes)]),
          200,
          headers: {'content-type': 'audio/pcm; rate=24000; channels=1; encoding=s16le'},
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      out = _Out();
    });

    test('is streamed to the speaker as it arrives, and kept for a second tap', () async {
      serve((_) => pcm([4800, 43200]));
      final voice = RendelVoice(out: out, client: client);
      await voice.speak('Yarın hava açık.', 'tr', url: 'https://api.test/v1/speech/t1', key: 'a1');
      expect(asked.single.toString(), 'https://api.test/v1/speech/t1?f=pcm');
      expect(out.opened, [24000]);
      expect(out.fed.fold<int>(0, (a, b) => a + b), 48000);
      expect(voice.playing.value, isNull, reason: 'heard to the end');
      expect(voice.keptKey, 'a1');
      await voice.speak('Yarın hava açık.', 'tr', url: 'https://api.test/v1/speech/t1', key: 'a1');
      expect(asked, hasLength(1), reason: 'the second tap plays what was kept');
      expect(out.fed.fold<int>(0, (a, b) => a + b), 96000);
    });

    test('keeps an odd byte for its other half', () async {
      serve((_) => pcm([4801, 4799]));
      final voice = RendelVoice(out: out, client: client);
      await voice.speak('Bir.', 'tr', url: 'https://api.test/v1/speech/t2');
      expect(out.fed.every((bytes) => bytes.isEven), isTrue);
      expect(out.fed.fold<int>(0, (a, b) => a + b), 9600);
    });

    test('waits for half a second of the voice before the first sound, then feeds the rest as it comes', () async {
      // As api.rendel.ai sends it: a fifth of a second, a pause, then the rest.
      serve((_) => pcm([9600, 4800, 9600, 24000]));
      final voice = RendelVoice(out: out, client: client);
      await voice.speak('Yarın hava açık.', 'tr', url: 'https://api.test/v1/speech/t5');
      expect(out.fed, [24000, 24000]);
    });

    test('stays silent when the voice stalls before half a second of it is in', () async {
      final voice = RendelVoice(out: out, client: _Stalls.new);
      await voice.speak('Yarın hava açık.', 'tr', url: 'https://api.test/v1/speech/t6');
      expect(out.opened, isEmpty, reason: 'the speaker was never opened');
      expect(voice.playing.value, isNull);
    });

    test('asks for the whole file where the server turned the stream away', () async {
      serve((url) => url.query.contains('f=pcm')
          ? http.StreamedResponse(const Stream.empty(), 404)
          : http.StreamedResponse(Stream.value(Uint8List(2)), 200));
      final voice = RendelVoice(out: out, client: client);
      await voice.speak('Bir.', 'tr', url: 'https://api.test/v1/speech/t3');
      expect(asked.map((u) => u.toString()), ['https://api.test/v1/speech/t3?f=pcm', 'https://api.test/v1/speech/t3']);
      expect(out.opened, isEmpty);
    });

    test('stays silent, not robotic, when the natural voice fails', () async {
      serve((_) => http.StreamedResponse(const Stream.empty(), 502));
      final voice = RendelVoice(out: out, client: client);
      await voice.speak('Bir.', 'tr', url: 'https://api.test/v1/speech/t4');
      expect(asked, hasLength(1));
      expect(out.opened, isEmpty);
      expect(voice.playing.value, isNull);
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

    late Completer<String?> heard;

    Future<(ConversationController, _Voice)> open(WidgetTester tester, List<RendelWireEvent> script,
        {String? locale, Future<void>? hold, bool voiced = true}) async {
      final c = ConversationController(
        api: _Api(script, hold: hold),
        actions: const {},
        sdkVersion: 'flutter/test',
        locale: locale,
      );
      final voice = _Voice();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ThreadScreen(
            controller: c,
            voice: voiced ? voice : null,
            onDictate: (onPartial) {
              heard = Completer<String?>();
              return heard.future;
            },
            onStopDictating: () {},
          ),
        ),
      ));
      await tester.pump();
      return (c, voice);
    }

    /// A question asked out loud: the microphone, and its words heard whole.
    Future<void> say(WidgetTester tester, String words) async {
      await tester.tap(find.bySemanticsLabel('Speak instead of typing'));
      await tester.pump();
      heard.complete(words);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> type(WidgetTester tester, ConversationController c, String words) async {
      await tester.runAsync(() => c.send(words));
      // The page's entrance, before its foot can be found.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    List<RendelWireEvent> answer(String markdown, {String? lang, String? token}) => [
          const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
          BlockReady(index: 0, block: _text(markdown)),
          if (token != null) TurnSpeech(token: token, text: markdown, lang: lang),
          TurnEnd(status: 'completed', pending: const [], lang: lang),
        ];

    testWidgets("reads a spoken question's answer by itself, the moment its opening is written", (tester) async {
      final end = Completer<void>();
      final (c, voice) = await open(
        tester,
        [
          const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
          const BlockStart(index: 0, id: 't', blockType: 'text'),
          const BlockDelta(index: 0, textDelta: 'C vitamini için bir doktora danışın. İşte mağazadakiler.'),
          const TurnSpeech(token: 'tok9', text: 'C vitamini için bir doktora danışın. İşte mağazadakiler.', lang: 'tr'),
          const BlockStart(index: 1, id: 'p', blockType: 'product_cards'),
          const TurnEnd(status: 'completed', pending: [], lang: 'tr'),
        ],
        hold: end.future,
      );
      await say(tester, 'C vitamini önerir misin');
      expect(c.busy, isTrue, reason: 'the turn has not ended');
      expect(voice.said, [('C vitamini için bir doktora danışın. İşte mağazadakiler.', 'tr')]);
      expect(voice.urls.single, '${c.api.config.apiBaseUrl}/v1/speech/tok9');
      end.complete();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(voice.said, hasLength(1), reason: 'read once, not again at the end');
      await tester.pump(const Duration(minutes: 2));
    });

    testWidgets("does not read a typed question's answer by itself; its own speaker reads it on a tap",
        (tester) async {
      final (c, voice) = await open(tester, answer('Tomorrow is clear.', lang: 'en', token: 'tok1'));
      await type(tester, c, 'Weather?');
      expect(voice.said, isEmpty);
      expect(find.text('Listen'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Listen to this answer'));
      await tester.pump();
      expect(voice.said, [('Tomorrow is clear.', 'en')]);
      expect(voice.urls.single, '${c.api.config.apiBaseUrl}/v1/speech/tok1');
      // While it reads, the same speaker stops it.
      final stops = voice.stops;
      await tester.tap(find.bySemanticsLabel('Stop reading'));
      await tester.pump();
      expect(voice.stops, greaterThan(stops));
      expect(find.text('Listen'), findsOneWidget);
    });

    testWidgets("sits under the answer's first paragraph and above its cards, and counts the time heard (QA 2026-10-24)",
        (tester) async {
      final (c, voice) = await open(tester, [
        const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
        BlockReady(index: 0, block: _text('Tomorrow is clear.')),
        const TurnSpeech(token: 'tok20', text: 'Tomorrow is clear.', lang: 'en'),
        BlockReady(
          index: 1,
          block: WireBlock(id: 'k', type: 'key_points', fallbackText: 'Dry', props: {
            'items': [
              {'icon': 'check', 'title': 'Dry all day', 'body': 'No rain.'},
            ],
          })
            ..ready = true,
        ),
        TurnEnd(status: 'completed', pending: const [], lang: 'en'),
      ]);
      await type(tester, c, 'Weather?');
      final pill = tester.getRect(find.text('Listen'));
      expect(pill.top, greaterThan(tester.getRect(find.text('Tomorrow is clear.')).bottom));
      expect(pill.bottom, lessThan(tester.getRect(find.text('Dry all day')).top));
      expect(tester.getSize(find.bySemanticsLabel('Listen to this answer')).height, greaterThanOrEqualTo(44));

      await tester.tap(find.bySemanticsLabel('Listen to this answer'));
      await tester.pump();
      expect(find.text('0:00'), findsOneWidget);
      voice.heard = const Duration(milliseconds: 4200);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('0:04'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Stop reading'));
      await tester.pump();
      expect(find.text('Listen'), findsOneWidget);
    });

    testWidgets('offers no speaker once its voice token has lived its thirty minutes', (tester) async {
      final (c, _) = await open(tester, answer('Tomorrow is clear.', lang: 'en', token: 'tok2'));
      await type(tester, c, 'Weather?');
      expect(find.bySemanticsLabel('Listen to this answer'), findsOneWidget);
      final answered = c.messages.last;
      answered.speech = RendelAnswerSpeech(token: 'tok2', lang: 'en', at: DateTime.now().subtract(const Duration(minutes: 31)));
      answered.touch();
      await tester.pump();
      expect(find.bySemanticsLabel('Listen to this answer'), findsNothing);
    });

    testWidgets('leaves it to the phone where the server has no voice', (tester) async {
      final (_, voice) = await open(tester, answer('Yarın hava açık.', lang: 'tr'));
      await say(tester, 'Hava nasıl?');
      expect(voice.urls.single, isNull);
      expect(voice.said, [('Yarın hava açık.', 'tr')]);
    });

    testWidgets("falls back to the app's language when the server does not say", (tester) async {
      final (_, voice) = await open(tester, answer('Tomorrow is clear.'), locale: 'en-GB');
      await say(tester, 'Weather?');
      expect(voice.said.single.$2, 'en-GB');
    });

    testWidgets('reads nothing that lands with the app in the background, and stops when it goes there',
        (tester) async {
      final (_, voice) = await open(tester, answer('Tomorrow is clear.', lang: 'en'));
      // The order the platform reports them in; the binding refuses a skipped step.
      void go(List<AppLifecycleState> states) => states.forEach(tester.binding.handleAppLifecycleStateChanged);
      final stops = voice.stops;
      go([AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      expect(voice.stops, greaterThan(stops), reason: 'put away, the voice stops');
      await say(tester, 'Weather?');
      expect(voice.said, isEmpty);
      go([AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    });

    testWidgets('reads nothing of a turn that did not finish', (tester) async {
      final (_, voice) = await open(tester, [
        const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
        BlockReady(index: 0, block: _text('Half an answer.')),
        const TurnEnd(status: 'error', pending: []),
      ]);
      await say(tester, 'Hi');
      expect(voice.said, isEmpty);
    });

    testWidgets("the header's Auto-read switch mutes what is read by itself, and a new question stops the voice",
        (tester) async {
      final (c, voice) = await open(tester, answer('Tomorrow is clear.', lang: 'en'));
      await say(tester, 'Weather?');
      expect(voice.said, hasLength(1));

      // Its own word and a switch, not a speaker glyph (QA 2026-10-24).
      expect(find.text('Auto-read'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Auto-read')),
        isSemantics(hasToggledState: true, isToggled: true, isButton: true, hint: 'Read answers aloud'),
      );
      await tester.tap(find.bySemanticsLabel('Auto-read'));
      await tester.pump();
      expect(voice.on.value, isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('Auto-read')), isSemantics(hasToggledState: true, isToggled: false));

      final stopsBefore = voice.stops;
      await say(tester, 'And Friday?');
      expect(voice.stops, greaterThan(stopsBefore));
      expect(voice.said, hasLength(1), reason: 'muted, a spoken question is not read by itself');
    });

    testWidgets('Auto-read fits the header on a narrow phone, and at 320 is the switch alone, still named', (tester) async {
      addTearDown(tester.view.reset);
      for (final (width, scale) in [(390.0, 1.0), (360.0, 1.0), (360.0, 1.3), (320.0, 1.0), (320.0, 1.6)]) {
        tester.view.physicalSize = Size(width * 3, 2400);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        final (c, _) = await open(tester, answer('Tomorrow is clear.', lang: 'en', token: 'tok30'));
        await type(tester, c, 'Weather?');
        expect(tester.takeException(), isNull, reason: 'no overflow at $width x$scale');
        expect(find.bySemanticsLabel('Auto-read'), findsOneWidget);
        expect(find.text('Auto-read'), width < 360 ? findsNothing : findsOneWidget, reason: '$width');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('draws no speaker at all where the host or the console turned voice off', (tester) async {
      final (c, _) = await open(tester, answer('Tomorrow is clear.', lang: 'en', token: 'tok3'), voiced: false);
      await type(tester, c, 'Weather?');
      expect(find.bySemanticsLabel('Listen to this answer'), findsNothing);
      expect(find.bySemanticsLabel('Auto-read'), findsNothing);
    });
  });

  group('the console switch', () {
    test('is a floor, like enabled: off in code or off in the console stays off', () {
      expect(const RendelConfig().readAloud, isTrue);
      expect(const RendelConfig().copyWith(readAloud: false).readAloud, isFalse);
      expect(const RendelConfig(readAloud: false).copyWith(readAloud: true).readAloud, isFalse);
    });
  });
}
