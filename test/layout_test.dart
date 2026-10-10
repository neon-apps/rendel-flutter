// Defects that throw nothing.
//
// `overflow_test.dart` catches a block that paints past its box. This suite
// catches the opposite failure: a block that stays inside its box by clipping
// or squeezing its own content down to something unusable. Flutter is happy,
// the analyzer is happy, and five columns are read through a 22pt window.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

/// Emits a scripted turn so the shell can be measured in a state it only ever
/// reaches through the real `_run` loop.
class _ScriptedApi extends RendelApiClient {
  _ScriptedApi(this.script)
      : super(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
        );

  final List<RendelWireEvent> script;

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) async* {
    for (final event in script) {
      yield event;
    }
  }
}

void main() {
  // Real Roboto, not flutter_test's monospace fallback.
  //
  // The default test font is about one em per glyph, roughly 1.9x wider than
  // Roboto, which makes every width measurement here a different number from
  // the one a user sees. Two defects in this file were found only once a
  // panel lens loaded the real font: a title squeezed to 46pt at the DEFAULT
  // text size, and a retry button reading "Try / ag..." from scale 1.6.
  setUpAll(() async {
    final dir = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.path}'
      '/cache/artifacts/material_fonts',
    );
    final roboto = File('${dir.path}/Roboto-Regular.ttf');
    if (!roboto.existsSync()) return; // Not fatal: the shape checks still run.
    final loader = FontLoader('Roboto')..addFont(
        Future.value(roboto.readAsBytesSync().buffer.asByteData()));
    await loader.load();
  });

  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  Future<void> pump(
    WidgetTester tester,
    String type,
    Map<String, dynamic> props, {
    required double scale,
    double width = 320,
  }) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
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
                      id: 'b_$type',
                      type: type,
                      fallbackText: 'A $type block.',
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

  /// Every laid-out paragraph that ran out of room and dropped content.
  ///
  /// `overflow_test.dart` proves nothing paints outside its box; an ellipsis
  /// is the other way to stay inside one, and it is silent.
  List<String> truncated(WidgetTester tester) => [
        for (final p in tester.renderObjectList<RenderParagraph>(
          find.byType(RichText),
        ))
          if (p.didExceedMaxLines) p.text.toPlainText(),
      ];

  group('label and value rows line their values up', () {
    // `_KeyValueRow` reaches `receipt`, `key_value`, `booking_card`'s lines,
    // `confirm_card`'s params_display and the form's sent view. A loose
    // Flexible packed the value against the label and made `textAlign: end` a
    // no-op, so the amount column was not a column at all. Measured, not
    // asserted: this fix was lost once in a batch that never wrote.
    testWidgets('a receipt right-aligns every amount to one edge',
        (tester) async {
      await pump(tester, 'receipt', {
        'title': 'Order 1042',
        'lines': [
          {'label': 'Trail Runner 27 Mens Shoe', 'amount': '£118.00'},
          {'label': 'Socks', 'amount': '£8.00'},
        ],
        'subtotal': '£126.00',
        'tax': '£25.20',
        'total': '£151.20',
      }, scale: 1.0);

      final edges = [
        for (final amount in ['£118.00', '£8.00', '£151.20'])
          tester.getRect(find.text(amount)).right,
      ];
      final spread = edges.reduce((a, b) => a > b ? a : b) -
          edges.reduce((a, b) => a < b ? a : b);
      expect(
        spread,
        lessThan(1.0),
        reason: 'amounts ended at $edges, a ${spread}pt spread, so the '
            'column is not a column',
      );
    });

    // Blocks v6 ("F3") flags the optional fields rather than the required
    // ones, and the value sits under its label inside the form's panel
    // rather than in a control shell of its own.
    testWidgets('an optional field pushes its flag to the far edge',
        (tester) async {
      await pump(tester, 'form', {
        'form_id': 'return_request',
        'title': 'Start a return',
        'fields': [
          {
            'kind': 'text',
            'name': 'order_id',
            'label': 'Order number',
          },
        ],
        'submit_label': 'Send',
      }, scale: 1.0);

      // Against the value below it, which spans the row. "Optional" has to
      // sit at that same trailing edge; set beside the label instead it reads
      // as the label's last word — "Order number Optional".
      final field = tester.getRect(find.byType(TextField));
      final flag = tester.getRect(find.text('Optional'));
      expect(
        (flag.right - field.right).abs(),
        lessThan(1.0),
        reason: 'flag ends at ${flag.right}, the field at ${field.right}',
      );
    });
  });

  group('table keeps a readable scrolling half at every OS font scale', () {
    // The sticky column scales with the reader's text size so its cells do not
    // clip. The screen does not scale with it. Unclamped, 132pt * 2.0 took 264
    // of a 288pt plate and left 22pt to scroll five columns through.
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('320pt @$scale', (tester) async {
        await pump(tester, 'table', {
          'columns': ['Item', 'Qty', 'Price', 'Status'],
          'rows': [
            ['Runner 27', '2', '£118.00', 'Shipped'],
            ['Trail 12', '1', '£94.00', 'Packing'],
          ],
        }, scale: scale);

        final scroller = tester.widgetList<Scrollable>(find.byType(Scrollable));
        final horizontal =
            scroller.where((s) => s.axisDirection == AxisDirection.right);
        expect(horizontal, hasLength(1), reason: 'one scrolling half');

        final viewport = tester.getSize(
          find.byWidget(horizontal.first as Widget),
        );
        // Half the plate is the guarantee: whatever the sticky column wants,
        // the columns you scroll to must stay legible.
        expect(
          viewport.width,
          greaterThan(120),
          reason: 'scrolling half collapsed to ${viewport.width}pt',
        );
      });
    }
  });

  // The shell was never in the overflow suite, which covers blocks. Both of
  // these overflowed from textScaler 1.3 on a 320pt phone, on the two rows
  // that exist to explain what is happening.
  group('the thread shell holds at every OS font scale', () {
    ConversationController controller({bool sandbox = false}) =>
        ConversationController(
          api: RendelApiClient(
            appKey: 'nc_pk_test_x',
            deviceId: 'd',
            config: const RendelConfig(),
          ),
          actions: const {},
          sdkVersion: 'flutter/test',
          sandbox: sandbox,
        );

    Future<void> pumpShell(
      WidgetTester tester,
      ConversationController c, {
      required double scale,
      double width = 320,
    }) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          // copyWith, not a bare MediaQueryData: a fresh one has Size.zero,
          // and the shell reads the viewport, so the whole thread laid out at
          // zero height and every assertion here passed against nothing.
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RendelThemeScope(
                theme: RendelTheme.paper(),
                child: Scaffold(
                  body: ThreadScreen(
                    controller: c,
                    title: 'Assistant',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      // Proof the thing under test is on screen. Without it this suite
      // silently measured an empty tree.
      expect(find.byType(ThreadScreen), findsOneWidget);
    }

    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('the pill holds while a long-named action runs @$scale',
          (tester) async {
        // The name is the host's and the schema puts no ceiling on it. Driven
        // through the real turn loop, so the action is really running.
        const long = 'create_return_shipping_label_for_order';
        final held = Completer<RendelResult>();
        final c = ConversationController(
          api: _ScriptedApi(const [
            TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
            ActionExecute(
              invocationId: 'inv_1',
              name: long,
              params: {},
              timeoutMs: 30000,
            ),
            TurnEnd(status: 'awaiting_tool_results', pending: ['inv_1']),
          ]),
          actions: {
            long: RendelAction(
              name: long,
              description: 'Holds until the test lets go.',
              params: RendelSchema.object(const {}),
              risk: RendelRisk.read,
              handler: (_) => held.future,
            ),
          },
          sdkVersion: 'flutter/test',
        );

        // Real async: the turn only reaches runningAction once the scripted
        // stream has drained, which the fake-async pump never lets happen.
        await tester.runAsync(() async {
          unawaited(c.send('Start my return'));
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        expect(c.phase, RendelPhase.runningAction);

        await pumpShell(tester, c, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Checking your app…'), findsOneWidget,
            reason: 'the pill has to be on screen to be measured');

        held.complete(RendelResult.ok(const {}));
        await tester.pump(const Duration(milliseconds: 50));
        c.dispose();
      });

      testWidgets('a failed turn with its retry @$scale', (tester) async {
        // Short, so the button is the thing competing for the row rather
        // than the wrap absorbing it.
        const message = 'Request failed (400)';
        final c = controller()
          ..messages.add(RendelMessage.user('Where is my order?'))
          ..errorText = message;
        await pumpShell(tester, c, scale: scale);
        expect(tester.takeException(), isNull);
        // The message is the point of the bar, and a non-flex retry button
        // takes its intrinsic width before the message gets any. The exact
        // trip point depends on the font, so this asserts the invariant
        // rather than a measurement from one harness.
        expect(
          tester.getSize(find.text(message)).width,
          greaterThan(80),
          reason: 'the explanation was squeezed',
        );
        c.dispose();
      });

      testWidgets('the test-mode badge @$scale', (tester) async {
        final c = controller(sandbox: true);
        await pumpShell(tester, c, scale: scale);
        expect(tester.takeException(), isNull);
        c.dispose();
      });
    }
  });

  testWidgets('the header title is not starved by its own spacer',
      (tester) async {
    // A `Spacer` is flex-1, so it competed with the title and the badge and
    // the free space split three ways: a 66.7pt title box on a 320pt phone,
    // at every font scale, with two thirds of the header empty and both
    // strings ellipsised.
    final c = ConversationController(
      api: RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
        ),
      actions: const {},
      sdkVersion: 'flutter/test',
      sandbox: true,
    )..messages.add(RendelMessage.user('hello'));

    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: ThreadScreen(controller: c, title: 'Assistant'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ThreadScreen), findsOneWidget);
    // 'Assistant', not 'ASSISTANT': `RendelOverline` no longer uppercases. The
    // web surfaces set this step condensed instead of letterspaced-caps, and
    // a catalog that shouted while the site whispered would not read as one
    // product.
    final title = tester.getSize(find.text('Assistant'));
    expect(
      title.width,
      greaterThan(90),
      reason: 'the title box is ${title.width}pt of a 320pt header',
    );
    c.dispose();
  });

  // A row where one child's width is decided before the other is measured.
  // Four of these shipped: a `ConstrainedBox` cap that is a non-flex child and
  // takes its whole constant first, and two flex-1 children splitting a row
  // 50/50 whatever either needs. All four were invisible to a per-block
  // harness, because a block is 24pt narrower inside the thread than in a
  // plain box, and to the default test font, which is ~1.9x Roboto's width.
  group('a trailing value never starves the content beside it', () {
    testWidgets('an item_list title keeps most of its own row', (tester) async {
      await pump(tester, 'item_list', {
        'items': [
          {
            'image_url': 'https://example.invalid/a.png',
            'title': 'Merino wool crew neck sweater in navy, size medium',
            'subtitle': 'Order 1042, out for delivery',
            'trailing': '£129.00',
          },
        ],
      }, scale: 1.0);

      final title = tester.getSize(
        find.text('Merino wool crew neck sweater in navy, size medium'),
      );
      // It was 46pt of a 232pt row at the default text size: three characters
      // of a field the schema allows 120.
      expect(
        title.width,
        greaterThan(90),
        reason: 'the title box is ${title.width}pt',
      );
    });

    testWidgets('a donut legend name keeps most of the legend',
        (tester) async {
      await pump(tester, 'chart', {
        'kind': 'donut',
        'labels': ['Merino wool crew neck sweater navy'],
        'series': [
          {'data': [1]},
        ],
      }, scale: 1.0);

      final name = tester.getSize(
        find.text('Merino wool crew neck sweater navy'),
      );
      expect(
        name.width,
        greaterThan(60),
        reason: 'the slice name box is ${name.width}pt',
      );
    });
  });

  group('the recovery control survives the reader\'s text size', () {
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('Try again is whole @$scale', (tester) async {
        const message = 'The connection dropped before the answer finished.';
        final c = ConversationController(
          api: RendelApiClient(
            appKey: 'nc_pk_test_x',
            deviceId: 'd',
            config: const RendelConfig(),
          ),
          actions: const {},
          sdkVersion: 'flutter/test',
        )
          ..messages.add(RendelMessage.user('Where is my order?'))
          ..errorText = message;

        tester.view.physicalSize = const Size(320 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RendelThemeScope(
                  theme: RendelTheme.paper(),
                  child: Scaffold(body: ThreadScreen(controller: c)),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(ThreadScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        // The one control offered on a failed turn. It read "Try / ag..." from
        // scale 1.6, because the row split itself evenly whatever either side
        // needed.
        expect(
          truncated(tester),
          isNot(anyElement(contains('Try again'))),
          reason: 'the retry label was cut',
        );
        c.dispose();
      });
    }
  });

  group('the sandbox badge keeps its word', () {
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('@$scale', (tester) async {
        final c = ConversationController(
          api: RendelApiClient(
            appKey: 'nc_pk_test_x',
            deviceId: 'd',
            config: const RendelConfig(),
          ),
          actions: const {},
          sdkVersion: 'flutter/test',
          sandbox: true,
        );

        tester.view.physicalSize = const Size(320 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RendelThemeScope(
                  theme: RendelTheme.paper(),
                  child: Scaffold(
                    body: ThreadScreen(controller: c, title: 'Assistant'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        // It is the difference between a test key and a live one, so it drops
        // to a second line rather than losing a word. Sentence case since
        // `overline` stopped uppercasing — matching the old string here would
        // have made this assertion vacuously true rather than failing.
        expect(
          find.text('Test mode'),
          findsOneWidget,
          reason: 'the sandbox badge is not on screen at all',
        );
        expect(
          truncated(tester),
          isNot(anyElement(contains('Test mode'))),
          reason: 'the sandbox badge was cut',
        );
        c.dispose();
      });
    }
  });
}
