// A question answered by tapping (`design/CHOICE.md`).
//
// A `choice` is answered by id, as a size on a picker is: one pick from
// chips, one or several from a list, an answer written in its `other` row,
// or none at all through its `skip`. Each goes up as a `selection` and is
// asked like any other question, and the block then folds into its answer
// for good. Each rule is held here through the real controller and thread
// screen, with the server answered by hand, as in `selection_test.dart`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// A server the test answers by hand, one event at a time.
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

/// A block as the server sends it, through the same parser.
WireBlock _wire(String id, Map<String, dynamic> props) => WireBlock.tryParse({
      'id': id,
      'type': 'choice',
      'fallback_text': 'A choice.',
      'props': props,
    })!;

WireBlock _surface() => _wire('b_surface', {
      'question': 'Where do you mostly run?',
      'mode': 'single',
      'options': [
        {'id': 'road', 'label': 'Road', 'icon': '🛣️'},
        {'id': 'trail', 'label': 'Trail', 'icon': '⛰️'},
        {'id': 'treadmill', 'label': 'Treadmill'},
      ],
      'skip': {'label': 'No preference'},
    });

WireBlock _items({int? min, int? max}) => _wire('b_items', {
      'question': 'Which ones are you returning?',
      'hint': 'Order #4821',
      'mode': 'multi',
      'options': [
        {'id': 'glide', 'label': 'Aero Glide 2', 'subtitle': '43 · Volt'},
        {'id': 'court', 'label': 'Court Low', 'subtitle': '42 · Bone'},
        {'id': 'socks', 'label': 'Running socks', 'icon': 'bag'},
      ],
      if (min != null) 'min_selected': min,
      if (max != null) 'max_selected': max,
      'submit_label': 'Return',
    });

WireBlock _why() => _wire('b_why', {
      'question': 'Why are you returning it?',
      'mode': 'single',
      'style': 'list',
      'options': [
        {'id': 'size', 'label': 'It does not fit'},
        {'id': 'damaged', 'label': 'It arrived damaged'},
      ],
      'other': {'label': 'Another reason', 'placeholder': 'In a few words'},
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
      unawaited(c.send('Help me choose'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await api.answer(tester, blocks);
    await settle(tester);
  }

  /// Taps [label]'s control, and waits out [lit] on the real clock, which is
  /// the one the controller waits on.
  Future<void> tap(WidgetTester tester, String label, {Duration lit = Duration.zero}) async {
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsLabel(label));
      await Future<void>.delayed(lit);
    });
    await tester.pump();
  }

  const singleLit = Duration(milliseconds: 320);

  SemanticsNode node(WidgetTester tester, String label) =>
      tester.getSemantics(find.bySemanticsLabel(label));

  /// The words the newest question was asked in, which are written over the
  /// screen while it is asked.
  Object? asked(ConversationController c) =>
      c.messages.lastWhere((m) => m.role == 'user').blocks.single.props['markdown'];

  /// The `other` row's field, not the composer's.
  final written = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == 'In a few words',
  );

  test('the handshake declares choice', () async {
    final api = _LiveApi();
    final c = controller(api);
    unawaited(c.send('hello'));
    await Future<void>.delayed(Duration.zero);
    final client = api.sent.single['client'] as Map<String, dynamic>;
    expect(client['components'], contains('choice'));
    c.dispose();
  });

  group('drawing', () {
    testWidgets('a single pick of short words is chips, a radio group across',
        (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await page(tester, c, api, [_surface()]);

      // Side by side: wrapping pills, not rows.
      final road = tester.getRect(find.bySemanticsLabel('Road'));
      final trail = tester.getRect(find.bySemanticsLabel('Trail'));
      expect(trail.top, road.top);
      expect(trail.left, greaterThan(road.right));
      expect(road.height, greaterThanOrEqualTo(46));
      expect(
        node(tester, 'Road'),
        isSemantics(
          hasCheckedState: true,
          isChecked: false,
          isInMutuallyExclusiveGroup: true,
          isButton: false,
          hasTapAction: true,
        ),
      );
      expect(find.text('No preference'), findsOneWidget);
    });

    testWidgets('a subtitle, a picture or several picks make a list of checkboxes',
        (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await page(tester, c, api, [_items()]);

      // Stacked rows, each the list's whole width and at least 64 tall.
      final glide = tester.getRect(find.bySemanticsLabel('Aero Glide 2, 43 · Volt'));
      final court = tester.getRect(find.bySemanticsLabel('Court Low, 42 · Bone'));
      expect(court.top, greaterThanOrEqualTo(glide.bottom));
      expect(court.width, glide.width);
      expect(glide.height, greaterThanOrEqualTo(64));
      expect(
        node(tester, 'Running socks'),
        isSemantics(hasCheckedState: true, isChecked: false, isInMutuallyExclusiveGroup: false),
      );
      expect(find.text('Order #4821'), findsOneWidget, reason: 'the hint');
    });

    testWidgets('style: list makes rows of a single pick too', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await page(tester, c, api, [_why()]);

      final fit = tester.getRect(find.bySemanticsLabel('It does not fit'));
      final damaged = tester.getRect(find.bySemanticsLabel('It arrived damaged'));
      expect(damaged.top, greaterThanOrEqualTo(fit.bottom));
      expect(node(tester, 'It does not fit'), isSemantics(isInMutuallyExclusiveGroup: true));
      expect(find.text('Another reason…'), findsOneWidget);
    });
  });

  group('answering', () {
    testWidgets(
        'a single tap lights at once, then sends its id and asks its label',
        (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      final surface = _surface();
      await page(tester, c, api, [_text('t', 'One thing first.'), surface]);
      final before = api.sent.length;

      await tester.runAsync(() async {
        await tester.tap(find.bySemanticsLabel('Trail'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      // Lit, and not yet sent.
      expect(node(tester, 'Trail'), isSemantics(isChecked: true));
      expect(api.sent, hasLength(before));

      await tester.runAsync(() => Future<void>.delayed(singleLit));
      await tester.pump();
      expect(api.sent.last['selection'], {
        'block_id': 'b_surface',
        'ids': ['trail'],
      });
      expect(api.sent.last.containsKey('message'), isFalse);
      // The question over the screen is what was picked.
      expect(asked(c), 'Trail');
      expect(find.text('Trail'), findsWidgets);

      await api.answer(tester, [_text('t2', 'The Trail Circuit, then.')]);
      await settle(tester);
      expect(find.text('The Trail Circuit, then.'), findsOneWidget);
    });

    testWidgets('multi sends the picked ids from the button, held to min and max',
        (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      final items = _items(min: 2, max: 2);
      await page(tester, c, api, [items]);
      final before = api.sent.length;

      expect(node(tester, 'Return'), isSemantics(isEnabled: false), reason: 'none picked');
      await tap(tester, 'Court Low, 42 · Bone');
      expect(node(tester, 'Court Low, 42 · Bone'), isSemantics(isChecked: true));
      expect(node(tester, 'Return · 1'), isSemantics(isEnabled: false), reason: 'below min');
      // The group, named by the question, says how many are picked.
      expect(find.semantics.byValue('1 of 3 selected'), findsOne);
      expect(
        find.semantics.byValue('1 of 3 selected').evaluate().single,
        isSemantics(label: 'Which ones are you returning?', isLiveRegion: true),
      );

      await tap(tester, 'Aero Glide 2, 43 · Volt');
      // Beyond max, the row does not tick.
      await tap(tester, 'Running socks');
      expect(node(tester, 'Running socks'), isSemantics(isChecked: false));
      expect(api.sent, hasLength(before), reason: 'a multi pick sends only from its button');

      await tap(tester, 'Return · 2');
      expect(api.sent.last['selection'], {
        'block_id': 'b_items',
        'ids': ['court', 'glide'],
      });
      expect(asked(c), 'Court Low, Aero Glide 2');
      await api.answer(tester, const []);
      await settle(tester);
    });

    testWidgets('other opens a field in place, and Send sends ids: [] with other_text',
        (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await page(tester, c, api, [_why()]);

      await tap(tester, 'Another reason…');
      expect(written, findsOneWidget);
      expect(node(tester, 'Send'), isSemantics(isEnabled: false), reason: 'nothing written');

      await tester.enterText(written, '  The colour is off  ');
      await tester.pump();
      await tap(tester, 'Send');
      expect(api.sent.last['selection'], {
        'block_id': 'b_why',
        'ids': <String>[],
        'other_text': 'The colour is off',
      });
      expect(asked(c), 'The colour is off');
      await api.answer(tester, const []);
      await settle(tester);
    });

    testWidgets('skip sends ids: [] and asks the skip label', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await page(tester, c, api, [_surface()]);

      await tap(tester, 'No preference');
      expect(api.sent.last['selection'], {
        'block_id': 'b_surface',
        'ids': <String>[],
      });
      expect(asked(c), 'No preference');
      await api.answer(tester, const []);
      await settle(tester);
    });

    testWidgets('the block folds into its answer, and is still folded on the way back',
        (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await page(tester, c, api, [_surface()]);

      await tap(tester, 'Road', lit: singleLit);
      await api.answer(tester, [_text('t2', 'The Aero Glide 2.')]);
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Previous page'));
      await settle(tester);
      // The question over what was picked, read-only.
      expect(find.text('Where do you mostly run?'), findsOneWidget);
      expect(find.text('Road'), findsOneWidget);
      expect(find.bySemanticsLabel('Trail'), findsNothing);
      expect(find.text('No preference'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // And it cannot be answered again, whatever manages to call it.
      final surface = c.pages.first.blocks.single;
      expect(await c.choose(surface, ['trail'], shown: 'Trail'), isFalse);
    });

    testWidgets('a tap during a turn sends nothing and lights nothing', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      final surface = _surface();
      await page(tester, c, api, [surface]);

      await tester.runAsync(() async {
        unawaited(c.send('Something else'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(c.busy, isTrue);
      final before = api.sent.length;

      await tap(tester, 'Trail', lit: singleLit);
      await tap(tester, 'No preference');
      expect(api.sent, hasLength(before));
      expect(surface.props.containsKey(RendelLocalKeys.chosen), isFalse);
      expect(surface.props.containsKey(RendelLocalKeys.answered), isFalse);
      await api.answer(tester, const []);
      await settle(tester);
    });
  });

  test('the controller sends only an answer the block takes', () async {
    final api = _LiveApi();
    final c = controller(api);
    addTearDown(c.dispose);
    final surface = _surface();
    final items = _items(max: 2);
    final why = _why();

    expect(await c.choose(surface, ['nope'], shown: 'Nope'), isFalse, reason: 'not offered');
    expect(await c.choose(surface, ['road', 'trail'], shown: 'x'), isFalse, reason: 'single');
    expect(await c.choose(surface, const [], shown: 'x', otherText: 'mine'), isFalse,
        reason: 'no other row');
    expect(await c.choose(why, const [], shown: 'x'), isFalse, reason: 'no skip');
    expect(await c.choose(why, const [], shown: 'x', otherText: '   '), isFalse,
        reason: 'nothing written');
    expect(await c.choose(items, const ['glide', 'court', 'socks'], shown: 'x'), isFalse,
        reason: 'beyond max');
    expect(await c.choose(items, const ['glide', 'glide'], shown: 'x'), isFalse,
        reason: 'twice');
    expect(api.sent, isEmpty);
    expect(surface.props.containsKey(RendelLocalKeys.answered), isFalse);
  });

  test('the three strings exist in all six languages', () {
    const english = RendelStrings();
    expect(english.choiceSubmit, 'Continue');
    expect(english.choiceSend, 'Send');
    expect(english.choiceCountOf(2, 5), '2 of 5 selected');
    expect(RendelStrings.forLocale('tr').choiceSubmit, 'Devam');
    expect(RendelStrings.forLocale('tr').choiceSend, 'Gönder');
    expect(RendelStrings.forLocale('tr').choiceCountOf(2, 5), '5 seçenekten 2 tanesi seçili');
    for (final language in ['tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      for (final (name, said, en) in [
        ('choiceSubmit', strings.choiceSubmit, english.choiceSubmit),
        ('choiceSend', strings.choiceSend, english.choiceSend),
        ('choiceCount', strings.choiceCount, english.choiceCount),
      ]) {
        expect(said, isNot(en), reason: '$name is still English in $language');
      }
      expect(strings.choiceCountOf(2, 5), allOf(contains('2'), contains('5')), reason: language);
    }
  });
}
