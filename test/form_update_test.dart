// Forms that update in place (`form_update`).
//
// The model reshapes a form by sending it again under the same `form_id`. The
// rules that make that safe live on the device and nowhere else — the server
// cannot see what the user typed until it is told — so each one is held here,
// through the real client and a fake server: what is declared, what replaces
// what, whose value wins, and what goes up with a message.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';

import 'wire_schema.dart';

void main() {
  ConversationController controller(_Server server) => ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          httpClient: server,
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  /// The return form, as the model first draws it.
  Map<String, dynamic> returnForm({
    String id = 'b_form1',
    String formId = 'return_request',
    List<Map<String, dynamic>>? fields,
  }) =>
      _block(id, 'form', {
        'form_id': formId,
        'title': 'Return an item',
        'fields': fields ??
            [
              {'name': 'order', 'label': 'Order', 'kind': 'text', 'value': '1042'},
              {
                'name': 'reason',
                'label': 'Reason',
                'kind': 'select',
                'value': 'damaged',
                'options': [
                  {'value': 'damaged', 'label': 'Damaged'},
                  {'value': 'wrong_size', 'label': 'Wrong size'},
                  {'value': 'other', 'label': 'Other'},
                ],
              },
              {'name': 'note', 'label': 'Note', 'kind': 'text'},
            ],
      });

  /// What the form widget does when the user changes a field.
  void userSets(WireBlock form, String name, Object value) {
    (form.props[RendelLocalKeys.values] as Map)[name] = value;
    ((form.props[RendelLocalKeys.edited] ??= <String>{}) as Set<String>).add(name);
  }

  Iterable<WireBlock> formsIn(ConversationController c) =>
      c.messages.expand((m) => m.blocks).where((b) => b.type == 'form');

  test('every request declares form_update', () async {
    final server = _Server([
      [_text('b0', 'Hi.')],
    ]);
    final c = controller(server);

    await c.send('hello');

    final client = server.chats.single['client'] as Map<String, dynamic>;
    expect(client['capabilities'], ['form_update', 'surface_update', 'answer_pages', 'detail_pages', 'notices', 'card_fill']);
    c.dispose();
  });

  test('a redrawn form replaces the open one, and what the user chose wins',
      () async {
    final server = _Server([
      [returnForm()],
      [
        _text('b1', 'Refund to your card, then.'),
        returnForm(id: 'b_form2', fields: [
          // The model proposes a new order number: nobody touched that field.
          {'name': 'order', 'label': 'Order', 'kind': 'text', 'value': '2000'},
          // And a reason the user already changed: theirs stays.
          {'name': 'reason', 'label': 'Reason', 'kind': 'select', 'value': 'other'},
          {'name': 'note', 'label': 'Note', 'kind': 'text'},
          {'name': 'refund_to', 'label': 'Refund to', 'kind': 'text', 'value': 'card'},
        ]),
      ],
    ]);
    final c = controller(server);

    await c.send('I want to return something');
    final first = formsIn(c).single;
    expect(first.props[RendelLocalKeys.values], {'order': '1042', 'reason': 'damaged'},
        reason: 'the model values are seeded on arrival, before any draw');
    userSets(first, 'reason', 'wrong_size');
    userSets(first, 'note', 'Too small');

    await c.send('make it a refund to my card');

    final form = formsIn(c).single;
    expect(form.id, 'b_form2', reason: 'the new one, where it arrived');
    expect(form.props[RendelLocalKeys.values], {
      'order': '2000',
      'reason': 'wrong_size',
      'note': 'Too small',
      'refund_to': 'card',
    });
    expect(form.props[RendelLocalKeys.edited], {'reason', 'note'});
    // The first answer was nothing but the form, so it leaves with it; the
    // thread is the two questions and the answer that holds the form.
    expect(c.messages.map((m) => m.role), ['user', 'user', 'assistant']);
    expect(c.messages.last.blocks.map((b) => b.id), ['b1', 'b_form2']);
    c.dispose();
  });

  test('a turn keeps its other blocks when its form is replaced', () async {
    final server = _Server([
      [_text('b0', 'Here is the form.'), returnForm()],
      [returnForm(id: 'b_form2')],
    ]);
    final c = controller(server);

    await c.send('return');
    await c.send('again');

    expect(c.messages[1].blocks.map((b) => b.id), ['b0']);
    expect(formsIn(c).map((b) => b.id), ['b_form2']);
    c.dispose();
  });

  test('fields the new form no longer has are dropped, edited mark and all',
      () async {
    final server = _Server([
      [returnForm()],
      [
        returnForm(id: 'b_form2', fields: [
          {'name': 'order', 'label': 'Order', 'kind': 'text'},
        ]),
      ],
    ]);
    final c = controller(server);

    await c.send('return');
    final first = formsIn(c).single;
    userSets(first, 'note', 'Too small');
    userSets(first, 'order', '1043');

    await c.send('just the order');

    final form = formsIn(c).single;
    expect(form.props[RendelLocalKeys.values], {'order': '1043'});
    expect(form.props[RendelLocalKeys.edited], {'order'});
    c.dispose();
  });

  test('a field with no new value keeps the one it had', () async {
    final server = _Server([
      [returnForm()],
      [
        returnForm(id: 'b_form2', fields: [
          {'name': 'order', 'label': 'Order', 'kind': 'text'},
          {'name': 'reason', 'label': 'Reason', 'kind': 'select'},
        ]),
      ],
    ]);
    final c = controller(server);

    await c.send('return');
    await c.send('again');

    expect(formsIn(c).single.props[RendelLocalKeys.values],
        {'order': '1042', 'reason': 'damaged'});
    expect(formsIn(c).single.props[RendelLocalKeys.edited], isNull);
    c.dispose();
  });

  test('a submitted form is never replaced', () async {
    final server = _Server([
      [returnForm()],
      [returnForm(id: 'b_form2')],
    ]);
    final c = controller(server);

    await c.send('return');
    final first = formsIn(c).single;
    userSets(first, 'reason', 'wrong_size');
    first.props[RendelLocalKeys.submitted] = true;

    await c.send('another one');

    expect(formsIn(c).map((b) => b.id), ['b_form1', 'b_form2']);
    expect(formsIn(c).last.props[RendelLocalKeys.values],
        {'order': '1042', 'reason': 'damaged'},
        reason: 'a new form for the same thing, not a copy of the sent one');
    expect(formsIn(c).last.props[RendelLocalKeys.edited], isNull);
    c.dispose();
  });

  test('a form whose submission is in flight is not replaced by its answer',
      () async {
    final server = _Server([
      [returnForm()],
      [returnForm(id: 'b_form2')],
    ]);
    final c = controller(server);

    await c.send('return');
    expect(await c.submitForm('return_request', {'order': '1042'}),
        RendelSubmitOutcome.sent);

    expect(formsIn(c).map((b) => b.id), ['b_form1', 'b_form2']);
    c.dispose();
  });

  test('a form with another id is a new form beside it', () async {
    final server = _Server([
      [returnForm()],
      [returnForm(id: 'b_form2', formId: 'exchange_request')],
    ]);
    final c = controller(server);

    await c.send('return');
    await c.send('exchange instead');

    expect(formsIn(c).map((b) => b.id), ['b_form1', 'b_form2']);
    c.dispose();
  });

  test('the focused field is handed to the same field of the new form',
      () async {
    final server = _Server([
      [returnForm()],
      [returnForm(id: 'b_form2')],
    ]);
    final c = controller(server);

    await c.send('return');
    formsIn(c).single.props[RendelLocalKeys.focused] = 'note';
    await c.send('again');

    expect(formsIn(c).single.props[RendelLocalKeys.refocus], 'note');
    c.dispose();
  });

  test('a redrawn form keeps a range the user changed by key, and its files', () async {
    final server = _Server([
      [
        returnForm(fields: [
          {'name': 'stay', 'label': 'Stay', 'kind': 'date_range', 'value': ['2026-11-10', '2026-11-14']},
          {'name': 'photos', 'label': 'Photos', 'kind': 'upload'},
        ]),
      ],
      [
        returnForm(id: 'b_form2', fields: [
          // The model moves both days; the user had moved only the end.
          {'name': 'stay', 'label': 'Stay', 'kind': 'date_range', 'value': ['2026-12-01', '2026-12-05']},
          {'name': 'photos', 'label': 'Photos', 'kind': 'upload'},
        ]),
      ],
    ]);
    final c = controller(server);

    await c.send('book');
    final first = formsIn(c).single;
    userSets(first, 'stay_end', '2026-11-20');
    // What the form widget keeps beside an upload's ids: the files, opaque
    // to the controller, which only carries them.
    final photos = [Object()];
    first.props[RendelLocalKeys.files] = {'photos': photos};
    await c.send('in December instead');

    final form = formsIn(c).single;
    expect(form.props[RendelLocalKeys.values], {'stay_start': '2026-12-01', 'stay_end': '2026-11-20'});
    expect(form.props[RendelLocalKeys.edited], {'stay_end'});
    expect((form.props[RendelLocalKeys.files] as Map)['photos'], same(photos),
        reason: 'the thumbnails go with the ids');
    c.dispose();
  });

  group('open_forms', () {
    test('goes with a message, with values and edited', () async {
      final server = _Server([
        [returnForm()],
        [_text('b1', 'Sure.')],
      ]);
      final c = controller(server);

      await c.send('return');
      userSets(formsIn(c).single, 'reason', 'wrong_size');
      await c.send('make it a refund');

      expect(server.chats.first['context'], isNull,
          reason: 'no forms and no providers: no context at all');
      expect(server.chats.last['context'], {
        'open_forms': [
          {
            'form_id': 'return_request',
            'values': {'order': '1042', 'reason': 'wrong_size'},
            'edited': ['reason'],
          },
        ],
      });
      c.dispose();
    });

    test('never with a submission or a tool result', () async {
      final server = _Server([
        [returnForm()],
        [_action('inv_1', 'look_up_order')],
        [_text('b2', 'Done.')],
      ]);
      final c = ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          httpClient: server,
        ),
        actions: {
          'look_up_order': RendelAction(
            name: 'look_up_order',
            description: 'Find an order.',
            params: RendelSchema.object({}),
            risk: RendelRisk.read,
            handler: (_) async => RendelResult.ok({'status': 'shipped'}),
          ),
        },
        sdkVersion: 'flutter/test',
      );

      await c.send('return');
      await c.submitForm('return_request', {'order': '1042'});

      expect(server.chats, hasLength(3));
      expect(server.chats[1]['form_submission'], isNotNull);
      expect(server.chats[1]['context'], isNull);
      expect(server.chats[2]['tool_results'], isNotNull);
      expect(server.chats[2]['context'], isNull);
      c.dispose();
    });

    test('the three most recent open forms, clipped to the schema', () async {
      final server = _Server([
        [
          returnForm(id: 'f1', formId: 'one'),
          returnForm(id: 'f2', formId: 'two'),
          returnForm(id: 'f3', formId: 'three'),
          returnForm(id: 'f4', formId: 'four'),
          returnForm(id: 'f5', formId: 'five'),
        ],
        [_text('b1', 'Sure.')],
      ]);
      final c = controller(server);

      await c.send('forms');
      final forms = formsIn(c).toList();
      forms[4].props[RendelLocalKeys.submitted] = true;
      userSets(forms[3], 'note', 'x' * 600);

      await c.send('next');

      final open = (server.chats.last['context'] as Map)['open_forms'] as List;
      expect(open.map((f) => (f as Map)['form_id']), ['four', 'three', 'two']);
      final note = ((open.first as Map)['values'] as Map)['note'] as String;
      expect(note.length, 500);
      c.dispose();
    });

    // Form v2: a multi_select's picks and an upload's ids are lists, and a
    // date range is its two keys, in the values and in `edited` alike.
    test('carries lists, and a range under its two keys', () async {
      final server = _Server([
        [
          returnForm(fields: [
            {
              'name': 'rooms',
              'label': 'Rooms',
              'kind': 'multi_select',
              'value': ['kitchen'],
              'options': [
                {'value': 'kitchen', 'label': 'Kitchen'},
                {'value': 'hall', 'label': 'Hall'},
              ],
            },
            {'name': 'stay', 'label': 'Stay', 'kind': 'date_range', 'value': ['2026-11-10', '2026-11-14']},
            {'name': 'photos', 'label': 'Photos', 'kind': 'upload'},
          ]),
        ],
        [_text('b1', 'Sure.')],
      ]);
      final c = controller(server);

      await c.send('claim');
      final form = formsIn(c).single;
      expect(form.props[RendelLocalKeys.values], {
        'rooms': ['kitchen'],
        'stay_start': '2026-11-10',
        'stay_end': '2026-11-14',
      }, reason: 'seeded on arrival, the range under its two keys');
      userSets(form, 'rooms', ['kitchen', 'hall']);
      userSets(form, 'stay_end', '2026-11-16');
      userSets(form, 'photos', ['8f0c6c1e-4b7a-4d55-9d1a-0c1f9a3e7b21']);
      await c.send('add the hall');

      final context = server.chats.last['context'] as Map<String, dynamic>;
      expect(context['open_forms'], [
        {
          'form_id': 'return_request',
          'values': {
            'rooms': ['kitchen', 'hall'],
            'stay_start': '2026-11-10',
            'stay_end': '2026-11-16',
            'photos': ['8f0c6c1e-4b7a-4d55-9d1a-0c1f9a3e7b21'],
          },
          'edited': ['rooms', 'stay_end', 'photos'],
        },
      ]);
      expect(
        schemaErrors(context, chatRequestSchema['properties']['context'] as Map),
        isEmpty,
        reason: 'what the server accepts',
      );
      c.dispose();
    });

    test('a form without a form_id is not listed', () async {
      final form = returnForm();
      (form['props'] as Map).remove('form_id');
      final server = _Server([
        [form],
        [_text('b1', 'Sure.')],
      ]);
      final c = controller(server);

      await c.send('return');
      await c.send('next');

      expect(server.chats.last['context'], isNull);
      c.dispose();
    });
  });

  group('the form widget', () {
    final dispatch = RendelDispatcher(
      onAction: (_) async => true,
      onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
      canHandle: (_) => true,
    );

    Future<WireBlock> pump(WidgetTester tester, Map<String, dynamic> props) async {
      final block = WireBlock(
        id: 'b_form',
        type: 'form',
        fallbackText: 'A form.',
        props: props,
      )..ready = true;
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) =>
                      ComponentRegistry.build(context, block, dispatch),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      return block;
    }

    Map<String, dynamic> props() => {
          'form_id': 'return_request',
          'fields': [
            {'name': 'order', 'label': 'Order', 'kind': 'text', 'value': '1042'},
            {'name': 'note', 'label': 'Note', 'kind': 'text'},
          ],
        };

    testWidgets('typing marks the field edited, and only that one',
        (tester) async {
      final block = await pump(tester, props());

      await tester.enterText(find.byType(TextField).last, 'Too small');

      expect(block.props[RendelLocalKeys.values],
          {'order': '1042', 'note': 'Too small'});
      expect(block.props[RendelLocalKeys.edited], {'note'});
      expect(block.props[RendelLocalKeys.focused], 'note');
    });

    testWidgets('a replacing form takes the keyboard where it was',
        (tester) async {
      await pump(tester, props()..[RendelLocalKeys.refocus] = 'note');
      await tester.pump();

      final note = tester.widget<TextField>(find.byType(TextField).last);
      expect(note.focusNode?.hasFocus, isTrue);
      final order = tester.widget<TextField>(find.byType(TextField).first);
      expect(order.focusNode?.hasFocus, isFalse);
    });
  });
}

Map<String, dynamic> _block(String id, String type, Map<String, dynamic> props) =>
    {'id': id, 'type': type, 'fallback_text': 'A $type block.', 'props': props};

Map<String, dynamic> _text(String id, String markdown) =>
    _block(id, 'text', {'markdown': markdown});

/// A turn that asks the device to run a read action instead of a block.
Map<String, dynamic> _action(String invocationId, String name) =>
    {'action': invocationId, 'name': name};

/// The API, answering each `/v1/chat` with the next scripted turn: its blocks
/// in order, then `turn.end`. A turn holding an action entry ends awaiting its
/// result instead.
class _Server extends http.BaseClient {
  _Server(this.turns);

  final List<List<Map<String, dynamic>>> turns;
  final List<Map<String, dynamic>> chats = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body =
        jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    chats.add(body);
    final turn = turns[chats.length - 1];
    var seq = 0;
    String frame(Map<String, dynamic> data) =>
        'event: ${data['type']}\ndata: ${jsonEncode({'v': 1, 'seq': seq++, ...data})}\n\n';
    var awaiting = false;
    final sse = StringBuffer(frame({
      'type': 'turn.start',
      'conversation_id': 'c1',
      'message_id': 'm${chats.length}',
      'model': 'test',
    }));
    for (var i = 0; i < turn.length; i++) {
      final entry = turn[i];
      if (entry.containsKey('action')) {
        awaiting = true;
        sse.write(frame({
          'type': 'action.execute',
          'invocation_id': entry['action'],
          'name': entry['name'],
          'params': <String, dynamic>{},
        }));
        continue;
      }
      sse.write(frame({'type': 'block.ready', 'index': i, 'block': entry}));
    }
    sse.write(frame({
      'type': 'turn.end',
      'status': awaiting ? 'awaiting_tool_results' : 'completed',
      'pending': <String>[],
    }));
    return http.StreamedResponse(
        Stream.value(utf8.encode(sse.toString())), 200);
  }
}
