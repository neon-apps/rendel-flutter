// Preference memory, wave 2b (design/plans/preference-memory.md §3.3–3.7):
// the `memory` event, the chips under an answer with their Undo, the
// "From your preferences" marks, and the "What I remember for you" sheet.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/memory.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/memory_chips.dart';
import 'package:rendel/src/ui/memory_sheet.dart';
import 'package:rendel/src/ui/thread_screen.dart';

import 'wire_schema.dart';

const _n1 = '6f1c2d3e-4b5a-4c6d-8e7f-901a2b3c4d5e';
const _n2 = '7a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const _n3 = '8b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e';

/// The last day of a note saved "until Sunday 1 November": the midnight UTC
/// after it.
const _sunday = '2026-11-02T00:00:00.000Z';

Map<String, dynamic> _memory(
  String op, {
  String? kind = 'stated',
  String? id,
  String key = 'diet',
  String? label,
  String? value,
  String? category,
  String? expiresAt,
}) =>
    {
      'type': 'memory',
      'op': op,
      'kind': kind,
      'id': id,
      'key': key,
      'label': label,
      'value': value,
      'category': category,
      'expires_at': expiresAt,
    };

/// One answer: a line of text, then [memory], then the end.
String _turn(String message, List<Map<String, dynamic>> memory) {
  final events = [
    {'type': 'turn.start', 'conversation_id': 'c1', 'message_id': message},
    {
      'type': 'block.ready',
      'index': 0,
      'block': {'id': 'b_$message', 'type': 'text', 'fallback_text': 'Here you go.', 'props': {'markdown': 'Here you go.'}},
    },
    ...memory,
    {'type': 'turn.end', 'status': 'completed', 'pending': <String>[]},
  ];
  return [
    for (final (seq, event) in events.indexed)
      'event: ${event['type']}\ndata: ${jsonEncode({'v': 1, 'seq': seq, ...event})}\n\n',
  ].join();
}

/// The API, scripted: each `/v1/chat` answers with the next of [turns], and
/// `/v1/memory` with [list] or [status].
class _Server {
  _Server({this.turns = const [], this.list = '{"enabled":true,"notes":[]}'});

  final List<String> turns;
  String list;
  int listStatus = 200;
  int status = 204;
  final List<http.BaseRequest> requests = [];

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/v1/chat')) {
      return http.Response(turns[requests.where((r) => r.url.path.endsWith('/v1/chat')).length - 1], 200,
          headers: {'content-type': 'text/event-stream'});
    }
    if (path == '/v1/memory' && request.method == 'GET') {
      return http.Response(list, listStatus, headers: {'content-type': 'application/json'});
    }
    if (path.startsWith('/v1/memory')) return http.Response('', status);
    return http.Response('{}', 200);
  });

  RendelApiClient api() => RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'device-1',
        config: const RendelConfig(),
        httpClient: client,
      );

  List<http.BaseRequest> get memory => [for (final r in requests) if (r.url.path.startsWith('/v1/memory')) r];
}

Widget _app(Widget child) => MaterialApp(
      home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: child)),
    );

/// Lets the scripted requests land, then the frames after them.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('the memory event', () {
    test('is read with every field', () {
      final event = RendelWireEvent.tryParse('memory', {
        'v': 1,
        'seq': 4,
        'type': 'memory',
        'op': 'saved',
        'kind': 'learned',
        'id': _n1,
        'key': 'diet',
        'label': 'Lactose-free',
        'value': 'Always lactose-free milk',
        'category': 'diet',
        'expires_at': _sunday,
      });
      expect(event, isA<MemoryChange>());
      final change = event! as MemoryChange;
      expect(change.op, MemoryOp.saved);
      expect(change.kind, MemoryKind.learned);
      expect(change.id, _n1);
      expect(change.key, 'diet');
      expect(change.label, 'Lactose-free');
      expect(change.value, 'Always lactose-free milk');
      expect(change.category, 'diet');
      expect(change.expiresAt, DateTime.utc(2026, 11, 2));
      expect(change.undone, isFalse);
    });

    test('a forget of everything has no id, kind or label', () {
      final change = RendelWireEvent.tryParse('memory', _memory('forgotten', kind: null, key: '*'))! as MemoryChange;
      expect(change.op, MemoryOp.forgotten);
      expect(change.kind, isNull);
      expect(change.id, isNull);
      expect(change.name, '*');
    });

    test('an op this build does not know is dropped', () {
      expect(RendelWireEvent.tryParse('memory', _memory('merged', id: _n1)), isNull);
      expect(RendelWireEvent.tryParse('memory', {..._memory('saved', id: _n1), 'key': null}), isNull);
    });

    // The midnight UTC after the last day, written with Istanbul's offset:
    // read in the device's zone (+03:00 here), it would be the 2nd.
    testWidgets('a day is said short, in UTC', (tester) async {
      late String said;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        said = memoryLastDay(context, DateTime.parse('2026-11-02T03:00:00+03:00'));
        return const SizedBox();
      })));
      expect(said, 'Nov 1');
    });
  });

  group('the API', () {
    test('lists as the signed-in person, with the HMAC', () async {
      final server = _Server(
        list: jsonEncode({
          'enabled': true,
          'notes': [
            {
              'id': _n1,
              'kind': 'stated',
              'key': 'diet',
              'label': 'Laktozsuz',
              'value': 'Hep laktozsuz süt',
              'category': 'diet',
              'expires_at': _sunday,
              'updated_at': '2026-10-23T10:00:00.000Z',
            },
            {'id': 'not-a-note'},
          ],
        }),
      );
      final memory = RendelMemory(server.api(), user: () => {'id': 'u_42', 'hmac': 'h_1'});
      final list = await memory.list();
      expect(list!.enabled, isTrue);
      expect(list.notes.single.name, 'Laktozsuz');
      expect(list.notes.single.value, 'Hep laktozsuz süt');
      expect(list.notes.single.expiresAt, DateTime.utc(2026, 11, 2));
      final request = server.memory.single;
      expect(request.method, 'GET');
      expect(request.headers['x-rendel-key'], 'nc_pk_test_x');
      expect(request.headers['x-rendel-device'], 'device-1');
      expect(request.headers['x-rendel-user'], 'u_42');
      expect(request.headers['x-rendel-user-hmac'], 'h_1');
    });

    test('signed out, names nobody: the server uses the device', () async {
      final server = _Server();
      await RendelMemory(server.api(), user: () => null).list();
      expect(server.memory.single.headers.containsKey('x-rendel-user'), isFalse);
      expect(server.memory.single.headers['x-rendel-device'], 'device-1');
    });

    test('forget and forget all', () async {
      final server = _Server();
      final memory = RendelMemory(server.api(), user: () => null);
      expect(await memory.forget(_n1), isTrue);
      expect(await memory.forgetAll(), isTrue);
      expect([for (final r in server.memory) '${r.method} ${r.url.path}'], ['DELETE /v1/memory/$_n1', 'DELETE /v1/memory']);
      // A note that is not there is gone too; a server that failed is not.
      server.status = 404;
      expect(await memory.forget(_n1), isTrue);
      server.status = 500;
      expect(await memory.forget(_n1), isFalse);
      expect(await memory.forgetAll(), isFalse);
      server.listStatus = 500;
      expect(await memory.list(), isNull);
    });
  });

  group('the chips under an answer', () {
    MemoryChange change(Map<String, dynamic> wire) => RendelWireEvent.tryParse('memory', wire)! as MemoryChange;

    Future<List<MemoryChange>> pump(WidgetTester tester, List<Map<String, dynamic>> wire, {VoidCallback? onOpen}) async {
      final changes = [for (final w in wire) change(w)];
      await tester.pumpWidget(_app(RendelMemoryChips(changes: changes, onUndo: (_) {}, onOpen: onOpen ?? () {})));
      return changes;
    }

    testWidgets('say a save, with Undo, and until when', (tester) async {
      await pump(tester, [
        _memory('saved', id: _n1, label: 'Lactose-free'),
        _memory('saved', id: _n2, key: 'week', label: 'Diet', expiresAt: _sunday),
      ]);
      expect(find.text("I'll remember: Lactose-free"), findsOneWidget);
      expect(find.text("I'll remember until Nov 1: Diet"), findsOneWidget);
      expect(find.text('Undo'), findsNWidgets(2));
    });

    testWidgets('say what Rendel noticed', (tester) async {
      await pump(tester, [
        _memory('saved', kind: 'learned', id: _n1, key: 'milk', label: 'Oat milk'),
        _memory('saved', kind: 'learned', id: _n2, key: 'snacks', label: 'Nut-free', expiresAt: _sunday),
      ]);
      expect(find.text('Noted for next time: Oat milk'), findsOneWidget);
      expect(find.text('Noted until Nov 1: Nut-free'), findsOneWidget);
    });

    testWidgets('say a change and a forget, with no Undo', (tester) async {
      await pump(tester, [
        _memory('updated', id: _n1, key: 'size', label: 'Shoe size 42'),
        _memory('forgotten', key: 'diet', label: 'Lactose-free'),
        _memory('forgotten', kind: null, key: '*'),
      ]);
      expect(find.text('Updated: Shoe size 42'), findsOneWidget);
      expect(find.text('Forgotten: Lactose-free'), findsOneWidget);
      expect(find.text("I've forgotten everything I remembered"), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('name the one note an answer relied on, by its key without a label', (tester) async {
      await pump(tester, [_memory('used', id: _n1, key: 'lactose_free')]);
      expect(find.text('Based on your lactose_free preference'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('count two or more, first', (tester) async {
      await pump(tester, [
        _memory('saved', id: _n3, key: 'brand', label: 'Oatly'),
        _memory('used', id: _n1, label: 'lactose-free'),
        _memory('used', id: _n2, key: 'size', label: 'size M'),
      ]);
      expect(find.text('Based on 2 of your preferences'), findsOneWidget);
      expect(find.textContaining('Based on your'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Based on 2 of your preferences')).dy,
        lessThan(tester.getTopLeft(find.text("I'll remember: Oatly")).dy),
      );
    });

    testWidgets('say a save taken back, with no Undo', (tester) async {
      final changes = [change(_memory('saved', id: _n1, label: 'Lactose-free'))..undone = true];
      await tester.pumpWidget(_app(RendelMemoryChips(changes: changes, onUndo: (_) {}, onOpen: () {})));
      expect(find.text('Not saved'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('open the sheet from their words', (tester) async {
      var opened = 0;
      await pump(tester, [_memory('used', id: _n1, label: 'lactose-free')], onOpen: () => opened++);
      await tester.tap(find.text('Based on your lactose-free preference'));
      expect(opened, 1);
    });
  });

  group('in the thread', () {
    ConversationController controller(_Server server, {Map<String, String>? user}) {
      final c = ConversationController(
        api: server.api(),
        actions: const {},
        sdkVersion: 'flutter/test',
        user: () => user,
      );
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('a memory event lands on the answer it came with', (tester) async {
      final server = _Server(turns: [
        _turn('m1', [_memory('saved', id: _n1, label: 'Lactose-free', value: 'Always lactose-free')]),
      ]);
      final c = controller(server);
      await tester.runAsync(() => c.send('Always lactose-free, please'));
      final answer = c.messages.last;
      expect(answer.role, 'assistant');
      expect(answer.memory.single.id, _n1);
      expect(answer.memory.single.value, 'Always lactose-free');
      expect(c.messages.first.memory, isEmpty);
    });

    testWidgets('Undo deletes the note as the person, then says it was not saved', (tester) async {
      final server = _Server(turns: [
        _turn('m1', [_memory('saved', id: _n1, label: 'Lactose-free')]),
      ]);
      final c = controller(server, user: {'id': 'u_42', 'hmac': 'h_1'});
      await tester.runAsync(() => c.send('Always lactose-free, please'));
      await tester.pumpWidget(_app(ThreadScreen(controller: c)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text("I'll remember: Lactose-free"), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await _settle(tester);

      final request = server.memory.single;
      expect('${request.method} ${request.url.path}', 'DELETE /v1/memory/$_n1');
      expect(request.headers['x-rendel-key'], 'nc_pk_test_x');
      expect(request.headers['x-rendel-device'], 'device-1');
      expect(request.headers['x-rendel-user'], 'u_42');
      expect(request.headers['x-rendel-user-hmac'], 'h_1');
      expect(find.text('Not saved'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      expect(c.messages.last.memory.single.undone, isTrue);
      // Taken back once; a second Undo sends nothing.
      expect(await tester.runAsync(() => c.undo(c.messages.last.memory.single)), isFalse);
      expect(server.memory, hasLength(1));
    });

    testWidgets('an Undo that did not reach the server leaves the chip as it was', (tester) async {
      final server = _Server(turns: [
        _turn('m1', [_memory('saved', id: _n1, label: 'Lactose-free')]),
      ])
        ..status = 500;
      final c = controller(server);
      await tester.runAsync(() => c.send('Always lactose-free, please'));
      expect(await tester.runAsync(() => c.undo(c.messages.last.memory.single)), isFalse);
      expect(c.messages.last.memory.single.undone, isFalse);
    });

    testWidgets('a note the answers rely on is named once a thread', (tester) async {
      final server = _Server(turns: [
        _turn('m1', [_memory('used', id: _n1, label: 'lactose-free')]),
        _turn('m2', [
          _memory('used', id: _n1, label: 'lactose-free'),
          _memory('used', id: _n2, key: 'size', label: 'size M'),
        ]),
        _turn('m3', [_memory('used', id: _n1, label: 'lactose-free')]),
      ]);
      final c = controller(server);
      await tester.runAsync(() => c.send('Milk?'));
      await tester.runAsync(() => c.send('And a shirt?'));
      final answers = [for (final m in c.messages) if (m.role == 'assistant') m];
      expect([for (final change in answers[0].memory) change.id], [_n1]);
      expect([for (final change in answers[1].memory) change.id], [_n2]);

      await tester.pumpWidget(_app(ThreadScreen(controller: c)));
      await tester.pump(const Duration(milliseconds: 600));
      // The newest page: one note left to name, so it is named, not counted.
      expect(find.text('Based on your size M preference'), findsOneWidget);
      expect(find.text('Based on 2 of your preferences'), findsNothing);
      expect(find.text('Based on your lactose-free preference'), findsNothing);

      // A new conversation names it again.
      c.reset();
      await tester.runAsync(() => c.send('Milk again?'));
      expect(c.messages.last.memory.single.id, _n1);
    });
  });

  group('the sheet', () {
    String notes(List<Map<String, dynamic>> notes, {bool enabled = true}) => jsonEncode({
          'enabled': enabled,
          'notes': [
            for (final note in notes)
              {
                'kind': 'stated',
                'label': null,
                'category': null,
                'expires_at': null,
                'updated_at': '2026-10-23T10:00:00.000Z',
                ...note,
              },
          ],
        });

    final three = [
      {'id': _n1, 'key': 'week', 'label': 'Diet', 'value': 'On a diet this week', 'expires_at': _sunday},
      {'id': _n2, 'kind': 'learned', 'key': 'milk', 'label': 'Oat milk', 'value': 'Buys oat milk'},
      {'id': _n3, 'kind': 'set', 'key': 'tier', 'value': 'Gold member'},
    ];

    Future<void> open(WidgetTester tester, _Server server) async {
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () => showRendelMemory(context, memory: RendelMemory(server.api(), user: () => null)),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    testWidgets('lists every note, with what it is and until when', (tester) async {
      final server = _Server(list: notes(three));
      await open(tester, server);
      expect(find.text('What I remember for you'), findsOneWidget);
      expect(find.text('Diet'), findsOneWidget);
      expect(find.text('On a diet this week'), findsOneWidget);
      expect(find.text('Until Nov 1'), findsOneWidget);
      expect(find.text('Oat milk'), findsOneWidget);
      expect(find.text('Noticed'), findsOneWidget);
      // No label: the key.
      expect(find.text('tier'), findsOneWidget);
      expect(find.text('From the app'), findsOneWidget);
      // Forget on what the person may take back; the app's own fact has none.
      expect(find.text('Forget'), findsNWidgets(2));
      expect(find.text('Forget all'), findsOneWidget);
      expect(find.text("The app's team can see these too."), findsOneWidget);
      expect('${server.memory.single.method} ${server.memory.single.url.path}', 'GET /v1/memory');
    });

    testWidgets('says how to start when there is nothing yet', (tester) async {
      await open(tester, _Server(list: notes(const [])));
      expect(find.textContaining('Tell me a preference once'), findsOneWidget);
      expect(find.text('Forget all'), findsNothing);
      expect(find.text("The app's team can see these too."), findsOneWidget);
    });

    testWidgets('says when the app keeps none', (tester) async {
      await open(tester, _Server(list: notes(const [], enabled: false)));
      expect(find.text("This app doesn't keep preferences."), findsOneWidget);
      expect(find.text("The app's team can see these too."), findsNothing);
    });

    testWidgets('says when it could not be read, and tries again', (tester) async {
      final server = _Server(list: notes(three))..listStatus = 500;
      await open(tester, server);
      expect(find.text('Try again'), findsOneWidget);
      server.listStatus = 200;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('Diet'), findsOneWidget);
    });

    testWidgets('Forget takes one note away', (tester) async {
      final server = _Server(list: notes(three));
      await open(tester, server);
      await tester.tap(find.text('Forget').first);
      await _settle(tester);
      expect('${server.memory.last.method} ${server.memory.last.url.path}', 'DELETE /v1/memory/$_n1');
      expect(find.text('Diet'), findsNothing);
      expect(find.text('Oat milk'), findsOneWidget);
    });

    testWidgets('Forget all asks once more in place, then keeps the app\'s own', (tester) async {
      final server = _Server(list: notes(three));
      await open(tester, server);

      await tester.tap(find.text('Forget all'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Forget everything I remember for you?'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Go back'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Forget everything I remember for you?'), findsNothing);
      expect(server.memory, hasLength(1));

      await tester.tap(find.text('Forget all'));
      await tester.pump(const Duration(milliseconds: 400));
      // The question's own button: the one that asked has made way for it.
      expect(find.text('Forget all'), findsOneWidget);
      await tester.tap(find.text('Forget all'));
      await _settle(tester);
      expect('${server.memory.last.method} ${server.memory.last.url.path}', 'DELETE /v1/memory');
      expect(find.text('Diet'), findsNothing);
      expect(find.text('Oat milk'), findsNothing);
      expect(find.text('tier'), findsOneWidget);
      expect(find.text('Forget all'), findsNothing);
      expect(find.text('Forget everything I remember for you?'), findsNothing);
    });

    testWidgets('Rendel.openMemory opens it as the person identify named', (tester) async {
      addTearDown(Rendel.resetForTest);
      final server = _Server(list: notes(three));
      await Rendel.init(
        appKey: 'nc_pk_test_example_000000000000000000000000',
        config: RendelConfig(httpClient: server.client, remoteConfig: false),
      );
      await tester.runAsync(() => Rendel.identify(userId: 'ayse', userHmac: 'h_ayse'));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(onPressed: () => Rendel.openMemory(context), child: const Text('open')),
        ),
      ));
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.text('What I remember for you'), findsOneWidget);
      expect(find.text('Diet'), findsOneWidget);
      final request = server.memory.single;
      expect(request.headers['x-rendel-user'], 'ayse');
      expect(request.headers['x-rendel-user-hmac'], 'h_ayse');
    });
  });

  group('"From your preferences"', () {
    Future<WireBlock> pump(WidgetTester tester, Map<String, dynamic> wire, VoidCallback onOpenMemory) async {
      expect(wireBlockErrors(wire), isEmpty);
      final block = WireBlock.tryParse(jsonDecode(jsonEncode(wire)) as Map<String, dynamic>)!;
      final dispatch = RendelDispatcher(
        onAction: (_) async => true,
        onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
        canHandle: (_) => true,
        onOpenMemory: onOpenMemory,
      );
      await tester.pumpWidget(_app(SingleChildScrollView(
        child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
      )));
      await tester.pump(const Duration(milliseconds: 400));
      return block;
    }

    testWidgets('marks the card row the server filled from a note, and opens the sheet', (tester) async {
      var opened = 0;
      await pump(
        tester,
        {
          'id': 'b_confirm',
          'type': 'confirm_card',
          'fallback_text': 'Order 2 lactose-free milks?',
          'props': {
            'invocation_id': 'i1',
            'action_name': 'add_to_cart',
            'summary': 'Add 2 milks to your cart?',
            'risk': 'write',
            'params_display': [
              {'label': 'Milk', 'value': 'Lactose-free', 'param': 'milk', 'remembered': true},
              {'label': 'Quantity', 'value': '2', 'param': 'qty'},
            ],
            'params': {'milk': 'lactose-free', 'qty': 2},
            'confirm': {'kind': 'confirm', 'invocation_id': 'i1'},
            'cancel': {'kind': 'cancel', 'invocation_id': 'i1'},
          },
        },
        () => opened++,
      );
      expect(find.text('From your preferences'), findsOneWidget);
      // Under its own row, above the next.
      final mark = tester.getTopLeft(find.text('From your preferences')).dy;
      expect(mark, greaterThan(tester.getTopLeft(find.text('Lactose-free')).dy));
      expect(mark, lessThan(tester.getTopLeft(find.text('Quantity')).dy));
      await tester.tap(find.text('From your preferences'));
      expect(opened, 1);
    });

    testWidgets('marks a form field until the person edits it', (tester) async {
      var opened = 0;
      final block = await pump(
        tester,
        {
          'id': 'b_form',
          'type': 'form',
          'fallback_text': 'Your delivery.',
          'props': {
            'form_id': 'delivery',
            'title': 'Delivery',
            'submit_label': 'Save',
            'fields': [
              {'kind': 'text', 'name': 'address', 'label': 'Address', 'value': 'Moda Cd. 12', 'remembered': true},
              {'kind': 'text', 'name': 'note', 'label': 'Note'},
            ],
          },
        },
        () => opened++,
      );
      expect(find.text('From your preferences'), findsOneWidget);
      await tester.tap(find.text('From your preferences'));
      expect(opened, 1);

      await tester.enterText(find.widgetWithText(TextField, 'Moda Cd. 12'), 'Bahariye Cd. 3');
      await tester.pump();
      expect(find.text('From your preferences'), findsNothing);
      expect(block.props[RendelLocalKeys.edited], contains('address'));
    });

    testWidgets('is text where nothing can open the sheet', (tester) async {
      final block = WireBlock.tryParse({
        'id': 'b_form',
        'type': 'form',
        'fallback_text': 'Your delivery.',
        'props': {
          'form_id': 'delivery',
          'fields': [
            {'kind': 'text', 'name': 'address', 'label': 'Address', 'value': 'Moda Cd. 12', 'remembered': true},
          ],
        },
      })!;
      final dispatch = RendelDispatcher(
        onAction: (_) async => true,
        onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
        canHandle: (_) => true,
      );
      await tester.pumpWidget(_app(SingleChildScrollView(
        child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
      )));
      expect(find.text('From your preferences'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('From your preferences'), matching: find.byType(RendelPressable)),
        findsNothing,
      );
    });
  });
}
