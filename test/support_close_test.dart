// The way out of the team's page (Tuna, 2026-11-04): ✕ closes all of Rendel,
// as on the web, and the way back returns to Rendel's own page.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/support_sheet.dart';
import 'package:rendel/src/ui/thread_screen.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';
const _thread = '00000000-0000-4000-8000-000000000001';

final _threadBody = {
  'thread_id': _thread,
  'conversation_id': 'c1',
  'state': {
    'thread_id': _thread,
    'mode': 'human',
    'state': 'open',
    'team_here': true,
    'team_read_seq': 0,
    'user_read_seq': 1,
    'last_seq': 1,
    'contact': {'state': 'not_needed', 'required': false},
  },
  'entries': [
    {
      'id': '00000000-0000-4000-8000-000000000011',
      'seq': 1,
      'kind': 'message',
      'author': {'kind': 'agent', 'name': 'Ayşe'},
      'text': 'Merhaba',
      'blocks': <Object>[],
      'attachments': <Object>[],
      'created_at': '2026-11-01T10:00:00Z',
    },
  ],
};

final _client = MockClient.streaming((request, body) async {
  final path = request.url.path;
  await body.drain<void>();
  http.StreamedResponse json(Object value) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), 200, headers: {'content-type': 'application/json'});
  if (path == '/v1/apps/config') {
    return json({
      'channel': 'published',
      'version': null,
      'updated_at': null,
      'config': <String, Object>{},
      'support': {'enabled': true, 'team': 'Grove'},
    });
  }
  if (path == '/v1/support/unread') return json({'unread': 0});
  if (path == '/v1/support/current') return json(_threadBody);
  if (path == '/v1/support/threads') return json({'threads': <Object>[]});
  // The team's stream, each time the page opens: held open, quiet.
  if (path.endsWith('/stream')) return http.StreamedResponse(StreamController<List<int>>().stream, 200);
  return json({'ok': true});
});

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Rendel open on its page, and the team's page over it.
Future<void> _openBoth(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Rendel.init(appKey: _key, config: RendelConfig(httpClient: _client));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      context = c;
      return const Scaffold(body: Text('the app'));
    }),
  ));
  unawaited(Rendel.open(context));
  await _settle(tester);
  unawaited(Rendel.openSupport(context));
  await _settle(tester);
  expect(find.byType(RendelSupportSheet), findsOneWidget);
  expect(Rendel.isOpen, isTrue);
}

void main() {
  tearDown(Rendel.resetForTest);

  testWidgets('✕ on the team page closes all of Rendel, as on the web', (tester) async {
    await _openBoth(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await _settle(tester);
    expect(find.byType(RendelSupportSheet), findsNothing);
    expect(find.byType(ThreadScreen), findsNothing);
    expect(Rendel.isOpen, isFalse);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets("the way back leaves the team's page for Rendel's", (tester) async {
    await _openBoth(tester);
    await tester.tap(find.bySemanticsLabel('Back to the assistant'));
    await _settle(tester);
    expect(find.byType(RendelSupportSheet), findsNothing);
    expect(find.byType(ThreadScreen), findsOneWidget);
    expect(Rendel.isOpen, isTrue);
  });
}
