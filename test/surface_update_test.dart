// Blocks that replace themselves (`surface_update`).
//
// The model names something that will change — a cart, an order — with a
// `surface_id`, and the server numbers each drawing of it. The rules that keep
// one of each on screen live on the device: what is declared, what replaces
// what, what an old drawing arriving late does, and which of the user's
// choices survive. Each is held here through the real client and a fake
// server.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';

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

  /// The cart, as the model draws it at [revision].
  Map<String, dynamic> cart(String id, int? revision, {String total = '£18.00'}) =>
      _surface(_block(id, 'key_value', {
        'title': 'Your cart',
        'rows': [
          {'label': 'Total', 'value': total},
        ],
      }), 'cart', revision);

  Map<String, dynamic> sizes(String id, int revision, List<Map<String, dynamic>> options,
          {String? selectedId}) =>
      _surface(_block(id, 'variant_picker', {
        'label': 'Size',
        if (selectedId != null) 'selected_id': selectedId,
        'options': [
          for (final option in options)
            {...option, 'label': option['id']},
        ],
      }), 'sizes', revision);

  Map<String, dynamic> slots(String id, int revision, List<String> ids) =>
      _surface(_block(id, 'datetime_slots', {
        'slots': [
          for (final slot in ids)
            {'id': slot, 'label': slot},
        ],
      }), 'slots', revision);

  Map<String, dynamic> returnForm(String id, int revision, {String formId = 'return_request'}) =>
      _surface(_block(id, 'form', {
        'form_id': formId,
        'fields': [
          {'name': 'order', 'label': 'Order', 'kind': 'text', 'value': '1042'},
          {'name': 'note', 'label': 'Note', 'kind': 'text'},
        ],
      }), 'return', revision);

  Iterable<WireBlock> blocksIn(ConversationController c) =>
      c.messages.expand((m) => m.blocks);

  final logs = <RendelLogRecord>[];
  setUp(() {
    logs.clear();
    RendelLog.sink = logs.add;
  });
  tearDown(() => RendelLog.sink = null);

  test('every request declares surface_update beside form_update', () async {
    final server = _Server([
      [_text('b0', 'Hi.')],
    ]);
    final c = controller(server);

    await c.send('hello');

    final client = server.chats.single['client'] as Map<String, dynamic>;
    expect(client['capabilities'], ['form_update', 'surface_update', 'answer_pages', 'detail_pages', 'notices', 'card_fill']);
    c.dispose();
  });

  test('a newer revision takes the old one\'s place, where it arrives',
      () async {
    final server = _Server([
      [_text('b0', 'Added.'), cart('b_cart1', 1)],
      [_text('b1', 'Added that too.'), cart('b_cart2', 2, total: '£30.00')],
    ]);
    final c = controller(server);

    await c.send('add the socks');
    await c.send('and the hat');

    expect(c.messages[1].blocks.map((b) => b.id), ['b0'],
        reason: 'the first turn keeps what else it said');
    expect(c.messages.last.blocks.map((b) => b.id), ['b1', 'b_cart2']);
    expect(blocksIn(c).where((b) => b.surfaceId == 'cart'), hasLength(1));
    expect(c.errorText, isNull);
    c.dispose();
  });

  test('a turn left with nothing goes with the drawing it held', () async {
    final server = _Server([
      [cart('b_cart1', 1)],
      [cart('b_cart2', 2)],
    ]);
    final c = controller(server);

    await c.send('add the socks');
    await c.send('and the hat');

    expect(c.messages.map((m) => m.role), ['user', 'user', 'assistant']);
    expect(blocksIn(c).map((b) => b.id), ['local', 'local', 'b_cart2']);
    c.dispose();
  });

  test('a later drawing in the same turn replaces the earlier one', () async {
    final server = _Server([
      [cart('b_cart1', 1), _text('b0', 'One more thing.'), cart('b_cart2', 2)],
    ]);
    final c = controller(server);

    await c.send('add both');

    expect(c.messages.last.blocks.map((b) => b.id), ['b0', 'b_cart2']);
    c.dispose();
  });

  test('a revision no newer than the one shown is dropped and logged',
      () async {
    final server = _Server([
      [cart('b_cart1', 1)],
      [cart('b_cart2', 2)],
      // A retry that delivers the same drawing again.
      [cart('b_cart2_again', 2)],
    ]);
    final c = controller(server);

    await c.send('add the socks');
    await c.send('and the hat');
    await c.send('again');

    expect(blocksIn(c).where((b) => b.surfaceId == 'cart').map((b) => b.id),
        ['b_cart2']);
    final stale = logs.where((r) => r.code == 'surface_stale').single;
    expect(stale.level, RendelLogLevel.debug);
    // The turn did answer; it had nothing new to show, which is not a failure
    // and leaves no empty bubble behind.
    expect(c.errorText, isNull);
    expect(c.messages.map((m) => m.role), ['user', 'user', 'assistant', 'user']);
    c.dispose();
  });

  test('out of order: revision 3 then revision 2 keeps 3', () async {
    final server = _Server([
      [cart('b_cart3', 3, total: '£42.00')],
      [_text('b1', 'Here is your cart.'), cart('b_cart2', 2)],
    ]);
    final c = controller(server);

    await c.send('cart');
    await c.send('cart again');

    final carts = blocksIn(c).where((b) => b.surfaceId == 'cart').toList();
    expect(carts.map((b) => b.id), ['b_cart3']);
    expect(carts.single.revision, 3);
    expect(c.messages.last.blocks.map((b) => b.id), ['b1']);
    expect(logs.map((r) => r.code), contains('surface_stale'));
    c.dispose();
  });

  test('a stale drawing that announced a skeleton takes it back', () async {
    final server = _Server([
      [cart('b_cart2', 2)],
      [_text('b1', 'Still the same.'), {...cart('b_cart1', 1), '_skeleton': true}],
    ]);
    final c = controller(server);

    await c.send('cart');
    await c.send('cart again');

    expect(c.messages.last.blocks.map((b) => b.id), ['b1'],
        reason: 'no skeleton left pulsing where the old drawing would have gone');
    expect(blocksIn(c).every((b) => b.ready), isTrue);
    c.dispose();
  });

  test('a surface_id without a revision is an ordinary block', () async {
    final server = _Server([
      [cart('b_a', null)],
      [cart('b_b', null)],
      [cart('b_c', 1)],
    ]);
    final c = controller(server);

    await c.send('one');
    await c.send('two');
    await c.send('three');

    expect(blocksIn(c).where((b) => b.type == 'key_value').map((b) => b.id),
        ['b_a', 'b_b', 'b_c']);
    expect(logs.where((r) => r.code == 'surface_stale'), isEmpty);
    c.dispose();
  });

  test('reset forgets every revision', () async {
    final server = _Server([
      [cart('b_cart2', 2)],
      [cart('b_cart1', 1)],
    ]);
    final c = controller(server);

    await c.send('cart');
    c.reset();
    await c.send('new conversation');

    expect(blocksIn(c).where((b) => b.surfaceId == 'cart').map((b) => b.id),
        ['b_cart1']);
    c.dispose();
  });

  group('the user\'s choices', () {
    test('a picked size stays picked while the new drawing offers it',
        () async {
      final server = _Server([
        [
          sizes('b_s1', 1, [
            {'id': 'm'},
            {'id': 'l'},
          ]),
        ],
        [
          sizes('b_s2', 2, [
            {'id': 's'},
            {'id': 'm'},
          ]),
        ],
      ]);
      final c = controller(server);

      await c.send('sizes');
      blocksIn(c).last.props[RendelLocalKeys.chosen] = 'm';
      await c.send('add small');

      expect(blocksIn(c).last.id, 'b_s2');
      expect(blocksIn(c).last.props[RendelLocalKeys.chosen], 'm');
      c.dispose();
    });

    test('a picked size that is gone, or sold out, is dropped', () async {
      final server = _Server([
        [
          sizes('b_s1', 1, [
            {'id': 'm'},
            {'id': 'l'},
          ]),
        ],
        [
          sizes('b_s2', 2, [
            {'id': 's'},
            {'id': 'l'},
          ]),
        ],
        [
          sizes('b_s3', 3, [
            {'id': 's'},
            {'id': 'l', 'available': false},
          ]),
        ],
      ]);
      final c = controller(server);

      await c.send('sizes');
      blocksIn(c).last.props[RendelLocalKeys.chosen] = 'm';
      await c.send('no medium');
      expect(blocksIn(c).last.props.containsKey(RendelLocalKeys.chosen), isFalse);

      blocksIn(c).last.props[RendelLocalKeys.chosen] = 'l';
      await c.send('large sold out');
      expect(blocksIn(c).last.id, 'b_s3');
      expect(blocksIn(c).last.props.containsKey(RendelLocalKeys.chosen), isFalse);
      c.dispose();
    });

    test('a redrawn picker with its own selection wins over the old tap',
        () async {
      final server = _Server([
        [
          sizes('b_s1', 1, [
            {'id': 'm'},
            {'id': 'l'},
          ]),
        ],
        [
          sizes('b_s2', 2, [
            {'id': 'm'},
            {'id': 'l'},
          ], selectedId: 'l'),
        ],
      ]);
      final c = controller(server);

      await c.send('sizes');
      blocksIn(c).last.props[RendelLocalKeys.chosen] = 'm';
      await c.send('make it L');

      final picker = blocksIn(c).last;
      expect(picker.id, 'b_s2');
      expect(picker.props.containsKey(RendelLocalKeys.chosen), isFalse,
          reason: 'the tap went up as a reply; the model\'s answer to it wins');
      expect(picker.props['selected_id'], 'l');
      c.dispose();
    });

    test('a chosen slot stays chosen while it is still offered, else goes',
        () async {
      final server = _Server([
        [slots('b_t1', 1, ['09:00', '10:00'])],
        [slots('b_t2', 2, ['10:00', '11:00'])],
        [slots('b_t3', 3, ['11:00'])],
      ]);
      final c = controller(server);

      await c.send('slots');
      blocksIn(c).last.props[RendelLocalKeys.chosen] = '10:00';
      await c.send('later');
      expect(blocksIn(c).last.id, 'b_t2');
      expect(blocksIn(c).last.props[RendelLocalKeys.chosen], '10:00');

      await c.send('later still');
      expect(blocksIn(c).last.id, 'b_t3');
      expect(blocksIn(c).last.props.containsKey(RendelLocalKeys.chosen), isFalse);
      c.dispose();
    });

    test('a block of another type carries nothing over', () async {
      final server = _Server([
        [slots('b_t1', 1, ['09:00'])],
        [_surface(_block('b_card', 'info_card', {'title': 'Booked'}), 'slots', 2)],
      ]);
      final c = controller(server);

      await c.send('slots');
      blocksIn(c).last.props[RendelLocalKeys.chosen] = '09:00';
      await c.send('book it');

      expect(blocksIn(c).last.id, 'b_card');
      expect(blocksIn(c).last.props.containsKey(RendelLocalKeys.chosen), isFalse);
      c.dispose();
    });
  });

  group('forms', () {
    test('a form with both ids is merged and replaced once', () async {
      final server = _Server([
        [_text('b0', 'Here.'), returnForm('b_f1', 1)],
        [returnForm('b_f2', 2)],
      ]);
      final c = controller(server);

      await c.send('return');
      final first = blocksIn(c).singleWhere((b) => b.type == 'form');
      (first.props[RendelLocalKeys.values] as Map)['note'] = 'Too small';
      first.props[RendelLocalKeys.edited] = <String>{'note'};
      first.props[RendelLocalKeys.focused] = 'note';
      await c.send('again');

      final forms = blocksIn(c).where((b) => b.type == 'form').toList();
      expect(forms.map((b) => b.id), ['b_f2']);
      expect(forms.single.props[RendelLocalKeys.values],
          {'order': '1042', 'note': 'Too small'});
      expect(forms.single.props[RendelLocalKeys.refocus], 'note');
      expect(c.messages[1].blocks.map((b) => b.id), ['b0']);
      expect(c.messages.map((m) => m.role),
          ['user', 'assistant', 'user', 'assistant']);
      c.dispose();
    });

    test('a stale form never takes the open one\'s place', () async {
      final server = _Server([
        [returnForm('b_f2', 2)],
        [returnForm('b_f1', 1)],
      ]);
      final c = controller(server);

      await c.send('return');
      await c.send('again');

      expect(blocksIn(c).where((b) => b.type == 'form').map((b) => b.id),
          ['b_f2']);
      c.dispose();
    });

    test('a sent form is replaced by its surface\'s next drawing', () async {
      final server = _Server([
        [returnForm('b_f1', 1)],
        [
          _surface(
              _block('b_done', 'info_card', {'title': 'Return requested'}),
              'return',
              2),
        ],
      ]);
      final c = controller(server);

      await c.send('return');
      expect(await c.submitForm('return_request', {'order': '1042'}),
          RendelSubmitOutcome.sent);

      expect(blocksIn(c).where((b) => b.surfaceId == 'return').map((b) => b.id),
          ['b_done']);
      c.dispose();
    });

    test('the keyboard moves to the same field under another form_id',
        () async {
      final server = _Server([
        [returnForm('b_f1', 1)],
        [returnForm('b_f2', 2, formId: 'exchange_request')],
      ]);
      final c = controller(server);

      await c.send('return');
      blocksIn(c).last.props[RendelLocalKeys.focused] = 'note';
      await c.send('exchange instead');

      final forms = blocksIn(c).where((b) => b.type == 'form').toList();
      expect(forms.map((b) => b.id), ['b_f2']);
      expect(forms.single.props[RendelLocalKeys.refocus], 'note');
      c.dispose();
    });
  });

  testWidgets('a tapped size goes to the sender as a pick on its block',
      (tester) async {
    final block = WireBlock.tryParse(sizes('b_s1', 1, [
      {'id': 'm'},
      {'id': 'l'},
    ]))!;
    final taps = <(WireBlock, String, String)>[];
    final dispatch = RendelDispatcher(
      onAction: (_) async => true,
      onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
      canHandle: (_) => true,
      onSelect: (block, id, shown) async {
        taps.add((block, id, shown));
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: Builder(
              builder: (context) =>
                  ComponentRegistry.build(context, block, dispatch),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('l'));
    await tester.pump();

    expect(taps.single.$1, same(block));
    expect(taps.single.$2, 'l');
    expect(taps.single.$3, 'Size: l');
  });
}

Map<String, dynamic> _block(String id, String type, Map<String, dynamic> props) =>
    {'id': id, 'type': type, 'fallback_text': 'A $type block.', 'props': props};

Map<String, dynamic> _surface(
        Map<String, dynamic> block, String surfaceId, int? revision) =>
    {...block, 'surface_id': surfaceId, if (revision != null) 'revision': revision};

Map<String, dynamic> _text(String id, String markdown) =>
    _block(id, 'text', {'markdown': markdown});

/// The API, answering each `/v1/chat` with the next scripted turn: its blocks
/// in order, then `turn.end`. A block marked `_skeleton` is announced with
/// `block.start` before it arrives.
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
    final sse = StringBuffer(frame({
      'type': 'turn.start',
      'conversation_id': 'c1',
      'message_id': 'm${chats.length}',
      'model': 'test',
    }));
    for (var i = 0; i < turn.length; i++) {
      final entry = {...turn[i]};
      if (entry.remove('_skeleton') == true) {
        sse.write(frame({
          'type': 'block.start',
          'index': i,
          'id': entry['id'],
          'block_type': entry['type'],
        }));
      }
      sse.write(frame({'type': 'block.ready', 'index': i, 'block': entry}));
    }
    sse.write(frame({
      'type': 'turn.end',
      'status': 'completed',
      'pending': <String>[],
    }));
    return http.StreamedResponse(
        Stream.value(utf8.encode(sse.toString())), 200);
  }
}
