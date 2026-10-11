// Picking on a block that offers a choice (`design/INFRA.md`, A1 and A2).
//
// A size on a `variant_picker` or a time on `datetime_slots` goes up as a
// `selection` naming the block and the option by id, never as a sentence, and
// is asked like any other question: the option lights at once, the question
// is written over the screen, then the pill, then a new page. Each rule is
// held here through the real controller and thread screen, with the server
// answered by hand.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// A server the test answers by hand, one event at a time, as in
/// `pages_test.dart`.
class _LiveApi extends RendelApiClient {
  _LiveApi()
      : super(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
        );

  final List<Map<String, dynamic>> sent = [];
  StreamController<RendelWireEvent>? _turn;

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) {
    sent.add(body);
    _turn = StreamController<RendelWireEvent>();
    return _turn!.stream;
  }

  Future<void> push(WidgetTester tester, List<RendelWireEvent> events) async {
    await tester.runAsync(() async {
      events.forEach(_turn!.add);
      await _turn!.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
  }

  Future<void> answer(WidgetTester tester, List<WireBlock> blocks) => push(tester, [
        TurnStart(conversationId: 'c1', messageId: 'm${sent.length}', model: 'test'),
        for (var i = 0; i < blocks.length; i++) BlockReady(index: i, block: blocks[i]),
        const TurnEnd(status: 'completed', pending: []),
      ]);
}

/// A block as the server now sends it: no `action` on any option.
WireBlock _wire(String id, String type, Map<String, dynamic> props) => WireBlock.tryParse({
      'id': id,
      'type': type,
      'fallback_text': 'A $type block.',
      'props': props,
    })!;

WireBlock _sizes({String? label = 'Size'}) => _wire('b_sizes', 'variant_picker', {
      'title': 'Aero Glide 2',
      if (label != null) 'label': label,
      'options': [
        {'id': 'eu-42', 'label': '42'},
        {'id': 'eu-41', 'label': '41', 'available': false},
        {'id': 'eu-43', 'label': '43'},
      ],
    });

WireBlock _slots() => _wire('b_slots', 'datetime_slots', {
      'title': 'Fitting',
      'slots': [
        {'id': 'slot-10', 'label': '10:00', 'starts_at': '2026-09-02T10:00:00Z'},
        {'id': 'slot-any', 'label': 'Any time'},
      ],
    });

WireBlock _text(String id, String markdown) =>
    WireBlock(id: id, type: 'text', fallbackText: markdown, props: {'markdown': markdown})
      ..ready = true;

void main() {
  ConversationController controller(_LiveApi api) => ConversationController(
        api: api,
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  Future<void> pump(WidgetTester tester, ConversationController c) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(body: ThreadScreen(controller: c)),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Asks something, and answers it with [blocks] drawn on a page.
  Future<void> page(
    WidgetTester tester,
    ConversationController c,
    _LiveApi api,
    List<WireBlock> blocks,
  ) async {
    await tester.runAsync(() async {
      unawaited(c.send('Which shoe?'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await api.answer(tester, blocks);
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(text));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  RendelChip chip(WidgetTester tester, String label) => tester.widget<RendelChip>(
        find.ancestor(of: find.text(label), matching: find.byType(RendelChip)),
      );

  test('the handshake declares the action kinds', () async {
    final api = _LiveApi();
    final c = controller(api);
    unawaited(c.send('hello'));
    await Future<void>.delayed(Duration.zero);
    final client = api.sent.single['client'] as Map<String, dynamic>;
    expect(client['actions'], ['reply', 'open_url', 'navigate', 'call', 'copy', 'add_to_calendar']);
    c.dispose();
  });

  testWidgets('the blocks parse without action on their options and draw them live',
      (tester) async {
    final api = _LiveApi();
    final c = controller(api);
    addTearDown(c.dispose);
    await pump(tester, c);
    await page(tester, c, api, [_sizes(), _slots()]);

    expect(chip(tester, '42').onTap, isNotNull);
    expect(chip(tester, '43').onTap, isNotNull);
    expect(chip(tester, '41').onTap, isNull, reason: 'sold out');
    expect(chip(tester, '10:00').onTap, isNotNull);
    expect(chip(tester, 'Any time').onTap, isNotNull);
  });

  testWidgets(
      'tapping an option sends a selection, lights it at once, and asks '
      '"<label>: <option>"', (tester) async {
    final api = _LiveApi();
    final c = controller(api);
    addTearDown(c.dispose);
    await pump(tester, c);
    final sizes = _sizes();
    await page(tester, c, api, [_text('t', 'The Aero Glide 2.'), sizes]);

    await tap(tester, '43');

    final body = api.sent.last;
    expect(body['selection'], {
      'block_id': 'b_sizes',
      'ids': ['eu-43'],
    });
    expect(body.containsKey('message'), isFalse);
    expect(body['turn_id'], isA<String>());
    expect(body['turn_id'], isNot(api.sent.first['turn_id']));
    // Chosen before any answer has come back.
    expect(sizes.props[RendelLocalKeys.chosen], 'eu-43');
    expect(chip(tester, '43').selected, isTrue);
    // The question over the screen, then the pill.
    expect(find.text('Size: 43'), findsOneWidget);
    expect(find.bySemanticsLabel('Thinking…'), findsOneWidget);

    await api.answer(tester, [_text('t2', 'Size 43 is in stock.')]);
    await settle(tester);
    expect(find.text('Size 43 is in stock.'), findsOneWidget);
    // Off the screen, and kept as the page's one faint line (2026-10-11).
    expect(tester.widget<Text>(find.text('Size: 43')).maxLines, 1);
    expect(c.page, 1, reason: 'the answer is a new page');
  });

  testWidgets('a picker with no label asks with the option alone', (tester) async {
    final api = _LiveApi();
    final c = controller(api);
    addTearDown(c.dispose);
    await pump(tester, c);
    await page(tester, c, api, [_sizes(label: null)]);

    await tap(tester, '42');

    expect(find.text('42'), findsNWidgets(2), reason: 'the chip and the question');
    expect(c.messages.lastWhere((m) => m.role == 'user').blocks.single.props['markdown'], '42');
    await api.answer(tester, const []);
    await settle(tester);
  });

  testWidgets('a datetime_slots tap sends its slot id, and asks its day and time',
      (tester) async {
    final api = _LiveApi();
    final c = controller(api);
    addTearDown(c.dispose);
    await pump(tester, c);
    await page(tester, c, api, [_slots()]);

    await tap(tester, '10:00');

    expect(api.sent.last['selection'], {
      'block_id': 'b_slots',
      'ids': ['slot-10'],
    });
    final day = const RendelStrings()
        .dayHeadingFor(DateTime.parse('2026-09-02T10:00:00Z').toLocal());
    expect(find.text('$day, 10:00'), findsOneWidget);
    await api.answer(tester, const []);
    await settle(tester);

    // A slot with no time on it has only its label to say.
    await tap(tester, 'Any time');
    expect(api.sent.last['selection'], {
      'block_id': 'b_slots',
      'ids': ['slot-any'],
    });
    expect(c.messages.lastWhere((m) => m.role == 'user').blocks.single.props['markdown'],
        'Any time');
    await api.answer(tester, const []);
    await settle(tester);
  });

  testWidgets('an unavailable option sends nothing', (tester) async {
    final api = _LiveApi();
    final c = controller(api);
    addTearDown(c.dispose);
    await pump(tester, c);
    final sizes = _sizes();
    await page(tester, c, api, [sizes]);
    final before = api.sent.length;

    await tap(tester, '41');
    expect(api.sent, hasLength(before));
    // Nor does the controller, whatever manages to call it.
    expect(await c.select(sizes, 'eu-41', shown: 'Size: 41'), isFalse);
    expect(await c.select(sizes, 'eu-99', shown: 'Size: 99'), isFalse);
    expect(api.sent, hasLength(before));
    expect(sizes.props.containsKey(RendelLocalKeys.chosen), isFalse);
  });

  test('a tap during a turn sends nothing', () async {
    final api = _LiveApi();
    final c = controller(api);
    final sizes = _sizes();
    unawaited(c.send('hello'));
    await Future<void>.delayed(Duration.zero);
    expect(c.busy, isTrue);

    expect(await c.select(sizes, 'eu-43', shown: 'Size: 43'), isFalse);
    expect(api.sent, hasLength(1));
    expect(sizes.props.containsKey(RendelLocalKeys.chosen), isFalse);
    c.dispose();
  });

  testWidgets('an invalid_request after a selection shows the server\'s message',
      (tester) async {
    final api = _LiveApi();
    final c = controller(api);
    addTearDown(c.dispose);
    await pump(tester, c);
    await page(tester, c, api, [_sizes()]);

    await tap(tester, '43');
    const message = 'That choice has changed. Pick again from the latest one.';
    await api.push(tester, const [
      RendelError(code: 'invalid_request', message: message, retryable: false),
      TurnEnd(status: 'error', pending: []),
    ]);
    await settle(tester);

    expect(c.errorCode, 'invalid_request');
    expect(find.text(message), findsOneWidget);
    expect(c.canRetry, isFalse);
  });
}
