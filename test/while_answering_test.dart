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

String sse(List<(String, Map<String, dynamic>)> frames) => frames
    .map((f) => 'event: ${f.$1}\ndata: ${jsonEncode({'v': 1, 'seq': 0, 'type': f.$1, ...f.$2})}\n\n')
    .join();

final answer = sse([
  ('turn.start', {'conversation_id': 'c1', 'message_id': 'm1', 'request_id': 'r1'}),
  ('block.start', {'index': 0, 'id': 'b0', 'block_type': 'text'}),
  ('block.ready', {
    'index': 0,
    'block': {'id': 'b0', 'type': 'text', 'fallback_text': 'Paste it', 'props': {'markdown': 'Paste it'}},
  }),
  ('turn.end', {'status': 'completed', 'pending': <String>[]}),
]);

/// A server that holds each answer until the test lets it go, and answers
/// the console's pairing code as the API reads it.
class _Server {
  final turns = <Completer<void>>[];
  final asked = <String>[];
  final claims = <String>[];
  late final client = MockClient((request) async {
    if (request.url.path.endsWith('/v1/pairings/claim')) {
      final code = (jsonDecode(request.body) as Map<String, dynamic>)['code'] as String;
      claims.add(code);
      return code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '') == 'K7Q2M9XD'
          ? http.Response(jsonEncode({'paired': true, 'ends_at': '2026-11-07T14:30:00.000Z'}), 200)
          : http.Response(jsonEncode({'error': {'code': 'pairing_not_found'}}), 404);
    }
    if (!request.url.path.endsWith('/v1/chat')) return http.Response('{}', 200);
    asked.add(((jsonDecode(request.body) as Map<String, dynamic>)['message'] as Map?)?['text'] as String? ?? '');
    final gate = Completer<void>();
    turns.add(gate);
    await gate.future;
    return http.Response(answer, 200, headers: {'content-type': 'text/event-stream'});
  });
}

/// Customer review 2026-11-05: a question typed while the first answer was
/// still being written went nowhere, and the box came back empty. The box a
/// question was typed in now stays, says what the turn is doing, and keeps
/// what is typed until the answer is done. The same review moved pairing
/// into the message box: on a test key, the console's code sent as a
/// message pairs the device. Parity with the web SDK's
/// while-answering.test.ts.
void main() {
  Future<(ConversationController, _Server)> pump(
    WidgetTester tester, {
    String appKey = 'rd_pk_test_x',
    bool voice = true,
  }) async {
    final server = _Server();
    final c = ConversationController(
      api: RendelApiClient(appKey: appKey, deviceId: 'd', config: const RendelConfig(), httpClient: server.client),
      actions: const {},
      sdkVersion: 'flutter/test',
      sandbox: appKey.startsWith('rd_pk_test_'),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: ThreadScreen(
            controller: c,
            onPickAttachment: (_) async => null,
            onDictate: voice ? (_) async => null : null,
          ),
        ),
      ),
    ));
    await tester.pump();
    if (voice) {
      await tester.tap(find.bySemanticsLabel('Type a message'));
      await tester.pumpAndSettle();
    }
    return (c, server);
  }

  Future<void> send(WidgetTester tester, String words) async {
    await tester.enterText(find.byType(TextField), words);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The stream's end is real I/O: it is let through outside the fake clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  String hint(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).decoration!.hintText!;

  testWidgets('the box a question was typed in stays, and says what the turn is doing', (tester) async {
    final (_, server) = await pump(tester);
    await send(tester, 'How do I add a refund policy?');
    expect(server.asked, ['How do I add a refund policy?']);
    expect(find.byType(TextField), findsOneWidget);
    expect(hint(tester), 'Thinking…');
    server.turns.single.complete();
    await settle(tester);
  });

  testWidgets('a second question typed meanwhile is kept, and goes once the answer is done', (tester) async {
    final (_, server) = await pump(tester);
    await send(tester, 'How do I add a refund policy?');
    await send(tester, 'And a shipping policy?');
    // Not sent, and not lost.
    expect(server.asked, ['How do I add a refund policy?']);
    expect(find.text('And a shipping policy?'), findsOneWidget);

    server.turns.single.complete();
    await settle(tester);
    // Kept through the answer's end: a box with words in it does not fold away.
    expect(find.text('And a shipping policy?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.asked, ['How do I add a refund policy?', 'And a shipping policy?']);
    server.turns.last.complete();
    await settle(tester);
  });

  testWidgets('without a microphone the box is all there is, through the turn too', (tester) async {
    final (_, server) = await pump(tester, voice: false);
    await send(tester, 'How do I add a refund policy?');
    expect(find.byType(TextField), findsOneWidget);
    expect(hint(tester), 'Thinking…');
    server.turns.single.complete();
    await settle(tester);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('pairs with the console when the code is sent on a test key, and asks nothing', (tester) async {
    final (_, server) = await pump(tester);
    await send(tester, 'k7q2-m9xd');
    await settle(tester);
    expect(server.claims, ['k7q2-m9xd']);
    expect(server.asked, isEmpty);
    expect(find.textContaining('Paired with the console until '), findsOneWidget);
  });

  testWidgets('says so when the code does not pair', (tester) async {
    final (_, server) = await pump(tester);
    await send(tester, 'ABCD EFGH');
    await settle(tester);
    expect(server.claims, ['ABCD EFGH']);
    expect(server.asked, isEmpty);
    expect(find.text("That code did not pair this device. Make a new one on the console's Test page."), findsOneWidget);
  });

  testWidgets("asks a live key's code-shaped message as a question", (tester) async {
    final (_, server) = await pump(tester, appKey: 'rd_pk_live_x');
    await send(tester, 'K7Q2-M9XD');
    expect(server.claims, isEmpty);
    expect(server.asked, ['K7Q2-M9XD']);
    server.turns.single.complete();
    await settle(tester);
  });

  testWidgets('never takes a plain word for a code', (tester) async {
    final (_, server) = await pump(tester);
    await send(tester, 'stranger');
    expect(server.claims, isEmpty);
    expect(server.asked, ['stranger']);
    server.turns.single.complete();
    await settle(tester);
  });
}
