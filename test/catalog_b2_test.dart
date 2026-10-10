// Catalog wave 2 on the device (`design/CATALOG-B2.md`).
//
// Three actions that put something into the user's hands — the dialler, the
// clipboard, the calendar's own editor — carried out by the real controller
// on a tap; `comparison`, drawn as the prototype's table; and the props the
// record blocks grew: amounts, status, groups, ranks, documents, an ETA that
// knows when it was true, copy and masked rows, people, `as_of`, references.
// Every fixture here is held to the protocol's own wire schema, as the
// gallery's and the overflow suite's are.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/batteries.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show RendelPage, readsFlatOnPage;
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'wire_schema.dart';

/// The device's dialler, which remembers the URIs it was handed and refuses
/// to be asked whether it can open one: the SDK must not ask.
class _Dialler extends UrlLauncherPlatform {
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

/// A server that only records what it was sent.
class _Api extends RendelApiClient {
  _Api() : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) {
    sent.add(body);
    return const Stream.empty();
  }
}

Map<String, dynamic> _wire(String type, Map<String, dynamic> props) => {
      'id': 'b_$type',
      'type': type,
      'fallback_text': 'A $type block.',
      'props': props,
    };

WireBlock _block(Map<String, dynamic> wire) => WireBlock.tryParse(wire)!;

/// An instant [from] now, as an action result gives one.
String _at(Duration from) => DateTime.now().toUtc().add(from).toIso8601String();

final _shoes = _wire('comparison', {
  'items': [
    {
      'title': 'Aero Glide 2',
      'price': '\$129',
      'badge': 'Best seller',
      'action': {'kind': 'reply', 'text': 'Tell me about the Aero Glide 2'},
    },
    {'title': 'Trail Circuit', 'price': '\$149'},
  ],
  'rows': [
    {'label': 'Weight', 'values': ['248 g', '296 g'], 'best_index': 0},
    {'label': 'Drop', 'values': ['8 mm', '6 mm']},
    {'label': 'Waterproof', 'values': ['no', 'yes'], 'kind': 'check'},
    for (var i = 0; i < 9; i++) {'label': 'Row $i', 'values': ['a$i', 'b$i']},
  ],
  'summary': 'On the road the Aero Glide is lighter.',
});

final _plans = _wire('comparison', {
  'items': [
    {'title': 'Basic'},
    {'title': 'Plus'},
    {'title': 'Pro'},
    {'title': 'Max'},
  ],
  'rows': [
    {'label': 'Data', 'values': ['20 GB', '50 GB', '80 GB', 'Unlimited'], 'best_index': 3},
    {'label': '5G', 'values': ['no', 'yes', 'yes', 'yes'], 'kind': 'check'},
  ],
});

final _transactions = _wire('item_list', {
  'items': [
    {
      'group': 'Today',
      'date_label': '09:12',
      'title': 'Neon Kicks',
      'amount': {'value': '€129.00', 'tone': 'negative'},
    },
    {
      'group': 'Today',
      'title': 'Refund',
      'amount': {'value': '€95.00', 'tone': 'positive'},
      'status': {'label': 'Pending', 'tone': 'warning'},
    },
    {
      'group': 'Last week',
      'title': 'Coffee Lab',
      'amount': {'value': '-€4.20', 'tone': 'negative'},
    },
    {
      'group': 'Last week',
      'title': 'Salary',
      'amount': {'value': '+€2,450.00', 'tone': 'positive'},
    },
    {
      'group': 'Last week',
      'title': 'To savings',
      'amount': {'value': '€300.00', 'tone': 'neutral'},
    },
    for (var i = 0; i < 5; i++)
      {
        'group': 'Last week',
        'title': 'Purchase $i',
        'amount': {'value': '€1$i.00', 'tone': 'negative'},
      },
  ],
});

final _ranking = _wire('item_list', {
  'items': [
    {'rank': 1, 'title': 'Meral D.', 'trailing': '412,880'},
    {'rank': 2, 'title': 'You', 'trailing': '398,150', 'highlight': true},
    {'file_type': 'pdf', 'title': 'September statement'},
    {'file_type': 'csv', 'title': 'Transactions'},
    {'file_type': 'image', 'title': 'Receipt'},
  ],
});

Map<String, dynamic> _tracker({String? eta, String? asOf, String? label}) => _wire('order_tracker', {
      'title': 'Order 1042',
      'steps': [
        {'label': 'Ordered', 'status': 'done'},
        {'label': 'Out for delivery', 'status': 'current', 'note': 'Three stops away'},
        {'label': 'Delivered', 'status': 'pending'},
      ],
      if (eta != null) 'eta': eta,
      if (asOf != null) 'as_of': asOf,
      if (label != null) 'eta_label': label,
      'reference': {'label': 'Tracking', 'value': '3SABCD1234567'},
    });

final _account = _wire('key_value', {
  'rows': [
    {'label': 'IBAN', 'value': 'NL91 ABNA 0417 1643 00', 'copy': true},
    {'label': 'Card number', 'value': '5355 4321 9876 4821', 'masked': true},
    {'label': 'Status', 'value': 'Active', 'tone': 'success'},
    {'label': 'Balance', 'value': '-€12.00', 'tone': 'error'},
    {'label': 'HbA1c', 'value': '5.9 %', 'range_label': '4.0–5.6'},
  ],
});

final _courier = _wire('info_card', {
  'icon': 'person',
  'avatar_url': 'https://example.com/mehmet.jpg',
  'title': 'Mehmet is on his way',
  'meta': 'White Egea · 34 ABC 123',
  'cta': {
    'label': 'Track',
    'action': {'kind': 'reply', 'text': 'Track it'},
  },
  'actions': [
    {
      'label': 'Call',
      'action': {'kind': 'call', 'phone': '+31 (20) 555-0134'},
    },
    {
      'label': 'Copy plate',
      'action': {'kind': 'copy', 'text': '34 ABC 123'},
    },
  ],
});

final _statement = _wire('info_card', {
  'file_type': 'pdf',
  'title': 'September statement',
  'meta': 'PDF · 120 KB',
  'cta': {
    'label': 'Open',
    'action': {'kind': 'reply', 'text': 'Open it'},
  },
});

const _calendarStart = '2026-10-14T10:00:00+02:00';

Map<String, dynamic> _booking({String? startsAt}) => _wire('booking_card', {
      'title': 'Fitting',
      'when': 'Wednesday, 10:00',
      if (startsAt != null) 'starts_at': startsAt,
      'status': {'label': 'Confirmed', 'tone': 'success'},
      'reference': {'label': 'Booking', 'value': 'FIT-2291'},
      'cta': {
        'label': 'Add to calendar',
        'action': {
          'kind': 'add_to_calendar',
          'title': 'Fitting',
          'starts_at': _calendarStart,
          'ends_at': '2026-10-14T10:45:00+02:00',
          'location': 'Haarlemmerstraat 24',
        },
      },
    });

final _stats = _wire('stat_group', {
  'items': [
    {'label': 'Balance', 'value': '€2,184'},
  ],
  'as_of': _at(const Duration(minutes: -12)),
});

void main() {
  late List<String> copied;
  late List<MethodCall> native;

  setUp(() {
    copied = [];
    native = [];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('rendel/platform'), (call) async {
      native.add(call);
      return true;
    });
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(const MethodChannel('rendel/platform'), null);
  });

  ConversationController controller([RendelApiClient? api]) => ConversationController(
        api: api ?? _Api(),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  final theme = RendelTheme.paper();

  /// [blocks] in a scrolling page, tapping through the real controller. On
  /// a page ([bar] set) a readout lies flat, as the thread draws it.
  Future<ConversationController> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> blocks, {
    double? bar,
  }) async {
    final c = controller();
    addTearDown(c.dispose);
    final dispatch = RendelDispatcher(
      onAction: c.tapAction,
      onSubmitForm: c.submitForm,
      canHandle: c.handles,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: theme,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final block in blocks.map(_block))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    // A node of its own per block, with explicit children, as
                    // the thread gives each block on a page.
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: Builder(builder: (context) {
                        final drawn = Builder(
                          builder: (context) => ComponentRegistry.build(context, block, dispatch),
                        );
                        return bar == null
                            ? drawn
                            : RendelPage(
                                flat: readsFlatOnPage(block.type),
                                inset: 16,
                                bar: bar,
                                child: drawn,
                              );
                      }),
                    ),
                  ),
                // Room to scroll a block up past the top.
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  group('the handshake', () {
    test('declares the three action kinds and comparison', () async {
      final api = _Api();
      final c = controller(api);
      unawaited(c.send('hello'));
      await Future<void>.delayed(Duration.zero);
      final client = api.sent.single['client'] as Map<String, dynamic>;
      expect(client['actions'], containsAll(['call', 'copy', 'add_to_calendar']));
      expect(client['components'], contains('comparison'));
      c.dispose();
    });

    test('the actions parse, and a malformed one is no action', () {
      final call = UIAction.tryParse({'kind': 'call', 'phone': '+31 20 555 0134', 'label': 'Courier'});
      expect(call, isA<CallAction>());
      expect((call as CallAction).label, 'Courier');
      expect(UIAction.tryParse({'kind': 'copy', 'text': 'FIT-2291'}), isA<CopyAction>());
      final event = UIAction.tryParse({
        'kind': 'add_to_calendar',
        'title': 'Fitting',
        'starts_at': _calendarStart,
      });
      expect(event, isA<AddToCalendarAction>());
      expect((event as AddToCalendarAction).startsAt, DateTime.parse(_calendarStart));
      expect(event.endsAt, isNull);
      expect(UIAction.tryParse({'kind': 'call'}), isNull);
      expect(UIAction.tryParse({'kind': 'copy', 'text': ''}), isNull);
      expect(UIAction.tryParse({'kind': 'add_to_calendar', 'title': 'x', 'starts_at': 'soon'}), isNull);
      final c = controller();
      expect(c.handles(call), isTrue);
      expect(c.handles(event), isTrue);
      c.dispose();
    });
  });

  group('the actions', () {
    testWidgets('call opens the dialler with the number, without asking first', (tester) async {
      final dialler = _Dialler();
      UrlLauncherPlatform.instance = dialler;
      await pump(tester, [_courier]);
      // The number is on the button before it is tapped.
      expect(find.text('+31 (20) 555-0134'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Call, +31 (20) 555-0134'));
      await tester.pump();
      expect(dialler.launched, [('tel:+31205550134', PreferredLaunchMode.externalApplication)]);
      expect(copied, isEmpty);
    });

    test('the dialler is handed digits, and a failure is not a crash', () async {
      final dialler = _Dialler();
      UrlLauncherPlatform.instance = dialler;
      expect(await dial('+90 (212) 555-01.01'), isTrue);
      expect(dialler.launched.single.$1, 'tel:+902125550101');
      expect(await dial(' - '), isFalse);
    });

    testWidgets('copy puts the text on the clipboard and says Copied for 1.5 s', (tester) async {
      await pump(tester, [_courier]);
      await tester.tap(find.bySemanticsLabel('Copy plate'));
      await tester.pump();
      await tester.pump();
      expect(copied, ['34 ABC 123']);
      expect(find.text('Copied'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // Said as well as drawn.
      expect(tester.getSemantics(find.bySemanticsLabel('Copied')), isSemantics(isLiveRegion: true));
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.text('Copied'), findsNothing);
      expect(find.text('Copy plate'), findsOneWidget);
    });

    testWidgets('add_to_calendar opens the native editor, filled in, and shows the start',
        (tester) async {
      await pump(tester, [_booking()]);
      final start = DateTime.parse(_calendarStart).toLocal();
      const material = DefaultMaterialLocalizations();
      final shown = '${material.formatMediumDate(start)}, '
          '${material.formatTimeOfDay(TimeOfDay.fromDateTime(start))}';
      expect(find.text(shown), findsOneWidget, reason: 'the start, in the device locale');
      await tester.tap(find.bySemanticsLabel('Add to calendar, $shown'));
      await tester.pump();
      final call = native.single;
      expect(call.method, 'addToCalendar');
      expect(call.arguments, {
        'title': 'Fitting',
        'starts_at': DateTime.parse(_calendarStart).millisecondsSinceEpoch,
        'ends_at': DateTime.parse('2026-10-14T10:45:00+02:00').millisecondsSinceEpoch,
        'location': 'Haarlemmerstraat 24',
      });
    });
  });

  group('comparison', () {
    testWidgets('one column per item, the best marked and said, check rows as ✓ and —',
        (tester) async {
      await pump(tester, [_plans, _shoes]);
      // The header's titles, the first of each (the pinned line has them
      // too), side by side; the badge stands over the first.
      final glide = tester.getRect(find.text('Aero Glide 2').first);
      final trail = tester.getRect(find.text('Trail Circuit').first);
      expect(trail.left, greaterThan(glide.right));
      expect(tester.getRect(find.text('Best seller')).bottom, lessThanOrEqualTo(glide.top));
      expect(trail.top, lessThan(glide.top));
      // Four items, four columns, on one line.
      final cells = [for (final v in ['20 GB', '50 GB', '80 GB', 'Unlimited']) tester.getRect(find.text(v))];
      for (var i = 1; i < cells.length; i++) {
        expect(cells[i].top, cells[0].top);
        expect(cells[i].left, greaterThan(cells[i - 1].right));
      }

      Finder marked(String value) => find.ancestor(
            of: find.text(value),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == theme.mark,
            ),
          );
      expect(marked('248 g'), findsOneWidget);
      expect(marked('296 g'), findsNothing);
      expect(marked('Unlimited'), findsOneWidget);
      expect(find.bySemanticsLabel('Weight, Aero Glide 2: 248 g, best'), findsOneWidget);
      expect(find.bySemanticsLabel('Weight, Trail Circuit: 296 g'), findsOneWidget);

      // yes is the ink round with a tick, no a faint dash; said as words.
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(1 + 3));
      expect(find.byIcon(Icons.remove_rounded), findsNWidgets(1 + 1));
      expect(find.bySemanticsLabel('Waterproof, Trail Circuit: Yes'), findsOneWidget);
      expect(find.bySemanticsLabel('Waterproof, Aero Glide 2: No'), findsOneWidget);

      // The badge, the price, the summary; an item with an action is a
      // control, one without is not.
      expect(find.text('Best seller'), findsOneWidget);
      expect(find.text('On the road the Aero Glide is lighter.'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Aero Glide 2, Best seller, \$129')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Trail Circuit, \$149')),
        isSemantics(isButton: false),
      );
    });

    testWidgets('the titles pin under the bar once the header has scrolled under it',
        (tester) async {
      await pump(tester, [_shoes], bar: 60);
      final pin = find.byKey(const ValueKey('rendel-comparison-pin'));
      double opacity() => tester.widget<AnimatedOpacity>(pin).opacity;
      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      Future<void> scrollTo(double offset) async {
        position.jumpTo(offset);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(opacity(), 0, reason: 'the header is in view');
      // The header's foot, in the list's own coordinates: the line under
      // the things, which is the top of the first row's label.
      final headFoot = tester.getRect(find.text('Weight')).top;
      final foot = tester.getRect(find.text('On the road the Aero Glide is lighter.')).bottom;

      await scrollTo(headFoot - 60 - 20);
      expect(opacity(), 0, reason: 'the header still shows under the bar');

      await scrollTo(headFoot - 60 + 20);
      expect(opacity(), 1);
      expect(tester.getTopLeft(pin).dy, moreOrLessEquals(60, epsilon: 0.5),
          reason: 'under the bar, not at the top of the screen');
      expect(find.descendant(of: pin, matching: find.text('Trail Circuit')), findsOneWidget);

      // Kept under the bar while the rows go by.
      await scrollTo(headFoot + 200);
      expect(opacity(), 1);
      expect(tester.getTopLeft(pin).dy, moreOrLessEquals(60, epsilon: 0.5));

      // Once the block's own foot comes up to the bar it goes.
      await scrollTo(foot - 60 + 10);
      expect(opacity(), 0);

      // And back with the header in view.
      await scrollTo(0);
      expect(opacity(), 0);
    });
  });

  group('item_list', () {
    testWidgets('signs amounts, draws status and one heading per group, and folds past 8',
        (tester) async {
      await pump(tester, [_transactions]);
      expect(find.text('−€129.00'), findsOneWidget, reason: 'a loss gets a true minus');
      expect(find.text('+€95.00'), findsOneWidget, reason: 'a gain gets its plus');
      expect(find.text('−€4.20'), findsOneWidget, reason: 'a hyphen becomes the minus');
      expect(find.text('+€2,450.00'), findsOneWidget, reason: 'a sign is not doubled');
      expect(find.text('€300.00'), findsOneWidget, reason: 'neutral is as written');
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('09:12'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Last week'), findsOneWidget);

      // Eight, and the rest behind one quiet button.
      expect(find.text('Purchase 2'), findsOneWidget);
      expect(find.text('Purchase 3'), findsNothing);
      expect(find.text('Show 2 more'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Show 2 more'));
      await tester.pump();
      expect(find.text('Purchase 4'), findsOneWidget);
      expect(find.text('Show 2 more'), findsNothing);
    });

    testWidgets('ranks in a column, the user highlighted, documents as their type',
        (tester) async {
      await pump(tester, [_ranking]);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        tester.getRect(find.text('Meral D.')).left,
        tester.getRect(find.text('September statement')).left - theme.size.rowThumb - theme.space.md,
        reason: 'a rank column keeps every title on one line',
      );
      expect(
        find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == theme.mark.withValues(alpha: 0.4)),
        findsOneWidget,
      );
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('IMG'), findsOneWidget);
    });
  });

  group('order_tracker', () {
    testWidgets('an ETA ahead and fresh is relative', (tester) async {
      await pump(tester, [
        _tracker(eta: _at(const Duration(minutes: 25)), asOf: _at(const Duration(minutes: -2))),
      ]);
      expect(find.text('Arrives in about 25 min'), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
    });

    testWidgets('an ETA known long ago is a clock time, as of then', (tester) async {
      await pump(tester, [
        _tracker(eta: _at(const Duration(minutes: 25)), asOf: _at(const Duration(hours: -2))),
      ]);
      expect(find.textContaining('in about'), findsNothing);
      expect(find.textContaining(RegExp(r'^Arrives .+ · as of .+$')), findsOneWidget);
    });

    testWidgets('an ETA already past is a clock time too, and eta_label says it', (tester) async {
      await pump(tester, [
        _tracker(
          eta: _at(const Duration(minutes: -30)),
          asOf: _at(const Duration(minutes: -5)),
          label: '14:20–14:40',
        ),
      ]);
      expect(find.textContaining(RegExp(r'^Arrives 14:20–14:40 · as of ')), findsOneWidget);
    });

    testWidgets('a note under its step, and the reference with a copy button', (tester) async {
      await pump(tester, [_tracker()]);
      expect(find.text('Three stops away'), findsOneWidget);
      expect(find.textContaining('Arrives'), findsNothing);
      expect(find.text('3SABCD1234567'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Copy, Tracking'));
      await tester.pump();
      await tester.pump();
      expect(copied, ['3SABCD1234567']);
      expect(tester.getSemantics(find.bySemanticsLabel('Copied')), isSemantics(isLiveRegion: true));
      await tester.pump(const Duration(milliseconds: 1600));
    });
  });

  group('key_value', () {
    for (final page in [false, true]) {
      testWidgets('copy, masked reveal, tone and range ${page ? 'on a page' : 'on a plate'}',
          (tester) async {
        await pump(tester, [_account], bar: page ? 0 : null);
        await tester.tap(find.bySemanticsLabel('Copy, IBAN'));
        await tester.pump();
        await tester.pump();
        expect(copied, ['NL91 ABNA 0417 1643 00']);
        await tester.pump(const Duration(milliseconds: 1600));

        expect(find.text('•••• 4821'), findsOneWidget);
        expect(find.text('5355 4321 9876 4821'), findsNothing);
        // A screen reader is told the tap shows it; a finger taps the dots.
        expect(
          tester.getSemantics(find.bySemanticsLabel(RegExp(r'•••• 4821, Show'))),
          isSemantics(hasTapAction: true),
        );
        await tester.tap(find.text('•••• 4821'));
        await tester.pump();
        expect(find.text('5355 4321 9876 4821'), findsOneWidget);

        expect(tester.widget<Text>(find.text('Active')).style?.color, theme.colors.onSurface);
        expect(tester.widget<Text>(find.text('-€12.00')).style?.color, theme.danger);
        expect(find.text('4.0–5.6'), findsOneWidget);
      });
    }
  });

  group('info_card', () {
    testWidgets('a person is their picture and a line, and actions replace the CTA',
        (tester) async {
      await pump(tester, [_courier]);
      expect(
        find.byWidgetPredicate((w) {
          if (w is! Image) return false;
          final provider = w.image;
          final inner = provider is ResizeImage ? provider.imageProvider : provider;
          return inner is NetworkImage && inner.url == 'https://example.com/mehmet.jpg';
        }),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.person_outline_rounded), findsNothing, reason: 'the picture is the icon');
      expect(find.text('White Egea · 34 ABC 123'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Track'), findsNothing, reason: 'actions replace the CTA');
    });

    testWidgets('a document is its type, and its CTA stays without actions', (tester) async {
      await pump(tester, [_statement]);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('PDF · 120 KB'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });
  });

  testWidgets('stat_group says when its figures were true', (tester) async {
    await pump(tester, [_stats]);
    expect(find.textContaining(RegExp(r'^as of .+')), findsOneWidget);
  });

  group('booking_card', () {
    testWidgets('the reference copies, the status sits by the title', (tester) async {
      await pump(tester, [_booking()]);
      expect(find.text('FIT-2291'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(
        tester.getRect(find.text('Confirmed')).top,
        lessThan(tester.getRect(find.text('Wednesday, 10:00')).top),
        reason: 'beside the title, above when',
      );
      await tester.tap(find.bySemanticsLabel('Copy, Booking'));
      await tester.pump();
      await tester.pump();
      expect(copied, ['FIT-2291']);
      await tester.pump(const Duration(milliseconds: 1600));
    });

    testWidgets('starts_at says how soon while it is ahead', (tester) async {
      final now = DateTime.now();
      final later = now.add(const Duration(hours: 2, minutes: 5));
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 10);
      await pump(tester, [
        _booking(startsAt: later.toUtc().toIso8601String()),
        _booking(startsAt: tomorrow.toUtc().toIso8601String()),
        _booking(startsAt: now.subtract(const Duration(hours: 1)).toUtc().toIso8601String()),
      ]);
      final sameDay = later.day == now.day;
      expect(find.text('in 2 hours'), sameDay ? findsOneWidget : findsNothing);
      expect(find.textContaining(RegExp(r'^tomorrow ')), findsNWidgets(sameDay ? 1 : 2));
      expect(find.textContaining('in about'), findsNothing, reason: 'the past one says nothing');
    });
  });

  test('every new string exists in all six languages', () {
    const english = RendelStrings();
    expect(english.copied, 'Copied');
    expect(english.showMoreCount(3), 'Show 3 more');
    expect(english.asOfTime('14:02'), 'as of 14:02');
    expect(english.arrivesAt('14:20'), 'Arrives 14:20');
    expect(english.reveal, 'Show');
    final turkish = RendelStrings.forLocale('tr');
    expect(turkish.copied, 'Kopyalandı');
    expect(turkish.showMoreCount(3), '3 tane daha göster');
    expect(turkish.asOfTime('14:02'), '14:02 itibarıyla');
    expect(turkish.arrivesAt('14:20'), 'Varış 14:20');
    expect(turkish.reveal, 'Göster');
    for (final language in ['tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      for (final (name, said, en) in [
        ('copy', strings.copy, english.copy),
        ('copied', strings.copied, english.copied),
        ('reveal', strings.reveal, english.reveal),
        ('showMore', strings.showMore, english.showMore),
        ('asOf', strings.asOf, english.asOf),
        ('arrives', strings.arrives, english.arrives),
        ('inMinutes', strings.inMinutes, english.inMinutes),
        ('inHours', strings.inHours, english.inHours),
        ('tomorrowAt', strings.tomorrowAt, english.tomorrowAt),
        ('best', strings.best, english.best),
      ]) {
        expect(said, isNot(en), reason: '$name is still English in $language');
      }
      expect(strings.showMoreCount(7), contains('7'), reason: language);
      expect(strings.asOfTime('14:02'), contains('14:02'), reason: language);
      expect(strings.arrivesAt('14:20'), contains('14:20'), reason: language);
      expect(strings.inMinutesCount(25), contains('25'), reason: language);
      expect(strings.inHoursCount(3), contains('3'), reason: language);
      expect(strings.tomorrowAtTime('10:00'), contains('10:00'), reason: language);
    }
  });

  group('the fixtures', () {
    // The gallery's are held in example/test/gallery_test.dart.
    test('parse against the protocol schema', () {
      for (final wire in [
        _shoes,
        _plans,
        _transactions,
        _ranking,
        _tracker(),
        _tracker(eta: _at(const Duration(minutes: 25)), asOf: _at(Duration.zero), label: '14:20'),
        _account,
        _courier,
        _statement,
        _booking(),
        _booking(startsAt: _at(const Duration(hours: 2))),
        _stats,
      ]) {
        expect(wireBlockErrors(wire), isEmpty, reason: '${wire['type']}');
      }
    });

    test('the schema check is a real one', () {
      // It would pass anything if it read nothing, so a few things it must
      // refuse.
      expect(wireBlockErrors(_wire('item_list', {'items': []})), isNotEmpty);
      expect(wireBlockErrors(_wire('info_card', {'title': 'x', 'colour': 'red'})), isNotEmpty);
      expect(
        wireBlockErrors(_wire('info_card', {
          'title': 'x',
          'actions': [
            {
              'label': 'Call',
              'action': {'kind': 'call', 'phone': '1'},
            },
          ],
        })),
        isNotEmpty,
        reason: 'a phone is three characters at least',
      );
      expect(
        wireBlockErrors(_wire('comparison', {
          'items': [
            {'title': 'a'},
            {'title': 'b'},
          ],
          'rows': [
            {'label': 'x', 'values': ['1', '2', '3']},
          ],
        })),
        isNotEmpty,
        reason: 'one value per item',
      );
      expect(
        wireBlockErrors(_tracker(eta: _at(Duration.zero))),
        isNotEmpty,
        reason: 'eta needs as_of',
      );
    });
  });
}
