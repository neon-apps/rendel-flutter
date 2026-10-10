// Catalog wave 6 on the device (`design/CATALOG-B6.md`).
//
// product_cards carries fact chips on one line; variant_picker draws swatches
// and thumbnails, ringing the picked one, striking the sold-out ones and
// falling back to a chip; key_points says pro and con; media_gallery puts a
// caption under a picture and hands a video to the system; a receipt line
// carries a note and a change; progress draws rings for up to three goals;
// chart draws area, hbar and stacked_bar; and code copies itself and scrolls
// sideways inside its plate. Every fixture is held to the protocol's own wire
// schema.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
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

Map<String, dynamic> _wire(String type, Map<String, dynamic> props, {String? id}) => {
      'id': id ?? 'b_$type',
      'type': type,
      'fallback_text': 'A $type block.',
      'props': props,
    };

WireBlock _block(Map<String, dynamic> wire) => WireBlock.tryParse(jsonDecode(jsonEncode(wire)))!;

final _flats = _wire('product_cards', {
  'items': [
    {
      'title': 'Moda flat',
      'subtitle': 'Kadıköy',
      'price': '₺4.2M',
      'action': {'kind': 'reply', 'text': 'Tell me about the Moda flat'},
      'chips': ['3+1', '120 m²', '2 baths', 'Sea view'],
    },
    {'title': 'Fenerbahçe flat', 'price': '₺5.1M'},
  ],
});

final _colours = _wire('variant_picker', {
  'label': 'Colour',
  'style': 'swatches',
  'options': [
    {'id': 'navy', 'label': 'Navy', 'swatch_hex': '#1F2A44'},
    {'id': 'sand', 'label': 'Sand', 'swatch_hex': '#D8C8A8'},
    {'id': 'white', 'label': 'White', 'swatch_hex': '#FFFFFF', 'available': false},
    {'id': 'custom', 'label': 'Custom'},
  ],
  'selected_id': 'navy',
});

final _looks = _wire('variant_picker', {
  'label': 'Finish',
  'style': 'images',
  'options': [
    {'id': 'matte', 'label': 'Matte', 'image_url': 'https://example.com/matte.jpg'},
    {'id': 'gloss', 'label': 'Gloss', 'image_url': 'https://example.com/gloss.jpg', 'available': false},
    {'id': 'raw', 'label': 'Raw'},
  ],
  'selected_id': 'matte',
}, id: 'b_variant_images');

final _verdict = _wire('key_points', {
  'items': [
    {'title': 'Light', 'body': '238 g in a 42.', 'tone': 'positive'},
    {'title': 'Short battery', 'tone': 'negative'},
    {'icon': 'clock', 'title': 'Ships in 2 days', 'tone': 'neutral'},
  ],
});

final _tour = _wire('media_gallery', {
  'images': [
    {'url': 'https://example.com/street.jpg', 'alt': 'The flat from the street', 'caption': 'From Moda Cd.'},
    {
      'url': 'https://example.com/poster.jpg',
      'alt': 'Walkthrough',
      'caption': 'A minute round the flat',
      'video_url': 'https://example.com/tour.mp4',
    },
  ],
});

final _carousel = _wire('media_gallery', {
  'layout': 'carousel',
  'images': [
    {'url': 'https://example.com/a.jpg', 'alt': 'Hall', 'caption': 'The hall, with the coat cupboard'},
    {'url': 'https://example.com/b.jpg', 'alt': 'Kitchen'},
  ],
}, id: 'b_gallery_carousel');

final _bill = _wire('receipt', {
  'title': 'November',
  'lines': [
    {'label': 'Rent', 'amount': '₺42,000', 'note': '1–30 November', 'delta': '+₺2,000'},
    {'label': 'Service charge', 'amount': '₺1,200'},
  ],
  'total': '₺43,200',
});

final _goals = _wire('progress', {
  'style': 'ring',
  'items': [
    {'label': 'Steps', 'value': 6400, 'max': 10000},
    {'label': 'Water', 'value': 1.5, 'max': 2, 'value_label': '1.5 of 2 L', 'caption': 'Two more glasses'},
  ],
});

final _fourGoals = _wire('progress', {
  'style': 'ring',
  'items': [
    {'label': 'Steps', 'value': 6400, 'max': 10000},
    {'label': 'Water', 'value': 1.5, 'max': 2},
    {'label': 'Sleep', 'value': 7, 'max': 8},
    {'label': 'Stand', 'value': 9, 'max': 12},
  ],
}, id: 'b_progress_four');

final _area = _wire('chart', {
  'kind': 'area',
  'labels': ['Jul', 'Aug', 'Sep', 'Oct'],
  'series': [
    {'data': [3, 5, 4, 6]},
  ],
});

final _line = _wire('chart', {
  'kind': 'line',
  'labels': ['Jul', 'Aug', 'Sep', 'Oct'],
  'series': [
    {'data': [3, 5, 4, 6]},
  ],
}, id: 'b_chart_line');

final _stacked = _wire('chart', {
  'kind': 'stacked_bar',
  'labels': ['Sep', 'Oct'],
  'series': [
    {'name': 'Online', 'data': [3, 4]},
    {'name': 'In store', 'data': [2, 1]},
  ],
}, id: 'b_chart_stacked');

final _hbar = _wire('chart', {
  'kind': 'hbar',
  'labels': ['Trail running shoes', 'Walking', 'Sandals'],
  'series': [
    {'data': [12, 30, 0]},
  ],
  'unit': 'pairs',
}, id: 'b_chart_hbar');

const _curl = "curl -H 'X-Rendel-Key: rd_pk_test_123' https://api.rendel.ai/v1/health --max-time 10 --retry 3";

final _snippet = _wire('code', {
  'language': 'bash',
  'code': '$_curl\necho done',
  'caption': 'Health check, from any shell.',
});

void main() {
  late _Launcher launcher;
  late List<String> copied;
  late List<(String, String)> selected;

  setUp(() {
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    copied = [];
    selected = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  final theme = RendelTheme.paper();

  ConversationController controller([_Api? api]) => ConversationController(
        api: api ?? _Api(),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  /// [blocks] in a scrolling list on a phone, acting through the real
  /// controller and recording what is picked.
  Future<void> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> blocks, {
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = controller();
    addTearDown(c.dispose);
    final dispatch = RendelDispatcher(
      onAction: c.tapAction,
      onSubmitForm: c.submitForm,
      canHandle: c.handles,
      onSelect: (block, id, shown) async {
        selected.add((id, shown));
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: RendelThemeScope(
            theme: theme,
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final block in blocks.map(_block))
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
      ),
    );
    await tester.pump();
  }

  /// The container painted [color] in a [BoxDecoration].
  Finder painted(Color color) => find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == color,
      );

  test('the handshake declares code', () async {
    final api = _Api();
    final c = controller(api);
    unawaited(c.send('hello'));
    await Future<void>.delayed(Duration.zero);
    final client = api.sent.single['client'] as Map<String, dynamic>;
    expect(client['components'], contains('code'));
    expect(supportedComponents, contains('code'));
    expect(ComponentRegistry.registeredTypes, contains('code'));
    c.dispose();
  });

  group('product_cards chips', () {
    testWidgets('under the title, on one line, clipped at the card, named in its label', (tester) async {
      await pump(tester, [_flats]);
      final chips = ['3+1', '120 m²', '2 baths', 'Sea view'];
      double top(String text) => tester.getRect(find.text(text)).top;
      for (final chip in chips) {
        expect(find.text(chip), findsOneWidget);
        expect(top(chip), top(chips.first), reason: 'one line');
      }
      expect(top('3+1'), greaterThan(tester.getRect(find.text('Kadıköy')).bottom));
      expect(top('3+1'), lessThan(top('₺4.2M')));
      // The row is clipped to the card's width rather than wrapped or
      // overflowing it.
      final clip = tester.getRect(find.ancestor(of: find.text('3+1'), matching: find.byType(ClipRect)).first);
      expect(clip.width, lessThanOrEqualTo(theme.size.cardWidth - 2 * theme.space.plate + 0.01));
      expect(tester.getRect(find.text('Sea view')).left, greaterThan(clip.right), reason: 'clipped, not wrapped');
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp(r'^Moda flat, Kadıköy, 3\+1, 120 m², 2 baths, Sea view, ₺4\.2M$')), findsOneWidget);
      // A pill with the hairline and no fill.
      final pill = tester.widget<Container>(find.ancestor(of: find.text('3+1'), matching: find.byType(Container)).first);
      final decoration = pill.decoration! as BoxDecoration;
      expect(decoration.color, isNull);
      expect((decoration.border! as Border).top.color, theme.hairline);
      expect(tester.widget<Text>(find.text('3+1')).style?.fontWeight, FontWeight.w600);
      // A card without chips draws none.
      expect(find.byWidgetPredicate((w) => w is ClipRect && w.child is OverflowBox), findsOneWidget);
    });
  });

  group('variant_picker', () {
    testWidgets('swatches: 32 pt circles, the picked one ringed 2 pt out, the label under at 12', (tester) async {
      await pump(tester, [_colours]);
      final navy = painted(const Color(0xFF1F2A44));
      expect(tester.getSize(navy), const Size(32, 32));
      expect((tester.widget<Container>(navy).decoration! as BoxDecoration).shape, BoxShape.circle);
      BoxDecoration ring(Finder swatch) => tester
          .widget<AnimatedContainer>(find.ancestor(of: swatch, matching: find.byType(AnimatedContainer)).first)
          .decoration! as BoxDecoration;
      final picked = ring(navy).border! as Border;
      expect(picked.top.color, theme.colors.onSurface);
      expect(picked.top.width, 2);
      expect(
        tester.getSize(find.ancestor(of: navy, matching: find.byType(AnimatedContainer)).first),
        const Size(40, 40),
        reason: 'a 2 pt gap inside a 2 pt ring',
      );
      final sand = painted(const Color(0xFFD8C8A8));
      expect((ring(sand).border! as Border).top.color.a, 0, reason: 'unpicked: no ring, and nothing moves');
      expect(tester.getRect(find.text('Navy')).top, greaterThan(tester.getRect(navy).bottom));
      expect(tester.widget<Text>(find.text('Navy')).style?.fontSize, 12);
      expect(tester.getSemantics(find.bySemanticsLabel('Navy')), isSemantics(isSelected: true, isButton: true));
    });

    testWidgets('a sold-out swatch is struck through and cannot be picked; a tap sends the pick', (tester) async {
      await pump(tester, [_colours]);
      final white = painted(const Color(0xFFFFFFFF));
      Finder struck(Finder of) => find.ancestor(
            of: of,
            matching: find.byWidgetPredicate((w) => w is CustomPaint && '${w.foregroundPainter?.runtimeType}' == '_Struck'),
          );
      expect(struck(white), findsOneWidget);
      expect(struck(painted(const Color(0xFF1F2A44))), findsNothing);
      expect(find.bySemanticsLabel('Unavailable, White'), findsOneWidget);
      expect(find.text('Sold out: White'), findsOneWidget);
      await tester.tap(find.text('White'), warnIfMissed: false);
      await tester.tap(find.bySemanticsLabel('Sand'));
      await tester.pump();
      expect(selected, [('sand', 'Colour: Sand')]);
    });

    testWidgets('an option with no swatch falls back to a chip', (tester) async {
      await pump(tester, [_colours]);
      expect(find.widgetWithText(RendelChip, 'Custom'), findsOneWidget);
      expect(find.widgetWithText(RendelChip, 'Navy'), findsNothing);
      await tester.tap(find.text('Custom'));
      expect(selected, [('custom', 'Colour: Custom')]);
    });

    testWidgets('images: 64 pt thumbnails at a 12 pt corner, the label under, a chip without one', (tester) async {
      await pump(tester, [_looks]);
      final pictures = find.byType(Image);
      expect(pictures, findsNWidgets(2));
      for (final picture in pictures.evaluate()) {
        expect(tester.getSize(find.byWidget(picture.widget)), const Size(64, 64));
      }
      final corner = tester.widget<ClipRRect>(find.ancestor(of: pictures.first, matching: find.byType(ClipRRect)).first);
      expect(corner.borderRadius, BorderRadius.circular(12));
      expect(tester.getRect(find.text('Matte')).top, greaterThan(tester.getRect(pictures.first).bottom));
      expect(find.widgetWithText(RendelChip, 'Raw'), findsOneWidget);
      expect(find.bySemanticsLabel('Unavailable, Gloss'), findsOneWidget);
      expect(
        find.ancestor(
          of: pictures.last,
          matching: find.byWidgetPredicate((w) => w is CustomPaint && '${w.foregroundPainter?.runtimeType}' == '_Struck'),
        ),
        findsOneWidget,
      );
    });
  });

  group('key_points tone', () {
    testWidgets('a + in an ink circle, a − in a faint one, the icon for neutral; read as Pro: and Con:',
        (tester) async {
      await pump(tester, [_verdict]);
      final plus = find.byIcon(Icons.add_rounded);
      final minus = find.byIcon(Icons.remove_rounded);
      expect(plus, findsOneWidget);
      expect(minus, findsOneWidget);
      expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
      BoxDecoration circle(Finder glyph) =>
          tester.widget<Container>(find.ancestor(of: glyph, matching: find.byType(Container)).first).decoration!
              as BoxDecoration;
      expect(circle(plus).color, theme.colors.onSurface);
      expect(circle(plus).shape, BoxShape.circle);
      expect(circle(minus).color, theme.rail);
      // In the icon's column: the titles still line up.
      expect(tester.getRect(find.text('Light')).left, tester.getRect(find.text('Ships in 2 days')).left);
      expect(find.bySemanticsLabel(RegExp(r'^Pro:\s+Light\s+238 g in a 42\.$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Con:\s+Short battery$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Ships in 2 days$')), findsOneWidget);
    });
  });

  group('media_gallery', () {
    testWidgets('a caption under its picture, 13 in the soft ink', (tester) async {
      await pump(tester, [_tour]);
      final street = tester.getRect(find.bySemanticsLabel('The flat from the street'));
      final caption = tester.getRect(find.text('From Moda Cd.'));
      expect(caption.top, greaterThan(street.bottom));
      expect(caption.left, street.left);
      final style = tester.widget<Text>(find.text('From Moda Cd.')).style!;
      expect(style.fontSize, 13);
      expect(style.color, theme.colors.onSurfaceSoft);
    });

    testWidgets('a video: a play glyph over its poster, and a tap opens it outside the copilot', (tester) async {
      await pump(tester, [_tour]);
      final play = find.byIcon(Icons.play_arrow_rounded);
      expect(play, findsOneWidget);
      final poster = find.bySemanticsLabel('Play video, Walkthrough');
      expect(tester.getRect(play).center, offsetMoreOrLessEquals(tester.getRect(poster).center, epsilon: 0.5));
      await tester.tap(poster);
      await tester.pump();
      expect(launcher.launched.single, ('https://example.com/tour.mp4', PreferredLaunchMode.externalApplication));
      // A picture that is not a video is no button.
      expect(tester.getSemantics(find.bySemanticsLabel('The flat from the street')), isNot(isSemantics(isButton: true)));
    });

    testWidgets('a carousel grows to its captions', (tester) async {
      await pump(tester, [_carousel]);
      expect(find.text('The hall, with the coat cupboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final hall = tester.getRect(find.bySemanticsLabel('Hall'));
      expect(tester.getRect(find.text('The hall, with the coat cupboard')).top, greaterThan(hall.bottom));
    });
  });

  group('receipt', () {
    testWidgets('a note under the line, and the change in a pill before the amount', (tester) async {
      await pump(tester, [_bill]);
      expect(tester.getRect(find.text('1–30 November')).top, greaterThan(tester.getRect(find.text('Rent')).bottom));
      final note = tester.widget<Text>(find.text('1–30 November')).style!;
      expect(note.fontSize, 12.5);
      expect(note.color, theme.colors.onSurfaceSoft);
      final delta = tester.getRect(find.text('+₺2,000'));
      final amount = tester.getRect(find.text('₺42,000'));
      expect(delta.right, lessThan(amount.left));
      expect(delta.center.dy, closeTo(amount.center.dy, 2));
      final pill = tester.widget<Container>(find.ancestor(of: find.text('+₺2,000'), matching: find.byType(Container)).first);
      expect((pill.decoration! as BoxDecoration).color, theme.highlight);
      expect(tester.widget<Text>(find.text('+₺2,000')).style?.color, theme.colors.onSurfaceSoft);
      // The amounts still end in one column.
      expect(amount.right, closeTo(tester.getRect(find.text('₺1,200')).right, 0.01));
      expect(
        find.bySemanticsLabel(RegExp(r'^Rent\s+1–30 November\s+\+₺2,000\s+₺42,000$')),
        findsOneWidget,
        reason: 'one fact',
      );
    });
  });

  group('progress rings', () {
    testWidgets('88 pt rings side by side: the rail, the ink arc, the value inside and the label under',
        (tester) async {
      await pump(tester, [_goals]);
      expect(find.text('64%'), findsOneWidget, reason: 'the share, with no value label');
      expect(find.text('1.5 of 2 L'), findsOneWidget);
      final ring = find.ancestor(of: find.text('64%'), matching: find.byType(CustomPaint)).first;
      expect(tester.getSize(ring), const Size(88, 88));
      expect(tester.getRect(find.text('64%')).center, offsetMoreOrLessEquals(tester.getRect(ring).center, epsilon: 0.5));
      expect(
        tester.renderObject(ring),
        paints
          ..arc(color: theme.rail, strokeWidth: theme.size.trackHeight)
          ..arc(color: theme.colors.onSurface, startAngle: -math.pi / 2, sweepAngle: math.pi * 2 * 0.64),
      );
      expect(tester.getRect(find.text('Steps')).top, greaterThan(tester.getRect(ring).bottom));
      expect(tester.getRect(find.text('Steps')).top, tester.getRect(find.text('Water')).top);
      expect(tester.getRect(find.text('Steps')).left, lessThan(tester.getRect(find.text('Water')).left));
      expect(find.text('Two more glasses'), findsOneWidget);
      expect(tester.widget<Text>(find.text('64%')).style?.fontSize, 15);
      expect(tester.widget<Text>(find.text('Steps')).style?.fontSize, 13);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Steps, 6400 / 10000')),
        isSemantics(label: 'Steps, 6400 / 10000', value: '64%'),
      );
    });

    testWidgets('more than three fall back to bars', (tester) async {
      await pump(tester, [_fourGoals]);
      expect(find.text('64%'), findsNothing);
      expect(find.text('6400 / 10000'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNWidgets(4));
    });
  });

  group('chart', () {
    Finder plot() => find.byWidgetPredicate((w) => w is CustomPaint && '${w.painter?.runtimeType}' == '_PlotPainter');

    testWidgets('area: the line with the area under it at 12% of its ink', (tester) async {
      await pump(tester, [_area, _line]);
      final ink = theme.colors.onSurface;
      final fill = ink.withValues(alpha: ink.a * 0.12);
      expect(
        tester.renderObject(plot().first),
        paints
          ..path(color: fill, style: PaintingStyle.fill)
          ..path(color: ink, style: PaintingStyle.stroke),
      );
      expect(tester.renderObject(plot().last), isNot(paints..path(color: fill)), reason: 'a line has no area');
    });

    testWidgets('stacked_bar: each column the sum of its parts, a point apart, with a legend', (tester) async {
      await pump(tester, [_stacked]);
      final size = tester.getSize(plot());
      final height = theme.size.plotHeight;
      // The scale is the tallest column, 3 + 2, not the largest part.
      expect(find.text('5'), findsOneWidget);
      double y(double v) => height - (v - 0) / (5 - 0) * height;
      final column = size.width / 2;
      final gap = math.min(4.0, column * 0.2);
      expect(
        tester.renderObject(plot()),
        paints
          ..rect(rect: Rect.fromLTRB(gap / 2, y(3), gap / 2 + column - gap, y(0)), color: theme.colors.onSurface)
          ..rect(rect: Rect.fromLTRB(gap / 2, y(5), gap / 2 + column - gap, y(3) - 1), color: theme.colors.onSurfaceSoft)
          ..rect(rect: Rect.fromLTRB(column + gap / 2, y(4), column + gap / 2 + column - gap, y(0)))
          ..rect(rect: Rect.fromLTRB(column + gap / 2, y(5), column + gap / 2 + column - gap, y(4) - 1)),
      );
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('In store'), findsOneWidget);
    });

    testWidgets('hbar: labels at the start, bars along, the values at their ends', (tester) async {
      await pump(tester, [_hbar]);
      final bars = painted(theme.readoutFill);
      expect(bars, findsNWidgets(2), reason: 'nothing is a dot');
      final shoes = tester.getRect(bars.first);
      final walking = tester.getRect(bars.last);
      expect(tester.getRect(find.text('Trail running shoes')).right, lessThan(shoes.left));
      expect(shoes.left, walking.left);
      expect(shoes.width / walking.width, closeTo(12 / 30, 0.001));
      expect(tester.getRect(find.text('12 pairs')).left, greaterThan(shoes.right));
      expect(find.text('30 pairs'), findsOneWidget);
      expect(find.text('0 pairs'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^A chart block')), findsOneWidget, reason: 'the fallback names it');
    });

    testWidgets('hbar in RTL: the labels on the right', (tester) async {
      await pump(tester, [_hbar], direction: TextDirection.rtl);
      final bars = painted(theme.readoutFill);
      expect(tester.getRect(find.text('Walking')).left, greaterThan(tester.getRect(bars.last).right));
    });
  });

  group('code', () {
    Finder plate() => painted(const Color(0xFF141414));

    testWidgets('a dark plate: the language and Copy on its head, the code monospaced, the caption under',
        (tester) async {
      await pump(tester, [_snippet]);
      expect(tester.getSize(plate()).width, 390 - 32);
      expect((tester.widget<Container>(plate()).decoration! as BoxDecoration).borderRadius, BorderRadius.circular(16));
      expect(find.text('bash'), findsOneWidget);
      expect(tester.widget<Text>(find.text('bash')).style?.fontSize, 12);
      expect(find.text('Copy'), findsOneWidget);
      expect(tester.getRect(find.text('Copy')).center.dy, closeTo(tester.getRect(find.text('bash')).center.dy, 0.5));
      final code = tester.widget<Text>(find.text('$_curl\necho done'));
      expect(code.style?.fontFamily, 'monospace');
      expect(code.style?.fontSize, 12.5);
      expect(code.style?.height, 1.6);
      expect(code.softWrap, isFalse);
      expect(tester.getRect(find.text('Health check, from any shell.')).top, greaterThan(tester.getRect(plate()).bottom));
      expect(find.bySemanticsLabel('Copy, bash'), findsOneWidget);
    });

    testWidgets('Copy copies the code, as the copy action does, and says Copied for 1.5 s', (tester) async {
      await pump(tester, [_snippet]);
      await tester.tap(find.bySemanticsLabel('Copy, bash'));
      await tester.pump();
      await tester.pump();
      expect(copied, ['$_curl\necho done']);
      expect(find.text('Copied'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Copied')), isSemantics(isLiveRegion: true));
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('a long line scrolls sideways inside the plate, and the page stays put', (tester) async {
      await pump(tester, [_snippet]);
      final before = tester.getRect(plate());
      final scroll = find.descendant(of: plate(), matching: find.byType(Scrollable));
      final position = tester.state<ScrollableState>(scroll).position;
      expect(position.axis, Axis.horizontal);
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.drag(scroll, const Offset(-200, 0));
      await tester.pump();
      expect(position.pixels, greaterThan(150));
      expect(tester.getRect(plate()), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('code reads left to right on a right-to-left page', (tester) async {
      await pump(tester, [_snippet], direction: TextDirection.rtl);
      expect(tester.getRect(find.text('$_curl\necho done')).left, tester.getRect(plate()).left + 14);
    });
  });

  test('every new string exists in all six languages', () {
    const english = RendelStrings();
    expect([english.pro, english.con, english.playVideo, english.copyCode], ['Pro', 'Con', 'Play video', 'Copy']);
    final turkish = RendelStrings.forLocale('tr');
    expect([turkish.pro, turkish.con, turkish.playVideo, turkish.copyCode], ['Artı', 'Eksi', 'Videoyu oynat', 'Kopyala']);
    for (final language in ['tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      for (final (name, said, en) in [
        // German says "Pro" too.
        if (language != 'de') ('pro', strings.pro, english.pro),
        ('con', strings.con, english.con),
        ('playVideo', strings.playVideo, english.playVideo),
        ('copyCode', strings.copyCode, english.copyCode),
      ]) {
        expect(said, isNot(en), reason: '$name is still English in $language');
      }
      expect(strings.pro, isNot(strings.con), reason: language);
      // The code block's Copy is the word every other copy button says.
      expect(strings.copyCode, strings.copy, reason: language);
    }
  });

  group('the fixtures', () {
    // The gallery's are held in example/test/gallery_test.dart.
    test('parse against the protocol schema', () {
      for (final wire in [
        _flats,
        _colours,
        _looks,
        _verdict,
        _tour,
        _carousel,
        _bill,
        _goals,
        _fourGoals,
        _area,
        _line,
        _stacked,
        _hbar,
        _snippet,
      ]) {
        expect(wireBlockErrors(wire), isEmpty, reason: '${wire['id']}');
      }
    });

    test('the schema check is a real one', () {
      expect(
        wireBlockErrors(_wire('product_cards', {
          'items': [
            {'title': 'x', 'chips': ['a', 'b', 'c', 'd', 'e']},
          ],
        })),
        isNotEmpty,
        reason: 'four chips at most',
      );
      expect(
        wireBlockErrors(_wire('variant_picker', {
          'style': 'swatches',
          'options': [
            {'id': 'a', 'label': 'A', 'swatch_hex': '#FFF'},
            {'id': 'b', 'label': 'B'},
          ],
        })),
        isNotEmpty,
        reason: '#RRGGBB',
      );
      expect(
        wireBlockErrors(_wire('key_points', {
          'items': [
            {'title': 'x', 'tone': 'mixed'},
          ],
        })),
        isNotEmpty,
      );
      expect(
        wireBlockErrors(_wire('media_gallery', {
          'images': [
            {'url': 'https://example.com/a.jpg', 'caption': 'x' * 121},
          ],
        })),
        isNotEmpty,
        reason: 'a caption is 120 at most',
      );
      expect(
        wireBlockErrors(_wire('receipt', {
          'lines': [
            {'label': 'x', 'amount': '1', 'delta': 'x' * 21},
          ],
        })),
        isNotEmpty,
      );
      expect(
        wireBlockErrors(_wire('progress', {
          'style': 'pie',
          'items': [
            {'label': 'x', 'value': 1, 'max': 2},
          ],
        })),
        isNotEmpty,
      );
      expect(
        wireBlockErrors(_wire('chart', {
          'kind': 'pie',
          'labels': ['a'],
          'series': [
            {'data': [1]},
          ],
        })),
        isNotEmpty,
      );
      expect(wireBlockErrors(_wire('code', {'language': 'bash'})), isNotEmpty, reason: 'code is required');
      expect(wireBlockErrors(_wire('code', {'code': 'x' * 4001})), isNotEmpty);
    });
  });
}
