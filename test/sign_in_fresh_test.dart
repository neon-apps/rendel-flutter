// A thread asked signed out does not stay for whoever signs in.
//
// sdkkaza, T38 (web, the same in Flutter): "where is my order?" asked signed
// out was answered "you are not signed in, so I cannot see it", and that
// answer was still on screen once Elif signed in, on a phone two people
// share. The sign-in starts the thread afresh; the same person told again
// who they are keeps theirs.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';
const _answer = 'You are not signed in, so I cannot see your orders.';

String _turn() {
  final events = [
    {'type': 'turn.start', 'conversation_id': 'c1', 'message_id': 'm1'},
    {
      'type': 'block.ready',
      'index': 0,
      'block': {'id': 'b1', 'type': 'text', 'fallback_text': _answer, 'props': {'markdown': _answer}},
    },
    {'type': 'turn.end', 'status': 'completed', 'pending': <String>[]},
  ];
  return [
    for (final (seq, event) in events.indexed)
      'event: ${event['type']}\ndata: ${jsonEncode({'v': 1, 'seq': seq, ...event})}\n\n',
  ].join();
}

final _client = MockClient((request) async {
  if (request.url.path.endsWith('/v1/chat')) {
    return http.Response(_turn(), 200, headers: {'content-type': 'text/event-stream'});
  }
  return http.Response('{"ok":true}', 200);
});

Future<void> _askSignedOut(WidgetTester tester) async {
  await tester.runAsync(() => Rendel.init(
        appKey: _key,
        config: RendelConfig(httpClient: _client, remoteConfig: false),
      ));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(onPressed: () => Rendel.open(context), child: const Text('open')),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(find.bySemanticsLabel('Type a message'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextField), 'Where is my order?');
  await tester.runAsync(() async {
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
  expect(find.textContaining(_answer, findRichText: true), findsWidgets);
}

void main() {
  tearDown(Rendel.resetForTest);

  testWidgets('somebody signing in starts the thread asked signed out afresh', (tester) async {
    await _askSignedOut(tester);
    await tester.runAsync(() => Rendel.identify(userId: 'elif'));
    await tester.pumpAndSettle();
    expect(find.textContaining(_answer, findRichText: true), findsNothing);
  });

  testWidgets('the same person told again who they are keeps their thread', (tester) async {
    await tester.runAsync(() => Rendel.identify(userId: 'elif'));
    await _askSignedOut(tester);
    await tester.runAsync(() => Rendel.identify(userId: 'elif'));
    await tester.pumpAndSettle();
    expect(find.textContaining(_answer, findRichText: true), findsWidgets);
  });
}
