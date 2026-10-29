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
    'block': {'id': 'b0', 'type': 'text', 'fallback_text': 'On its way', 'props': {'markdown': 'On its way'}},
  }),
  ('turn.end', {'status': 'completed', 'pending': <String>[]}),
]);

/// A server that holds each answer until the test lets it go.
class _Held {
  final turns = <Completer<void>>[];
  late final client = MockClient((request) async {
    if (!request.url.path.endsWith('/v1/chat')) return http.Response('{}', 200);
    final gate = Completer<void>();
    turns.add(gate);
    await gate.future;
    return http.Response(answer, 200, headers: {'content-type': 'text/event-stream'});
  });
}

/// QA on 2026-10-29 (R4-2, Grove): Send tapped twice quickly left the
/// previous page under "The connection dropped before the answer finished",
/// though the server had the one message.
void main() {
  Future<(ConversationController, _Held)> pump(WidgetTester tester) async {
    final server = _Held();
    final c = ConversationController(
      api: RendelApiClient(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig(), httpClient: server.client),
      actions: const {},
      sdkVersion: 'flutter/test',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: ThreadScreen(controller: c, onPickAttachment: (_) async => null, onDictate: (_) async => null),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Type a message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'where is my order');
    await tester.pump();
    return (c, server);
  }

  AbsorbPointer hold(WidgetTester tester) => tester.widget<AbsorbPointer>(
        find.descendant(of: find.byType(ThreadScreen), matching: find.byType(AbsorbPointer)).first,
      );

  testWidgets('a second tap on Send sends nothing, and the answer arrives', (tester) async {
    final (c, server) = await pump(tester);
    final at = tester.getCenter(find.bySemanticsLabel('Send message'));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 80));
    expect(server.turns, hasLength(1));
    expect(c.messages.where((m) => m.role == 'user'), hasLength(1));

    server.turns.single.complete();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.errorCode, isNull);
    expect(find.text('The connection dropped before the answer finished.'), findsNothing);
    expect(c.messages.last.blocks.single.props['markdown'], 'On its way');
  });

  testWidgets('the thread takes no taps for a moment after Send, then takes them again', (tester) async {
    final (_, server) = await pump(tester);
    expect(hold(tester).absorbing, isFalse);
    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    expect(hold(tester).absorbing, isTrue);
    await tester.pump(sendHoldDuration);
    expect(hold(tester).absorbing, isFalse);
    server.turns.single.complete();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
