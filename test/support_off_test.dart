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

/// The same thread once the app switched Support off: closed, with its line and the app's channels (K1).
final _closedByOff = {
  ..._threadBody,
  'state': {
    ...(_threadBody['state'] as Map<String, Object?>),
    'mode': 'closed',
    'state': 'resolved',
    'closed_reason': 'support_off',
    'contact_channels': [
      {'kind': 'email', 'label': 'Email us', 'value': 'help@grove.example'},
    ],
  },
  'entries': [
    ...(_threadBody['entries'] as List<Object?>),
    {
      'id': '00000000-0000-4000-8000-000000000012',
      'seq': 2,
      'kind': 'marker',
      'marker': 'support_off',
      'author': {'kind': 'system'},
      'text': 'Messages here no longer reach the Grove team, so this conversation is closed.',
      'blocks': <Object>[],
      'attachments': <Object>[],
      'created_at': '2026-11-01T10:05:00Z',
    },
  ],
};

class _Server {
  _Server({required this.supportOn, this.current});

  /// Whether the config says Support is on; switched by a test while the page is up.
  bool supportOn;

  /// The phone's thread, as the server reads it.
  Map<String, Object?>? current;

  /// Lines are refused with 409 support_unavailable: Support was switched off since the page opened.
  bool refuseLines = false;

  /// The open team stream, to have it say something.
  StreamController<List<int>>? stream;

  void say(List<Map<String, Object?>> events) => stream!.add(utf8.encode([for (final e in events) 'data: ${jsonEncode(e)}\n\n'].join()));

  /// What each resolve asked, by its body.
  final List<Object?> resolves = [];
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
    if (path == '/v1/support/current' || path == '/v1/support/handoff') return json(current ?? _threadBody);
    if (path.endsWith('/messages') && refuseLines) {
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'error': {'code': 'support_unavailable'}}))), 409, headers: {'content-type': 'application/json'});
    }
    if (path.endsWith('/resolve')) {
      resolves.add(jsonDecode(text));
      return http.StreamedResponse(const Stream.empty(), 204);
    }
    // The team's stream, each time the page opens: held open, quiet until the test has it say something.
    if (path.endsWith('/stream')) return http.StreamedResponse((stream = StreamController<List<int>>()).stream, 200);
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

  testWidgets("reads the team's count on its beat with no launcher on screen and nothing known to be open (sdk-m1)", (tester) async {
    final server = _Server(supportOn: true);
    await tester.runAsync(() async {
      await Rendel.init(appKey: _key, config: RendelConfig(httpClient: server.client));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    int reads() => server.supportCalls.where((p) => p == '/v1/support/unread').length;
    final before = reads();
    // The server says nothing is open; the beat reads the count all the same.
    await tester.runAsync(Rendel.supportTick);
    expect(reads(), before + 1);
    expect(Rendel.supportUnread.value, 2);
  });

  testWidgets('keeps the conversation this phone already had once Support is switched off: Contact us opens it, and nothing new starts (D4)', (tester) async {
    late BuildContext context;
    Future<void> mount() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const Scaffold(body: SizedBox());
        }),
      ));
      await _settle(tester);
    }

    // A first launch with Support on: the person reached the team.
    final first = _Server(supportOn: true);
    await tester.runAsync(() async {
      await Rendel.init(appKey: _key, config: RendelConfig(httpClient: first.client));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await mount();
    unawaited(Rendel.openSupport(context));
    await _settle(tester);
    expect(find.byType(RendelSupportSheet), findsOneWidget);
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _settle(tester);
    // Support is switched off, which closes the conversation, and the app starts again, keeping what the phone kept.
    Rendel.resetForTest(relaunch: true);
    final second = _Server(supportOn: false, current: _closedByOff);
    await tester.runAsync(() async {
      await Rendel.init(appKey: _key, config: RendelConfig(httpClient: second.client));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await mount();
    unawaited(Rendel.openSupport(context));
    await _settle(tester);
    await _settle(tester);
    expect(find.byType(RendelSupportSheet), findsOneWidget);
    expect(find.textContaining('no longer reach the Grove team'), findsOneWidget);
    expect(find.text('Reach the Grove team'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    // The conversation is read; nothing is opened, counted or followed.
    expect(second.supportCalls, contains('/v1/support/current'));
    expect(second.supportCalls.where((p) => p == '/v1/support/handoff' || p == '/v1/support/unread' || p.endsWith('/stream')), isEmpty);
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _settle(tester);
  });

  /// A launch with Support on, the team's page open on the conversation.
  Future<(_Server, BuildContext)> openOnTeamPage(WidgetTester tester) async {
    final server = _Server(supportOn: true);
    await tester.runAsync(() async {
      await Rendel.init(appKey: _key, config: RendelConfig(httpClient: server.client));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        context = c;
        return const Scaffold(body: SizedBox());
      }),
    ));
    await _settle(tester);
    unawaited(Rendel.openSupport(context));
    await _settle(tester);
    await _settle(tester);
    expect(find.byType(TextField), findsOneWidget);
    return (server, context);
  }

  int configReads(_Server server) => server.paths.where((p) => p == '/v1/apps/config').length;

  testWidgets("draws the closing line, the app's channels and no box or chip when Support is switched off with the team page open (qa3-k1-01)", (tester) async {
    final (server, context) = await openOnTeamPage(tester);
    final before = configReads(server);
    // Switched off while the page is up: the stream says the conversation closed, and the config now says off.
    server
      ..supportOn = false
      ..current = _closedByOff;
    server.say([
      {'type': 'support.entry', 'entry': (_closedByOff['entries'] as List).last},
      {'type': 'support.state', 'state': _closedByOff['state']},
    ]);
    await _settle(tester);
    await _settle(tester);
    expect(configReads(server), before + 1);
    expect(Rendel.supportOn, isFalse);
    expect(find.textContaining('no longer reach the Grove team'), findsOneWidget);
    expect(find.text('Reach the Grove team'), findsOneWidget);
    expect(find.text('Email help@grove.example'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text("I'm sorted"), findsNothing);
    expect(find.textContaining('By mistake'), findsNothing);
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _settle(tester);
    // Off, the config is read again on a beat (qa4-k1-02): that timer goes with the test.
    Rendel.resetForTest();
  });

  testWidgets('reads the config again once it saw Support switched off, so Support switched back on reaches the app without a restart (qa4-k1-02)', (tester) async {
    final (server, context) = await openOnTeamPage(tester);
    server
      ..supportOn = false
      ..current = _closedByOff;
    server.say([
      {'type': 'support.entry', 'entry': (_closedByOff['entries'] as List).last},
      {'type': 'support.state', 'state': _closedByOff['state']},
    ]);
    await _settle(tester);
    await _settle(tester);
    expect(find.text('Reach the Grove team'), findsOneWidget);
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _settle(tester);
    // Back to the foreground: read again.
    final before = configReads(server);
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await _settle(tester);
    expect(configReads(server), before + 1);
    expect(Rendel.supportOn, isFalse);
    // Switched back on, and the app's own Contact us: the config first, then a page to write in.
    server.supportOn = true;
    unawaited(Rendel.openSupport(context));
    await _settle(tester);
    await _settle(tester);
    expect(configReads(server), before + 2);
    expect(Rendel.supportOn, isTrue);
    expect(find.text('Reach the Grove team'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _settle(tester);
    // On again, the team's count is read on its beat: that timer goes with the test.
    Rendel.resetForTest();
  });

  testWidgets('says why a line did not go when the server refuses it because Support is off, and redraws the page as off (qa3-k1-01)', (tester) async {
    final (server, context) = await openOnTeamPage(tester);
    // Switched off since the page opened, and nothing on the stream said so.
    server
      ..supportOn = false
      ..current = _closedByOff
      ..refuseLines = true;
    await tester.enterText(find.byType(TextField).last, 'Are you there?');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _settle(tester);
    await _settle(tester);
    expect(find.text('Not sent. Messages here no longer reach the team.'), findsOneWidget);
    expect(find.text('Not sent. Tap to try again.'), findsNothing);
    expect(find.text('Reach the Grove team'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _settle(tester);
  });
}
