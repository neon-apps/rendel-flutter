// Catalog wave 4 on the device (`design/CATALOG-B4.md`).
//
// contact opens the app's own channels and does nothing more; rating is
// answered with a tap and recorded through `/v1/ratings` with no turn, a
// comment after it, a fold, and a retry when the post fails; disclosure folds
// detail away; checklist ticks on the device and offers its finishing button
// only once every step is ticked; timeline sets planned things under day
// headings on a rail. Every fixture here is held to the protocol's own wire
// schema, as the gallery's and the overflow suite's are.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/batteries.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'wire_schema.dart';

/// The device's launcher, which remembers what it was handed and refuses to
/// be asked whether it can open something: the SDK must not ask.
class _Launcher extends UrlLauncherPlatform {
  final List<(String, PreferredLaunchMode)> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) => throw StateError('canLaunchUrl was asked');

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    return true;
  }
}

/// A server the test answers by hand, which also takes ratings, or refuses
/// them while [takes] is false.
class _Api extends RendelApiClient {
  _Api() : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<Map<String, dynamic>> sent = [];
  final List<Map<String, dynamic>> ratings = [];
  bool takes = true;
  StreamController<RendelWireEvent>? _turn;

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) {
    sent.add(body);
    _turn = StreamController<RendelWireEvent>();
    return _turn!.stream;
  }

  @override
  Future<bool> sendRating(Map<String, dynamic> body) async {
    ratings.add(body);
    return takes;
  }

  Future<void> answer(WidgetTester tester, List<WireBlock> blocks) async {
    await tester.runAsync(() async {
      for (final event in [
        TurnStart(conversationId: 'c1', messageId: 'm${sent.length}', model: 'test'),
        for (var i = 0; i < blocks.length; i++) BlockReady(index: i, block: blocks[i]),
        const TurnEnd(status: 'completed', pending: []),
      ]) {
        _turn!.add(event);
      }
      await _turn!.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
  }
}

Map<String, dynamic> _wire(String type, Map<String, dynamic> props, {String? id}) => {
      'id': id ?? 'b_$type',
      'type': type,
      'fallback_text': 'A $type block.',
      'props': props,
    };

WireBlock _block(Map<String, dynamic> wire) => WireBlock.tryParse(jsonDecode(jsonEncode(wire)))!;

final _support = _wire('contact', {
  'title': 'Talk to our support team',
  'body': 'They can change an order that has already shipped.',
  'channels': [
    {'kind': 'call', 'label': 'Call', 'value': '+90 850 222 00 00'},
    {'kind': 'email', 'label': 'Email', 'value': 'help@kicks.example'},
    {'kind': 'url', 'label': 'Open the help centre', 'value': 'https://example.com/help'},
  ],
  'hours_label': 'Weekdays 9:00–18:00',
});

Map<String, dynamic> _rating(String scale, {bool comment = false}) => _wire(
      'rating',
      {
        'question': 'How was your delivery?',
        'scale': scale,
        if (scale != 'thumbs') 'low_label': 'Poor',
        if (scale != 'thumbs') 'high_label': 'Great',
        if (comment) 'comment': {'placeholder': 'What could be better?'},
      },
      id: 'b_rating_$scale',
    );

Map<String, dynamic> _faq({bool single = false}) => _wire('disclosure', {
      'items': [
        {'title': 'What is the return window?', 'body': '30 days from delivery.'},
        {'title': 'Who pays for the return?', 'body': 'We do, with the label in your email.'},
        {'title': 'How long does a refund take?', 'body': 'Five working days.'},
      ],
      if (single) 'single_open': true,
    });

final _modem = _wire('checklist', {
  'title': 'Get the internet back',
  'items': [
    {'id': 'unplug', 'title': 'Unplug the modem for 30 seconds', 'done': true},
    {'id': 'light', 'title': 'Check the DSL light is steady', 'body': 'It blinks while it connects.'},
    {'id': 'wifi', 'title': "Restart your phone's Wi-Fi", 'due_label': 'Today'},
  ],
  'on_complete': {'label': 'Still not working', 'reply_text': 'I did all three and it still does not work.'},
});

final _weekend = _wire('timeline', {
  'title': 'Race weekend',
  'groups': [
    {'label': 'Saturday'},
    {'label': 'Sunday'},
  ],
  'items': [
    {'group_index': 1, 'time_label': '09:00', 'title': 'Start', 'subtitle': 'Museumplein', 'icon': 'location'},
    {
      'group_index': 0,
      'time_label': '11:00',
      'title': 'Bib pick-up',
      'action': {'kind': 'reply', 'text': 'Where do I pick up my bib?'},
    },
    {'time_label': 'Fri', 'title': 'Pack the bag'},
    {'group_index': 0, 'time_label': '17:30', 'title': 'Shakeout run', 'subtitle': '5 km, easy'},
  ],
});

void main() {
  late _Launcher launcher;

  setUp(() {
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
  });

  ConversationController controller(_Api api) => ConversationController(
        api: api,
        actions: const {},
        sdkVersion: 'flutter/test',
        // The SDK's own link opener, as `Rendel.init` wires it.
        onOpenUrl: openLink,
      );

  final theme = RendelTheme.paper();

  /// [blocks] in a scrolling list, tapping through the real controller.
  Future<ConversationController> pump(WidgetTester tester, List<Map<String, dynamic>> blocks, [_Api? api]) async {
    final c = controller(api ?? _Api());
    addTearDown(c.dispose);
    final dispatch = RendelDispatcher(
      onAction: c.tapAction,
      onSubmitForm: c.submitForm,
      canHandle: c.handles,
      onRate: (block, score, {comment}) => c.rate(block, score, comment: comment),
    );
    final drawn = blocks.map(_block).toList();
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: theme,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final block in drawn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  /// A thread whose answer is [block], drawn on its page: the rating's own
  /// path, which needs the turn's `message_id`.
  Future<(ConversationController, _Api)> answered(WidgetTester tester, Map<String, dynamic> block) async {
    final api = _Api();
    final c = controller(api);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(theme: theme, child: Scaffold(body: ThreadScreen(controller: c))),
      ),
    );
    await tester.runAsync(() async {
      unawaited(c.send('How did it go?'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await api.answer(tester, [_block(block)]);
    await tester.pump(const Duration(seconds: 1));
    return (c, api);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsLabel(label));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    // Twice: the block's own size settles first, and the page's around it
    // only after.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  SemanticsNode node(WidgetTester tester, String label) => tester.getSemantics(find.bySemanticsLabel(label));

  test('the handshake declares the five', () async {
    final api = _Api();
    final c = controller(api);
    unawaited(c.send('hello'));
    await Future<void>.delayed(Duration.zero);
    final client = api.sent.single['client'] as Map<String, dynamic>;
    expect(client['components'], containsAll(['contact', 'rating', 'disclosure', 'checklist', 'timeline']));
    // An email is the contact block's own; the server never sends one.
    expect(client['actions'], isNot(contains('email')));
    c.dispose();
  });

  group('contact', () {
    testWidgets('each channel opens its own app with its value, and nothing is sent', (tester) async {
      final api = _Api();
      await pump(tester, [_support], api);
      expect(find.text('Talk to our support team'), findsOneWidget);
      expect(find.text('Weekdays 9:00–18:00'), findsOneWidget);
      // The first lit, the rest quiet.
      bool quiet(String label) => tester
          .widget<RendelActionButton>(find.ancestor(of: find.text(label), matching: find.byType(RendelActionButton)))
          .quiet;
      expect(quiet('Call +90 850 222 00 00'), isFalse);
      expect(quiet('Email help@kicks.example'), isTrue);
      expect(quiet('Open the help centre'), isTrue);

      await tester.tap(find.bySemanticsLabel('Call +90 850 222 00 00'));
      await tester.tap(find.bySemanticsLabel('Email help@kicks.example'));
      await tester.tap(find.bySemanticsLabel('Open the help centre'));
      await tester.pump();
      expect(launcher.launched, [
        ('tel:+908502220000', PreferredLaunchMode.externalApplication),
        ('mailto:help@kicks.example', PreferredLaunchMode.externalApplication),
        ('https://example.com/help', PreferredLaunchMode.inAppBrowserView),
      ]);
      expect(api.sent, isEmpty, reason: 'no turn');
    });

    testWidgets('a link this build cannot open is drawn, as no button', (tester) async {
      final c = ConversationController(api: _Api(), actions: const {}, sdkVersion: 'flutter/test');
      addTearDown(c.dispose);
      final dispatch = RendelDispatcher(onAction: c.tapAction, onSubmitForm: c.submitForm, canHandle: c.handles);
      final block = _block(_support);
      await tester.pumpWidget(MaterialApp(
        home: RendelThemeScope(
          theme: theme,
          child: Scaffold(body: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch))),
        ),
      ));
      expect(node(tester, 'Open the help centre'), isSemantics(isEnabled: false, hasTapAction: false));
      expect(node(tester, 'Email help@kicks.example'), isSemantics(isEnabled: true, hasTapAction: true));
    });

    test('the mail app is handed the address, and an empty one is not opened', () async {
      final launcher = _Launcher();
      UrlLauncherPlatform.instance = launcher;
      expect(await mail(' help@kicks.example '), isTrue);
      expect(launcher.launched.single, ('mailto:help@kicks.example', PreferredLaunchMode.externalApplication));
      expect(await mail('  '), isFalse);
    });
  });

  group('rating', () {
    for (final (scale, label, score) in [
      ('stars_5', '4 of 5', 4),
      ('thumbs', 'Good', 1),
      ('thumbs', 'Not good', 0),
      ('nps_11', '8', 8),
    ]) {
      testWidgets('$scale: "$label" posts $score at once, with no turn, and folds', (tester) async {
        final (c, api) = await answered(tester, _rating(scale));
        final asked = api.sent.length;
        final messages = c.messages.length;
        expect(node(tester, label), isSemantics(isInMutuallyExclusiveGroup: true, hasCheckedState: true));
        await tap(tester, label);
        expect(api.ratings, [
          {'message_id': 'm1', 'block_id': 'b_rating_$scale', 'score': score},
        ]);
        expect(api.sent.length, asked, reason: 'no chat request');
        expect(c.messages.length, messages, reason: 'no question over the screen');
        expect(c.busy, isFalse);
        expect(find.text('Thanks for telling us'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('^How was your delivery\\?, .*Thanks for telling us\$')), findsOneWidget);
        // Folded for good: nothing left to tap.
        expect(find.bySemanticsLabel(label), findsNothing);
      });
    }

    testWidgets('the scales draw what the brief says', (tester) async {
      // A phone.
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester, [_rating('stars_5'), _rating('thumbs'), _rating('nps_11')]);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
      expect(tester.widget<Icon>(find.byIcon(Icons.star_rounded).first).size, 40);
      final thumb = find.ancestor(of: find.byIcon(Icons.thumb_up_outlined), matching: find.byType(AnimatedContainer));
      expect(tester.getSize(thumb), const Size(52, 52));
      // 0–10 on a phone: two rows, 0–5 over 6–10, and the ends labelled.
      for (var n = 0; n <= 10; n++) {
        expect(find.text('$n'), findsOneWidget);
      }
      expect(tester.getRect(find.text('5')).top, tester.getRect(find.text('0')).top);
      expect(tester.getRect(find.text('6')).top, greaterThan(tester.getRect(find.text('5')).bottom));
      expect(tester.getRect(find.text('6')).left, tester.getRect(find.text('0')).left);
      expect(find.text('Poor'), findsNWidgets(2));
      expect(find.text('Great'), findsNWidgets(2));
    });

    testWidgets('NPS takes one row where eleven fit', (tester) async {
      tester.view.physicalSize = const Size(900 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester, [_rating('nps_11')]);
      expect(tester.getRect(find.text('10')).top, tester.getRect(find.text('0')).top);
    });

    testWidgets('with a comment: the field after the score, then the score again with it', (tester) async {
      final (_, api) = await answered(tester, _rating('thumbs', comment: true));
      expect(find.byType(TextField).hitTestable(), findsOneWidget, reason: 'only the composer');
      await tap(tester, 'Good');
      expect(api.ratings.single, {'message_id': 'm1', 'block_id': 'b_rating_thumbs', 'score': 1});
      // Not folded yet: the field and its quiet Send.
      expect(find.text('Thanks for telling us'), findsNothing);
      final field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'What could be better?');
      expect(field, findsOneWidget);
      expect(node(tester, 'Send'), isSemantics(isEnabled: false));
      await tester.enterText(field, '  The box was crushed.  ');
      await tester.pump();
      expect(node(tester, 'Send'), isSemantics(isEnabled: true, hasTapAction: true));
      await tap(tester, 'Send');
      expect(api.ratings.last, {
        'message_id': 'm1',
        'block_id': 'b_rating_thumbs',
        'score': 1,
        'comment': 'The box was crushed.',
      });
      expect(api.sent.length, 1, reason: 'still no turn');
      expect(find.text('Thanks for telling us'), findsOneWidget);
      expect(field, findsNothing);
    });

    testWidgets('a post that failed says so and can be made again', (tester) async {
      final (_, api) = await answered(tester, _rating('stars_5'));
      api.takes = false;
      await tap(tester, '3 of 5');
      expect(api.ratings, hasLength(1));
      const failed = 'Something failed while finishing that. Try again.';
      expect(find.text(failed), findsOneWidget);
      expect(tester.getSemantics(find.text(failed)), isSemantics(isLiveRegion: true));
      expect(find.text('Thanks for telling us'), findsNothing);
      // Not lit: the server never took it.
      expect(node(tester, '3 of 5'), isSemantics(isChecked: false, hasTapAction: true));
      api.takes = true;
      await tap(tester, '3 of 5');
      expect(api.ratings, hasLength(2));
      expect(api.ratings.last['score'], 3);
      expect(find.text(failed), findsNothing);
      expect(find.text('Thanks for telling us'), findsOneWidget);
    });

    test('a score off the scale, or a block on no turn, is never sent', () async {
      final api = _Api();
      final c = controller(api);
      final loose = _block(_rating('stars_5'));
      expect(await c.rate(loose, 4), isFalse, reason: 'no message holds it');
      c.messages.add(RendelMessage.assistant()
        ..serverId = 'm9'
        ..blocks.add(loose));
      expect(await c.rate(loose, 0), isFalse, reason: 'stars are 1 to 5');
      expect(await c.rate(loose, 6), isFalse);
      expect(api.ratings, isEmpty);
      expect(await c.rate(loose, 5, comment: '   '), isTrue);
      expect(api.ratings.single, {'message_id': 'm9', 'block_id': 'b_rating_stars_5', 'score': 5});
      expect(ratingScores({'scale': 'thumbs'}), [0, 1]);
      expect(ratingScores({'scale': 'nps_11'}), List.generate(11, (i) => i));
      expect(ratingScores({'scale': 'stars_10'}), isEmpty);
      c.dispose();
    });

    test('POST /v1/ratings carries the key, the device and the body as given', () async {
      final requests = <http.Request>[];
      var status = 200;
      final api = RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'device-1',
        config: const RendelConfig(),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'ok': true}), status);
        }),
      );
      final body = {'message_id': 'm1', 'block_id': 'b1', 'score': 9, 'comment': 'Fast'};
      expect(await api.sendRating(body), isTrue);
      final sent = requests.single;
      expect(sent.method, 'POST');
      expect(sent.url.path, '/v1/ratings');
      expect(sent.headers['X-Rendel-Key'], 'nc_pk_test_x');
      expect(sent.headers['X-Rendel-Device'], 'device-1');
      expect(jsonDecode(sent.body), body);
      // `ratingRequest` in packages/protocol/src/chat.ts: a strict object.
      expect(
        (jsonDecode(sent.body) as Map).keys.toSet().difference({'message_id', 'block_id', 'score', 'comment'}),
        isEmpty,
      );
      status = 404;
      expect(await api.sendRating(body), isFalse);
    });
  });

  group('disclosure', () {
    String body(int i) => (_faq()['props']['items'] as List)[i]['body'] as String;
    const titles = ['What is the return window?', 'Who pays for the return?', 'How long does a refund take?'];

    testWidgets('all shut at first; a tap opens and shuts, said as expanded and collapsed', (tester) async {
      await pump(tester, [_faq()]);
      for (var i = 0; i < 3; i++) {
        expect(find.text(body(i)), findsNothing);
        expect(node(tester, titles[i]), isSemantics(hasExpandedState: true, isExpanded: false, onTapHint: 'Show'));
      }
      await tester.tap(find.bySemanticsLabel(titles[0]));
      await tester.pumpAndSettle();
      expect(find.text(body(0)), findsOneWidget);
      expect(node(tester, titles[0]), isSemantics(hasExpandedState: true, isExpanded: true, onTapHint: 'Hide'));
      // Without single_open, another opens beside it.
      await tester.tap(find.bySemanticsLabel(titles[1]));
      await tester.pumpAndSettle();
      expect(find.text(body(0)), findsOneWidget);
      expect(find.text(body(1)), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(titles[0]));
      await tester.pumpAndSettle();
      expect(find.text(body(0)), findsNothing);
      expect(find.text(body(1)), findsOneWidget);
    });

    testWidgets('single_open shuts the others', (tester) async {
      await pump(tester, [_faq(single: true)]);
      await tester.tap(find.bySemanticsLabel(titles[0]));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(titles[2]));
      await tester.pumpAndSettle();
      expect(find.text(body(0)), findsNothing);
      expect(find.text(body(2)), findsOneWidget);
      expect(node(tester, titles[0]), isSemantics(hasExpandedState: true, isExpanded: false));
    });

    testWidgets('the chevron turns, over 220 ms, and at once under reduced motion', (tester) async {
      await pump(tester, [_faq()]);
      await tester.tap(find.bySemanticsLabel(titles[0]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      final half = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation).first);
      expect(half.turns, 0.5);
      expect(half.duration, const Duration(milliseconds: 220));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      final block = _block(_faq());
      final c = controller(_Api());
      addTearDown(c.dispose);
      final dispatch = RendelDispatcher(onAction: c.tapAction, onSubmitForm: c.submitForm, canHandle: c.handles);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: RendelThemeScope(
            theme: theme,
            child: Scaffold(body: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch))),
          ),
        ),
      ));
      await tester.tap(find.bySemanticsLabel(titles[1]));
      await tester.pump();
      expect(find.text(body(1)), findsOneWidget, reason: 'in the first frame');
      expect(find.byType(AnimatedSize), findsNothing);
    });
  });

  group('checklist', () {
    testWidgets('done items start ticked, a tap ticks, and the button waits for all', (tester) async {
      final api = _Api();
      await pump(tester, [_modem], api);
      expect(node(tester, 'Unplug the modem for 30 seconds'), isSemantics(hasCheckedState: true, isChecked: true));
      expect(node(tester, 'Check the DSL light is steady, It blinks while it connects.'),
          isSemantics(hasCheckedState: true, isChecked: false));
      expect(node(tester, "Restart your phone's Wi-Fi, Today"), isSemantics(isChecked: false));
      expect(find.text('Today'), findsOneWidget, reason: 'the due label as a pill');
      TextDecoration? struck(String title) => tester.widget<Text>(find.text(title)).style?.decoration;
      expect(struck('Unplug the modem for 30 seconds'), TextDecoration.lineThrough);
      expect(struck("Restart your phone's Wi-Fi"), isNot(TextDecoration.lineThrough));
      expect(find.text('Still not working'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Check the DSL light is steady, It blinks while it connects.'));
      await tester.pumpAndSettle();
      expect(find.text('Still not working'), findsNothing, reason: 'one still to go');
      await tester.tap(find.bySemanticsLabel("Restart your phone's Wi-Fi, Today"));
      await tester.pumpAndSettle();
      expect(struck("Restart your phone's Wi-Fi"), TextDecoration.lineThrough);
      expect(find.text('Still not working'), findsOneWidget);
      expect(api.sent, isEmpty, reason: 'ticks stay on the device');

      // Untick one and the button goes again.
      await tester.tap(find.bySemanticsLabel('Unplug the modem for 30 seconds'));
      await tester.pumpAndSettle();
      expect(find.text('Still not working'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Unplug the modem for 30 seconds'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.bySemanticsLabel('Still not working'));
        await Future<void>.delayed(Duration.zero);
      });
      expect((api.sent.single['message'] as Map)['text'], 'I did all three and it still does not work.');
    });

    testWidgets('the ticks are kept with the block when it is drawn again', (tester) async {
      final block = _block(_modem);
      final c = controller(_Api());
      addTearDown(c.dispose);
      final dispatch = RendelDispatcher(onAction: c.tapAction, onSubmitForm: c.submitForm, canHandle: c.handles);
      Widget drawn() => MaterialApp(
            home: RendelThemeScope(
              theme: theme,
              child: Scaffold(body: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch))),
            ),
          );
      await tester.pumpWidget(drawn());
      await tester.tap(find.bySemanticsLabel('Unplug the modem for 30 seconds'));
      await tester.tap(find.bySemanticsLabel("Restart your phone's Wi-Fi, Today"));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(drawn());
      expect(node(tester, 'Unplug the modem for 30 seconds'), isSemantics(isChecked: false));
      expect(node(tester, "Restart your phone's Wi-Fi, Today"), isSemantics(isChecked: true));
    });
  });

  group('timeline', () {
    testWidgets('items sit under their day headings, the loose ones first, on a rail', (tester) async {
      await pump(tester, [_weekend]);
      double top(String text) => tester.getRect(find.text(text)).top;
      // As written, never uppercased: Dart has no Turkish capitals.
      expect(find.text('Saturday'), findsOneWidget);
      expect(find.text('SATURDAY'), findsNothing);
      expect(node(tester, 'Saturday'), isSemantics(isHeader: true));
      expect(top('Pack the bag'), lessThan(top('Saturday')));
      expect(top('Saturday'), lessThan(top('Bib pick-up')));
      expect(top('Bib pick-up'), lessThan(top('Shakeout run')));
      expect(top('Shakeout run'), lessThan(top('Sunday')));
      expect(top('Sunday'), lessThan(top('Start')));
      // The time in its own 56 pt column, the title after it.
      expect(tester.getRect(find.text('Bib pick-up')).left - tester.getRect(find.text('11:00')).left,
          greaterThanOrEqualTo(56));
      expect(find.byIcon(Icons.place_outlined), findsOneWidget);

      final rail = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border is BorderDirectional &&
          ((w.decoration as BoxDecoration).border as BorderDirectional).start ==
              BorderSide(color: theme.rail, width: 2));
      expect(rail, findsNWidgets(4), reason: 'one stretch of rail per row');

      // A row with an action is a control; the rest are not.
      expect(node(tester, '11:00, Bib pick-up'), isSemantics(isButton: true, hasTapAction: true));
      expect(find.bySemanticsLabel(RegExp('Shakeout run')), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel(RegExp('Shakeout run'))), isSemantics(isButton: false));
    });
  });

  test('every new string exists in all six languages', () {
    const english = RendelStrings();
    expect(english.ratingThanks, 'Thanks for telling us');
    expect(english.ratingStarsOf(4), '4 of 5');
    expect(english.thumbsUp, 'Good');
    expect(english.thumbsDown, 'Not good');
    expect(english.expand, 'Show');
    expect(english.collapse, 'Hide');
    final turkish = RendelStrings.forLocale('tr');
    expect(turkish.ratingThanks, 'Bildirdiğin için teşekkürler');
    expect(turkish.ratingStarsOf(4), '5 üzerinden 4');
    expect(turkish.thumbsUp, 'İyi');
    expect(turkish.thumbsDown, 'İyi değil');
    expect(turkish.expand, 'Göster');
    expect(turkish.collapse, 'Gizle');
    for (final language in ['tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      for (final (name, said, en) in [
        ('ratingThanks', strings.ratingThanks, english.ratingThanks),
        ('ratingStars', strings.ratingStars, english.ratingStars),
        ('thumbsUp', strings.thumbsUp, english.thumbsUp),
        ('thumbsDown', strings.thumbsDown, english.thumbsDown),
        ('expand', strings.expand, english.expand),
        ('collapse', strings.collapse, english.collapse),
      ]) {
        expect(said, isNot(en), reason: '$name is still English in $language');
      }
      expect(strings.ratingStarsOf(3), contains('3'), reason: language);
      expect(strings.thumbsUp, isNot(strings.thumbsDown), reason: language);
    }
  });

  group('the fixtures', () {
    // The gallery's are held in example/test/gallery_test.dart.
    test('parse against the protocol schema', () {
      for (final wire in [
        _support,
        _rating('stars_5'),
        _rating('thumbs', comment: true),
        _rating('nps_11'),
        _faq(),
        _faq(single: true),
        _modem,
        _weekend,
      ]) {
        expect(wireBlockErrors(wire), isEmpty, reason: '${wire['type']}');
      }
    });

    test('the schema check is a real one', () {
      expect(wireBlockErrors(_wire('rating', {'question': 'x', 'scale': 'stars_10'})), isNotEmpty);
      expect(
        wireBlockErrors(_wire('contact', {
          'title': 'x',
          'channels': [
            {'kind': 'chat', 'label': 'Chat', 'value': 'now'},
          ],
        })),
        isNotEmpty,
        reason: 'no live chat',
      );
      expect(
        wireBlockErrors(_wire('checklist', {
          'items': [
            for (var i = 0; i < 11; i++) {'id': '$i', 'title': 't'},
          ],
        })),
        isNotEmpty,
        reason: 'ten steps at most',
      );
      expect(
        wireBlockErrors(_wire('timeline', {
          'items': [
            {'group_index': 7, 'time_label': '9', 'title': 't'},
          ],
        })),
        isNotEmpty,
        reason: 'seven days at most',
      );
    });
  });
}
