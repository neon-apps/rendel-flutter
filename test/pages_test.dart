import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show readsFlatOnPage;
import 'package:rendel/src/ui/thread_screen.dart';

/// A server the test answers by hand, one event at a time, so the screen can
/// be looked at between them.
///
/// Fed through `runAsync`: the turn loop does not reach its end on the
/// widget tester's fake clock (see `layout_test.dart`).
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

  Future<void> push(
    WidgetTester tester,
    List<RendelWireEvent> events, {
    bool end = false,
  }) async {
    await tester.runAsync(() async {
      events.forEach(_turn!.add);
      if (end) await _turn!.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
  }

  /// The rest of a turn: its blocks, ready, and its end.
  Future<void> answer(WidgetTester tester, List<WireBlock> blocks) => push(
        tester,
        [
          TurnStart(conversationId: 'c1', messageId: 'm${sent.length}', model: 'test'),
          for (var i = 0; i < blocks.length; i++) BlockReady(index: i, block: blocks[i]),
          const TurnEnd(status: 'completed', pending: []),
        ],
        end: true,
      );
}

Future<void> _send(WidgetTester tester, ConversationController c, String text) async {
  await tester.runAsync(() async {
    unawaited(c.send(text));
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}

WireBlock _block(String id, String type, Map<String, dynamic> props) =>
    WireBlock(id: id, type: type, fallbackText: 'A $type block.', props: props)
      ..ready = true;

WireBlock _text(String id, String markdown) =>
    _block(id, 'text', {'markdown': markdown});

/// The design brief's tests for answer pages (`design/PAGES.md`).
void main() {
  ConversationController controller(RendelApiClient api) => ConversationController(
        api: api,
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  ConversationController offline() => controller(RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
      ));

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

  /// Past every arrival, fade and dissolve a page plays.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> ask(
    WidgetTester tester,
    ConversationController c,
    _LiveApi api,
    String question,
    List<WireBlock> blocks,
  ) async {
    await _send(tester, c, question);
    await api.answer(tester, blocks);
    await settle(tester);
  }

  /// A page drawn from answers the conversation already holds.
  ConversationController seeded(List<WireBlock> blocks) {
    final c = offline();
    c.messages
      ..add(RendelMessage.user('Which shoe should I buy?'))
      ..add(RendelMessage.assistant()..blocks.addAll(blocks));
    return c;
  }

  group('the handshake', () {
    test('says this build draws pages', () async {
      final api = _LiveApi();
      final c = controller(api);
      unawaited(c.send('hello'));
      await Future<void>.delayed(Duration.zero);
      final client = api.sent.single['client'] as Map<String, dynamic>;
      expect(client['capabilities'], contains('answer_pages'));
      c.dispose();
    });

    test('declares section and key_points', () async {
      expect(supportedComponents, containsAll(['section', 'key_points']));
      final api = _LiveApi();
      final c = controller(api);
      unawaited(c.send('hello'));
      await Future<void>.delayed(Duration.zero);
      final client = api.sent.single['client'] as Map<String, dynamic>;
      expect(client['components'], containsAll(['section', 'key_points']));
      c.dispose();
    });
  });

  group('the question', () {
    testWidgets('is never a bubble', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);

      await _send(tester, c, 'Which shoe should I buy?');
      // Written over the screen while it is asked…
      expect(find.text('Which shoe should I buy?'), findsOneWidget);

      await api.answer(tester, [_text('b0', 'The Aero Glide 2.')]);
      await settle(tester);
      // …and once the answer starts, only the small line over it remains
      // (Tuna, 2026-10-11): one line, no bubble.
      expect(find.text('The Aero Glide 2.'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Which shoe should I buy?')).maxLines, 1);
    });

    testWidgets('is revealed a word at a time, unless it was spoken',
        (tester) async {
      // How far the last word has come in: its ink's opacity.
      double lastWord(String question) {
        final text = tester.widget<Text>(find.text(question));
        final words = (text.textSpan! as TextSpan).children!;
        return (words.last as TextSpan).style!.foreground!.color.a;
      }

      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      final heard = Completer<String?>();
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                onDictate: (_) => heard.future,
                onStopDictating: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await _send(tester, c, 'Which shoe should I buy?');
      expect(lastWord('Which shoe should I buy?'), lessThan(0.5));
      await api.answer(tester, [_text('a', 'The Aero Glide 2.')]);
      await settle(tester);

      // Held, as a finger holds it while it speaks.
      await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Speak instead of typing')));
      await tester.pump();
      await tester.runAsync(() async {
        heard.complete('And in size 43?');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();
      expect(lastWord('And in size 43?'), 1);
      await api.answer(tester, const []);
      await settle(tester);
    });

    testWidgets('goes when a turn ends with nothing to show', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);

      await _send(tester, c, 'Anything?');
      expect(find.text('Anything?'), findsOneWidget);
      await api.answer(tester, const []);
      await settle(tester);
      expect(find.text('Anything?'), findsNothing);
    });
  });

  group('the pill', () {
    testWidgets("follows turn.status, and keeps its word for a step it doesn't know",
        (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);

      await _send(tester, c, 'Do you have size 43?');
      expect(find.bySemanticsLabel('Thinking…'), findsOneWidget);

      await api.push(tester, const [
        TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
        TurnStatus(step: 'action', action: 'check_stock'),
      ]);
      expect(find.bySemanticsLabel('Checking your app…'), findsOneWidget);
      expect(find.bySemanticsLabel('Thinking…'), findsNothing);

      await api.push(tester, const [TurnStatus(step: 'daydreaming')]);
      expect(find.bySemanticsLabel('Checking your app…'), findsOneWidget);

      await api.push(tester, const [TurnStatus(step: 'composing')]);
      expect(find.bySemanticsLabel('Putting it together…'), findsOneWidget);

      await api.push(
        tester,
        [
          BlockReady(index: 0, block: _text('b0', 'Yes, size 43 is in stock.')),
          const TurnEnd(status: 'completed', pending: []),
        ],
        end: true,
      );
      await settle(tester);
      expect(find.bySemanticsLabel('Putting it together…'), findsNothing);
      expect(c.turnStatus, isNull, reason: 'the next turn starts thinking again');
    });

    test('turn.status parses, unknown steps included', () {
      final event = RendelWireEvent.tryParse('turn.status', {
        'v': 1,
        'seq': 3,
        'type': 'turn.status',
        'step': 'action',
        'action': 'check_stock',
      });
      expect(event, isA<TurnStatus>());
      expect((event! as TurnStatus).step, 'action');
      expect((event as TurnStatus).action, 'check_stock');
      // Kept as the wire's word, for the controller to ignore.
      expect(
        (RendelWireEvent.tryParse('turn.status', {'step': 'later'})! as TurnStatus).step,
        'later',
      );
      expect(RendelWireEvent.tryParse('turn.status', {'action': 'x'}), isNull);
    });
  });

  group('back and forward', () {
    testWidgets('restore a page without a request', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);

      await ask(tester, c, api, 'First?', [_text('a', 'First answer.')]);
      await ask(tester, c, api, 'Second?', [_text('b', 'Second answer.')]);
      expect(find.text('Second answer.'), findsOneWidget);
      expect(find.text('First answer.'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Next page')),
        isSemantics(isButton: true, isEnabled: false),
      );

      await tester.tap(find.bySemanticsLabel('Previous page'));
      await tester.pump();
      // Instantly, from memory.
      expect(find.text('First answer.'), findsOneWidget);
      expect(find.text('Second answer.'), findsNothing);
      expect(api.sent, hasLength(2));

      await tester.tap(find.bySemanticsLabel('Next page'));
      await tester.pump();
      expect(find.text('Second answer.'), findsOneWidget);
      expect(api.sent, hasLength(2));
    });

    testWidgets('asking from an old page drops the ones after it',
        (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);

      await ask(tester, c, api, 'First?', [_text('a', 'First answer.')]);
      await ask(tester, c, api, 'Second?', [_text('b', 'Second answer.')]);
      await tester.tap(find.bySemanticsLabel('Previous page'));
      await tester.pump();

      await ask(tester, c, api, 'Third?', [_text('c', 'Third answer.')]);
      expect(find.text('Third answer.'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Next page')),
        isSemantics(isEnabled: false),
      );

      await tester.tap(find.bySemanticsLabel('Previous page'));
      await tester.pump();
      expect(find.text('First answer.'), findsOneWidget,
          reason: 'the second page went when the third was asked from the first');
      // The record is not the pages: the conversation still holds all three.
      expect(c.messages.where((m) => m.role == 'assistant'), hasLength(3));
      expect(c.pages, hasLength(2));
    });

    testWidgets('a new conversation starts with none', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await ask(tester, c, api, 'First?', [_text('a', 'First answer.')]);

      c.reset();
      await settle(tester);
      expect(c.pages, isEmpty);
      expect(c.page, -1);
      // No second page, so back and forward are not drawn (QA 2026-10-24).
      expect(find.bySemanticsLabel('Previous page'), findsNothing);
    });
  });

  group('the two blocks', () {
    testWidgets('section and key_points draw, and an unknown icon keeps its column',
        (tester) async {
      final c = seeded([
        _block('s', 'section', {
          'title': 'Why this one',
          'subtitle': 'What matters in the first weeks.',
        }),
        _block('k', 'key_points', {
          'items': [
            {'icon': 'heart', 'title': 'Soft landing', 'body': 'Kind to your joints.'},
            {'icon': 'not_an_icon', 'title': 'Light', 'body': '240 g a shoe.'},
          ],
        }),
      ]);
      addTearDown(c.dispose);
      await pump(tester, c);
      await settle(tester);

      expect(find.text('Why this one'), findsOneWidget);
      // The page's own heading, not an overline.
      expect(
        find.ancestor(of: find.text('Why this one'), matching: find.byType(RendelOverline)),
        findsNothing,
      );
      expect(find.text('What matters in the first weeks.'), findsOneWidget);
      expect(find.text('Kind to your joints.'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_outlined), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Light')).dx,
        tester.getTopLeft(find.text('Soft landing')).dx,
        reason: 'the point with no icon it could draw still lines up',
      );
    });
  });

  testWidgets("a page's first paragraph is its lede", (tester) async {
    final c = seeded([
      _text('a', 'The Aero Glide 2.'),
      _block('s', 'section', {'title': 'Why this one'}),
      _text('b', 'Soft, and in your size.'),
    ]);
    addTearDown(c.dispose);
    await pump(tester, c);
    await settle(tester);

    expect(tester.widget<Text>(find.text('The Aero Glide 2.')).style?.fontSize, 21);
    expect(tester.widget<Text>(find.text('Soft, and in your size.')).style?.fontSize, 15);
  });

  // Tuna, 2026-10-11: the question stays on its answer page, as a small line.
  testWidgets('an answer page keeps its question as one faint line over it', (tester) async {
    final c = seeded([_text('a', 'The Aero Glide 2.')]);
    addTearDown(c.dispose);
    await pump(tester, c);
    await settle(tester);

    final line = tester.widget<Text>(find.text('Which shoe should I buy?'));
    expect(line.maxLines, 1);
    expect(line.overflow, TextOverflow.ellipsis);
    // Above the answer's own first line.
    expect(
      tester.getTopLeft(find.text('Which shoe should I buy?')).dy,
      lessThan(tester.getTopLeft(find.text('The Aero Glide 2.')).dy),
    );
  });

  testWidgets('only the first paragraph of a long opening is the lede (Grove report)', (tester) async {
    final c = seeded([
      _text('a', "I can't give dietary advice.\n\nWhat I can do is show you the label for any snack."),
    ]);
    addTearDown(c.dispose);
    await pump(tester, c);
    await settle(tester);

    expect(tester.widget<Text>(find.text("I can't give dietary advice.")).style?.fontSize, 21);
    expect(tester.widget<Text>(find.text('What I can do is show you the label for any snack.')).style?.fontSize, 15);
  });

  group('a marked phrase', () {
    final marks = find.byWidgetPredicate((w) => '${w.runtimeType}' == '_Marks');

    testWidgets('==x== becomes a highlight in the mark role', (tester) async {
      final c = seeded([_text('t', 'The pick is ==Aero Glide 2==, in your size.')]);
      addTearDown(c.dispose);
      await pump(tester, c);
      await settle(tester);

      expect(find.text('The pick is Aero Glide 2, in your size.'), findsOneWidget);
      expect(find.textContaining('=='), findsNothing);
      expect(marks, findsOneWidget);
      expect(
        tester.renderObject(marks),
        paints..rrect(color: RendelTheme.paper().mark),
      );
    });

    testWidgets('an unclosed == stays literal', (tester) async {
      final c = seeded([_text('t', 'If a == b, then ==this stays as it is.')]);
      addTearDown(c.dispose);
      await pump(tester, c);
      await settle(tester);

      expect(find.text('If a == b, then ==this stays as it is.'), findsOneWidget);
      expect(marks, findsNothing);
    });

    test('the mark role is Toprak mixed into the ground', () {
      final paper = RendelTheme.paper();
      expect(paper.mark,
          Color.lerp(paper.colors.surface, const Color(0xFFB5532B), 0.18));
      final deep = RendelTheme.deep();
      expect(
        deep.mark,
        Color.lerp(deep.colors.surface, const Color(0xFFB5532B), 0.3),
      );
    });
  });

  group('plates on a page', () {
    int plates(WidgetTester tester) {
      final glass = RendelTheme.paper().glass;
      return tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .where((box) => (box.decoration as BoxDecoration?)?.color == glass)
          .length;
    }

    final blocks = [
      _block('kv', 'key_value', {
        'rows': [
          {'label': 'Size', 'value': '43'},
        ],
      }),
      _block('form', 'form', {
        'form_id': 'size',
        'fields': [
          {'name': 'size', 'label': 'Size', 'kind': 'number'},
        ],
        'submit_label': 'Send',
      }),
    ];

    testWidgets('a readout lies flat and a question keeps its plate',
        (tester) async {
      final c = seeded(blocks);
      addTearDown(c.dispose);
      await pump(tester, c);
      await settle(tester);
      expect(find.text('43'), findsOneWidget);
      expect(plates(tester), 1, reason: "only the form's");
    });

    test('the blocks that ask keep it', () {
      for (final type in [
        'confirm_card',
        'form',
        'booking_card',
        'datetime_slots',
        'variant_picker',
      ]) {
        expect(readsFlatOnPage(type), isFalse, reason: type);
      }
      for (final type in [
        'text',
        'section',
        'key_points',
        'key_value',
        'stat_group',
        'chart',
        'table',
        'article_card',
        'item_list',
        'progress',
        'order_tracker',
        'receipt',
        'quick_replies',
        'status_banner',
        'info_card',
      ]) {
        expect(readsFlatOnPage(type), isTrue, reason: type);
      }
    });
  });

  testWidgets('the way on asks the whole question', (tester) async {
    final api = _LiveApi();
    final c = controller(api);
    addTearDown(c.dispose);
    await pump(tester, c);
    await ask(tester, c, api, 'Which shoe?', [
      _text('t', 'The Aero Glide 2.'),
      _block('q', 'quick_replies', {
        'title': 'Where to from here?',
        'items': [
          {
            'label': 'Add size 43 to my bag',
            'icon': 'bag',
            'action': {'kind': 'reply', 'text': 'Add size 43 to my bag'},
          },
        ],
      }),
    ]);

    expect(find.text('Where to from here?'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsLabel('Add size 43 to my bag'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(
      (api.sent.last['message'] as Map)['text'],
      'Add size 43 to my bag',
    );
    await api.answer(tester, const []);
    await settle(tester);
  });

  test('every new string is in all six languages', () {
    const english = RendelStrings();
    for (final language in ['en', 'tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      final words = {
        'statusThinking': (strings.statusThinking, english.statusThinking),
        'statusAction': (strings.statusAction, english.statusAction),
        'statusComposing': (strings.statusComposing, english.statusComposing),
        'previousPage': (strings.previousPage, english.previousPage),
        'nextPage': (strings.nextPage, english.nextPage),
      };
      for (final MapEntry(key: name, value: (said, inEnglish)) in words.entries) {
        expect(said, isNotEmpty, reason: '$language $name');
        if (language != 'en') {
          expect(said, isNot(inEnglish), reason: '$language $name is still English');
        }
      }
    }
    expect(RendelStrings.forLocale('tr').statusAction, 'Uygulamanda bakılıyor…');
    expect(RendelStrings.forLocale('tr').statusComposing, 'Sayfa hazırlanıyor…');
  });
}
