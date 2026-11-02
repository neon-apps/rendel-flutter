// Human support on a phone (design/plans/human-support.md §3, §10): an
// explicit ask hands the turn to the team; the support page draws the thread
// as lines with an author whenever the speaker changes, never "Seen"; a
// person nobody can reach is asked for an email after the first line; a line
// that did not go says so and goes again under the same id; and the config
// says when an app's Support is on.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/support.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/support_sheet.dart';

const _thread = '00000000-0000-4000-8000-000000000001';
const _invocation = '00000000-0000-4000-8000-0000000000aa';

Map<String, dynamic> _entry(int seq, {String author = 'user', String? name, String? text, String kind = 'message', String? client, List<Object> blocks = const []}) => {
      'id': '00000000-0000-4000-8000-0000000000${10 + seq}',
      'seq': seq,
      'kind': kind,
      'author': {'kind': author, if (name != null) 'name': name},
      if (text != null) 'text': text,
      'blocks': blocks,
      'attachments': <Object>[],
      if (client != null) 'client_msg_id': client,
      'created_at': '2026-11-01T10:00:00Z',
    };

Map<String, dynamic> _state({String mode = 'waiting', Map<String, dynamic> contact = const {'state': 'not_needed', 'required': false}}) => {
      'thread_id': _thread,
      'mode': mode,
      'state': 'open',
      'team_here': true,
      'team_read_seq': 0,
      'user_read_seq': 0,
      'last_seq': 2,
      'contact': contact,
    };

class _Server {
  _Server({required this.entries, Map<String, dynamic>? state}) : state = state ?? _state();

  List<Map<String, dynamic>> entries;
  Map<String, dynamic> state;
  final List<({String path, Map<String, dynamic>? body})> posts = [];

  /// How each message post is answered, in turn; 200 once they run out.
  final List<int> messageStatus = [];

  /// The stream is held open and says nothing, as a quiet thread's does, until a test [say]s something on it.
  final StreamController<List<int>> _quiet = StreamController<List<int>>();

  void say(Map<String, dynamic> event) => _quiet.add(utf8.encode('event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n'));

  late final client = MockClient.streaming((request, body) async {
    final path = request.url.path;
    if (path.endsWith('/stream')) return http.StreamedResponse(_quiet.stream, 200);
    Map<String, dynamic>? sent;
    final raw = await body.bytesToString();
    if (raw.isNotEmpty) sent = jsonDecode(raw) as Map<String, dynamic>;
    http.StreamedResponse json(Object value, [int status = 200]) =>
        http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), status, headers: {'content-type': 'application/json'});
    if (path == '/v1/support/current') return json({'thread_id': _thread, 'conversation_id': 'c1', 'state': state, 'entries': entries});
    if (path == '/v1/support/unread') return json({'unread': 2});
    if (request.method == 'POST') posts.add((path: path.split('/threads/$_thread/').last, body: sent));
    if (path.endsWith('/messages')) {
      final status = messageStatus.isEmpty ? 200 : messageStatus.removeAt(0);
      if (status != 200) return json({'error': {'code': 'internal'}}, status);
      final entry = _entry(entries.length + 1, text: sent!['text'] as String, client: sent['client_msg_id'] as String);
      entries = [...entries, entry];
      return json({'entry': entry});
    }
    if (path.contains('/cards/')) {
      entries = [
        for (final e in entries)
          {
            ...e,
            'blocks': [
              for (final b in e['blocks'] as List)
                (b as Map)['type'] == 'confirm_card'
                    ? {
                        ...b,
                        'props': {
                          ...(b['props'] as Map),
                          'invocation_id': _invocation,
                          'confirm': {'kind': 'confirm', 'invocation_id': _invocation},
                          'cancel': {'kind': 'cancel', 'invocation_id': _invocation},
                        },
                      }
                    : b,
            ],
          },
      ];
      final block = entries.expand((e) => e['blocks'] as List).firstWhere((b) => (b as Map)['type'] == 'confirm_card');
      return json({'block': block});
    }
    if (path.endsWith('/continue')) return json({'status': 'succeeded'});
    if (path.endsWith('/confirm')) return json({'status': 'confirmed'});
    if (path.endsWith('/contact')) {
      state = _state(contact: {'state': 'stated', 'required': false});
      return json({'state': 'stated', 'emailed': false});
    }
    return http.StreamedResponse(const Stream.empty(), 204);
  });

  RendelApiClient api() => RendelApiClient(appKey: 'nc_pk_test_x', deviceId: 'device-1', config: const RendelConfig(), httpClient: client);

  RendelSupport support() => RendelSupport(api(), user: () => null, locale: () => 'en');
}

Widget _app(Widget child) => MaterialApp(
      home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: child)),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _open(WidgetTester tester, RendelSupport support) async {
  await tester.pumpWidget(_app(Builder(
    builder: (context) => TextButton(
      onPressed: () => showRendelSupport(
        context,
        support: support,
        team: 'Grove',
        onAction: (_) async => true,
        canHandle: (_) => true,
      ),
      child: const Text('open'),
    ),
  )));
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Future<void> _openArabic(WidgetTester tester, RendelSupport support) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: RendelThemeScope(
      theme: RendelTheme.paper(),
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRendelSupport(
              context,
              support: support,
              team: 'Grove',
              onAction: (_) async => true,
              canHandle: (_) => true,
              strings: RendelStrings.forLocale('ar'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close_rounded));
  await _settle(tester);
}

void main() {
  group('the support page', () {
    testWidgets('draws an author line only when the speaker changes, and never says Seen', (tester) async {
      final server = _Server(
        entries: [
          _entry(1, kind: 'marker', author: 'system', text: 'Your message is with the Grove team.'),
          _entry(2, text: 'Kargom gelmedi'),
          _entry(3, text: 'Ve kutu ezik'),
          _entry(4, author: 'agent', name: 'Ayşe', text: 'Hemen bakıyorum.'),
        ],
        state: _state(mode: 'human'),
      );
      await _open(tester, server.support());
      expect(find.text('Grove team'), findsOneWidget);
      expect(find.text('Your message is with the Grove team.'), findsOneWidget);
      expect(find.textContaining('You · '), findsOneWidget);
      expect(find.textContaining('Ayşe · '), findsOneWidget);
      expect(find.textContaining('Seen'), findsNothing);
      // The team has answered: no "By mistake?", but "I'm sorted".
      expect(find.text("I'm sorted"), findsOneWidget);
      expect(find.text('Write to Ayşe…'), findsNothing);
      await _close(tester);
    });

    testWidgets('keeps the place to write above the keyboard', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Bakıyorum.')], state: _state(mode: 'human'));
      await _open(tester, server.support());
      final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final field = find.byType(TextField).last;
      expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(height - 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reads right to left in Arabic, with its words and nothing cut', (tester) async {
      final server = _Server(
        entries: [
          _entry(1, kind: 'marker', author: 'system', text: 'رسالتك لدى فريق Grove.'),
          _entry(2, text: 'لم تصل شحنتي بعد، والطلب رقم M-2021'),
          _entry(3, author: 'agent', name: 'Ayşe', text: 'سأتحقق من ذلك الآن.'),
        ],
        state: _state(mode: 'human'),
      );
      await _openArabic(tester, server.support());
      expect(tester.takeException(), isNull);
      final ar = RendelStrings.forLocale('ar');
      expect(find.text(ar.supportSorted), findsOneWidget);
      // The page's start is on the right: the person's line hugs it, the close is at the other end.
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final line = tester.getTopRight(find.text('لم تصل شحنتي بعد، والطلب رقم M-2021'));
      expect(line.dx, greaterThan(width * 0.8));
      expect(tester.getCenter(find.byIcon(Icons.close_rounded)).dx, lessThan(width / 2));
      await _close(tester);
    });

    testWidgets('lets the first line go before asking for an email, as the server does', (tester) async {
      final server = _Server(
        entries: [_entry(1, kind: 'marker', author: 'system', text: 'Your message is with the Grove team.')],
        state: _state(contact: {'state': 'none', 'required': true}),
      );
      await _open(tester, server.support());
      expect(find.widgetWithText(TextField, 'Write to the Grove team…'), findsOneWidget);
      expect(find.text('Where should we send the reply? Add your email to keep going.'), findsNothing);
      await _close(tester);
    });

    testWidgets('asks for an email after the first line when nobody can reach the person, and takes it', (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Kargom gelmedi')],
        state: _state(contact: {'state': 'none', 'required': true}),
      );
      await _open(tester, server.support());
      expect(find.text('Where should we send the reply? Add your email to keep going.'), findsOneWidget);
      // No field to write in until the address is given.
      expect(find.widgetWithText(TextField, 'Write to the Grove team…'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'zeynep@example.com');
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'contact').body, {'email': 'zeynep@example.com'});
      expect(find.text('Thanks. Check your inbox to confirm the address.'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('says a line did not go, and sends it again under the same id', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')])..messageStatus.add(500);
      await _open(tester, server.support());
      await tester.enterText(find.byType(TextField).last, 'Merhaba?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(find.text('Not sent. Tap to try again.'), findsOneWidget);
      await tester.tap(find.text('Not sent. Tap to try again.'));
      await _settle(tester);
      final sent = [for (final p in server.posts) if (p.path == 'messages') p.body!];
      expect(sent, hasLength(2));
      expect(sent[0]['client_msg_id'], sent[1]['client_msg_id']);
      expect(find.text('Not sent. Tap to try again.'), findsNothing);
      expect(find.text('Merhaba?'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('opens a confirm card the team sent on this phone, and a yes goes through Support', (tester) async {
      final server = _Server(
        entries: [
          _entry(1, text: 'Kargom gelmedi'),
          _entry(2, author: 'agent', name: 'Ayşe', text: 'Yeniden gönderelim mi?', blocks: [
            {
              'id': 'card-1',
              'type': 'confirm_card',
              'fallback_text': 'Send order M-2020 again',
              'props': {'invocation_id': '', 'action_name': 'reship_order', 'summary': 'Send order M-2020 again', 'params': {'order_id': 'M-2020'}, 'params_display': <Object>[]},
            },
          ]),
        ],
        state: _state(mode: 'human'),
      );
      await _open(tester, server.support());
      await _settle(tester);
      expect(server.posts.any((p) => p.path.startsWith('cards/') && p.path.endsWith('/open')), isTrue);
      expect(find.text('Send order M-2020 again'), findsWidgets);
      await tester.ensureVisible(find.text('Confirm').last);
      await tester.tap(find.text('Confirm').last);
      for (var i = 0; i < 4; i++) {
        await _settle(tester);
      }
      expect(server.posts.singleWhere((p) => p.path == 'continue').body, {'invocation_id': _invocation});
      await _close(tester);
    });

    testWidgets('answers a read the team asked for, and asks first when the app says so', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state(mode: 'human'));
      await _open(tester, server.support());
      server.say({'type': 'support.lookup', 'lookup_id': 'L1', 'action': 'Ayşe would like to check your account.', 'ask': false});
      server.say({'type': 'support.lookup', 'lookup_id': 'L2', 'action': 'Ayşe would like to check your account.', 'ask': true});
      await _settle(tester);
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'lookups/L1/run').body, {'allow': true});
      expect(find.text('Ayşe would like to check your account.'), findsOneWidget);
      await tester.tap(find.text('Go back'));
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'lookups/L2/run').body, {'allow': false});
      expect(find.text('Ayşe would like to check your account.'), findsNothing);
      await _close(tester);
    });

    test("counts the team's unread lines", () async {
      final support = _Server(entries: const []).support();
      expect(await support.refreshUnread(), 2);
      expect(support.value.value.unread, 2);
    });
  });

  group('a turn that hands the person to the team', () {
    testWidgets('leaves no question or empty answer behind and says which thread opened', (tester) async {
      final events = [
        {'type': 'turn.start', 'conversation_id': 'c1', 'message_id': 'm1'},
        {'type': 'support.handoff', 'thread_id': _thread, 'conversation_id': 'c1'},
        {'type': 'turn.end', 'status': 'completed', 'pending': <String>[]},
      ];
      final sse = [
        for (final (seq, event) in events.indexed) 'event: ${event['type']}\ndata: ${jsonEncode({'v': 1, 'seq': seq, ...event})}\n\n',
      ].join();
      final client = MockClient((request) async => http.Response(sse, 200, headers: {'content-type': 'text/event-stream'}));
      final c = ConversationController(
        api: RendelApiClient(appKey: 'nc_pk_test_x', deviceId: 'device-1', config: const RendelConfig(), httpClient: client),
        actions: const {},
        sdkVersion: 'flutter/test',
      );
      addTearDown(c.dispose);
      String? opened;
      c.onSupportHandoff = (thread) => opened = thread;
      await tester.runAsync(() => c.send('I want to talk to a person'));
      expect(opened, _thread);
      expect(c.messages, isEmpty);
      // Handed over is an answer: no "No answer came back" waits under the thread when the team's page closes.
      expect(c.errorCode, isNull);
      expect(c.errorText, isNull);
    });
  });

  group('the config', () {
    test('says Support is on with the team, and keeps it through the cache', () {
      final on = RendelRemoteConfig.tryParse(jsonEncode({
        'channel': 'published',
        'config': <String, Object>{},
        'support': {'enabled': true, 'team': 'Grove'},
      }))!;
      expect(on.supportTeam, 'Grove');
      expect(RendelRemoteConfig.tryParse(on.toCache())!.supportTeam, 'Grove');
      final off = RendelRemoteConfig.tryParse(jsonEncode({'channel': 'published', 'config': <String, Object>{}}))!;
      expect(off.supportTeam, isNull);
    });
  });
}
