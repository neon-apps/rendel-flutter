// The last answer after the app is killed and opened again.
//
// QA, 2026-10-29: a person asked which store is closest to Bondi and when it
// opens, and the app was killed two seconds later. The server finished the
// answer; after the relaunch the assistant opened fresh, and the person never
// saw it. The thread now opens on the conversation the last turn was on, when
// it was the same person's and within the hour, read back from the server so
// an answer that finished while the app was dead is there too.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';
const _answer = 'Bondi Junction is closest, and opens at 9.';

class _Server {
  /// How many times the conversation's messages were asked for.
  var read = 0;

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/v1/chat')) {
      // The stream is cut before the answer: the app was killed.
      return http.Response(
        'event: turn.start\ndata: {"conversation_id":"c-bondi","message_id":"m2"}\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    if (path.endsWith('/v1/conversations/c-bondi/messages')) {
      read++;
      // What the server stored once it finished, with nobody listening.
      return http.Response(
        jsonEncode({
          'conversation_id': 'c-bondi',
          'messages': [
            {
              'id': 'm1',
              'role': 'user',
              'blocks': [
                {'id': 'u0', 'type': 'text', 'fallback_text': '', 'props': {'markdown': 'Which store is closest to Bondi?'}},
              ],
            },
            {
              'id': 'm2',
              'role': 'assistant',
              'blocks': [
                {'id': 'b0', 'type': 'text', 'fallback_text': '', 'props': {'markdown': _answer}},
              ],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{"ok":true}', 200);
  });
}

Future<void> _launch(WidgetTester tester, _Server server) async {
  await tester.runAsync(() => Rendel.init(
        appKey: _key,
        config: RendelConfig(httpClient: server.client, remoteConfig: false),
      ));
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Rendel.open(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

/// Asks, and the app is killed before the answer arrives.
Future<void> _askAndKill(WidgetTester tester, _Server server) async {
  await _launch(tester, server);
  await _open(tester);
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(find.bySemanticsLabel('Type a message'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextField), 'Which store is closest to Bondi?');
  await tester.runAsync(() async {
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.textContaining(_answer, findRichText: true), findsNothing);
  // A process ending: what the device stored stays, nothing else does.
  Rendel.resetForTest(relaunch: true);
}

void main() {
  tearDown(Rendel.resetForTest);

  testWidgets('the same person opens on the answer that finished while the app was dead', (tester) async {
    final server = _Server();
    await tester.runAsync(() => Rendel.identify(userId: 'olivia'));
    await _askAndKill(tester, server);

    // The host's session restore calls nothing: the stored user is Olivia.
    await _launch(tester, server);
    await _open(tester);
    expect(server.read, 1);
    expect(find.textContaining(_answer, findRichText: true), findsWidgets);
  });

  testWidgets('another person signed in on the same phone opens fresh', (tester) async {
    final server = _Server();
    await tester.runAsync(() => Rendel.identify(userId: 'olivia'));
    await _askAndKill(tester, server);

    await _launch(tester, server);
    await tester.runAsync(() => Rendel.identify(userId: 'jack'));
    await _open(tester);
    expect(server.read, 0, reason: "Olivia's thread is not Jack's to read");
    expect(find.textContaining(_answer, findRichText: true), findsNothing);
  });

  testWidgets('a conversation older than the window opens fresh', (tester) async {
    final server = _Server();
    await tester.runAsync(() => Rendel.identify(userId: 'olivia'));
    await _askAndKill(tester, server);

    await _launch(tester, server);
    // The hour, as a moment that has already passed.
    Rendel.restoreWithin = Duration.zero;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await _open(tester);
    expect(server.read, 0);
    expect(find.textContaining(_answer, findRichText: true), findsNothing);
  });

  testWidgets('a thread started over is not the one a relaunch opens on', (tester) async {
    final server = _Server();
    await tester.runAsync(() => Rendel.identify(userId: 'olivia'));
    await _askAndKill(tester, server);

    // Opened on it, then started over, then killed again.
    await _launch(tester, server);
    await _open(tester);
    expect(server.read, 1);
    await tester.tap(find.bySemanticsLabel('Start a new conversation'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    Rendel.resetForTest(relaunch: true);

    await _launch(tester, server);
    await _open(tester);
    expect(server.read, 1);
    expect(find.textContaining(_answer, findRichText: true), findsNothing);
  });
}
