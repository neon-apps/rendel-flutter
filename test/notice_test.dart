import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// When the assistant will not answer on purpose (a usage limit, a paused
/// budget), the person sees a calm answer and a resting composer, never the
/// error strip or a retry (Tuna, 2026-10-12: "bozulmuş gibi göstermemek için").
void main() {
  String sse(List<(String, String)> frames) => frames.map((f) => 'event: ${f.$1}\ndata: ${f.$2}\n\n').join();

  ConversationController controller(String body, {void Function(String)? onUnavailable}) => ConversationController(
        onUnavailable: onUnavailable,
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          httpClient: MockClient((request) async => request.url.path.endsWith('/v1/chat')
              ? http.Response(body, 200, headers: {'content-type': 'text/event-stream'})
              : http.Response('{}', 200)),
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  test('declares notices in the handshake', () {
    expect(clientCapabilities, contains('notices'));
  });

  test('parses a notice frame', () {
    final event = RendelWireEvent.tryParse('notice', {
      'kind': 'limit',
      'message': 'Free accounts get 3 questions a day.',
      'hint': 'Back tomorrow',
      'until': '2026-10-13T00:00:00.000Z',
      'action': {'label': 'See plans', 'url': 'https://example.com/plans'},
    });
    expect(event, isA<RendelNotice>());
    final notice = event! as RendelNotice;
    expect(notice.until, DateTime.utc(2026, 10, 13));
    expect(notice.actionLabel, 'See plans');
  });

  testWidgets('a notice is the answer, the composer rests, and nothing is an error', (tester) async {
    final until = DateTime.now().add(const Duration(hours: 3)).toUtc().toIso8601String();
    final c = controller(sse([
      ('turn.start', '{"v":1,"seq":0,"type":"turn.start","conversation_id":"c1","message_id":"m1"}'),
      ('notice', '{"v":1,"seq":1,"type":"notice","kind":"limit","message":"Free accounts get 3 questions a day.","hint":"Back tomorrow","until":"$until","action":{"label":"See plans","url":"https://example.com/plans"}}'),
      ('turn.end', '{"v":1,"seq":2,"type":"turn.end","status":"completed","pending":[]}'),
    ]));
    await tester.runAsync(() => c.send('one more?'));
    expect(c.errorText, isNull);
    expect(c.resting, isTrue);
    expect(await c.send('and now?'), isFalse);
    expect(c.messages.last.blocks.single.type, 'notice');

    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: ThreadScreen(controller: c))),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Free accounts get 3 questions a day.'), findsOneWidget);
    expect(find.text('See plans'), findsOneWidget);
    expect(find.text('Back tomorrow'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a paused app closes quietly: no error, no answer, the question gone', (tester) async {
    String? told;
    final c = controller(
      sse([
        ('turn.start', '{"v":1,"seq":0,"type":"turn.start","conversation_id":"c1","message_id":"m1"}'),
        ('notice', '{"v":1,"seq":1,"type":"notice","kind":"paused","message":"The assistant is taking a break.","hint":"Paused for now","until":null,"action":null}'),
        ('turn.end', '{"v":1,"seq":2,"type":"turn.end","status":"completed","pending":[]}'),
      ]),
      onUnavailable: (reason) => told = reason,
    );
    await tester.runAsync(() => c.send('hello?'));
    expect(told, 'paused');
    expect(c.errorText, isNull);
    expect(c.messages, isEmpty);
    // Nothing on screen still thinks: the sheet is back to its empty state.
    expect(c.busy, isFalse);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: ThreadScreen(controller: c))),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Thinking'), findsNothing);
  });

  testWidgets('says when one question is left, until the next is sent', (tester) async {
    final c = controller(sse([
      ('turn.start', '{"v":1,"seq":0,"type":"turn.start","conversation_id":"c1","message_id":"m1"}'),
      ('block.ready', '{"v":1,"seq":1,"type":"block.ready","index":0,"block":{"id":"b1","type":"text","fallback_text":"In stock.","props":{"markdown":"In stock."}}}'),
      ('turn.end', '{"v":1,"seq":2,"type":"turn.end","status":"completed","pending":[],"remaining":{"count":1,"hint":"1 question left today"}}'),
    ]));
    await tester.runAsync(() => c.send('44?'));
    expect(c.hint, '1 question left today');
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: ThreadScreen(controller: c))),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('1 question left today'), findsOneWidget);
  });
}
