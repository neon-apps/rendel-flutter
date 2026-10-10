import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records the URLs handed to the system, as in `catalog_b2_test.dart`.
class _Dialler extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

/// A server the test answers by hand, as in `pages_test.dart`.
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

  Map<String, dynamic> get lastMessage => sent.last['message'] as Map<String, dynamic>;

  Future<void> answer(WidgetTester tester, List<WireBlock> blocks) async {
    await tester.runAsync(() async {
      _turn!
        ..add(TurnStart(conversationId: 'c1', messageId: 'm${sent.length}', model: 'test'))
        ..add(const TurnStatus(step: 'composing'));
      for (var i = 0; i < blocks.length; i++) {
        _turn!.add(BlockReady(index: i, block: blocks[i]));
      }
      _turn!.add(const TurnEnd(status: 'completed', pending: []));
      await _turn!.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
  }
}

WireBlock _block(String id, String type, Map<String, dynamic> props) =>
    WireBlock(id: id, type: type, fallbackText: 'A $type block.', props: props)
      ..ready = true;

Map<String, dynamic> _reply(String text) => {'kind': 'reply', 'text': text};

final _shoes = _block('cards', 'product_cards', {
  'items': [
    {
      'title': 'Aero Glide 2',
      'subtitle': 'Road, soft',
      'price': r'$129',
      'image_url': 'https://example.com/glide.jpg',
      'images': ['https://example.com/glide-top.jpg', 'https://example.com/glide-sole.jpg'],
      'action': _reply('Tell me more about the Aero Glide 2'),
    },
    {
      'title': 'Trail Circuit',
      'subtitle': 'Trail',
      'price': r'$149',
      'image_url': 'https://example.com/trail.jpg',
    },
    {
      'title': 'Court Classic',
      'price': r'$99',
      'action': {'kind': 'open_url', 'url': 'https://example.com/court'},
    },
  ],
});

/// What the server says about the Aero Glide 2.
final _glide = [
  _block('d1', 'text', {'markdown': 'A soft, light road shoe for your first kilometres.'}),
  _block('d2', 'tags', {
    'items': ['Soft', 'For beginners', '43 in stock'],
  }),
  _block('d3', 'actions', {
    'items': [
      {'label': 'Add to cart', 'icon': 'bag', 'action': _reply('Add the Aero Glide 2 in 43 to my cart')},
      {
        'label': 'Open the site',
        'icon': 'link',
        'action': {'kind': 'open_url', 'url': 'https://example.com/glide'},
      },
    ],
  }),
  _block('d4', 'key_points', {
    'items': [
      {'icon': 'heart', 'title': 'Kind to your joints', 'body': 'Thick foam takes the landing.'},
    ],
  }),
  _block('d5', 'section', {'title': 'Specs'}),
  _block('d6', 'key_value', {
    'rows': [
      {'label': 'Drop', 'value': '8 mm'},
      {'label': 'Weight', 'value': '240 g'},
    ],
  }),
];

final _sheet = find.byWidgetPredicate((w) => '${w.runtimeType}' == '_DetailSheet');
final _lit = find.byWidgetPredicate((w) => '${w.runtimeType}' == '_LitAction');

Finder _inSheet(String text) => find.descendant(of: _sheet, matching: find.text(text));

/// The design brief's tests for detail pages (`design/DETAIL.md`).
void main() {
  ConversationController controller(
    RendelApiClient api, {
    Future<void> Function(String url)? onOpenUrl,
  }) =>
      ConversationController(
        api: api,
        actions: const {},
        sdkVersion: 'flutter/test',
        onOpenUrl: onOpenUrl,
      );

  Future<void> pump(WidgetTester tester, ConversationController c) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: ThreadScreen(
              controller: c,
              // A recogniser, so the microphone is drawn.
              onDictate: (_) => Completer<String?>().future,
              onStopDictating: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

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
    await tester.runAsync(() async {
      unawaited(c.send(question));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await api.answer(tester, blocks);
    await settle(tester);
  }

  /// A page of shoes, on screen.
  Future<(ConversationController, _LiveApi)> shoes(
    WidgetTester tester, {
    Future<void> Function(String url)? onOpenUrl,
  }) async {
    final api = _LiveApi();
    final c = controller(api, onOpenUrl: onOpenUrl);
    addTearDown(c.dispose);
    await pump(tester, c);
    await ask(tester, c, api, 'Which shoe should I buy?', [
      _block('lede', 'text', {'markdown': 'Three to choose from.'}),
      _shoes,
    ]);
    return (c, api);
  }

  Future<void> open(WidgetTester tester, String title) async {
    await tester.tap(find.bySemanticsLabel(RegExp('^$title')));
    await tester.pump();
  }

  test('the handshake declares detail_pages, actions and tags', () async {
    final api = _LiveApi();
    final c = controller(api);
    unawaited(c.send('hello'));
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    final declared = api.sent.single['client'] as Map<String, dynamic>;
    expect(declared['capabilities'], contains('detail_pages'));
    expect(declared['components'], containsAll(['actions', 'tags']));
  });

  group('opening a card', () {
    testWidgets('draws its head at once and asks with its own reply',
        (tester) async {
      final (c, api) = await shoes(tester);
      await open(tester, 'Aero Glide 2');

      // Before any answer: the card's own name and what it said of itself.
      expect(_sheet, findsOneWidget);
      expect(_inSheet('Aero Glide 2'), findsOneWidget);
      expect(_inSheet(r'Road, soft · $129'), findsOneWidget);
      expect(find.bySemanticsLabel('Getting the details…'), findsOneWidget);

      expect(api.sent, hasLength(2));
      expect(api.lastMessage['text'], 'Tell me more about the Aero Glide 2');
      expect(api.lastMessage['detail_of'], {
        'title': 'Aero Glide 2',
        'subtitle': 'Road, soft',
        'image_url': 'https://example.com/glide.jpg',
      });
      // No question over the screen: the sheet is the feedback.
      expect(find.text('Tell me more about the Aero Glide 2'), findsNothing);

      await api.answer(tester, _glide);
      await settle(tester);
    });

    testWidgets('a card with no reply of its own asks about itself',
        (tester) async {
      final (c, api) = await shoes(tester);
      await tester.drag(find.bySemanticsLabel(RegExp('^Aero Glide 2')), const Offset(-200, 0));
      await settle(tester);
      await open(tester, 'Trail Circuit');

      expect(_inSheet('Trail Circuit'), findsOneWidget);
      expect(api.lastMessage['text'], 'Tell me about Trail Circuit');
      expect((api.lastMessage['detail_of'] as Map)['title'], 'Trail Circuit');
      await api.answer(tester, const []);
      await settle(tester);
    });

    test('in Turkish the question is Turkish', () {
      expect(
        RendelStrings.forLocale('tr').detailAskAbout('Aero Glide 2'),
        'Aero Glide 2 hakkında bilgi ver',
      );
    });

    testWidgets('an item that is a link still opens the link', (tester) async {
      final opened = <String>[];
      final (c, api) = await shoes(tester, onOpenUrl: (url) async => opened.add(url));
      await tester.drag(find.bySemanticsLabel(RegExp('^Aero Glide 2')), const Offset(-500, 0));
      await settle(tester);
      await open(tester, 'Court Classic');

      expect(opened, ['https://example.com/court']);
      expect(_sheet, findsNothing);
      expect(api.sent, hasLength(1));
    });

    testWidgets('a list item opens too', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await ask(tester, c, api, 'My orders?', [
        _block('list', 'item_list', {
          'items': [
            {'title': 'Order 1042', 'subtitle': 'Two items', 'trailing': '£42.00'},
          ],
        }),
      ]);
      await open(tester, 'Order 1042');

      expect(_inSheet('Two items · £42.00'), findsOneWidget);
      expect(api.lastMessage['detail_of'], {'title': 'Order 1042', 'subtitle': 'Two items'});
      await api.answer(tester, const []);
      await settle(tester);
    });

    /// A call, a copy or an event acts on the device, as a link does. The
    /// web SDK does the same.
    testWidgets('a list row that calls, copies or adds to the calendar does that instead',
        (tester) async {
      final dialler = _Dialler();
      final launcher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = dialler;
      addTearDown(() => UrlLauncherPlatform.instance = launcher);
      final copied = <String>[];
      final native = <MethodCall>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(const MethodChannel('rendel/platform'), (call) async {
        native.add(call);
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(const MethodChannel('rendel/platform'), null);
      });

      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await ask(tester, c, api, 'My courier?', [
        _block('list', 'item_list', {
          'items': [
            {
              'title': 'Courier',
              'action': {'kind': 'call', 'phone': '+31 20 555 0134'},
            },
            {
              'title': 'Tracking number',
              'action': {'kind': 'copy', 'text': '3SABCD1234567'},
            },
            {
              'title': 'Delivery window',
              'action': {
                'kind': 'add_to_calendar',
                'title': 'Delivery',
                'starts_at': '2026-10-14T10:00:00+02:00',
              },
            },
          ],
        }),
      ]);

      for (final title in ['Courier', 'Tracking number', 'Delivery window']) {
        await open(tester, title);
        await tester.pump();
      }

      expect(dialler.launched, ['tel:+31205550134']);
      expect(copied, ['3SABCD1234567']);
      expect(native.single.method, 'addToCalendar');
      expect(_sheet, findsNothing);
      expect(api.sent, hasLength(1), reason: 'no detail was asked for');
    });

    /// Not only a thing with an action: every header opens. The web SDK does
    /// the same.
    for (final (title, asks) in [
      ('Aero Glide 2', 'Tell me about the Aero Glide 2'),
      ('Trail Circuit', 'Tell me about Trail Circuit'),
    ]) {
      testWidgets('a comparison header opens its detail: $title', (tester) async {
        final api = _LiveApi();
        final c = controller(api);
        addTearDown(c.dispose);
        await pump(tester, c);
        await ask(tester, c, api, 'Which is lighter?', [
          _block('cmp', 'comparison', {
            'items': [
              {
                'title': 'Aero Glide 2',
                'price': r'$129',
                'action': _reply('Tell me about the Aero Glide 2'),
              },
              {'title': 'Trail Circuit', 'price': r'$149'},
            ],
            'rows': [
              {'label': 'Weight', 'values': ['248 g', '296 g'], 'best_index': 0},
            ],
          }),
        ]);

        await tester.tap(find.bySemanticsLabel(RegExp('^$title')).first);
        await tester.pump();

        expect(_sheet, findsOneWidget);
        expect(api.sent, hasLength(2));
        expect(api.lastMessage['text'], asks);
        expect((api.lastMessage['detail_of'] as Map)['title'], title);
        await api.answer(tester, const []);
        await settle(tester);
      });
    }
  });

  group('the answer', () {
    testWidgets('is drawn in the sheet, not on the page, and is no page',
        (tester) async {
      final (c, api) = await shoes(tester);
      await open(tester, 'Aero Glide 2');
      await api.answer(tester, _glide);
      await settle(tester);

      for (final text in [
        'A soft, light road shoe for your first kilometres.',
        'For beginners',
        'Kind to your joints',
        'Specs',
        '8 mm',
      ]) {
        expect(_inSheet(text), findsOneWidget, reason: text);
      }
      // The summary is centred.
      expect(
        tester.widget<Text>(_inSheet('A soft, light road shoe for your first kilometres.')).textAlign,
        TextAlign.center,
      );
      expect(c.pages, hasLength(1));
      expect(c.pages.single.blocks.map((b) => b.id), ['lede', 'cards']);

      // Back and forward skip it.
      await tester.tap(find.bySemanticsLabel('Close'));
      await settle(tester);
      expect(_sheet, findsNothing);
      await ask(tester, c, api, 'And for trails?', [
        _block('t', 'text', {'markdown': 'The Trail Circuit.'}),
      ]);
      expect(c.pages, hasLength(2));
      await tester.tap(find.bySemanticsLabel('Previous page'));
      await tester.pump();
      expect(find.text('Three to choose from.'), findsOneWidget);
      expect(_sheet, findsNothing);
      await tester.tap(find.bySemanticsLabel('Next page'));
      await tester.pump();
      expect(find.text('The Trail Circuit.'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Next page')),
        isSemantics(isEnabled: false),
      );
    });

    testWidgets('its first action is lit beside the microphone', (tester) async {
      final (c, api) = await shoes(tester);
      await open(tester, 'Aero Glide 2');
      expect(_lit, findsNothing, reason: 'not before the block is there');
      await api.answer(tester, _glide);
      await settle(tester);

      expect(_lit, findsOneWidget);
      expect(find.descendant(of: _lit, matching: find.text('Add to cart')), findsOneWidget);
      final mic = tester.getRect(find.bySemanticsLabel('Speak instead of typing'));
      final lit = tester.getRect(_lit);
      expect(lit.left, greaterThan(mic.right));
      expect(lit.center.dy, closeTo(mic.center.dy, 1));
    });

    testWidgets('a reply action closes the sheet and opens a new page',
        (tester) async {
      final (c, api) = await shoes(tester);
      await open(tester, 'Aero Glide 2');
      await api.answer(tester, _glide);
      await settle(tester);

      await tester.tap(_lit);
      await tester.pump();
      // The sheet goes first; the question waits for it.
      expect(api.sent, hasLength(2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_sheet, findsNothing);
      expect(api.sent, hasLength(3));
      expect(api.lastMessage['text'], 'Add the Aero Glide 2 in 43 to my cart');
      expect(api.lastMessage.containsKey('detail_of'), isFalse);
      // The usual question over the screen.
      expect(find.text('Add the Aero Glide 2 in 43 to my cart'), findsOneWidget);
      expect(find.bySemanticsLabel('Thinking…'), findsOneWidget);

      await api.answer(tester, [
        _block('done', 'text', {'markdown': 'Added to your cart.'}),
      ]);
      await settle(tester);
      expect(find.text('Added to your cart.'), findsOneWidget);
      expect(c.pages, hasLength(2));
    });
  });

  group('closing', () {
    testWidgets('puts the page back as it was, scroll and all', (tester) async {
      final api = _LiveApi();
      final c = controller(api);
      addTearDown(c.dispose);
      await pump(tester, c);
      await ask(tester, c, api, 'Which shoe should I buy?', [
        _block('lede', 'text', {'markdown': 'Three to choose from.'}),
        for (var i = 0; i < 6; i++) _block('p$i', 'text', {'markdown': 'Paragraph $i. ' * 12}),
        _shoes,
      ]);
      await tester.scrollUntilVisible(
        find.bySemanticsLabel(RegExp('^Aero Glide 2')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      final page = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final before = page.pixels;
      expect(before, greaterThan(0));

      await open(tester, 'Aero Glide 2');
      await api.answer(tester, _glide);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Close'));
      await settle(tester);

      expect(_sheet, findsNothing);
      expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, before);
      expect(find.bySemanticsLabel(RegExp('^Aero Glide 2')), findsOneWidget);
    });

    testWidgets('reopening the same card shows it at once, without a request',
        (tester) async {
      final (c, api) = await shoes(tester);
      await open(tester, 'Aero Glide 2');
      await api.answer(tester, _glide);
      await settle(tester);
      // The system back closes the sheet, not the copilot.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(_sheet, findsNothing);
      expect(find.text('Three to choose from.'), findsOneWidget);

      await open(tester, 'Aero Glide 2');
      expect(_inSheet('A soft, light road shoe for your first kilometres.'), findsOneWidget);
      expect(api.sent, hasLength(2));
    });
  });

  testWidgets('tags and actions draw on a page that is not a detail',
      (tester) async {
    final c = controller(_LiveApi());
    addTearDown(c.dispose);
    c.messages.add(RendelMessage.assistant()..blocks.addAll([_glide[1], _glide[2]]));
    await pump(tester, c);
    await settle(tester);

    expect(find.text('Soft'), findsOneWidget);
    expect(find.text('43 in stock'), findsOneWidget);
    expect(tester.widget<Wrap>(find.ancestor(of: find.text('Soft'), matching: find.byType(Wrap))).alignment,
        WrapAlignment.start);
    final buttons = tester.widgetList<RendelActionButton>(find.byType(RendelActionButton)).toList();
    expect(buttons.map((b) => (b.label, b.quiet)), [('Add to cart', false), ('Open the site', true)]);
  });

  test('every new string is in all six languages', () {
    const english = RendelStrings();
    for (final language in ['en', 'tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      final words = {
        'statusDetail': (strings.statusDetail, english.statusDetail),
        'detailAsk': (strings.detailAsk, english.detailAsk),
        'closeDetail': (strings.closeDetail, english.closeDetail),
      };
      for (final MapEntry(key: name, value: (said, inEnglish)) in words.entries) {
        expect(said, isNotEmpty, reason: '$language $name');
        if (language != 'en') {
          expect(said, isNot(inEnglish), reason: '$language $name is still English');
        }
      }
      expect(strings.detailAsk, contains('{title}'), reason: language);
    }
    expect(english.statusDetail, 'Getting the details…');
    expect(english.detailAskAbout('Aero Glide 2'), 'Tell me about Aero Glide 2');
    expect(english.closeDetail, 'Close');
    expect(RendelStrings.forLocale('tr').statusDetail, 'Ayrıntılar getiriliyor…');
    expect(RendelStrings.forLocale('tr').closeDetail, 'Kapat');
  });
}
