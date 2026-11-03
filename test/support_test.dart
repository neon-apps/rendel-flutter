// Human support on a phone (design/plans/human-support.md §3, §10): an
// explicit ask hands the turn to the team; the support page draws the thread
// as a messaging app does, a speaker's lines as one run under who wrote them,
// never "Seen" or "Read"; a person nobody can reach is asked for an email
// after the first line; a line that did not go says so and goes again under
// the same id; an open conversation waits at the top of the thread once its
// page is closed; and the config says when an app's Support is on.

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
import 'package:rendel/src/ui/thread_screen.dart';

const _thread = '00000000-0000-4000-8000-000000000001';
const _past = '00000000-0000-4000-8000-0000000000a1';
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

  /// The device's conversations with the team, for Recent.
  List<Map<String, dynamic>> threads = const [];

  /// Past threads by id, as they were.
  final Map<String, ({Map<String, dynamic> state, List<Map<String, dynamic>> entries})> past = {};

  /// A line in a sorted thread opens it again; with [otherOpen], another one is open and it cannot.
  String? otherOpen;

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
    if (path == '/v1/support/unread') return json({'unread': 2, 'open': state['state'] != 'resolved'});
    if (path == '/v1/support/threads') return json({'threads': threads});
    if (request.method == 'GET' && path.startsWith('/v1/support/threads/') && path.split('/').length == 5) {
      final id = path.split('/').last;
      final known = past[id];
      return json({'thread_id': known == null ? _thread : id, 'conversation_id': 'c2', 'state': known?.state ?? state, 'entries': known?.entries ?? entries});
    }
    if (request.method == 'POST') posts.add((path: path.split('/threads/$_thread/').last, body: sent));
    if (path.endsWith('/messages')) {
      final id = path.split('/')[4];
      if (past[id] case final known? when known.state['state'] == 'resolved') {
        if (otherOpen != null) return json({'error': {'code': 'another_open', 'thread_id': otherOpen}}, 409);
        final reopened = {..._entry(known.entries.length + 1, kind: 'marker', author: 'system', text: 'Back with the Grove team.'), 'marker': 'reopened'};
        final line = _entry(known.entries.length + 2, text: sent!['text'] as String, client: sent['client_msg_id'] as String);
        past[id] = (state: {...known.state, 'state': 'open', 'mode': 'human'}, entries: [...known.entries, reopened, line]);
        return json({'entry': line, 'reopened': reopened});
      }
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
    testWidgets("groups a speaker's lines, names who answered for which team, and says what happened with its time (design A)", (tester) async {
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
      expect(find.textContaining('Your message is with the Grove team. · '), findsOneWidget);
      // The person's two lines are one run; the team's is under who wrote it, for which team, once.
      expect(find.text('Ayşe · Grove team'), findsOneWidget);
      expect(find.text('You'), findsNothing);
      expect(find.textContaining('Seen'), findsNothing);
      // The person's lines on the end, the team's on the start.
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getTopRight(find.text('Kargom gelmedi')).dx, greaterThan(width * 0.8));
      expect(tester.getTopLeft(find.text('Hemen bakıyorum.')).dx, lessThan(width * 0.3));
      // The team has answered: "I'm sorted" as the chip above the box, not "By mistake?".
      expect(find.text("I'm sorted"), findsOneWidget);
      expect(find.textContaining('By mistake'), findsNothing);
      // The box names the team, never the person in it.
      expect(find.widgetWithText(TextField, 'Message the Grove team'), findsOneWidget);
      await _close(tester);
    });

    testWidgets("keeps an open conversation at the top of the thread with the team's count, and opens it from there", (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Hemen bakıyorum.')],
        state: _state(mode: 'human'),
      );
      final support = server.support();
      final controller = ConversationController(api: server.api(), actions: const {}, sdkVersion: 'flutter/test', onOpenUrl: (_) async => true);
      addTearDown(controller.dispose);
      var opened = 0;
      // As after a restart: the API says a conversation is open, and the row reads its lines.
      await tester.runAsync(support.refreshUnread);
      await tester.pumpWidget(_app(ThreadScreen(controller: controller, support: support, supportTeam: 'Grove', onSupportOpen: () => opened++)));
      await _settle(tester);
      await _settle(tester);
      expect(find.bySemanticsLabel(RegExp('Your conversation with the Grove team')), findsOneWidget);
      expect(find.text('Grove team'), findsOneWidget);
      expect(find.text('Ayşe: Hemen bakıyorum.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('New messages from the team: 2')), findsOneWidget);
      await tester.tap(find.text('Grove team'));
      expect(opened, 1);
      // Sorted: the row goes.
      server.state = {..._state(mode: 'human'), 'state': 'resolved'};
      await tester.runAsync(support.load);
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Your conversation with the Grove team')), findsNothing);
    });

    testWidgets('says who is helping and when, Read under the run the team read, and sorted as a card (design A)', (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Hemen bakıyorum.')],
        state: {..._state(mode: 'human'), 'presence': 'Ayşe is here · replies in about 10 minutes', 'team_read_seq': 1},
      );
      await _open(tester, server.support());
      expect(find.text('Ayşe is here · replies in about 10 minutes'), findsOneWidget);
      expect(find.textContaining(' · Read'), findsOneWidget);
      expect(find.text("I'm sorted"), findsOneWidget);
      await tester.tap(find.text("I'm sorted"));
      server.state = {...server.state, 'state': 'resolved'};
      await _settle(tester);
      expect(find.text('You marked this sorted'), findsOneWidget);
      expect(find.text('Write any time and the Grove team picks it up again.'), findsOneWidget);
      // The box to write in stays: a line opens it again.
      expect(find.widgetWithText(TextField, 'Write to open it again'), findsOneWidget);
      expect(find.text("I'm sorted"), findsNothing);
      // Sorted, the header shows the tick where the close was: out by the way back.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await _settle(tester);
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

    testWidgets('lists the sorted ones under the suggestions, and See all opens them by week with a search', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: {..._state(), 'state': 'resolved'});
      final now = DateTime.now().toUtc();
      server.threads = [
        {'thread_id': _thread, 'state': 'resolved', 'title': 'Kargom gelmedi', 'unread': 0, 'last_message_at': now.toIso8601String()},
        {'thread_id': _past, 'state': 'resolved', 'title': 'My order 1042 came with the box crushed', 'agent': 'Ayşe', 'unread': 0, 'last_message_at': '2026-10-12T10:00:00Z'},
      ];
      final support = server.support();
      final controller = ConversationController(api: server.api(), actions: const {}, sdkVersion: 'flutter/test', onOpenUrl: (_) async => true);
      addTearDown(controller.dispose);
      final opened = <String>[];
      await tester.pumpWidget(_app(ThreadScreen(controller: controller, support: support, supportTeam: 'Grove', onSupportThread: opened.add)));
      await _settle(tester);
      await _settle(tester);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Sorted with Ayşe'), findsOneWidget);
      await tester.tap(find.text('My order 1042 came with the box crushed'));
      expect(opened, [_past]);
      await tester.tap(find.text('See all'));
      await _settle(tester);
      await _settle(tester);
      expect(find.text('With the Grove team'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
      // Recent stays under the list; the list itself lets go of what does not match.
      expect(find.text('Kargom gelmedi'), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).last, '1042');
      await tester.pump();
      expect(find.text('Kargom gelmedi'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'nothing like it');
      await tester.pump();
      expect(find.text('No conversation matches that.'), findsOneWidget);
    });

    testWidgets('opens a sorted one as it was, and writing in it opens it again in place', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')]);
      server.past[_past] = (
        state: {..._state(mode: 'closed'), 'thread_id': _past, 'state': 'resolved', 'user_read_seq': 3, 'last_seq': 3},
        entries: [
          _entry(1, text: 'My order 1042 came with the box crushed'),
          _entry(2, author: 'agent', name: 'Ayşe', text: 'Done. Your new pair ships today.'),
          {..._entry(3, kind: 'marker', author: 'system', text: 'Marked as sorted.'), 'marker': 'resolved'},
        ],
      );
      final support = server.support();
      await tester.runAsync(() => support.show(_past));
      await _open(tester, support);
      expect(find.textContaining('Sorted on '), findsOneWidget);
      expect(find.textContaining('Sorted · '), findsOneWidget);
      expect(find.text('You marked this sorted'), findsNothing);
      expect(find.widgetWithText(TextField, 'Write to open it again'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'The new pair is a bit small, can I get a 43?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      await _settle(tester);
      expect(find.textContaining('Opened again · '), findsOneWidget);
      expect(find.text("I'm sorted"), findsOneWidget);
      await _close(tester);
    });

    testWidgets('says when another conversation is open, and goes to it', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')])..otherOpen = _thread;
      server.past[_past] = (
        state: {..._state(mode: 'closed'), 'thread_id': _past, 'state': 'resolved'},
        entries: [_entry(1, text: 'My order 1042 came with the box crushed'), {..._entry(2, kind: 'marker', author: 'system', text: 'Marked as sorted.'), 'marker': 'resolved'}],
      );
      final support = server.support();
      await tester.runAsync(() => support.show(_past));
      await _open(tester, support);
      await tester.enterText(find.byType(TextField).last, 'One more thing');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(find.text('Another conversation with the team is open.'), findsOneWidget);
      await tester.tap(find.text('Go to it'));
      await _settle(tester);
      await _settle(tester);
      expect(support.value.value.threadId, _thread);
      expect(find.text('Another conversation with the team is open.'), findsNothing);
      await _close(tester);
    });

    testWidgets("opens at New above the team's lines the person had not read", (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Can I swap the Aero Glide for a 44?'), _entry(2, author: 'agent', name: 'Dana', text: 'Morning, Dana here. The 44 is in stock.')],
        state: {..._state(mode: 'human'), 'user_read_seq': 1, 'last_seq': 2},
      );
      await _open(tester, server.support());
      expect(find.textContaining('New · '), findsOneWidget);
      final mark = tester.getTopLeft(find.textContaining('New · ')).dy;
      expect(mark, lessThan(tester.getTopLeft(find.text('Morning, Dana here. The 44 is in stock.')).dy));
      expect(mark, greaterThan(tester.getTopLeft(find.text('Can I swap the Aero Glide for a 44?')).dy));
      await _close(tester);
    });

    testWidgets('says the row is waiting while the team is away, with a clock, and the reply is a line at the top of an answer', (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Can I swap the Aero Glide for a 44?')],
        state: {..._state(), 'team_here': false, 'waiting': 'Waiting for the team · back tomorrow at 09:00'},
      );
      final support = server.support();
      final controller = ConversationController(api: server.api(), actions: const {}, sdkVersion: 'flutter/test', onOpenUrl: (_) async => true);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await support.load();
        // Nothing unread yet: the team has not answered.
        support.value.value = support.value.value.copyWith(unread: 0);
      });
      await tester.pumpWidget(_app(ThreadScreen(controller: controller, support: support, supportTeam: 'Grove', onSupportOpen: () {})));
      await tester.pump();
      expect(find.text('Waiting for the team · back tomorrow at 09:00'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
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
      // The page's start is on the right: the team's line and the way back are there; the person's own line and the close on the other side.
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getTopLeft(find.text('لم تصل شحنتي بعد، والطلب رقم M-2021')).dx, lessThan(width * 0.2));
      expect(tester.getTopRight(find.text('سأتحقق من ذلك الآن.')).dx, greaterThan(width * 0.7));
      expect(tester.getCenter(find.byIcon(Icons.chevron_left_rounded)).dx, greaterThan(width / 2));
      expect(tester.getCenter(find.byIcon(Icons.close_rounded)).dx, lessThan(width / 2));
      await _close(tester);
    });

    testWidgets('lets the first line go before asking for an email, as the server does', (tester) async {
      final server = _Server(
        entries: [_entry(1, kind: 'marker', author: 'system', text: 'Your message is with the Grove team.')],
        state: _state(contact: {'state': 'none', 'required': true}),
      );
      await _open(tester, server.support());
      expect(find.widgetWithText(TextField, 'Message the Grove team'), findsOneWidget);
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
      expect(find.widgetWithText(TextField, 'Message the Grove team'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'zeynep@example.com');
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'contact').body, {'email': 'zeynep@example.com'});
      expect(find.text('Thanks. Check your inbox to confirm the address.'), findsOneWidget);
      await _close(tester);
    });

    test("holds an address to the API's own rule", () {
      for (final ok in ['ahmet@example.com', ' Ahmet.Yilmaz+shop@Mail.Example.COM ', "o'neil@example.co.uk", 'a_b-c@x-y.io']) {
        expect(supportEmailProblem(ok), isNull, reason: ok);
      }
      expect(supportEmailProblem('   '), 'empty');
      for (final bad in ['ahmet', 'ahmet@', '@example.com', 'ahmet@example', 'ahmet@example.c', 'ahmet@@example.com', '.ahmet@example.com', 'ah..met@example.com', 'ahmet.@example.com', 'ahmet@-example.com', 'ahmet @example.com', '${'a' * 250}@x.com']) {
        expect(supportEmailProblem(bad), 'invalid', reason: bad);
      }
    });

    testWidgets('warns under the email field when the address is wrong, and sends nothing until it is right', (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Kargom gelmedi')],
        state: _state(contact: {'state': 'none', 'required': true}),
      );
      await _open(tester, server.support());
      await tester.enterText(find.byType(TextField).first, 'ahmet');
      await tester.pump();
      // Not while the first letters go in.
      expect(find.text('Check the address. It should look like you@example.com.'), findsNothing);
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text('Check the address. It should look like you@example.com.'), findsOneWidget);
      expect(server.posts.where((p) => p.path == 'contact'), isEmpty);
      // The placeholder never stands in for a message on the page: only the field's own hint says it.
      expect(find.text('you@example.com').evaluate().where((e) => e.findAncestorWidgetOfExactType<TextField>() == null), isEmpty);
      await tester.enterText(find.byType(TextField).first, 'ahmet@example.com');
      await tester.pump();
      expect(find.text('Check the address. It should look like you@example.com.'), findsNothing);
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'contact').body, {'email': 'ahmet@example.com'});
      await _close(tester);
    });

    testWidgets('brings the warning above the keyboard when Save keeps the field', (tester) async {
      final server = _Server(
        entries: [for (var i = 1; i <= 6; i++) _entry(i, text: 'Kargom hâlâ gelmedi, sipariş $i')],
        state: _state(contact: {'state': 'none', 'required': true}),
      );
      // A phone, whose keyboard comes up under the field once it is tapped.
      tester.view.physicalSize = const Size(402, 874) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await _open(tester, server.support());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.showKeyboard(find.byType(TextField).first);
      tester.view.viewInsets = FakeViewPadding(bottom: 336 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).first, 'ahmet');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Save'));
      await _settle(tester);
      final warning = find.text('Check the address. It should look like you@example.com.');
      final thread = tester.getRect(find.ancestor(of: warning, matching: find.byType(Scrollable)).first);
      expect(tester.getRect(warning).bottom, lessThanOrEqualTo(thread.bottom));
      expect(tester.getRect(find.byType(TextField).first).top, greaterThanOrEqualTo(thread.top));
      expect(tester.takeException(), isNull);
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
