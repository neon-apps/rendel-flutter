// The confirm card, in the two states nothing else exercised.
//
// Both defects here shipped green: the resolved card is only reachable through
// a local key the server never sends, so no schema-derived fixture produced
// it, and expiry is a clock rather than a prop. A card that overflows by 122px
// or draws a live accent button over a dead invocation is the worst thing in
// the catalog to get wrong, so it gets its own suite.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';

void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  Future<void> pump(
    WidgetTester tester,
    Map<String, dynamic> props, {
    double scale = 1.0,
    double width = 320,
  }) async {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) => ComponentRegistry.build(
                    context,
                    WireBlock(
                      id: 'b_confirm',
                      type: 'confirm_card',
                      fallbackText: 'Confirm this?',
                      props: props,
                    )..ready = true,
                    dispatch,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Map<String, dynamic> card({String risk = 'write'}) => {
        'summary': 'Cancel order 1042?',
        'risk': risk,
        'params_display': <Map<String, dynamic>>[],
        'params': <String, dynamic>{'order_id': '1042'},
        'confirm': {'kind': 'reply', 'text': 'yes'},
        'cancel': {'kind': 'reply', 'text': 'no'},
      };

  group('resolved card fits the phone it settles on', () {
    // "Not confirmed" beside its mark is a Row of two children, and the label
    // had no flex share: at the top OS font scale it ran 122px past a 320pt
    // screen, on every width a phone ships in.
    for (final resolution in ['confirmed', 'declined']) {
      for (final scale in [1.0, 1.6, 2.0]) {
        testWidgets('$resolution @$scale', (tester) async {
          await pump(
            tester,
            card()..[RendelLocalKeys.resolved] = resolution,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // Grove report P0-2: a paying card said "Confirm" over raw ids, and every
  // destructive one claimed it could not be undone.
  group('the card in the user\'s terms', () {
    testWidgets('the button says what happens, with the amount', (tester) async {
      await pump(
        tester,
        card(risk: 'destructive')..['confirm_label'] = 'Place order · A\$8.41',
        scale: 2.0,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Place order · A\$8.41'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Go back'), findsOneWidget);
    });

    testWidgets('a destructive card says it cannot be undone by default',
        (tester) async {
      await pump(tester, card(risk: 'destructive'));
      expect(find.text('This cannot be undone'), findsOneWidget);
    });

    testWidgets('an action the app can take back does not claim otherwise',
        (tester) async {
      await pump(tester, card(risk: 'destructive')..['irreversible'] = false);
      expect(find.text('This cannot be undone'), findsNothing);
    });

    // Halden, 2026-10-25: the card the owner wants everywhere. Parity with
    // the web SDK's confirm.test.ts.
    testWidgets('the item\'s picture sits at 64pt beside the sentence, over the rows and two buttons',
        (tester) async {
      const picture = 'https://cdn.halden.example/court-low.jpg';
      final props = card()
        ..['summary'] = 'Add the Court Low to your bag?'
        ..['image_url'] = picture
        ..['confirm_label'] = 'Add to bag'
        ..['params_display'] = [
          {'label': 'Item', 'value': 'Court Low'},
          {'label': 'Size', 'value': '42'},
          {'label': 'Price', 'value': '€89'},
          {'label': 'Arrives', 'value': 'Thu 29 Oct'},
        ];
      for (final scale in [1.0, 2.0]) {
        await pump(tester, props, scale: scale);
        expect(tester.takeException(), isNull);
      }
      final image = find.byWidgetPredicate((w) {
        if (w is! Image) return false;
        final provider = w.image;
        final inner = provider is ResizeImage ? provider.imageProvider : provider;
        return inner is NetworkImage && inner.url == picture;
      });
      expect(image, findsOneWidget);
      expect(tester.getSize(image), const Size(64, 64));
      // Beside the sentence, in one row, not above it.
      final summary = find.text('Add the Court Low to your bag?');
      expect(find.ancestor(of: image, matching: find.byType(Row)).evaluate().toSet()
          .intersection(find.ancestor(of: summary, matching: find.byType(Row)).evaluate().toSet()), isNotEmpty);
      for (final value in ['Court Low', '42', '€89', 'Thu 29 Oct']) {
        expect(find.text(value), findsOneWidget);
      }
      expect(find.text('Add to bag'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);
    });

    testWidgets('no picture, no thumbnail', (tester) async {
      await pump(tester, card());
      expect(find.byType(Image), findsNothing);
      expect(find.text('Cancel order 1042?'), findsOneWidget);
    });

    testWidgets('a long value is read whole, at any scale', (tester) async {
      final props = card()
        ..['params_display'] = [
          {
            'label': 'Message',
            'value':
                'My order arrived with the yoghurt split open and the bag soaked through, please refund it',
          },
        ];
      for (final scale in [1.0, 2.0]) {
        await pump(tester, props, scale: scale);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('expiry', () {
    testWidgets('a passed deadline replaces the buttons', (tester) async {
      await pump(
        tester,
        card()
          ..['expires_at'] = DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
      );
      expect(find.text('Expired'), findsOneWidget);
      // The controller would refuse the invocation anyway; the point is that
      // the user is never offered the press in the first place.
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Go back'), findsNothing);
    });

    testWidgets('a live deadline leaves the card confirmable', (tester) async {
      await pump(
        tester,
        card()
          ..['expires_at'] =
              DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      );
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Expired'), findsNothing);
    });

    testWidgets('the deadline passing while the card is on screen flips it',
        (tester) async {
      await pump(
        tester,
        card()
          ..['expires_at'] = DateTime.now()
              .add(const Duration(seconds: 30))
              .toIso8601String(),
      );
      expect(find.text('Confirm'), findsOneWidget);
      // No unrelated event redraws the thread while the user sits and reads,
      // so the card has to watch its own clock.
      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
    });

    testWidgets('an already-resolved card outranks its deadline',
        (tester) async {
      await pump(
        tester,
        card()
          ..[RendelLocalKeys.resolved] = 'confirmed'
          ..['expires_at'] = DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
      );
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Expired'), findsNothing);
    });

    testWidgets('an unparseable deadline is not an expired card',
        (tester) async {
      await pump(tester, card()..['expires_at'] = 'next tuesday');
      expect(find.text('Confirm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('abandonment', () {
    testWidgets('a card the user walked past says so', (tester) async {
      await pump(tester, card()..[RendelLocalKeys.resolved] = 'abandoned');
      expect(find.text('Not answered'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Go back'), findsNothing);
    });

    testWidgets('an abandoned destructive card releases its raised edge',
        (tester) async {
      // Nothing left to warn about, the same reason a resolved one does.
      await pump(
        tester,
        card(risk: 'destructive')..[RendelLocalKeys.resolved] = 'abandoned',
        scale: 2.0,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Not answered'), findsOneWidget);
    });

    testWidgets('abandonment outranks a deadline still ticking',
        (tester) async {
      await pump(
        tester,
        card()
          ..[RendelLocalKeys.resolved] = 'abandoned'
          ..['expires_at'] =
              DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      );
      expect(find.text('Not answered'), findsOneWidget);
      expect(find.text('Expired'), findsNothing);
    });
  });

  group('who carries out the confirmed action', () {
    // A console action that changes something runs on the server, as the
    // signed-in user, once the tap is recorded. The device has nothing to run,
    // so it must neither look for a handler nor refuse for want of one — and
    // the continuation that tells the server to go ahead is the request that
    // has to carry the user's token.
    Map<String, dynamic> serverCard({bool server = true}) => {
          'invocation_id': 'inv_7',
          'action_name': 'book_class',
          'summary': 'Book Tuesday 09:00?',
          'risk': 'write',
          'params': <String, dynamic>{'class_id': 'c-12'},
          'params_display': <Map<String, dynamic>>[],
          'confirm': {'kind': 'confirm', 'invocation_id': 'inv_7'},
          'cancel': {'kind': 'cancel', 'invocation_id': 'inv_7'},
          if (server) 'executes': 'server',
        };

    ConversationController controller(_Server server) {
      final c = ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: RendelConfig(userToken: () async => 'jwt-person'),
          httpClient: server,
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );
      c.messages.add(RendelMessage.assistant()
        ..blocks.add(WireBlock(
          id: 'b_card',
          type: 'confirm_card',
          fallbackText: 'Book Tuesday 09:00?',
          props: serverCard(server: server.cardRunsOnServer),
        )..ready = true));
      return c;
    }

    test('a server-run card records the tap and continues with no data',
        () async {
      final server = _Server();
      final c = controller(server);

      expect(await c.confirmInvocation('inv_7'), isTrue);

      expect(server.paths, ['/v1/invocations/inv_7/confirm', '/v1/chat']);
      expect(server.decisions, ['confirm']);
      final continuation = server.chats.single;
      expect(continuation.body['tool_results'], [
        {'invocation_id': 'inv_7', 'status': 'success', 'confirmed': true},
      ]);
      expect(continuation.headers['X-Rendel-User-Token'], 'jwt-person');
      expect(c.messages.first.blocks.single.props[RendelLocalKeys.resolved],
          'confirmed');
      expect(c.errorText, isNull);
      expect(c.phase, RendelPhase.idle);
      c.dispose();
    });

    test('it is running the action while the tap is being recorded', () async {
      final server = _Server()..holdDecision = Completer<void>();
      final c = controller(server);

      final confirming = c.confirmInvocation('inv_7');
      await Future<void>.delayed(Duration.zero);
      expect(c.phase, RendelPhase.runningAction);
      expect(await c.confirmInvocation('inv_7'), isFalse,
          reason: 'a second tap must not confirm twice');

      server.holdDecision!.complete();
      await confirming;
      expect(c.phase, RendelPhase.idle);
      expect(server.chats, hasLength(1));
      c.dispose();
    });

    test('an expired confirmation stops there, as for a handler', () async {
      final server = _Server()..decisionStatus = 'expired';
      final c = controller(server);

      expect(await c.confirmInvocation('inv_7'), isTrue);

      expect(server.chats, isEmpty);
      expect(c.errorCode, 'confirmation_expired');
      expect(c.messages.first.blocks.single.props[RendelLocalKeys.resolved],
          'declined');
      expect(c.busy, isFalse);
      c.dispose();
    });

    test('declining a server-run card is an ordinary decline', () async {
      final server = _Server();
      final c = controller(server);

      expect(await c.declineInvocation('inv_7'), isTrue);

      expect(server.decisions, ['decline']);
      expect(server.chats.single.body['tool_results'], [
        {'invocation_id': 'inv_7', 'status': 'declined'},
      ]);
      c.dispose();
    });

    test('a card the device runs, with no handler here, still errors',
        () async {
      final server = _Server()..cardRunsOnServer = false;
      final c = controller(server);

      expect(await c.confirmInvocation('inv_7'), isTrue);

      expect(server.decisions, isEmpty);
      expect(server.chats.single.body['tool_results'], [
        {
          'invocation_id': 'inv_7',
          'status': 'error',
          'error': 'action not registered on this device',
        },
      ]);
      expect(c.messages.first.blocks.single.props[RendelLocalKeys.resolved],
          'declined');
      c.dispose();
    });
  });
}

/// The API, as far as a confirmation reaches it: the confirm endpoint answers
/// with [decisionStatus], and every turn answers one sentence.
class _Server extends http.BaseClient {
  bool cardRunsOnServer = true;
  String decisionStatus = 'confirmed';
  Completer<void>? holdDecision;

  final List<String> paths = [];
  final List<String> decisions = [];
  final List<({Map<String, dynamic> body, Map<String, String> headers})> chats =
      [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    paths.add(path);
    final body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    if (path.endsWith('/confirm')) {
      decisions.add(body['decision'] as String);
      await holdDecision?.future;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'status': decisionStatus}))),
        200,
      );
    }
    chats.add((body: body, headers: request.headers));
    String frame(Map<String, dynamic> data) =>
        'event: ${data['type']}\ndata: ${jsonEncode({'v': 1, ...data})}\n\n';
    final sse = [
      frame({
        'seq': 0,
        'type': 'turn.start',
        'conversation_id': 'c1',
        'message_id': 'm2',
        'model': 'test',
      }),
      frame({
        'seq': 1,
        'type': 'block.ready',
        'index': 0,
        'block': {
          'id': 'b0',
          'type': 'text',
          'fallback_text': 'Done.',
          'props': {'markdown': 'Done.'},
        },
      }),
      frame({
        'seq': 2,
        'type': 'turn.end',
        'status': 'completed',
        'pending': <String>[],
      }),
    ].join();
    return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
  }
}
