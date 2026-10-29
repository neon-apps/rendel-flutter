import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// The SDK's own words follow the language the conversation is answered in.
///
/// Found in Grove (2026-10-29): an app configured `languages: ['en']`, a
/// person writing Turkish, a Turkish answer — and "Confirm", "Go back" and
/// "Thinking…" around it, because the words were fixed by the config.
void main() {
  String sse(List<(String, Map<String, dynamic>)> frames) => frames
      .map((f) => 'event: ${f.$1}\ndata: ${jsonEncode({'v': 1, 'seq': 0, 'type': f.$1, ...f.$2})}\n\n')
      .join();

  String turn({String? lang}) => sse([
        ('turn.start', {
          'conversation_id': 'c1',
          'message_id': 'm1',
          'request_id': 'r1',
          if (lang != null) 'lang': lang,
        }),
        ('block.start', {'index': 0, 'id': 'b0', 'block_type': 'confirm_card'}),
        ('block.ready', {
          'index': 0,
          'block': {
            'id': 'b0',
            'type': 'confirm_card',
            'fallback_text': 'Cancel order 1042?',
            'props': {
              'invocation_id': 'inv_1',
              'action_name': 'cancel_order',
              'summary': '1042 numaralı siparişi iptal edelim mi?',
              'risk': 'destructive',
              'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
              'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
            },
          },
        }),
        ('turn.end', {'status': 'completed', 'pending': <String>[]}),
      ]);

  ConversationController controller({String? lang}) => ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          httpClient: MockClient((request) async {
            if (!request.url.path.endsWith('/v1/chat')) return http.Response('{}', 200);
            return http.Response.bytes(utf8.encode(turn(lang: lang)), 200, headers: {'content-type': 'text/event-stream'});
          }),
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  Future<void> pump(
    WidgetTester tester,
    ConversationController c, {
    RendelStrings strings = const RendelStrings(),
    bool follow = true,
  }) async {
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: ThreadScreen(controller: c, strings: strings, followAnswerLanguage: follow),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> ask(WidgetTester tester, ConversationController c) async {
    unawaited(c.send('siparişimi iptal et'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('turn.start lang', () {
    test('is parsed when the server names it', () {
      final event = RendelWireEvent.tryParse('turn.start', {
        'conversation_id': 'c1',
        'message_id': 'm1',
        'model': 'x',
        'lang': 'tr',
      });
      expect(event, isA<TurnStart>().having((e) => e.lang, 'lang', 'tr'));
    });

    test('is null from an older server, or one that sends something else', () {
      final older = RendelWireEvent.tryParse('turn.start', {'conversation_id': 'c1', 'message_id': 'm1'});
      expect(older, isA<TurnStart>().having((e) => e.lang, 'lang', isNull));
      final odd = RendelWireEvent.tryParse('turn.start', {'conversation_id': 'c1', 'message_id': 'm1', 'lang': 7});
      expect(odd, isA<TurnStart>().having((e) => e.lang, 'lang', isNull));
    });
  });

  test('the controller keeps the language until the conversation starts over', () async {
    final c = controller(lang: 'tr');
    addTearDown(c.dispose);
    await c.send('merhaba');
    expect(c.answerLanguage, 'tr');
    c.reset();
    expect(c.answerLanguage, isNull);
  });

  test('an older server leaves the language unknown', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.send('merhaba');
    expect(c.answerLanguage, isNull);
  });

  testWidgets('a Turkish answer is framed in Turkish, and a new conversation in the default', (tester) async {
    final c = controller(lang: 'tr');
    await pump(tester, c);
    expect(find.text('Ask anything about this app.'), findsOneWidget);

    await ask(tester, c);
    expect(find.text('Onayla'), findsOneWidget);
    expect(find.text('Geri'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Go back'), findsNothing);

    c.reset();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ask anything about this app.'), findsOneWidget);
    expect(find.text('Bu uygulamayla ilgili ne isterseniz sorun.'), findsNothing);
  });

  testWidgets('an older page keeps the language it was answered in', (tester) async {
    // An English answer, then a Turkish one (QA R2-7: going back drew the English page in Turkish).
    final langs = ['en', 'tr'];
    var turns = 0;
    final c = ConversationController(
      api: RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
        httpClient: MockClient((request) async {
          if (!request.url.path.endsWith('/v1/chat')) return http.Response('{}', 200);
          final n = turns++;
          final text = n == 0 ? 'Your order arrives today.' : 'Siparişiniz bugün geliyor.';
          final frames = sse([
            ('turn.start', {'conversation_id': 'c1', 'message_id': 'm$n', 'request_id': 'r$n', 'lang': langs[n % langs.length]}),
            ('block.start', {'index': 0, 'id': 'b$n', 'block_type': 'text'}),
            ('block.ready', {
              'index': 0,
              'block': {'id': 'b$n', 'type': 'text', 'fallback_text': text, 'props': {'markdown': text}},
            }),
            ('turn.end', {'status': 'completed', 'pending': <String>[]}),
          ]);
          return http.Response.bytes(utf8.encode(frames), 200, headers: {'content-type': 'text/event-stream'});
        }),
      ),
      actions: const {},
      sdkVersion: 'flutter/test',
    );
    await pump(tester, c);
    await tester.runAsync(() => c.send('where is my order'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => c.send('siparişim nerede'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.pages.map((p) => p.lang), ['en', 'tr']);
    expect(find.bySemanticsLabel('Önceki sayfa'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Önceki sayfa'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.page, 0);
    expect(find.bySemanticsLabel('Previous page'), findsOneWidget);
    expect(find.bySemanticsLabel('Önceki sayfa'), findsNothing);
  });

  testWidgets("a language the SDK does not ship keeps the thread's words", (tester) async {
    final c = controller(lang: 'ja');
    await pump(tester, c);
    await ask(tester, c);
    expect(find.text('Confirm'), findsOneWidget);
  });

  testWidgets("the host's own words still win whole", (tester) async {
    final c = controller(lang: 'tr');
    // What `Rendel` passes when `RendelConfig.strings` is set.
    await pump(tester, c, strings: const RendelStrings(confirm: 'Do it'), follow: false);
    await ask(tester, c);
    expect(c.answerLanguage, 'tr');
    expect(find.text('Do it'), findsOneWidget);
    expect(find.text('Onayla'), findsNothing);
  });
}
