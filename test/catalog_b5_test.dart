// Catalog wave 5 on the device (`design/CATALOG-B5.md`).
//
// open_url.external goes to the system, past the host's opener; place_card
// builds the way there per platform, calls, and opens its detail on a page;
// map fits its pins, takes no gesture on the page, opens full screen with
// gestures and Open in Maps, and lists its pins when the engine fails; pass
// paints the server's QR matrix and code128 bars module for module, inside
// their quiet zones, on white, with display_text and the wallet button the
// platform has. The map engine is a fake here: a widget test runs no platform
// view. Every fixture is held to the protocol's own wire schema.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/batteries.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show RendelPage, RendelPassCode;
import 'package:rendel/src/ui/renderer/map_engine.dart';
import 'package:rendel/src/ui/thread_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'wire_schema.dart';

/// The device's launcher, which remembers what it was handed.
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

/// A map engine with no platform view behind it: a plain ground, and a note
/// of every map asked for, and how.
class _Engine extends RendelMapEngine {
  final List<({RendelMapCamera camera, bool interactive})> built = [];

  /// Fails every map it is asked for, as an engine with no network does.
  bool fails = false;

  /// What the full-screen map reports its camera moves to.
  ValueChanged<RendelMapCamera>? moved;

  @override
  Widget build({
    required RendelMapCamera camera,
    required bool interactive,
    required ValueChanged<RendelMapCamera> onMove,
    required VoidCallback onFailed,
  }) {
    built.add((camera: camera, interactive: interactive));
    if (interactive) moved = onMove;
    if (fails) WidgetsBinding.instance.addPostFrameCallback((_) => onFailed());
    return ColoredBox(key: ValueKey(interactive ? 'full-map' : 'page-map'), color: const Color(0xFFE7ECDF));
  }
}

/// A server the test answers by hand.
class _Api extends RendelApiClient {
  _Api() : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

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

final _store = _wire('place_card', {
  'name': 'Neon Kicks Kadıköy',
  'address': 'Bağdat Cd. 312, Kadıköy',
  'lat': 40.9634,
  'lng': 29.0652,
  'distance_label': '1.2 km',
  'open_now': true,
  'hours_today': 'until 21:00',
  'hours_week': [
    {'day': 'Mon–Fri', 'hours': '10:00–21:00'},
    {'day': 'Sun', 'hours': '11:00–20:00'},
  ],
  'phone': '+90 216 555 01 12',
  'rating': 4.6,
  'rating_count': 312,
  'image_url': 'https://example.com/kadikoy.jpg',
  'directions': true,
  'website': 'https://www.neonkicks.example/stores/kadikoy',
});

final _closed = _wire('place_card', {
  'name': 'Neon Kicks Moda',
  'address': 'Moda Cd. 88, Kadıköy',
  'open_now': false,
  'directions': true,
}, id: 'b_place_closed');

final _stores = _wire('map', {
  'pins': [
    {'lat': 40.9634, 'lng': 29.0652, 'label': 'Kadıköy', 'subtitle': 'Bağdat Cd. 312'},
    {'lat': 40.9806, 'lng': 29.0262, 'label': 'Moda', 'subtitle': 'Moda Cd. 88'},
    {'lat': 41.0422, 'lng': 29.0083, 'label': 'Beşiktaş'},
  ],
  'caption': 'Three stores with the Aero Glide 2 in a 42.',
});

/// The server's own drawing (`apps/api/src/lib/pass-code.ts`, bwip-js) of a
/// QR for "RD-4821-XYZ", of a code128 for "4821XYZ" and of a PDF417. The
/// PDF417's `rows` is the ten rows its bits hold: bwip-js reports `pixy` as
/// 30, its rows already multiplied by the three that `module_aspect` says
/// again, and the server passes that on as `rows`.
const _qr = {
  'rows': 21,
  'cols': 21,
  'bits': '/nP8FxBukrt1JduvLsEVB/qv4B8AXvbVA2ZXtPUYYk654ABEX/lYMFO/uvI91couiNcFjS/jGwA=',
  'module_aspect': 1,
};
const _bars = [
  2, 1, 1, 2, 3, 2, 3, 1, 3, 1, 2, 1, 2, 1, 3, 2, 1, 2, 1, 1, 4, 1, 3, 1, 3, 3, 1, 1, //
  2, 1, 3, 1, 2, 1, 1, 3, 3, 1, 2, 3, 1, 1, 1, 2, 2, 1, 3, 2, 2, 3, 3, 1, 1, 1, 2,
];
const _pdf417 = {
  'rows': 10,
  'cols': 120,
  'bits': '/1R1ODXeGaQKYYfV8/op/1R9RiQeWZ6PNzfUw/op/1RU8DH228TIjfaj4/op/1RX3ycdHq8NGca8+/op/1RrhD1zlPht79a4g'
      '/op/1R9ezeWH15r0CevC/op/1RTnDsI2EFsmcdO+/op/1R6UCn7n7Frv0a/e/op/1R+mTJPnPLofaUx8/op/1RRgyjDHHRI57UYY/op',
  'module_aspect': 3,
};

final _pickup = _wire('pass', {
  'kind': 'pickup',
  'title': 'Order 4821',
  'subtitle': 'Neon Kicks Kadıköy, at the counter',
  'fields': [
    {'label': 'Items', 'value': '2'},
    {'label': 'Name', 'value': 'T. Öztürk'},
    {'label': 'Shelf', 'value': 'B12'},
    {'label': 'Bag', 'value': 'Large'},
  ],
  'code': {'format': 'qr', 'value': 'RD-4821-XYZ', 'display_text': 'RD-4821-XYZ', 'matrix': _qr},
  'wallet': {
    'apple_pkpass_url': 'https://neonkicks.example/passes/4821.pkpass',
    'google_save_url': 'https://pay.google.com/gp/v/save/eyJhbGciOi',
  },
  'valid_until': '2026-10-17T21:00:00+03:00',
});

final _coupon = _wire('pass', {
  'kind': 'coupon',
  'title': '15% off your next pair',
  'code': {'format': 'code128', 'value': '4821XYZ', 'display_text': '4821 XYZ', 'bars': _bars},
}, id: 'b_pass_coupon');

final _boarding = _wire('pass', {
  'kind': 'boarding',
  'title': 'IST → BER · TK 1723',
  'code': {'format': 'pdf417', 'value': 'M1OZTURK/TUNA EABC123 ISTBERTK 1723', 'matrix': _pdf417},
}, id: 'b_pass_boarding');

final _member = _wire('pass', {
  'kind': 'membership',
  'title': 'Neon Kicks Club',
  'code': {'format': 'aztec', 'value': 'NK00427731', 'display_text': 'NK 0042 7731'},
}, id: 'b_pass_member');

void main() {
  late _Launcher launcher;
  late _Engine engine;

  setUp(() {
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    engine = _Engine();
    RendelMapEngine.current = engine;
  });

  tearDown(() {
    RendelMapEngine.current = const MapLibreEngine();
    debugDefaultTargetPlatformOverride = null;
  });

  ConversationController controller([_Api? api]) => ConversationController(
        api: api ?? _Api(),
        actions: const {},
        sdkVersion: 'flutter/test',
        onOpenUrl: openLink,
      );

  /// [blocks] in a scrolling list on a phone, tapping through the real
  /// controller.
  Future<ScrollController> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> blocks, {
    RendelTheme? theme,
    bool detail = false,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = controller();
    addTearDown(c.dispose);
    final dispatch = RendelDispatcher(onAction: c.tapAction, onSubmitForm: c.submitForm, canHandle: c.handles);
    final drawn = blocks.map(_block).toList();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Widget page(Widget child) =>
        detail ? RendelPage(flat: false, inset: 16, detail: true, child: child) : child;
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: theme ?? RendelTheme.paper(),
          child: Scaffold(
            body: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                for (final block in drawn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    // A node of its own per block, as the thread gives it.
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: page(Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch))),
                    ),
                  ),
                // Room to scroll.
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return scroll;
  }

  test('the handshake declares the three', () async {
    final api = _Api();
    final c = controller(api);
    unawaited(c.send('hello'));
    await Future<void>.delayed(Duration.zero);
    final client = api.sent.single['client'] as Map<String, dynamic>;
    expect(client['components'], containsAll(['place_card', 'map', 'pass']));
    c.dispose();
  });

  group('open_url.external', () {
    test('goes to the system, not to the host or an in-app browser', () async {
      final opened = <String>[];
      final c = ConversationController(
        api: _Api(),
        actions: const {},
        sdkVersion: 'flutter/test',
        onOpenUrl: (url) async => opened.add(url),
      );
      const maps = 'https://maps.apple.com/?daddr=40.9634,29.0652';
      final external = UIAction.tryParse({'kind': 'open_url', 'url': maps, 'external': true});
      expect(external, isA<OpenUrlAction>().having((a) => a.external, 'external', isTrue));
      expect(await c.tapAction(external!), isTrue);
      expect(launcher.launched.single, (maps, PreferredLaunchMode.externalApplication));
      expect(opened, isEmpty, reason: "the host's opener is for pages");

      // Without it, unchanged: the host opens it.
      final plain = UIAction.tryParse({'kind': 'open_url', 'url': 'https://example.com/a'})!;
      expect((plain as OpenUrlAction).external, isFalse);
      await c.tapAction(plain);
      expect(opened, ['https://example.com/a']);
      expect(launcher.launched, hasLength(1));
      c.dispose();
    });

    test('needs no host opener, and opens nothing but https', () async {
      final c = ConversationController(api: _Api(), actions: const {}, sdkVersion: 'flutter/test');
      expect(c.handles(const OpenUrlAction('https://maps.apple.com/?daddr=1,2', external: true)), isTrue);
      expect(c.handles(const OpenUrlAction('https://example.com')), isFalse);
      expect(await openExternally('http://maps.apple.com/'), isFalse);
      expect(await openExternally('tel:123'), isFalse);
      expect(launcher.launched, isEmpty);
      c.dispose();
    });
  });

  group('place_card', () {
    testWidgets('draws the place, whether it is open, and the two buttons', (tester) async {
      await pump(tester, [_store, _closed]);
      expect(find.text('Neon Kicks Kadıköy'), findsOneWidget);
      expect(find.text('Bağdat Cd. 312, Kadıköy · 1.2 km'), findsOneWidget);
      expect(find.text('Open now · until 21:00 · ★ 4.6 (312)'), findsOneWidget);
      final line = tester.widget<Text>(find.text('Open now · until 21:00 · ★ 4.6 (312)'));
      final open = (line.textSpan! as TextSpan).children!.first as TextSpan;
      expect(open.text, 'Open now');
      expect(open.style?.fontWeight, FontWeight.w600);
      expect(find.text('Closed'), findsOneWidget);
      // The week is the detail's, not the card's.
      expect(find.text('Mon–Fri'), findsNothing);
      // Directions lit, Call quiet, side by side; the site as its address.
      bool quiet(String label) => tester
          .widget<RendelActionButton>(find.ancestor(of: find.text(label).first, matching: find.byType(RendelActionButton)))
          .quiet;
      expect(quiet('Directions'), isFalse);
      expect(quiet('Call'), isTrue);
      expect(tester.getRect(find.text('Call')).center.dy, tester.getRect(find.text('Directions').first).center.dy);
      expect(find.text('neonkicks.example'), findsOneWidget);
      // No phone, no call.
      expect(find.text('Call'), findsOneWidget);
    });

    testWidgets('Directions on Android: Google Maps to the coordinates, to the system', (tester) async {
      await pump(tester, [_store]);
      await tester.tap(find.bySemanticsLabel('Directions'));
      await tester.pump();
      expect(launcher.launched.single, (
        'https://www.google.com/maps/dir/?api=1&destination=40.9634,29.0652',
        PreferredLaunchMode.externalApplication,
      ));
    });

    testWidgets('Directions on iOS: Apple Maps', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pump(tester, [_store]);
      await tester.tap(find.bySemanticsLabel('Directions'));
      await tester.pump();
      expect(launcher.launched.single.$1, 'https://maps.apple.com/?daddr=40.9634,29.0652');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('without coordinates, to the address, encoded', (tester) async {
      await pump(tester, [_closed]);
      await tester.tap(find.bySemanticsLabel('Directions'));
      await tester.pump();
      expect(
        launcher.launched.single.$1,
        'https://www.google.com/maps/dir/?api=1&destination=Moda%20Cd.%2088%2C%20Kad%C4%B1k%C3%B6y',
      );
    });

    testWidgets('Call dials, and the site opens in the in-app browser', (tester) async {
      await pump(tester, [_store]);
      await tester.tap(find.bySemanticsLabel('Call'));
      await tester.tap(find.bySemanticsLabel('neonkicks.example'));
      await tester.pump();
      expect(launcher.launched, [
        ('tel:+902165550112', PreferredLaunchMode.externalApplication),
        ('https://www.neonkicks.example/stores/kadikoy', PreferredLaunchMode.inAppBrowserView),
      ]);
    });

    testWidgets('no directions without directions: true', (tester) async {
      await pump(tester, [
        _wire('place_card', {'name': 'ATM', 'address': 'Moda Cd. 1', 'lat': 40.98, 'lng': 29.02}),
      ]);
      expect(find.text('Directions'), findsNothing);
      expect(find.byType(RendelActionButton), findsNothing);
    });

    testWidgets('on a detail page, the week under the line', (tester) async {
      await pump(tester, [_store], detail: true);
      expect(find.text('Mon–Fri'), findsOneWidget);
      expect(find.text('10:00–21:00'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('on an answer page it opens its detail, headed by its name, address and distance', (tester) async {
      final api = _Api();
      final c = controller(api);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: ThreadScreen(controller: c))),
        ),
      );
      await tester.runAsync(() async {
        unawaited(c.send('Where can I try them on?'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await api.answer(tester, [_block(_store)]);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.bySemanticsLabel(RegExp('^Neon Kicks Kadıköy, ')));
      await tester.pump();
      expect(api.sent, hasLength(2));
      expect(api.lastMessage['text'], 'Tell me about Neon Kicks Kadıköy');
      expect(api.lastMessage['detail_of'], {
        'title': 'Neon Kicks Kadıköy',
        'subtitle': 'Bağdat Cd. 312, Kadıköy · 1.2 km',
        'image_url': 'https://example.com/kadikoy.jpg',
      });
      await api.answer(tester, []);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('map', () {
    Size mapSize(WidgetTester tester, String key) => tester.getSize(find.byKey(ValueKey(key)));

    testWidgets('on the page: 200 tall, all pins fitted 40 in, no gestures, the credit and the caption', (tester) async {
      await pump(tester, [_stores]);
      final page = engine.built.last;
      expect(page.interactive, isFalse);
      final size = mapSize(tester, 'page-map');
      expect(size.height, 200);
      final points = [
        for (final pin in (_stores['props']['pins'] as List).cast<Map>())
          page.camera.project(pin['lat'] as double, pin['lng'] as double, size),
      ];
      for (final at in points) {
        expect(at.dx, inInclusiveRange(40 - 1e-6, size.width - 40 + 1e-6));
        expect(at.dy, inInclusiveRange(40 - 1e-6, size.height - 40 + 1e-6));
      }
      // Fitted, not merely inside: the pins span the room on one axis.
      final xs = points.map((p) => p.dx);
      final ys = points.map((p) => p.dy);
      final spanX = xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
      final spanY = ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
      expect(
        (spanX - (size.width - 80)).abs() < 0.01 || (spanY - (size.height - 80)).abs() < 0.01,
        isTrue,
        reason: 'spans $spanX × $spanY in ${size.width - 80} × ${size.height - 80}',
      );
      for (final label in ['Kadıköy', 'Moda', 'Beşiktaş']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('© OpenStreetMap'), findsOneWidget);
      expect(find.text('Three stores with the Aero Glide 2 in a 42.'), findsOneWidget);
    });

    testWidgets('a drag on the page map scrolls the page', (tester) async {
      final scroll = await pump(tester, [_stores]);
      await tester.drag(find.byKey(const ValueKey('page-map')), const Offset(0, -120));
      await tester.pump();
      expect(scroll.offset, greaterThan(90), reason: 'all of the drag but the touch slop');
      expect(engine.built.every((map) => !map.interactive), isTrue);
    });

    testWidgets('a tap opens it full screen: gestures, the pins, a callout, Open in Maps, ✕', (tester) async {
      await pump(tester, [_stores]);
      await tester.tap(find.byKey(const ValueKey('page-map')));
      await tester.pumpAndSettle();
      final full = engine.built.lastWhere((map) => map.interactive);
      expect(find.byKey(const ValueKey('full-map')), findsOneWidget);
      expect(mapSize(tester, 'full-map'), const Size(390, 844));
      expect(find.text('© OpenStreetMap'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);

      // Open in Maps, with no pin picked: the first.
      await tester.tap(find.bySemanticsLabel('Open in Maps'));
      await tester.pump();
      expect(launcher.launched.last, (
        'https://www.google.com/maps/dir/?api=1&destination=40.9634,29.0652',
        PreferredLaunchMode.externalApplication,
      ));

      // A pin tapped: its callout, and Open in Maps opens it.
      expect(find.text('Moda Cd. 88'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Moda, Moda Cd. 88'));
      await tester.pump();
      expect(find.text('Moda Cd. 88'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Moda, Moda Cd. 88')), isSemantics(isSelected: true));
      await tester.tap(find.bySemanticsLabel('Open in Maps, Moda'));
      await tester.pump();
      expect(launcher.launched.last.$1, 'https://www.google.com/maps/dir/?api=1&destination=40.9806,29.0262');

      // The pins follow the map as the user moves it.
      final before = tester.getRect(find.text('Kadıköy')).center;
      engine.moved!(RendelMapCamera(lat: full.camera.lat + 0.01, lng: full.camera.lng, zoom: full.camera.zoom));
      await tester.pump();
      final after = tester.getRect(find.text('Kadıköy')).center;
      expect(after.dx, closeTo(before.dx, 0.01));
      expect(after.dy, greaterThan(before.dy + 10), reason: 'north moved up the screen');

      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('full-map')), findsNothing);
      expect(find.byKey(const ValueKey('page-map')), findsOneWidget);
    });

    testWidgets('fitted full screen clear of the ✕ and the button', (tester) async {
      await pump(tester, [_stores]);
      await tester.tap(find.byKey(const ValueKey('page-map')));
      await tester.pumpAndSettle();
      final full = engine.built.lastWhere((map) => map.interactive);
      final button = tester.getRect(find.ancestor(of: find.text('Open in Maps'), matching: find.byType(RendelActionButton)));
      final close = tester.getRect(find.bySemanticsLabel('Close'));
      for (final pin in (_stores['props']['pins'] as List).cast<Map>()) {
        final at = full.camera.project(pin['lat'] as double, pin['lng'] as double, const Size(390, 844));
        expect(at.dy, lessThan(button.top - 30));
        expect(at.dy, greaterThan(close.bottom + 30));
      }
    });

    testWidgets('when the engine fails, the pins as a list, each opening in the maps app', (tester) async {
      engine.fails = true;
      await pump(tester, [_stores]);
      await tester.pump();
      expect(find.byKey(const ValueKey('page-map')), findsNothing);
      expect(find.text('Kadıköy'), findsOneWidget);
      expect(find.text('Bağdat Cd. 312'), findsOneWidget);
      expect(find.text('© OpenStreetMap'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Beşiktaş'));
      await tester.pump();
      expect(launcher.launched.single, (
        'https://www.google.com/maps/dir/?api=1&destination=41.0422,29.0083',
        PreferredLaunchMode.externalApplication,
      ));
    });

    test('the camera: one pin close in, a fit that round-trips', () {
      const size = Size(358, 200);
      final one = RendelMapCamera.fit([(lat: 40.9634, lng: 29.0652)], size, padding: const EdgeInsets.all(40));
      expect(one.zoom, RendelMapCamera.closest);
      expect(one.project(40.9634, 29.0652, size), offsetMoreOrLessEquals(const Offset(179, 100), epsilon: 1e-6));
      // Uneven padding moves the view's centre, not the pins' middle.
      final lopsided = RendelMapCamera.fit(
        [(lat: 40.96, lng: 29.06), (lat: 41.04, lng: 29.00)],
        const Size(390, 844),
        padding: const EdgeInsets.fromLTRB(40, 120, 40, 140),
      );
      final a = lopsided.project(40.96, 29.06, const Size(390, 844));
      final b = lopsided.project(41.04, 29.00, const Size(390, 844));
      expect((a.dx + b.dx) / 2, closeTo(195, 1e-6));
      expect((a.dy + b.dy) / 2, closeTo(120 + (844 - 260) / 2, 1e-6));
    });
  });

  group('pass', () {
    /// The code as the device drew it, pixel for pixel.
    Future<(ui.Image, ByteData)> grab(WidgetTester tester, Finder code) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.descendant(of: code, matching: find.byType(RepaintBoundary)).first,
      );
      late ui.Image image;
      late ByteData bytes;
      await tester.runAsync(() async {
        image = await boundary.toImage(pixelRatio: 3);
        bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      return (image, bytes);
    }

    bool dark(ByteData bytes, ui.Image image, int x, int y) {
      final i = (y * image.width + x) * 4;
      final (r, g, b) = (bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      // Pure ink or pure paper and nothing between: no smoothing.
      expect((r, g, b), anyOf((0, 0, 0), (255, 255, 255)), reason: 'pixel $x,$y is grey');
      return r == 0;
    }

    testWidgets('a QR matrix, module for module, in a quiet zone of 4', (tester) async {
      await pump(tester, [_pickup]);
      final (image, bytes) = await grab(tester, find.byType(RendelPassCode));
      const quiet = 4, n = 21;
      expect(image.width % (n + 2 * quiet), 0, reason: 'whole device pixels a module');
      final m = image.width ~/ (n + 2 * quiet);
      expect(image.height, image.width, reason: 'square');
      expect(m * (n + 2 * quiet) / 3, greaterThanOrEqualTo(160), reason: 'at least 160 pt wide');
      final bits = base64.decode(_qr['bits'] as String);
      var mismatches = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final (c, r) = (x ~/ m - quiet, y ~/ m - quiet);
          final inside = c >= 0 && c < n && r >= 0 && r < n;
          final expected = inside && bits[(r * n + c) >> 3] & (0x80 >> ((r * n + c) & 7)) != 0;
          if (dark(bytes, image, x, y) != expected) mismatches++;
        }
      }
      expect(mismatches, 0);
      expect(find.text('RD-4821-XYZ'), findsOneWidget);
      final shown = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(shown.style?.fontFamily, 'monospace');
    });

    testWidgets('code128 bars, bar first, in a quiet zone of 10', (tester) async {
      await pump(tester, [_coupon]);
      final (image, bytes) = await grab(tester, find.byType(RendelPassCode));
      final modules = _bars.fold<int>(0, (sum, width) => sum + width);
      expect(image.width % (modules + 20), 0);
      final m = image.width ~/ (modules + 20);
      expect(m * (modules + 20) / 3, greaterThanOrEqualTo(280), reason: 'at least 280 pt wide');
      // The module each column falls in is dark where a bar is.
      final ink = <bool>[];
      for (final (i, width) in _bars.indexed) {
        ink.addAll(List.filled(width, i.isEven));
      }
      final top = 4 * m, bottom = image.height - 4 * m;
      for (var x = 0; x < image.width; x++) {
        final k = x ~/ m - 10;
        final expected = k >= 0 && k < modules && ink[k];
        for (final y in [0, top, image.height ~/ 2, bottom - 1, image.height - 1]) {
          expect(dark(bytes, image, x, y), y >= top && y < bottom && expected, reason: 'column $x, row $y');
        }
      }
      expect(find.text('4821 XYZ'), findsOneWidget);
    });

    testWidgets('a PDF417 row is three modules tall', (tester) async {
      await pump(tester, [_boarding]);
      final (image, _) = await grab(tester, find.byType(RendelPassCode));
      final m = image.width ~/ (120 + 8);
      expect(image.width, m * (120 + 8));
      expect(image.height, m * (10 * 3 + 8));
    });

    testWidgets('no code drawn: only the display text', (tester) async {
      await pump(tester, [_member]);
      expect(find.byType(RendelPassCode), findsNothing);
      expect(find.text('NK 0042 7731'), findsOneWidget);
      expect(find.text('Membership'), findsOneWidget);
    });

    testWidgets('on white in a dark theme too', (tester) async {
      await pump(tester, [_pickup], theme: RendelTheme.deep());
      final (image, bytes) = await grab(tester, find.byType(RendelPassCode));
      expect(dark(bytes, image, 1, 1), isFalse, reason: 'the quiet zone is white');
    });

    testWidgets('the kind, the fields in three columns, until when', (tester) async {
      await pump(tester, [_pickup]);
      expect(find.text('Pickup'), findsOneWidget);
      expect(find.text('Order 4821'), findsOneWidget);
      double top(String text) => tester.getRect(find.text(text)).top;
      double left(String text) => tester.getRect(find.text(text)).left;
      expect(top('Items'), top('Shelf'));
      expect(left('Items'), lessThan(left('Name')));
      expect(top('Bag'), greaterThan(top('Items')), reason: 'a fourth starts a row');
      expect(left('Bag'), left('Items'));
      expect(find.textContaining(RegExp(r'^Valid until .*17')), findsOneWidget);
    });

    testWidgets('Android: Save to Google Wallet, to the system; no Apple badge', (tester) async {
      await pump(tester, [_pickup]);
      expect(find.byType(UiKitView), findsNothing);
      await tester.tap(find.bySemanticsLabel('Save to Google Wallet'));
      await tester.pump();
      expect(launcher.launched.single, (
        'https://pay.google.com/gp/v/save/eyJhbGciOi',
        PreferredLaunchMode.externalApplication,
      ));
    });

    testWidgets("iOS: Apple's own button, from the plugin, with the pass's address; no Google badge",
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final created = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
        if (call.method == 'create') created.add(call.arguments);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null));
      await pump(tester, [_pickup]);
      await tester.pump();
      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(view.viewType, 'rendel/add-pass');
      expect(view.creationParams, {'url': 'https://neonkicks.example/passes/4821.pkpass'});
      expect(find.bySemanticsLabel('Save to Google Wallet'), findsNothing);
      expect(created, hasLength(1));
      debugDefaultTargetPlatformOverride = null;
    });

    test('a code that cannot be painted is none', () {
      expect(RendelPassCode.tryParse({'format': 'qr', 'value': 'x'}), isNull);
      expect(
        RendelPassCode.tryParse({
          'matrix': {'rows': 21, 'cols': 21, 'bits': 'AAAA', 'module_aspect': 1},
        }),
        isNull,
        reason: 'too few bits for 21 × 21',
      );
      expect(RendelPassCode.tryParse({'bars': [2, 0, 1]}), isNull);
      expect(RendelPassCode.tryParse({'matrix': _qr})?.span, 21 + 8);
      expect(RendelPassCode.tryParse({'bars': _bars})?.span, _bars.fold<int>(0, (a, b) => a + b) + 20);
    });
  });

  test('every new string exists in all six languages', () {
    const english = RendelStrings();
    expect(english.directions, 'Directions');
    expect(english.call, 'Call');
    expect(english.openNow, 'Open now');
    expect(english.closed, 'Closed');
    expect(english.openInMaps, 'Open in Maps');
    expect(english.validUntilDate('12 Oct'), 'Valid until 12 Oct');
    expect(
      [english.passBoarding, english.passTicket, english.passPickup, english.passCoupon, english.passMembership],
      ['Boarding pass', 'Ticket', 'Pickup', 'Coupon', 'Membership'],
    );
    final turkish = RendelStrings.forLocale('tr');
    expect(turkish.directions, 'Yol tarifi');
    expect(turkish.call, 'Ara');
    expect(turkish.openNow, 'Şu an açık');
    expect(turkish.closed, 'Kapalı');
    expect(turkish.openInMaps, 'Haritalarda aç');
    expect(turkish.validUntilDate('12 Eki'), '12 Eki tarihine kadar geçerli');
    expect(
      [turkish.passBoarding, turkish.passTicket, turkish.passPickup, turkish.passCoupon, turkish.passMembership],
      ['Biniş kartı', 'Bilet', 'Teslim alma', 'Kupon', 'Üyelik'],
    );
    for (final language in ['tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      for (final (name, said, en) in [
        ('directions', strings.directions, english.directions),
        ('call', strings.call, english.call),
        ('openNow', strings.openNow, english.openNow),
        ('closed', strings.closed, english.closed),
        ('openInMaps', strings.openInMaps, english.openInMaps),
        ('validUntil', strings.validUntil, english.validUntil),
        ('passBoarding', strings.passBoarding, english.passBoarding),
        // German says "Ticket" too.
        if (language != 'de') ('passTicket', strings.passTicket, english.passTicket),
        ('passPickup', strings.passPickup, english.passPickup),
        ('passCoupon', strings.passCoupon, english.passCoupon),
        ('passMembership', strings.passMembership, english.passMembership),
      ]) {
        expect(said, isNot(en), reason: '$name is still English in $language');
      }
      expect(strings.validUntilDate('X'), contains('X'), reason: language);
      expect(strings.openNow, isNot(strings.closed), reason: language);
    }
  });

  group('the fixtures', () {
    // The gallery's are held in example/test/gallery_test.dart.
    test('parse against the protocol schema, the drawn codes included', () {
      for (final wire in [_store, _closed, _stores, _pickup, _coupon, _boarding, _member]) {
        expect(wireBlockErrors(wire), isEmpty, reason: '${wire['id']}');
      }
      final external = _wire('quick_replies', {
        'items': [
          {
            'label': 'Directions',
            'action': {'kind': 'open_url', 'url': 'https://maps.apple.com/?daddr=1,2', 'external': true},
          },
        ],
      });
      expect(wireBlockErrors(external), isEmpty, reason: 'open_url carries external');
    });

    test('the schema check is a real one', () {
      expect(
        wireBlockErrors(_wire('pass', {
          'kind': 'pickup',
          'title': 'x',
          'code': {'format': 'code128', 'value': 'x', 'bars': [5]},
        })),
        isNotEmpty,
        reason: 'a bar is 1 to 4 modules',
      );
      expect(wireBlockErrors(_wire('map', {'pins': []})), isNotEmpty, reason: 'a pin at least');
      expect(
        wireBlockErrors(_wire('place_card', {'name': 'x', 'address': 'y', 'lat': 91})),
        isNotEmpty,
        reason: 'a latitude',
      );
      expect(wireBlockErrors(_wire('pass', {'kind': 'visa', 'title': 'x'})), isNotEmpty);
    });
  });
}
