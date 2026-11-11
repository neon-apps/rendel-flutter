import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

void main() {
  String sse(List<(String, Map<String, dynamic>)> frames) => frames
      .map((f) => 'event: ${f.$1}\ndata: ${jsonEncode({'v': 1, 'seq': 0, 'type': f.$1, ...f.$2})}\n\n')
      .join();

  final turn = sse([
    ('turn.start', {'conversation_id': 'c1', 'message_id': 'm1', 'request_id': 'r1'}),
    ('block.start', {'index': 0, 'id': 'b0', 'block_type': 'text'}),
    ('block.ready', {
      'index': 0,
      'block': {'id': 'b0', 'type': 'text', 'fallback_text': 'tamam', 'props': {'markdown': 'tamam'}},
    }),
    ('turn.end', {'status': 'completed', 'pending': <String>[]}),
  ]);

  /* The answer is held until the test lets it go, so the composer sees the
     turn running, and then it is really over: the stream's end is real I/O,
     let through outside the fake clock. Without both, this measured the
     composer mid-turn (the box stays then: while_answering_test.dart). */
  late Completer<void> gate;

  Future<void> answer(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    gate.complete();
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ConversationController> pump(WidgetTester tester) async {
    gate = Completer<void>();
    final c = ConversationController(
      api: RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
        httpClient: MockClient((request) async {
          if (!request.url.path.endsWith('/v1/chat')) return http.Response('{}', 200);
          await gate.future;
          return http.Response(turn, 200, headers: {'content-type': 'text/event-stream'});
        }),
      ),
      actions: const {},
      sdkVersion: 'flutter/test',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: ThreadScreen(
            controller: c,
            suggestions: const ['Siparişim nerede?'],
            onPickAttachment: (_) async => null,
            onDictate: (_) async => null,
          ),
        ),
      ),
    ));
    await tester.pump();
    return c;
  }

  testWidgets('typed question: the composer is back at rest after the answer', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Type a message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'merhaba');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await answer(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('Type a message'), findsOneWidget);
  });

  testWidgets('send button: the composer is back at rest after the answer', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Type a message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'merhaba');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send message'));
    await answer(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('Type a message'), findsOneWidget);
  });
}
