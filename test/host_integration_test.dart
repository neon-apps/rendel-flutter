// The test a host has to be able to write.
//
// The DX review's sharpest finding was that a customer could not prove their
// own action handler was reachable without hitting the network or importing
// `package:rendel/src/...` — which the reference tells them never to do,
// and which every suite in this package was doing precisely because there was
// no other way. `RendelConfig.httpClient` and `Rendel.resetForTest()` close
// that hole; this file is the proof, written the way a customer would write
// it, importing only the public entry point.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Stands in for the device's browser, and remembers what it was asked to open.
class _Browser extends UrlLauncherPlatform {
  final List<String> opened = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Rendel.resetForTest);

  test('a host can init offline and see its manifest go out', () async {
    final seen = <String, Object?>{};

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/v1/apps/manifest')) {
        seen['manifest'] = jsonDecode(request.body);
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 200);
    });

    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(httpClient: client, remoteConfig: false),
      actions: [
        RendelAction(
          name: 'cancel_order',
          description: 'Cancel an order the user placed',
          params: RendelSchema.object({'order_id': RendelSchema.string()}),
          risk: RendelRisk.destructive,
          handler: (params) async => RendelResult.ok({'status': 'cancelled'}),
        ),
      ],
    );

    // The sync is fire-and-forget on the launch path, so give it a turn of
    // the event loop rather than making `init` slower for every real host.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(Rendel.isInitialized, isTrue);
    final body = seen['manifest'] as Map<String, dynamic>?;
    expect(body, isNotNull,
        reason: 'the SDK never sent a manifest, so the copilot would have '
            'no idea this app can cancel an order');
    final manifest = body!['manifest'] as Map<String, dynamic>;
    final actions = (manifest['actions'] as List).cast<Map<String, dynamic>>();
    expect(actions.map((a) => a['name']), contains('cancel_order'));
    final cancel = actions.firstWhere((a) => a['name'] == 'cancel_order');
    expect(
      (cancel['nc'] as Map<String, dynamic>)['risk'],
      'destructive',
      reason: 'a risk level that does not survive the wire is a guardrail '
          'that does not exist',
    );
    expect(
      (cancel['inputSchema'] as Map<String, dynamic>)['properties'],
      contains('order_id'),
      reason: 'the model is told what to pass by this schema and nothing else',
    );
  });

  // Two people, one phone. The server used to keep the signed-in user as a
  // binding on the device, and a logout did not end it: the next person's
  // turns went into the last one's history. The user rides on the turn now.
  testWidgets('every turn says who is signed in, and a logout ends it',
      (tester) async {
    final identified = <Map<String, dynamic>>[];
    final turns = <Map<String, dynamic>>[];
    String sse(String event, Map<String, Object?> data) =>
        'event: $event\ndata: ${jsonEncode(data)}\n\n';

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/v1/identify')) {
        identified.add(jsonDecode(request.body) as Map<String, dynamic>);
      }
      if (request.url.path.endsWith('/v1/chat')) {
        turns.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          sse('turn.start', {'conversation_id': 'c${turns.length}', 'message_id': 'm'}) +
              sse('turn.end', {'status': 'completed', 'pending': <String>[]}),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return http.Response('{"ok":true}', 200);
    });

    // A restored session, before the copilot is initialised.
    await Rendel.identify(userId: 'ayse', traits: {'plan': 'gold'});
    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(httpClient: client, remoteConfig: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Rendel.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Real async for the turn itself: the mocked stream does not finish under
    // the test clock, and a turn that never ends keeps the composer busy.
    Future<void> say(String text) async {
      await _type(tester, text);
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 400));
    }

    await say('where is my order');
    expect(identified.single['external_user_id'], 'ayse',
        reason: 'an identify before init used to be dropped without a word');
    expect(turns.last['user'], {'id': 'ayse'});

    Rendel.reset();
    await tester.pump(const Duration(milliseconds: 400));
    await say('hello');
    expect(turns.last.containsKey('user'), isTrue,
        reason: 'absent means an old SDK, which the server serves the old way');
    expect(turns.last['user'], isNull);

    await Rendel.identify(userId: 'mehmet');
    await say('and mine?');
    expect(turns.last['user'], {'id': 'mehmet'});
  });

  // `identify` once, at sign-in. 0.13 forgot the user on a relaunch, so every
  // host needed a second call in its session-restore path — code the
  // quickstart does not show.
  testWidgets('a relaunch is still signed in, and a relaunch after a logout is not',
      (tester) async {
    final turns = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/v1/chat')) {
        turns.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          'event: turn.start\ndata: {"conversation_id":"c","message_id":"m"}\n\n'
          'event: turn.end\ndata: {"status":"completed","pending":[]}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return http.Response('{"ok":true}', 200);
    });

    Future<Object?> launchAndSay(String text) async {
      await Rendel.init(
        appKey: 'nc_pk_test_example_000000000000000000000000',
        config: RendelConfig(httpClient: client, remoteConfig: false),
      );
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Rendel.open(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _type(tester, text);
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 400));
      Navigator.of(tester.element(find.byType(TextField))).pop();
      await tester.pump(const Duration(milliseconds: 600));
      return turns.last['user'];
    }

    await Rendel.identify(userId: 'ayse');
    expect(await launchAndSay('hi'), {'id': 'ayse'});

    // A cold start, and the host's session restore calls nothing.
    Rendel.resetForTest(relaunch: true);
    expect(await launchAndSay('still me?'), {'id': 'ayse'});

    Rendel.reset();
    Rendel.resetForTest(relaunch: true);
    expect(await launchAndSay('and now?'), isNull);
  });

  testWidgets('a different person signing in does not inherit the thread',
      (tester) async {
    String sse(String event, Map<String, Object?> data) =>
        'event: $event\ndata: ${jsonEncode(data)}\n\n';
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/v1/chat')) {
        // An answer that repeats what was said, so it is on the page.
        return http.Response(
          sse('turn.start', {'conversation_id': 'c1', 'message_id': 'm'}) +
              sse('block.start', {'index': 0, 'id': 'b1', 'block_type': 'text'}) +
              sse('block.ready', {
                'index': 0,
                'block': {
                  'id': 'b1',
                  'type': 'text',
                  'fallback_text': 'Your address is Moda.',
                  'props': {'markdown': 'Your address is Moda.'},
                },
              }) +
              sse('turn.end', {'status': 'completed', 'pending': <String>[]}),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return http.Response('{"ok":true}', 200);
    });
    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(httpClient: client, remoteConfig: false),
    );
    await Rendel.identify(userId: 'ayse');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Rendel.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _type(tester, 'my address is Moda');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Your address is Moda.'), findsOneWidget);

    // The host forgot `reset()` at the logout.
    await tester.runAsync(() => Rendel.identify(userId: 'mehmet'));
    // A frame to start the swap to the empty state, time for it to finish,
    // and a frame for it to let the old page go.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Your address is Moda.'), findsNothing,
        reason: "Ayşe's thread is not Mehmet's to read on a shared phone");
  });

  test('resetForTest clears actions between tests', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(httpClient: client, remoteConfig: false),
      actions: [
        RendelAction(
          name: 'only_in_the_first_test',
          description: 'Present in the first test and nowhere else',
          params: RendelSchema.object({}),
          risk: RendelRisk.read,
          handler: (_) async => RendelResult.ok({}),
        ),
      ],
    );
    Rendel.resetForTest();
    expect(Rendel.isInitialized, isFalse);
  });

  // A card's link, in an app that wired nothing but `init`. Until 0.20 the
  // button was drawn and did nothing: opening it needed `onOpenUrl`, which
  // the quickstart never mentions.
  testWidgets("a card's link opens with nothing but init", (tester) async {
    final browser = _Browser();
    UrlLauncherPlatform.instance = browser;
    String sse(String event, Map<String, Object?> data) =>
        'event: $event\ndata: ${jsonEncode(data)}\n\n';

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/v1/chat')) {
        return http.Response(
          sse('turn.start', {'conversation_id': 'c', 'message_id': 'm'}) +
              sse('block.start', {'index': 0, 'id': 'b1', 'block_type': 'info_card'}) +
              sse('block.ready', {
                'index': 0,
                'block': {
                  'id': 'b1',
                  'type': 'info_card',
                  'fallback_text': 'High-rise flare jeans',
                  'props': {
                    'title': 'High-rise flare jeans',
                    'cta': {
                      'label': 'Go to the product',
                      'action': {'kind': 'open_url', 'url': 'https://shop.example.com/jeans/42'},
                    },
                  },
                },
              }) +
              sse('turn.end', {'status': 'completed', 'pending': <String>[]}),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return http.Response('{"ok":true}', 200);
    });

    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(httpClient: client, remoteConfig: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Rendel.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _type(tester, 'show me the jeans');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Go to the product'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(browser.opened, ['https://shop.example.com/jeans/42']);
  });
}

/// The composer rests on the "+", the microphone and the keyboard; the
/// keyboard opens the box. One already open has its field.
Future<void> _type(WidgetTester tester, String text) async {
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(find.bySemanticsLabel('Type a message'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextField), text);
}
