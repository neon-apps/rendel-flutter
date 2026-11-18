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
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Reads of the count that fail with these, in turn, before the count answers again.
  final List<int> unreadStatus = [];

  /// How a confirmed card's write went, and the answers to a read's run that fail before one goes.
  Map<String, Object> continueAnswer = const {'status': 'succeeded'};
  int continueStatus = 200;
  final List<int> runStatus = [];

  /// The phone's current thread on the server: another id once a new one opened after a sorted one.
  String currentId = _thread;

  /// The phone has no thread until a handoff opens one (K3); how each handoff is answered, in turn (200 once they run out).
  bool noThread = false;
  final List<int> handoffStatus = [];
  final List<Map<String, dynamic>> handoffs = [];

  /// The device's conversations with the team, for Recent.
  List<Map<String, dynamic>> threads = const [];

  /// Past threads by id, as they were.
  final Map<String, ({Map<String, dynamic> state, List<Map<String, dynamic>> entries})> past = {};

  /// A line in a sorted thread opens it again; with [otherOpen], another one is open and it cannot.
  String? otherOpen;

  /// What the server says when a card is opened, when not its 200.
  int? openCard;

  /// The reads the team asked for that the count brings (C6).
  List<Map<String, dynamic>> lookups = const [];

  /// How each yes or no to a card is answered, in turn (status and body); `confirmed` once they run out.
  final List<(int, Map<String, Object>)> confirmAnswers = [];

  /// Each yes or no to a card, with the headers it carried.
  final List<({Map<String, String> headers, Map<String, dynamic>? body})> confirms = [];

  /// What the count and the stream were asked with.
  final List<String> queries = [];

  /// The person's next line is held for an address (409 contact_required).
  bool holdForContact = false;

  /// Whether a saved address is emailed its code (never on a test key), the code an address is refused with (409),
  /// and how each ask for the code again is answered, in turn (200 once they run out).
  bool emailed = true;
  String? contactRefused;
  final List<int> resendStatus = [];

  /// The stream is held open and says nothing, as a quiet thread's does, until a test [say]s something on it.
  /// Broadcast, so the page opened a second time listens again.
  final StreamController<List<int>> _quiet = StreamController<List<int>>.broadcast();

  void say(Map<String, dynamic> event) => _quiet.add(utf8.encode('event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n'));

  late final client = MockClient.streaming((request, body) async {
    final path = request.url.path;
    if (path.endsWith('/stream') || path == '/v1/support/unread') queries.add('${path.split('/').last}?${request.url.query}');
    if (path.endsWith('/stream')) return http.StreamedResponse(_quiet.stream, 200);
    Map<String, dynamic>? sent;
    final raw = await body.bytesToString();
    if (raw.isNotEmpty) sent = jsonDecode(raw) as Map<String, dynamic>;
    http.StreamedResponse json(Object value, [int status = 200]) =>
        http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), status, headers: {'content-type': 'application/json'});
    // As the server reads it: the lines after the cursor.
    if (path == '/v1/support/handoff') {
      handoffs.add(sent!);
      final status = handoffStatus.isEmpty ? 200 : handoffStatus.removeAt(0);
      if (status != 200) return json({'error': {'code': status == 429 ? 'rate_limited' : 'internal'}}, status);
      if (noThread) {
        noThread = false;
        entries = [
          _entry(1, kind: 'marker', author: 'system', text: 'Your message is with the Grove team.'),
          if (sent['text'] case final String text) _entry(2, text: text, client: sent['client_msg_id'] as String),
        ];
      }
      return json({'thread_id': _thread, 'conversation_id': 'c1', 'state': state, 'entries': entries});
    }
    if (path == '/v1/support/current') {
      if (noThread) return http.StreamedResponse(const Stream.empty(), 204);
      final after = int.tryParse(request.url.queryParameters['after'] ?? '') ?? 0;
      return json({'thread_id': currentId, 'conversation_id': 'c1', 'state': state, 'entries': [for (final e in entries) if ((e['seq'] as int) > after) e]});
    }
    if (path == '/v1/support/unread') {
      if (unreadStatus.isNotEmpty) return json({'error': {'code': 'internal'}}, unreadStatus.removeAt(0));
      return json({'unread': 2, 'open': state['state'] != 'resolved', 'thread_id': currentId, 'lookups': lookups});
    }
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
        // Open again, as the server opens it: no longer closed by Support's switch.
        past[id] = (state: {...known.state, 'state': 'open', 'mode': 'human'}..remove('closed_reason'), entries: [...known.entries, reopened, line]);
        return json({'entry': line, 'reopened': reopened});
      }
      if (holdForContact) return json({'error': {'code': 'contact_required'}}, 409);
      final status = messageStatus.isEmpty ? 200 : messageStatus.removeAt(0);
      if (status != 200) return json({'error': {'code': 'internal'}}, status);
      final entry = _entry(entries.length + 1, text: sent!['text'] as String, client: sent['client_msg_id'] as String);
      entries = [...entries, entry];
      return json({'entry': entry});
    }
    if (path.contains('/cards/')) {
      if (openCard case final status?) return json({'error': {'code': 'not_cardable'}}, status);
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
    if (path.endsWith('/continue')) return json(continueAnswer, continueStatus);
    if (path.endsWith('/run') && runStatus.isNotEmpty) return json({'error': {'code': 'internal'}}, runStatus.removeAt(0));
    if (path.endsWith('/confirm')) {
      confirms.add((headers: request.headers, body: sent));
      if (confirmAnswers.isNotEmpty) {
        final (status, answer) = confirmAnswers.removeAt(0);
        return json(answer, status);
      }
      return json({'status': 'confirmed'});
    }
    if (path.endsWith('/contact/resend')) {
      final status = resendStatus.isEmpty ? 200 : resendStatus.removeAt(0);
      if (status != 200) return json({'error': {'code': status == 429 ? 'too_soon' : 'internal'}}, status);
      return json({'emailed': true});
    }
    if (path.endsWith('/contact')) {
      if (contactRefused case final code?) return json({'error': {'code': code}}, 409);
      state = _state(contact: {'state': 'stated', 'required': false});
      return json({'state': 'stated', 'emailed': emailed});
    }
    // A slip is no history: the phone has no current conversation after it (qa3-sdk-03).
    if (path.endsWith('/resolve') && sent?['by_mistake'] == true) noThread = true;
    return http.StreamedResponse(const Stream.empty(), 204);
  });

  RendelApiClient api({Future<String?> Function()? token}) => RendelApiClient(appKey: 'nc_pk_test_x', deviceId: 'device-1', config: RendelConfig(userToken: token), httpClient: client);

  RendelSupport support({Map<String, String>? user, Future<String?> Function()? token}) => RendelSupport(api(token: token), user: () => user, locale: () => 'en');
}

Widget _app(Widget child) => MaterialApp(
      home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: child)),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _open(WidgetTester tester, RendelSupport support, {List<UIAction>? actions, bool supportOn = true, bool sandbox = false}) async {
  await tester.pumpWidget(_app(Builder(
    builder: (context) => TextButton(
      onPressed: () => showRendelSupport(
        context,
        support: support,
        team: 'Grove',
        onAction: (action) async {
          actions?.add(action);
          return true;
        },
        canHandle: (_) => true,
        supportOn: () => supportOn,
        sandbox: sandbox,
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

    testWidgets('names the day where the conversation runs into another one, as the web SDK does, and none within one day', (tester) async {
      final server = _Server(
        entries: [
          _entry(1, text: "I'd like to talk to a person"),
          {..._entry(2, text: 'Is anyone there?'), 'created_at': '2026-11-07T10:00:00Z'},
        ],
        state: _state(mode: 'human'),
      );
      await _open(tester, server.support());
      final context = tester.element(find.text('Is anyone there?'));
      final words = MaterialLocalizations.of(context);
      final later = words.formatMediumDate(DateTime.parse('2026-11-07T10:00:00Z').toLocal());
      // The second day once, between the two lines; the day the conversation began is not named.
      expect(find.text(later), findsOneWidget);
      expect(tester.getTopLeft(find.text(later)).dy, greaterThan(tester.getTopLeft(find.text("I'd like to talk to a person")).dy));
      expect(tester.getTopLeft(find.text(later)).dy, lessThan(tester.getTopLeft(find.text('Is anyone there?')).dy));
      expect(find.text(words.formatMediumDate(DateTime.parse('2026-11-01T10:00:00Z').toLocal())), findsNothing);
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

    testWidgets('asks how it went once the team closed it: a thumb, a comment, then thanks', (tester) async {
      final server = _Server(
        entries: [_entry(1, author: 'agent', name: 'Ayşe', text: 'Çözüldü.')],
        state: {
          ..._state(mode: 'closed'),
          'state': 'resolved',
          'rating': {
            'question': 'How did it go?',
            'up': 'It went well',
            'down': 'It did not',
            'comment_hint': 'Anything else?',
            'send': 'Send it',
            'skip': 'Not now',
            'thanks': 'Thanks for telling us.',
          },
        },
      );
      await _open(tester, server.support());
      expect(find.text('How did it go?'), findsOneWidget);
      await tester.tap(find.text('It went well'));
      await tester.pumpAndSettle();
      expect(server.posts.singleWhere((p) => p.path == 'rating').body, {'rating': 'up'});
      // The server stops asking at the thumb; the comment is still this page's.
      server.state = {...server.state}..remove('rating');
      await tester.enterText(find.byType(TextField).first, 'Quick');
      await tester.tap(find.text('Send it'));
      await tester.pumpAndSettle();
      expect(server.posts.where((p) => p.path == 'rating').last.body, {'comment': 'Quick'});
      expect(find.text('Thanks for telling us.'), findsOneWidget);
    });

    testWidgets('an unasked thread shows no card', (tester) async {
      final server = _Server(entries: [_entry(1, author: 'agent', name: 'Ayşe', text: 'Çözüldü.')], state: {..._state(mode: 'closed'), 'state': 'resolved'});
      await _open(tester, server.support());
      expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
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

    testWidgets("says New above the team's reply on a second opening, from what the server says then (sdk-08)", (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Can I swap the Aero Glide for a 44?'), _entry(2, author: 'agent', name: 'Dana', text: 'Let me check.')],
        state: {..._state(mode: 'human'), 'user_read_seq': 2, 'last_seq': 2},
      );
      final support = server.support();
      await _open(tester, support);
      expect(find.textContaining('New · '), findsNothing);
      await _close(tester);
      // While the page is closed, the team replies.
      server.entries = [...server.entries, _entry(3, author: 'agent', name: 'Dana', text: 'The 44 is in stock.')];
      server.state = {...server.state, 'last_seq': 3};
      await _open(tester, support);
      expect(find.textContaining('New · '), findsOneWidget);
      expect(tester.getTopLeft(find.textContaining('New · ')).dy, lessThan(tester.getTopLeft(find.text('The 44 is in stock.')).dy));
      await _close(tester);
    });

    test('reads a new thread after a sorted one from its first line, and a turn to another thread starts from nothing (sdk-02)', () async {
      const other = '00000000-0000-4000-8000-0000000000b2';
      final server = _Server(
        entries: [_entry(1, text: 'Old question'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Old answer'), _entry(3, kind: 'marker', author: 'system', text: 'Sorted.')],
        state: {..._state(mode: 'closed'), 'state': 'resolved', 'last_seq': 3},
      );
      final support = server.support();
      await support.load();
      support.handedTo(_thread);
      expect(support.value.value.entries, hasLength(3));
      server
        ..currentId = other
        ..entries = [_entry(1, kind: 'marker', author: 'system', text: 'Your message is with the Grove team.'), _entry(2, text: 'A new question')]
        ..state = {..._state(), 'thread_id': other};
      await support.load();
      expect(support.value.value.threadId, other);
      expect([for (final e in support.value.value.entries) e.seq], [1, 2]);
      support.handedTo('00000000-0000-4000-8000-0000000000c3');
      expect(support.value.value.threadId, isNull);
      expect(support.value.value.entries, isEmpty);
    });

    testWidgets('drops the open conversation as soon as the team sorts it while the person watches (sdk-14)', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state(mode: 'human'));
      final support = server.support();
      await tester.runAsync(support.refreshUnread);
      expect(support.open, isTrue);
      await _open(tester, support);
      server.say({'type': 'support.state', 'state': {..._state(mode: 'closed'), 'state': 'resolved'}});
      await _settle(tester);
      expect(support.open, isFalse);
      await _close(tester);
    });

    // The reply as a line at the top of an answer has its own test (sdk-09); this one only ever held the waiting row (sdk-26).
    testWidgets('says the row is waiting while the team is away, with a clock', (tester) async {
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

    testWidgets("shows the team's reply as a line at the top of one of Rendel's answers, and opens their page from it (sdk-09)", (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Can I swap the Aero Glide for a 44?'), _entry(2, author: 'agent', name: 'Dana', text: 'The 44 is in stock.')],
        state: _state(mode: 'human'),
      );
      final support = server.support();
      final controller = ConversationController(api: server.api(), actions: const {}, sdkVersion: 'flutter/test', onOpenUrl: (_) async => true);
      addTearDown(controller.dispose);
      controller.loadHistory('c1', [
        {'id': 'm1', 'role': 'user', 'blocks': [{'id': 'b1', 'type': 'text', 'fallback_text': 'Which sizes?', 'props': {'markdown': 'Which sizes?'}}]},
        {'id': 'm2', 'role': 'assistant', 'blocks': [{'id': 'b2', 'type': 'text', 'fallback_text': 'From 38 to 46.', 'props': {'markdown': 'From 38 to 46.'}}]},
      ]);
      await tester.runAsync(() async {
        await support.load();
        await support.refreshUnread();
      });
      var opened = 0;
      await tester.pumpWidget(_app(ThreadScreen(controller: controller, support: support, supportTeam: 'Grove', onSupportOpen: () => opened++)));
      await tester.pump();
      expect(controller.page, 0);
      expect(find.textContaining('Dana replied'), findsOneWidget);
      // The full row is the opening's; on a page only the reply shows.
      expect(find.text('Grove team'), findsNothing);
      await tester.tap(find.textContaining('Dana replied'));
      expect(opened, 1);
    });

    // sdk-17: at 320x568 with text at 2.0 and the keyboard up, the head, chip and box ran 83px off the bottom;
    // at 375 with text at 2.0 the New line ran 27px off the side.
    for (final (size, keyboard) in [(const Size(320, 568), 260.0), (const Size(375, 812), 0.0)]) {
      testWidgets('draws nothing off the page with text at 2.0, ${size.width.toInt()} wide${keyboard > 0 ? ' with the keyboard up' : ''}', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
        addTearDown(tester.view.reset);
        final server = _Server(
          entries: [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Hemen bakıyorum, sipariş numaranız nedir?')],
          state: {..._state(mode: 'human'), 'user_read_seq': 1},
        );
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showRendelSupport(context, support: server.support(), team: 'Grove', onAction: (_) async => true, canHandle: (_) => true, strings: RendelStrings.forLocale('tr')),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        // With the keyboard up the short list may hold only the newest lines.
        if (keyboard == 0) expect(find.textContaining('Yeni · '), findsOneWidget);
      });
    }

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

    testWidgets('puts the optional email card away with its ✕, for this conversation, and keeps it away on the next open (Tuna, 2026-11-04)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final server = _Server(
        entries: [_entry(1, kind: 'marker', author: 'system', text: 'Your message is with the Grove team.'), _entry(2, text: 'Kargom gelmedi')],
        state: _state(contact: {'state': 'none', 'required': false, 'offer': true}),
      );
      await _open(tester, server.support());
      expect(find.text('Want the reply by email too?'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('No thanks'));
      await _settle(tester);
      expect(find.text('Want the reply by email too?'), findsNothing);
      // The place to write stays.
      expect(find.widgetWithText(TextField, 'Message the Grove team'), findsOneWidget);
      await _close(tester);
      // Opened again, on a session that reads it from the phone.
      await _open(tester, server.support());
      await _settle(tester);
      expect(find.text('Want the reply by email too?'), findsNothing);
      await _close(tester);
      // A timer the pages set is still running: it goes off before the test ends.
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets("offers no optional email card where the app doesn't email people, or the server doesn't say (§4 Q24)", (tester) async {
      SharedPreferences.setMockInitialValues({});
      for (final contact in [
        {'state': 'none', 'required': false, 'offer': false},
        {'state': 'none', 'required': false},
      ]) {
        final server = _Server(
          entries: [_entry(1, kind: 'marker', author: 'system', text: 'Your message is with the Grove team.'), _entry(2, text: 'Kargom gelmedi')],
          state: _state(contact: contact),
        );
        await _open(tester, server.support());
        expect(find.text('Want the reply by email too?'), findsNothing);
        expect(find.widgetWithText(TextField, 'Message the Grove team'), findsOneWidget);
        await _close(tester);
      }
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('keeps the required email card, with no way to put it away', (tester) async {
      final server = _Server(
        entries: [_entry(1, kind: 'marker', author: 'system', text: 'Your message is with the Grove team.'), _entry(2, text: 'Kargom gelmedi')],
        state: _state(contact: {'state': 'none', 'required': true}),
      );
      await _open(tester, server.support());
      expect(find.text('Where should we send the reply? Add your email to keep going.'), findsOneWidget);
      expect(find.bySemanticsLabel('No thanks'), findsNothing);
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

    testWidgets('asks for no code on a test key, where no email goes: says the address is saved, and lets it be changed', (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Kargom gelmedi')],
        state: _state(contact: {'state': 'stated', 'required': false}),
      );
      await _open(tester, server.support(), sandbox: true);
      expect(find.text('Address saved. This is a test key, so no email is sent and there is no code to enter.'), findsOneWidget);
      // No code box, and no code to ask for again: the only field is the one to write to the team in.
      expect(find.text('Got a code by email? Enter it here'), findsNothing);
      expect(find.text('Send the code again'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('Change the address'));
      await _settle(tester);
      expect(find.widgetWithText(TextField, 'you@example.com'), findsOneWidget);
      expect(find.text('Address saved. This is a test key, so no email is sent and there is no code to enter.'), findsNothing);
      // The new address is saved, and still nothing asks for a code or says one could not go.
      await tester.enterText(find.byType(TextField).first, 'yeni@example.com');
      server.emailed = false;
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'contact').body, {'email': 'yeni@example.com'});
      expect(find.text('Address saved. This is a test key, so no email is sent and there is no code to enter.'), findsOneWidget);
      expect(find.text("We can't send a code right now. Try again in an hour."), findsNothing);
      await _close(tester);
    });

    testWidgets('sends the code again from under the code box, and says when it cannot yet', (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Kargom gelmedi')],
        state: _state(contact: {'state': 'stated', 'required': false}),
      );
      await _open(tester, server.support());
      expect(find.text('Got a code by email? Enter it here'), findsOneWidget);
      expect(find.text('Send the code again'), findsOneWidget);
      expect(find.text('Change the address'), findsOneWidget);
      await tester.tap(find.text('Send the code again'));
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'contact/resend').body, <String, dynamic>{});
      expect(find.text('A new code is on its way. The earlier one no longer works.'), findsOneWidget);
      server.resendStatus.add(429);
      await tester.tap(find.text('Send the code again'));
      await _settle(tester);
      expect(server.posts.where((p) => p.path == 'contact/resend'), hasLength(2));
      expect(find.text('A new code is on its way. The earlier one no longer works.'), findsNothing);
      expect(find.text("We can't send a code right now. Try again in an hour."), findsOneWidget);
      await _close(tester);
    });

    testWidgets('takes another address in place of the code box, goes back to the code, and says when it cannot change again', (tester) async {
      final server = _Server(
        entries: [_entry(1, text: 'Kargom gelmedi')],
        state: _state(contact: {'state': 'stated', 'required': false}),
      );
      await _open(tester, server.support());
      await tester.tap(find.text('Change the address'));
      await _settle(tester);
      // The email card stands in for the code box, under the link's own words; its ✕ is the way back, and puts nothing away.
      expect(find.text('Change the address'), findsOneWidget);
      expect(find.text('Got a code by email? Enter it here'), findsNothing);
      expect(find.bySemanticsLabel('No thanks'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Go back'));
      await _settle(tester);
      expect(find.text('Got a code by email? Enter it here'), findsOneWidget);
      expect(server.posts.where((p) => p.path.startsWith('contact')), isEmpty);
      await tester.tap(find.text('Change the address'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'zeynep.yeni@example.com');
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'contact').body, {'email': 'zeynep.yeni@example.com'});
      // An email went: the code box is back, saying so.
      expect(find.text('Got a code by email? Enter it here'), findsOneWidget);
      expect(find.text('Thanks. Check your inbox to confirm the address.'), findsOneWidget);
      // Saved with no email sent (too many codes this hour): the code box says a code cannot go now, never "check your inbox".
      server.emailed = false;
      await tester.tap(find.text('Change the address'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'zeynep.baska@example.com');
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text('Thanks. Check your inbox to confirm the address.'), findsNothing);
      expect(find.text("We can't send a code right now. Try again in an hour."), findsOneWidget);
      // Changed as often as a conversation allows: said under the field, which stays.
      server.contactRefused = 'too_many_changes';
      await tester.tap(find.text('Change the address'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'zeynep.son@example.com');
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text("The address can't be changed again in this conversation."), findsOneWidget);
      expect(find.widgetWithText(TextField, 'zeynep.son@example.com'), findsOneWidget);
      // The page's own ✕, above the card's.
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await _settle(tester);
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
      // Answered, it says so, and asks nothing more.
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      await _close(tester);
    });

    testWidgets('reads a card whose run failed as not gone through on every later load, never as confirmed (qa3-sdk-01)', (tester) async {
      // As the server sends it once the invocation failed: `_resolved` in its props for Flutter, `resolved` for Web.
      final server = _Server(
        entries: [
          _entry(1, text: 'Kargom gelmedi'),
          _entry(2, author: 'agent', name: 'Ayşe', blocks: [
            {
              'id': 'card-1',
              'type': 'confirm_card',
              'fallback_text': 'Clip the coupon SPRING5',
              'resolved': 'failed',
              'props': {'invocation_id': _invocation, 'action_name': 'clip_coupon', 'summary': 'Clip the coupon SPRING5', 'params_display': <Object>[], '_resolved': 'failed'},
            },
          ]),
        ],
        state: _state(mode: 'human'),
      );
      await _open(tester, server.support());
      await _settle(tester);
      expect(find.text(const RendelStrings().cardFailed), findsOneWidget);
      expect(find.text('Confirmed'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
      await _close(tester);
    });

    testWidgets("tells the server a slip with By mistake, and nothing more with I'm sorted (qa3-sdk-06)", (tester) async {
      final slip = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state());
      await _open(tester, slip.support());
      await tester.tap(find.textContaining('By mistake'));
      await _settle(tester);
      expect(slip.posts.singleWhere((p) => p.path == 'resolve').body, {'by_mistake': true});
      final sorted = _Server(entries: [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Bakıyorum.')], state: _state(mode: 'human'));
      await _open(tester, sorted.support());
      await tester.tap(find.text("I'm sorted"));
      await _settle(tester);
      expect(sorted.posts.singleWhere((p) => p.path == 'resolve').body, isEmpty);
    });

    testWidgets('forgets a conversation put away By mistake: Contact us opens an empty page, and the next line starts a new one (qa4-sdk-02)', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state());
      final support = server.support();
      await _open(tester, support);
      await tester.tap(find.textContaining('By mistake'));
      await _settle(tester);
      expect(find.byType(RendelSupportSheet), findsNothing);
      expect(support.open, isFalse);
      // Contact us, in the same app life.
      support.begin('open_support');
      await _open(tester, support);
      expect(find.text('Kargom gelmedi'), findsNothing);
      expect(find.text('Write to open it again'), findsNothing);
      await tester.enterText(find.byType(TextField).last, 'Bir sorum daha var');
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await _settle(tester);
      expect([for (final h in server.handoffs) h['text']], ['Bir sorum daha var']);
      expect(server.posts.where((p) => p.path == 'messages'), isEmpty);
      await _close(tester);
    });

    test('says a read once, even when a state read before the server had it comes back (qa4-sdk-04)', () async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Bakıyorum.')], state: _state(mode: 'human'));
      final support = server.support();
      await support.load();
      support.read();
      // The stream's or a reload's state, from before the server had the read.
      await support.load();
      support.read();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect([for (final p in server.posts) if (p.path == 'read') p.body], [
        {'seq': 2},
      ]);
    });

    testWidgets('closes with nothing of the last person on it when they sign out with the page up (qa3-sdk-02)', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Bakıyorum.')], state: _state(mode: 'human'));
      final support = server.support();
      await _open(tester, support);
      expect(find.text('Bakıyorum.'), findsOneWidget);
      support.reset();
      await _settle(tester);
      expect(find.byType(RendelSupportSheet), findsNothing);
      expect(find.text('Bakıyorum.'), findsNothing);
      // A read asked for before the sign-out, answered after it, is the last person's: it is not taken.
      server.entries = [_entry(1, text: 'Someone else')];
      final stale = support.load();
      support.reset();
      expect(await tester.runAsync(() => stale), isFalse);
      expect(support.value.value.threadId, isNull);
    });

    testWidgets('draws a card the server will not open here as not answered, never loading, and asks once (Tuna, 2026-11-04)', (tester) async {
      final server = _Server(
        entries: [
          _entry(1, text: 'I want to talk to a person'),
          _entry(2, author: 'agent', name: 'Dana', blocks: [
            {
              'id': 'card-1',
              'type': 'confirm_card',
              'fallback_text': 'Apply the code SOCKS to your bag?',
              'props': {'invocation_id': '', 'action_name': 'apply_coupon', 'summary': 'Apply the code SOCKS to your bag?', 'params': {'code': 'SOCKS'}, 'params_display': <Object>[]},
            },
          ]),
        ],
        state: _state(mode: 'human'),
      )..openCard = 409;
      await _open(tester, server.support());
      await _settle(tester);
      await _settle(tester);
      expect(find.text('Apply the code SOCKS to your bag?'), findsWidgets);
      expect(find.text('Not answered'), findsOneWidget);
      expect(find.text('Loading'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
      expect(server.posts.where((p) => p.path.startsWith('cards/')).length, 1);
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
      // In plain words: a yes and a no to the read, never "Confirm" and "Go back" (sdk-20, check-11).
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Go back'), findsNothing);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(server.posts.singleWhere((p) => p.path == 'lookups/L2/run').body, {'allow': false});
      expect(find.text('Ayşe would like to check your account.'), findsNothing);
      await _close(tester);
    });

    testWidgets("keeps the team's question when the answer does not go, says so, and sends it again (sdk-20)", (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state(mode: 'human'))..runStatus.add(503);
      await _open(tester, server.support());
      server.say({'type': 'support.lookup', 'lookup_id': 'L2', 'action': 'Ayşe would like to check your orders.', 'ask': true});
      await _settle(tester);
      await tester.tap(find.text('Allow'));
      await _settle(tester);
      expect(find.text('Ayşe would like to check your orders.'), findsOneWidget);
      expect(find.text("Your answer didn't reach the team. Try again."), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await _settle(tester);
      expect(server.posts.where((p) => p.path == 'lookups/L2/run'), hasLength(2));
      expect(find.text('Ayşe would like to check your orders.'), findsNothing);
      await _close(tester);
    });

    test('never says confirmed for a card whose write then failed, and keeps one with no answer open (sdk-21)', () async {
      // A write that ran and failed is the server's answer; no answer at all asks to be tried again (qa2-sdk-03).
      for (final (answer, status, resolved, said) in [
        (const <String, Object>{'status': 'failed'}, 200, 'failed', 'failed'),
        (const <String, Object>{'error': 'down'}, 503, null, 'unanswered'),
      ]) {
        final server = _Server(entries: [
          _entry(1, author: 'agent', name: 'Ayşe', blocks: [
            {'id': 'card-1', 'type': 'confirm_card', 'fallback_text': 'Send order M-2020 again', 'props': {'invocation_id': '', 'summary': 'Send order M-2020 again', 'params_display': <Object>[]}},
          ]),
        ], state: _state(mode: 'human'))
          ..continueAnswer = answer
          ..continueStatus = status;
        final support = server.support();
        await support.load();
        await support.openCard(support.value.value.entries.single.id);
        expect(await support.decideCard(_invocation, confirm: true), said);
        final props = support.value.value.entries.single.blocks.single['props'] as Map;
        expect(props['_resolved'], resolved);
      }
    });

    testWidgets('puts a line the API refuses as too long back in the box, with why (sdk-19)', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state(mode: 'human'))..messageStatus.add(400);
      final support = server.support();
      await _open(tester, support);
      await tester.enterText(find.byType(TextField).last, 'x' * 50);
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await _settle(tester);
      expect(find.text('x' * 50), findsOneWidget);
      expect(find.text("That's too long to send. Shorten it and try again."), findsOneWidget);
      expect(support.value.value.pending, isEmpty);
      // Near the limit, how much is used.
      await tester.enterText(find.byType(TextField).last, 'y' * 3812);
      await tester.pump();
      expect(find.text('3,812 / 4,000'), findsOneWidget);
      await _close(tester);
    });

    test("counts the team's unread lines", () async {
      final support = _Server(entries: const []).support();
      expect(await support.refreshUnread(), 2);
      expect(support.value.value.unread, 2);
    });

    test('keeps the count and the open conversation when one read of it fails (sdk-13)', () async {
      final server = _Server(entries: const []);
      final support = server.support();
      await support.refreshUnread();
      server.unreadStatus.addAll([503, 429]);
      expect(await support.refreshUnread(), 2);
      expect(await support.refreshUnread(here: true), 2);
      expect(support.value.value.unread, 2);
      expect(support.open, isTrue);
    });
  });

  // C6 (check-01): the reads the team asked for come with the count too, so they reach an app that is open while the
  // conversation is not on screen; each is taken up once, whichever way it came.
  group("the team's reads, outside the conversation's page", () {
    const lookup = '00000000-0000-4000-8000-0000000000c1';
    Map<String, dynamic> offer({bool ask = false, String id = lookup, String action = 'Ayşe is checking your account.', DateTime? expires}) =>
        {'type': 'support.lookup', 'lookup_id': id, 'action': action, 'ask': ask, if (expires != null) 'expires_at': expires.toUtc().toIso8601String()};

    testWidgets('runs a read the count brings while the page is closed, once, though the stream offers it again', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state(mode: 'human'))..lookups = [offer()];
      final support = server.support();
      await tester.runAsync(() async {
        await support.refreshUnread(here: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await support.refreshUnread(here: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(server.posts.where((p) => p.path == 'lookups/$lookup/run').map((p) => p.body), [
        {'allow': true},
      ]);
      await _open(tester, support);
      server.say(offer());
      await _settle(tester);
      expect(server.posts.where((p) => p.path == 'lookups/$lookup/run'), hasLength(1));
      await _close(tester);
    });

    test('offers a read again once its answer did not reach the server', () async {
      final server = _Server(entries: const [])
        ..lookups = [offer()]
        ..runStatus.add(503);
      final support = server.support();
      for (var i = 0; i < 3; i++) {
        await support.refreshUnread();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(server.posts.where((p) => p.path == 'lookups/$lookup/run'), hasLength(2));
    });

    testWidgets('puts a question the count brings on the page, and takes it off when it runs out (check-11)', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state(mode: 'human'))
        ..lookups = [offer(ask: true, action: 'Ayşe would like to check your account.', expires: DateTime.now().add(const Duration(seconds: 3)))];
      final support = server.support();
      await tester.runAsync(() => support.refreshUnread(here: true));
      await _open(tester, support);
      expect(find.text('Ayşe would like to check your account.'), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3200)));
      await _settle(tester);
      expect(find.text('Ayşe would like to check your account.'), findsNothing);
      // Offered again by a count that is behind: it ran out, and stays off.
      await tester.runAsync(() => support.refreshUnread(here: true));
      await _settle(tester);
      expect(support.value.value.asks, isEmpty);
      await _close(tester);
    });

    test('never takes a question that already ran out, and keeps one asked in another thread off this page', () async {
      final server = _Server(entries: const [])
        ..currentId = _past
        ..lookups = [
          offer(ask: true, id: '00000000-0000-4000-8000-0000000000c2', action: 'Ayşe would like to check your orders.', expires: DateTime.now().subtract(const Duration(seconds: 1))),
          offer(ask: true, action: 'Ayşe would like to check your account.'),
        ];
      final support = server.support();
      await support.refreshUnread();
      expect(support.value.value.asks.map((a) => a.text), ['Ayşe would like to check your account.']);
      expect(support.value.value.asks.single.threadId, _past);
      await support.show(_thread);
      expect(support.value.value.asksHere, isEmpty);
    });

    test('says on the count and the stream whether the person is signed in, only when the app gave a token (add-10)', () async {
      String? token = 'tok';
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')]);
      final signedIn = server.support(token: () async => token);
      await signedIn.refreshUnread(here: true);
      token = null;
      await signedIn.refreshUnread();
      await server.support().refreshUnread(here: true);
      final api = server.api(token: () async => 'tok');
      await api.supportStream(_thread, 3).first.timeout(const Duration(milliseconds: 50), onTimeout: () => const {});
      expect(server.queries, ['unread?here=1&signed_in=1', 'unread?signed_in=0', 'unread?here=1', 'stream?after=3&signed_in=1']);
    });
  });

  // K1 (Tuna, 2026-11-17): switching Support off closes the conversation with a line, and the person gets the app's
  // own channels to tap instead of a box to write in.
  group('a conversation closed because the app switched Support off', () {
    const closing = 'Messages here no longer reach the Grove team, so this conversation is closed. You can reach them at Customer service (+90 212 555 0101).';
    Map<String, dynamic> closedState() => {
          ..._state(mode: 'closed', contact: const {'state': 'none', 'required': true, 'offer': true, 'blocking': true}),
          'state': 'resolved',
          'closed_reason': 'support_off',
          'contact_channels': [
            {'kind': 'call', 'label': 'Customer service', 'value': '+90 212 555 0101'},
            {'kind': 'url', 'label': 'Help centre', 'value': 'https://grove.example/help'},
          ],
        };
    _Server closed() => _Server(
          entries: [_entry(1, text: 'Kargom gelmedi'), {..._entry(2, kind: 'marker', author: 'system', text: closing), 'marker': 'support_off'}],
          state: closedState(),
        );

    testWidgets("says the closing line, offers the app's own channels to tap, and has no box to write in, while Support is off", (tester) async {
      final actions = <UIAction>[];
      final server = closed();
      await _open(tester, server.support(), actions: actions, supportOn: false);
      expect(find.textContaining(closing), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Reach the Grove team'), findsOneWidget);
      // The contact block is its own plate, never inside a second card (qa2-k1-01): nothing wraps it but the column.
      final reach = find.byKey(const ValueKey('rd-support-reach'));
      expect(reach, findsOneWidget);
      expect(find.ancestor(of: reach, matching: find.byWidgetPredicate((w) => w is Container && w.decoration != null)), findsNothing);
      // Nothing written here would reach the team: no box, no "Write to open it again", no email card, nothing to sort.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Write to open it again'), findsNothing);
      expect(find.textContaining('By mistake'), findsNothing);
      // Nobody on the team writes in it: its stream is not asked for, again and again (qa2-k1-04).
      expect(server.queries.where((q) => q.startsWith('stream')), isEmpty);
      // Each button says what it is and where it goes, as the assistant's contact card does, never the app's label (qa3-k1-02).
      expect(find.text('Call +90 212 555 0101'), findsOneWidget);
      expect(find.text('Customer service +90 212 555 0101'), findsNothing);
      expect(find.text('Help centre'), findsOneWidget);
      await tester.ensureVisible(find.text('Call +90 212 555 0101'));
      await tester.tap(find.text('Call +90 212 555 0101'));
      await _settle(tester);
      expect(actions.whereType<CallAction>().single.phone, '+90 212 555 0101');
      await _close(tester);
    });

    testWidgets('reads like any sorted one once Support is on again: no channels, and writing in it opens it again and follows it (D4, qa2-k1-05)', (tester) async {
      final server = closed();
      server.past[_thread] = (state: server.state, entries: server.entries);
      final support = server.support();
      await tester.runAsync(() => support.show(_thread));
      await _open(tester, support);
      expect(find.text('Reach the Grove team'), findsNothing);
      expect(find.widgetWithText(TextField, 'Write to open it again'), findsOneWidget);
      expect(server.queries.where((q) => q.startsWith('stream')), isEmpty);
      await tester.enterText(find.byType(TextField).last, 'Still waiting for my parcel');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      await _settle(tester);
      expect(server.posts.where((p) => p.path.endsWith('messages')), hasLength(1));
      expect(find.text('Closed'), findsNothing);
      await _settle(tester);
      expect(server.queries.where((q) => q.startsWith('stream')), isNotEmpty);
      await _close(tester);
    });

    testWidgets('names it closed, never sorted, in Recent', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: {..._state(), 'state': 'resolved'});
      server.threads = [
        {'thread_id': _thread, 'state': 'resolved', 'title': 'Kargom gelmedi', 'unread': 0, 'last_message_at': DateTime.now().toUtc().toIso8601String(), 'closed_reason': 'support_off'},
      ];
      final controller = ConversationController(api: server.api(), actions: const {}, sdkVersion: 'flutter/test', onOpenUrl: (_) async => true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(ThreadScreen(controller: controller, support: server.support(), supportTeam: 'Grove', onSupportThread: (_) {})));
      await _settle(tester);
      await _settle(tester);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.textContaining('Sorted'), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    test('starts a new conversation from Contact us once Support is on again, never back in the closed one', () async {
      final support = closed().support();
      await support.load();
      expect(support.value.value.threadId, _thread);
      support.begin('open_support');
      expect(support.value.value.threadId, isNull);
      expect(await support.load(), isFalse);
      expect(support.value.value.threadId, isNull);
    });
  });

  // K2 (Tuna, 2026-11-17): while the team is live for the person, the email card is a request above the box.
  group('the email card while the team is live for the person', () {
    final asked = [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Sipariş numaranız?')];
    const request = 'Add your email so the reply reaches you after you leave.';
    const required = 'Where should we send the reply? Add your email to keep going.';
    Map<String, dynamic> contact({required bool blocking}) => {'state': 'none', 'required': true, 'offer': true, 'blocking': blocking};

    testWidgets('keeps the box while the team is live, with the card above it as a request and no way to put it away', (tester) async {
      final server = _Server(entries: asked, state: _state(mode: 'human', contact: contact(blocking: false)));
      await _open(tester, server.support());
      expect(find.text(request), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Message the Grove team'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget); // the sheet's own close, and no ✕ on the card
      await _close(tester);
    });

    testWidgets('holds the box for the address once the team is not live, and gives it back when the stream says they are', (tester) async {
      final server = _Server(entries: asked, state: _state(mode: 'human', contact: contact(blocking: true)));
      await _open(tester, server.support());
      expect(find.text(required), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Message the Grove team'), findsNothing);
      server.say({'type': 'support.state', 'state': _state(mode: 'human', contact: contact(blocking: false))});
      await _settle(tester);
      expect(find.text(request), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Message the Grove team'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('lets a sorted conversation be written in again, and asks for the address only when the server holds the line (sdk-03)', (tester) async {
      final server = _Server(
        entries: [...asked, {..._entry(3, kind: 'marker', author: 'system', text: 'Sorted'), 'marker': 'resolved'}],
        state: {..._state(mode: 'closed', contact: contact(blocking: true)), 'state': 'resolved'},
      )..holdForContact = true;
      await _open(tester, server.support());
      expect(find.text(required), findsNothing);
      expect(find.widgetWithText(TextField, 'Write to open it again'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Bir sorum daha var');
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await _settle(tester);
      expect(find.text(required), findsOneWidget);
      await _close(tester);
    });
  });

  // C4 (apps-06): wherever the team's return is named, it is said on the person's own clock.
  group("when the team is back, on the person's own clock", () {
    String clock(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    String day(DateTime at) => 'day ${at.day}';

    test('says every line that names the time again on this phone, the day word included', () {
      // Exactly a day ahead, wherever the phone is: "tomorrow" on its calendar too.
      final now = DateTime.utc(2026, 11, 17, 12);
      const backAt = '2026-11-18T04:00:00-08:00';
      final mine = clock(DateTime.parse(backAt).toLocal());
      final said = rendelSupportBack(
        const RendelStrings(),
        presence: 'Back tomorrow at 04:00',
        waiting: 'Waiting for the team · back tomorrow at 04:00',
        expectation: "The team is back tomorrow at 04:00. We'll notify you when they reply.",
        backAt: backAt,
        time: clock,
        day: day,
        now: now,
      );
      expect(said.presence, 'Back tomorrow at $mine');
      expect(said.waiting, 'Waiting for the team · back tomorrow at $mine');
      expect(said.expectation, "The team is back tomorrow at $mine. We'll notify you when they reply.");
      expect(rendelSupportBack(RendelStrings.forLocale('tr'), presence: 'x', backAt: backAt, time: clock, day: day, now: now).presence, 'Dönüş: yarın saat $mine');
    });

    test("leaves the server's lines as they are with no time to show, or one already past", () {
      final said = rendelSupportBack(const RendelStrings(), presence: 'Away', waiting: 'Waiting', time: clock, day: day);
      expect(said, (presence: 'Away', waiting: 'Waiting', expectation: null));
      final past = rendelSupportBack(const RendelStrings(), presence: 'Back today at 09:00', backAt: '2026-01-01T09:00:00+03:00', time: clock, day: day);
      expect(past.presence, 'Back today at 09:00');
    });

    testWidgets("draws the page's head with it", (tester) async {
      final at = DateTime.now().toUtc().add(const Duration(hours: 3));
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: {..._state(), 'team_here': false, 'presence': 'Back today at 99:99', 'back_at': at.toIso8601String()});
      await _open(tester, server.support());
      expect(find.textContaining('99:99'), findsNothing);
      expect(find.textContaining(RegExp(r'^Back (today|tomorrow) at ')), findsOneWidget);
      await _close(tester);
    });
  });

  testWidgets('draws the same read said twice in a row once (check-08)', (tester) async {
    const said = 'Grove QA checked your account to help.';
    Map<String, dynamic> lookup(int seq) => {..._entry(seq, kind: 'marker', author: 'system', text: said), 'marker': 'lookup'};
    final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi'), lookup(2), lookup(3), _entry(4, author: 'agent', name: 'Ayşe', text: 'Gördüm.'), lookup(5)], state: _state(mode: 'human'));
    await _open(tester, server.support());
    expect(find.textContaining(said), findsNWidgets(2));
    await _close(tester);
  });

  // C8 (add-07, sdk-10): a card's yes says who the person is, with their token and what they typed; a server that
  // runs it at the tap answers how it went, and nothing is continued after it.
  group('a card the team sent, confirmed at the tap', () {
    List<Map<String, dynamic>> lines({Map<String, Object> props = const {}}) => [
          _entry(1, author: 'agent', name: 'Ayşe', blocks: [
            {'id': 'card-1', 'type': 'confirm_card', 'fallback_text': 'Apply the code SOCKS?', 'props': {'invocation_id': '', 'summary': 'Apply the code SOCKS?', 'params_display': <Object>[], ...props}},
          ]),
        ];

    test("sends the person and their token with a yes, and takes the server's word when it ran then and there", () async {
      for (final (said, resolved) in [('succeeded', 'confirmed'), ('failed', 'failed')]) {
        final server = _Server(entries: lines(), state: _state(mode: 'human'))..confirmAnswers.add((200, {'status': said}));
        final support = server.support(user: const {'id': 'u-7', 'hmac': 'h'}, token: () async => 'tok');
        await support.load();
        await support.openCard(support.value.value.entries.single.id);
        expect(await support.decideCard(_invocation, confirm: true), said);
        final sent = server.confirms.single;
        expect(sent.headers['x-rendel-user'] ?? sent.headers['X-Rendel-User'], 'u-7');
        expect(sent.headers['x-rendel-user-hmac'] ?? sent.headers['X-Rendel-User-Hmac'], 'h');
        expect(sent.headers['x-rendel-user-token'] ?? sent.headers['X-Rendel-User-Token'], 'tok');
        expect(server.posts.any((p) => p.path == 'continue'), isFalse);
        expect((support.value.value.entries.single.blocks.single['props'] as Map)['_resolved'], resolved);
      }
    });

    test('sends what the person typed, and keeps the card open with why when it does not match (sdk-10)', () async {
      final server = _Server(entries: lines(props: {'type_to_confirm': {'param': 'code', 'value': 'SOCKS'}}), state: _state(mode: 'human'))
        ..confirmAnswers.add((422, {'error': {'code': 'typed_mismatch'}}));
      final support = server.support();
      await support.load();
      await support.openCard(support.value.value.entries.single.id);
      expect(await support.decideCard(_invocation, confirm: true, typed: 'SOCK'), 'typed_mismatch');
      expect(server.confirms.single.body, {'decision': 'confirm', 'typed': 'SOCK'});
      final props = support.value.value.entries.single.blocks.single['props'] as Map;
      expect(props['_mismatch'], isTrue);
      expect(props['_resolved'], isNull);
    });
  });

  // K3 (Tuna, 2026-11-17): the team's page opens at once, and the thread is made by the person's first line.
  group('the support page with no thread yet', () {
    testWidgets('asks the team for nothing until the person writes; the first line opens the thread with its words', (tester) async {
      final server = _Server(entries: const [])..noThread = true;
      final support = server.support()..begin('open_support');
      await _open(tester, support);
      expect(server.handoffs, isEmpty);
      expect(find.text('Grove team'), findsOneWidget);
      // Nothing is known of the team yet, and there is nothing to sort or take back.
      expect(find.text('Away'), findsNothing);
      expect(find.textContaining('By mistake'), findsNothing);
      await tester.enterText(find.byType(TextField).last, 'My order 1042 never came');
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await _settle(tester);
      expect(server.handoffs, hasLength(1));
      expect(server.handoffs.single, containsPair('trigger', 'open_support'));
      expect(server.handoffs.single, containsPair('text', 'My order 1042 never came'));
      expect(server.handoffs.single.containsKey('conversation_id'), isFalse);
      expect(support.value.value.threadId, _thread);
      expect(support.value.value.pending, isEmpty);
      expect(find.text('My order 1042 never came'), findsOneWidget);
      expect(find.text('Here'), findsOneWidget);
      await _close(tester);
    });

    test('opens the thread from an answer rated down with its conversation, and sends a failed first line again under the same id', () async {
      final server = _Server(entries: const [])
        ..noThread = true
        ..handoffStatus.add(503);
      final support = server.support()..begin('offer', conversationId: 'c-rated');
      expect(await support.send('That answer was wrong'), 'failed');
      expect(support.value.value.pending.single.failed, isTrue);
      await support.retry(support.value.value.pending.single.clientMsgId);
      expect(server.handoffs, hasLength(2));
      expect(server.handoffs.last, containsPair('trigger', 'offer'));
      expect(server.handoffs.last, containsPair('conversation_id', 'c-rated'));
      expect(server.handoffs.last['client_msg_id'], server.handoffs.first['client_msg_id']);
      expect(support.value.value.pending, isEmpty);
      expect(support.value.value.entries.any((e) => e.text == 'That answer was wrong'), isTrue);
      expect(server.posts.where((p) => p.path.endsWith('messages')), isEmpty);
    });

    test('writes in the thread the phone already has, never opening a second', () async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')]);
      final support = server.support()..begin('open_support');
      await support.load();
      expect(await support.send('One more thing'), 'ok');
      expect(server.handoffs, isEmpty);
      expect([for (final p in server.posts) if (p.path == 'messages') p.body?['text']], ['One more thing']);
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

  // The last round before Support goes to production (support-qa2, 2026-11-18), as the web SDK does it.
  group('the support page, after the second QA round', () {
    test('says which build calls on every support call, the stream too (D3)', () async {
      final seen = <String, String?>{};
      final client = MockClient.streaming((request, body) async {
        await body.drain<void>();
        seen[request.url.path] = request.headers['X-Rendel-SDK'] ?? request.headers['x-rendel-sdk'];
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200, headers: {'content-type': 'application/json'});
      });
      final api = RendelApiClient(appKey: 'nc_pk_test_x', deviceId: 'device-1', config: const RendelConfig(), httpClient: client);
      await api.support('GET', 'current?after=0');
      await api.support('POST', 'handoff', body: {'trigger': 'open_support', 'client_msg_id': 'c1', 'text': 'Hi'});
      await api.supportStream(_thread, 0).drain<void>();
      expect(seen.keys, containsAll(['/v1/support/current', '/v1/support/handoff', '/v1/support/threads/$_thread/stream']));
      expect(seen.values.toSet(), {const RendelConfig().sdkVersion});
      expect(const RendelConfig().sdkVersion, startsWith('flutter/'));
    });

    testWidgets('says why a first line did not go when too many conversations were started from here, until it goes (D1)', (tester) async {
      final server = _Server(entries: const [])
        ..noThread = true
        ..handoffStatus.add(429);
      final support = server.support();
      support.begin('open_support');
      await _open(tester, support);
      await tester.enterText(find.byType(TextField).last, 'Kargom gelmedi');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(support.value.value.pending.single.reason, 'rate_limited');
      expect(find.text(const RendelStrings().supportTooMany), findsOneWidget);
      await tester.tap(find.text(const RendelStrings().supportUnsent));
      await _settle(tester);
      await _settle(tester);
      expect(server.handoffs, hasLength(2));
      expect(find.text(const RendelStrings().supportTooMany), findsNothing);
      await _close(tester);
    });

    testWidgets("offers I'm sorted, never By mistake, once a teammate joined or read their account (qa2-sdk-05)", (tester) async {
      final joined = {..._entry(2, kind: 'marker', author: 'system', text: 'Ayşe from Grove is helping you.'), 'marker': 'joined'};
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi'), joined], state: _state(mode: 'human'));
      await _open(tester, server.support());
      expect(find.text("I'm sorted"), findsOneWidget);
      expect(find.textContaining('By mistake'), findsNothing);
      await _close(tester);
      final lookup = RendelSupportEntry.tryParse({..._entry(2, kind: 'marker', author: 'system', text: 'Ayşe checked your account to help.'), 'marker': 'lookup'})!;
      expect(rendelSupportTeamStarted([RendelSupportEntry.tryParse(_entry(1, text: 'Hi'))!]), isFalse);
      expect(rendelSupportTeamStarted([lookup]), isTrue);
    });

    testWidgets('lets go of the too-long note once the box is emptied (qa2-sdk-02)', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi')], state: _state(mode: 'human'))..messageStatus.add(400);
      await _open(tester, server.support());
      await tester.enterText(find.byType(TextField).last, 'x' * 50);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(find.text(const RendelStrings().supportTooLong), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '');
      await tester.pump();
      expect(find.text(const RendelStrings().supportTooLong), findsNothing);
      await _close(tester);
    });

    testWidgets('asks to try again under a card only when no answer came, never under one that ran and failed (qa2-sdk-03)', (tester) async {
      for (final (answer, again) in [((200, const <String, Object>{'status': 'failed'}), false), ((503, const <String, Object>{'error': 'down'}), true)]) {
        final server = _Server(
          entries: [
            _entry(1, author: 'agent', name: 'Ayşe', blocks: [
              {'id': 'card-1', 'type': 'confirm_card', 'fallback_text': 'Send order M-2020 again', 'props': {'invocation_id': '', 'summary': 'Send order M-2020 again', 'params_display': <Object>[]}},
            ]),
          ],
          state: _state(mode: 'human'),
        )..confirmAnswers.add(answer);
        await _open(tester, server.support());
        await _settle(tester);
        await tester.ensureVisible(find.text('Confirm').last);
        await tester.tap(find.text('Confirm').last);
        for (var i = 0; i < 4; i++) {
          await _settle(tester);
        }
        expect(find.text(const RendelStrings().turnFailed), again ? findsOneWidget : findsNothing);
        await _close(tester);
      }
    });

    testWidgets('opens nothing new while Support is off: the page has no box and nothing to sort for a conversation of theirs (D4)', (tester) async {
      final server = _Server(entries: [_entry(1, text: 'Kargom gelmedi'), _entry(2, author: 'agent', name: 'Ayşe', text: 'Bakıyorum.')], state: {..._state(mode: 'human'), 'state': 'resolved'});
      await _open(tester, server.support(), supportOn: false);
      expect(find.byType(TextField), findsNothing);
      expect(find.text("I'm sorted"), findsNothing);
      expect(server.handoffs, isEmpty);
    });
  });
}
