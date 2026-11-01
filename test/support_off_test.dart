// Support is dark until the app's config turns it on (the 0.73.0 train's
// release condition): with the default config the phone asks the support API
// nothing and shows no support page or badge, on init, on opening, on a
// return to the foreground, on a push from the team or a follow-up's, on a
// launcher tap and on the app's own "Contact us", and not even when a turn
// says the person was handed to the team. With Support on in the config, the
// same steps reach it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/support_sheet.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';
const _thread = '00000000-0000-4000-8000-000000000001';
const _followup = '0b8d3c1e-5f6a-4b7c-8d9e-0f1a2b3c4d5e';

final _threadBody = {
  'thread_id': _thread,
  'conversation_id': 'c1',
  'state': {
    'thread_id': _thread,
    'mode': 'waiting',
    'state': 'open',
    'team_here': true,
    'team_read_seq': 0,
    'user_read_seq': 0,
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

final _handedOff = [
  {'type': 'turn.start', 'conversation_id': 'c1', 'message_id': 'm1'},
  {'type': 'support.handoff', 'thread_id': _thread, 'conversation_id': 'c1'},
  {'type': 'turn.end', 'status': 'completed', 'pending': <String>[]},
];

class _Server {
  _Server({required this.supportOn});

  final bool supportOn;
  final List<String> paths = [];

  /// Each turn's declared capabilities.
  final List<List<Object?>> declared = [];

  List<String> get supportCalls => [for (final p in paths) if (p.startsWith('/v1/support/')) p];

  late final client = MockClient.streaming((request, body) async {
    final path = request.url.path;
    paths.add(path);
    final text = await utf8.decodeStream(body);
    if (path == '/v1/chat') declared.add(((jsonDecode(text) as Map)['client'] as Map)['capabilities'] as List<Object?>);
    http.StreamedResponse json(Object value) =>
        http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), 200, headers: {'content-type': 'application/json'});
    if (path == '/v1/apps/config') {
      return json({
        'channel': 'published',
        'version': null,
        'updated_at': null,
        'config': <String, Object>{},
        if (supportOn) 'support': {'enabled': true, 'team': 'Grove'},
      });
    }
    if (path == '/v1/followups/next') {
      return json({
        'followup': {'id': _followup, 'type': 'watch', 'title': 'Pegasus 41 indirimde', 'body': "449,90 TL'ye düştü.", 'button': 'Göster'},
      });
    }
    if (path == '/v1/followups/$_followup/open') return json({'conversation_id': 'c-f'});
    if (path == '/v1/conversations/c-f/messages') {
      return json({
        'conversation_id': 'c-f',
        'messages': [
          {
            'id': 'm0',
            'role': 'assistant',
            'blocks': [
              {'id': 'b0', 'type': 'text', 'fallback_text': '', 'props': {'markdown': 'Pegasus 41 artık 449,90 TL.'}},
            ],
            'created_at': '2026-11-01T09:00:00Z',
          },
        ],
      });
    }
    if (path == '/v1/chat') {
      final sse = [
        for (final (seq, event) in _handedOff.indexed) 'event: ${event['type']}\ndata: ${jsonEncode({'v': 1, 'seq': seq, ...event})}\n\n',
      ].join();
      return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200, headers: {'content-type': 'text/event-stream'});
    }
    if (path == '/v1/support/unread') return json({'unread': 2});
    if (path == '/v1/support/current' || path == '/v1/support/handoff') return json(_threadBody);
    // The team's stream, each time the page opens: held open, quiet.
    if (path.endsWith('/stream')) return http.StreamedResponse(StreamController<List<int>>().stream, 200);
    return json({'ok': true});
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Every way in, in turn: whether a support page or the launcher's count was on screen after any of them.
Future<({bool sheet, bool badge})> _walk(WidgetTester tester, _Server server) async {
  await tester.runAsync(() async {
    await Rendel.init(appKey: _key, config: RendelConfig(httpClient: server.client));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      context = c;
      return const Scaffold(floatingActionButton: RendelLauncher());
    }),
  ));
  await _settle(tester);
  var sheet = false;
  var badge = false;
  void look() {
    sheet |= find.byType(RendelSupportSheet).evaluate().isNotEmpty;
    badge |= find.descendant(of: find.byType(RendelLauncher), matching: find.text('2')).evaluate().isNotEmpty;
  }

  Future<void> closeAll() async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _settle(tester);
  }

  look();
  // Opened, and a turn the server hands to the team.
  unawaited(Rendel.open(context));
  await _settle(tester);
  look();
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(find.bySemanticsLabel('Type a message'));
    await _settle(tester);
  }
  await tester.enterText(find.byType(TextField).last, 'I want to talk to a person');
  await tester.runAsync(() async {
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await _settle(tester);
  look();
  await closeAll();
  // Away, and back to the foreground.
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await _settle(tester);
  look();
  // A push from the team, and a follow-up's.
  unawaited(Rendel.handlePush(context, {'rendel': '1', 'rendel_support': _thread}));
  await _settle(tester);
  look();
  await closeAll();
  unawaited(Rendel.handlePush(context, {'rendel': '1', 'rendel_followup': _followup}));
  await _settle(tester);
  look();
  await closeAll();
  // The launcher, tapped.
  await tester.tap(find.byType(RendelLauncher));
  await _settle(tester);
  look();
  await closeAll();
  // The app's own "Contact us".
  unawaited(Rendel.openSupport(context));
  await _settle(tester);
  look();
  await closeAll();
  return (sheet: sheet, badge: badge);
}

void main() {
  tearDown(Rendel.resetForTest);

  testWidgets('is dark with the default config: no support call, no support page, no badge', (tester) async {
    final server = _Server(supportOn: false);
    final seen = await _walk(tester, server);
    // The walk itself happened.
    expect(server.paths, containsAll(['/v1/apps/config', '/v1/chat', '/v1/followups/$_followup/open']));
    expect(server.supportCalls, isEmpty);
    expect(seen, (sheet: false, badge: false));
    expect(Rendel.supportOn, isFalse);
    expect(Rendel.supportUnread.value, 0);
    // Not declared either: a handoff would open a page this build keeps shut.
    expect(server.declared, isNotEmpty);
    expect(server.declared.expand((c) => c), isNot(contains('support')));
  });

  testWidgets('reaches the team once the config turns Support on', (tester) async {
    final server = _Server(supportOn: true);
    final seen = await _walk(tester, server);
    expect(server.supportCalls, containsAll(['/v1/support/unread', '/v1/support/current']));
    expect(server.supportCalls.any((p) => p.endsWith('/stream')), isTrue);
    expect(seen, (sheet: true, badge: true));
    expect(server.declared, everyElement(contains('support')));
  });
}
