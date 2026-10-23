// Follow-ups in an app (design/plans/marketing-channels.md §3.10): asked
// after init, shown over the launcher, opened as the conversation the server
// wrote; pushes, the push token and purchases.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/followups.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';

const _id = '0b8d3c1e-5f6a-4b7c-8d9e-0f1a2b3c4d5e';
const _key = 'nc_pk_test_example_000000000000000000000000';

final _followup = {
  'id': _id,
  'type': 'watch',
  'title': 'Pegasus 41 indirimde',
  'body': "Baktığınız koşu ayakkabısı 449,90 TL'ye düştü.",
  'button': 'Göster',
};

final _history = [
  {
    'id': 'm1',
    'role': 'assistant',
    'blocks': [
      {'id': 'b0', 'type': 'text', 'fallback_text': '', 'props': {'markdown': 'Pegasus 41 artık 449,90 TL.'}},
    ],
    'created_at': '2026-10-24T09:00:00Z',
  },
];

class _Server {
  final events = <Map<String, dynamic>>[];
  final opened = <String>[];
  final tokens = <Map<String, dynamic>>[];
  var asked = 0;
  Map<String, dynamic>? next = _followup;

  static http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/v1/followups/next')) {
      asked++;
      final card = next;
      return card == null ? http.Response('', 204) : _json({'followup': card});
    }
    if (path.endsWith('/open')) {
      opened.add(path.split('/')[3]);
      return _json({'conversation_id': 'c-f'});
    }
    if (path.endsWith('/v1/conversations/c-f/messages')) {
      return _json({'conversation_id': 'c-f', 'messages': _history});
    }
    if (path.endsWith('/v1/events')) {
      events.addAll(((jsonDecode(request.body) as Map)['events'] as List).cast<Map<String, dynamic>>());
      return http.Response('', 204);
    }
    if (path.endsWith('/v1/push/token')) {
      tokens.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('', 204);
    }
    return http.Response('{"ok":true}', 200);
  });

  List<Map<String, dynamic>> of(String type) => events.where((e) => e['type'] == type).toList();
}

Future<_Server> _init(WidgetTester tester, {Map<String, dynamic>? next = const {}}) async {
  final server = _Server();
  if (next == null) server.next = null;
  await tester.runAsync(() async {
    await Rendel.init(appKey: _key, config: RendelConfig(remoteConfig: false, httpClient: server.client));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  return server;
}

Widget _app() => const MaterialApp(home: Scaffold(floatingActionButton: RendelLauncher()));

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump();
}

void main() {
  tearDown(Rendel.resetForTest);

  testWidgets('a follow-up shows over the launcher, counted as shown once', (tester) async {
    final server = await _init(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump();
    expect(Rendel.followup.value?.id, _id);
    expect(find.text('Pegasus 41 indirimde'), findsOneWidget);
    expect(find.text('Göster'), findsOneWidget);
    await tester.pump();
    await _settle(tester);
    expect(server.of('followup_shown'), [
      {'type': 'followup_shown', 'followup_id': _id},
    ]);
  });

  testWidgets('a tap opens the conversation the server wrote, as history', (tester) async {
    final server = await _init(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Göster'));
    await _settle(tester);
    await _settle(tester);
    expect(server.opened, [_id]);
    expect(Rendel.followup.value, isNull);
    expect(Rendel.isOpen, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Pegasus 41 artık 449,90 TL.', findRichText: true), findsWidgets);
    // Used: the popup is gone.
    expect(find.text('Göster'), findsNothing);
    Navigator.of(tester.element(find.byType(Scaffold).first)).maybePop();
    await tester.pumpAndSettle();
  });

  testWidgets('opened from the launcher, the thread shows it at its top instead', (tester) async {
    await _init(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(RendelLauncher));
    await _settle(tester);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    // One copy: the card in the thread; the popup went with the opening.
    expect(Rendel.isOpen, isTrue);
    expect(find.text('Pegasus 41 indirimde'), findsOneWidget);
    expect(find.ancestor(of: find.text('Pegasus 41 indirimde'), matching: find.byType(Overlay)), findsWidgets);
    Navigator.of(tester.element(find.byType(Scaffold).first)).maybePop();
    await tester.pumpAndSettle();
  });

  testWidgets('the cross puts it away for good', (tester) async {
    final server = await _init(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pump();
    await _settle(tester);
    expect(find.text('Pegasus 41 indirimde'), findsNothing);
    expect(Rendel.followup.value, isNull);
    expect(server.of('followup_dismiss'), [
      {'type': 'followup_dismiss', 'followup_id': _id},
    ]);
  });

  testWidgets('nothing is drawn when there is none', (tester) async {
    final server = await _init(tester, next: null);
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(server.asked, 1);
    expect(Rendel.followup.value, isNull);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets("a push opens Rendel's own and leaves the app's alone", (tester) async {
    final server = await _init(tester, next: null);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    late bool theirs;
    late bool ours;
    await tester.runAsync(() async {
      theirs = await Rendel.handlePush(context, {'type': 'chat'});
      ours = await Rendel.handlePush(context, {'rendel': '1', 'rendel_followup': _id});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(theirs, isFalse);
    expect(ours, isTrue);
    expect(server.opened, [_id]);
    expect(Rendel.isOpen, isTrue);
    Navigator.of(context).maybePop();
    await tester.pumpAndSettle();
  });

  testWidgets('the push token goes with the platform, zone and language', (tester) async {
    final server = await _init(tester, next: null);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.runAsync(() async {
        await Rendel.setPushToken('fcm-token', timezone: 'Europe/Istanbul');
        await Rendel.setPushToken(null);
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    expect(server.tokens.first, {'token': 'fcm-token', 'platform': 'ios', 'timezone': 'Europe/Istanbul', 'locale': isA<String>()});
    expect(server.tokens.last['token'], isNull);
    expect(server.tokens.last['timezone'], offsetZone(DateTime.now().timeZoneOffset));
  });

  testWidgets('a purchase is sent once it is whole, and refused when it is not', (tester) async {
    final server = await _init(tester, next: null);
    Rendel.track('purchase', {'value': 549.9, 'currency': 'try', 'items': [{'id': 'p1', 'quantity': 1}]});
    Rendel.track('purchase', {'value': -1, 'currency': 'TRY'});
    Rendel.track('purchase', {'value': 10, 'currency': 'lira'});
    Rendel.track('signup', {'value': 1, 'currency': 'TRY'});
    await _settle(tester);
    expect(server.of('purchase'), [
      {'type': 'purchase', 'value': 549.9, 'currency': 'TRY', 'items': [{'id': 'p1', 'quantity': 1}]},
    ]);
  });

  test('a zone without a name is its offset, IANA-signed', () {
    expect(offsetZone(const Duration(hours: 3)), 'Etc/GMT-3');
    expect(offsetZone(const Duration(hours: -5)), 'Etc/GMT+5');
    expect(offsetZone(Duration.zero), 'Etc/GMT');
    expect(offsetZone(const Duration(hours: 5, minutes: 30)), isNull);
  });

  test('a conversation loads as history, its newest answer on screen', () {
    final c = ConversationController(
      api: RendelApiClient(appKey: _key, deviceId: 'd', config: const RendelConfig()),
      actions: const {},
      sdkVersion: 'flutter/test',
      onOpenUrl: (_) async => true,
    );
    addTearDown(c.dispose);
    c.loadHistory('c-f', [
      {'id': 'u1', 'role': 'user', 'blocks': [{'id': 'q', 'type': 'text', 'fallback_text': '', 'props': {'markdown': 'Var mı?'}}]},
      ..._history,
      {'id': 'x', 'role': 'system', 'blocks': []},
    ]);
    expect(c.conversationId, 'c-f');
    expect(c.messages.map((m) => [m.role, m.serverId]), [
      ['user', 'u1'],
      ['assistant', 'm1'],
    ]);
    expect(c.messages.last.blocks.single.ready, isTrue);
    expect(c.pages.single.serverId, 'm1');
    expect(c.page, 0);
  });
}
