// The design rules, as assertions.
//
// A rule nobody checks is a preference. These three are the system the
// catalog is built on, and each of them is the kind of thing that decays one
// well-meaning renderer at a time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show buildSkeleton;

void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  /// Blocks that ask the reader something. Everything else is a readout.
  const asking = {
    'form',
    'datetime_slots',
    'variant_picker',
    'booking_card',
    'confirm_card',
  };

  /// The same palette with raised cards. Since 0.31 a card is flat unless a
  /// style asks otherwise, and the plate's material (hairline, shadow) is
  /// what these tests read, so they ask for it.
  RendelTheme raisedOf(RendelTheme t) => RendelTheme(
        colors: t.colors,
        accentText: t.accentText,
        accentEdge: t.accentEdge,
        danger: t.danger,
        style: const RendelStyle(card: RendelCardStyle.raised),
      );

  Future<void> pump(WidgetTester tester, Widget child, {RendelTheme? theme}) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RendelThemeScope(
          theme: theme ?? RendelTheme.paper(),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Every colour this subtree paints, from decorations and text alike.
  Set<Color> paintedColours(WidgetTester tester) {
    final found = <Color>{};
    for (final box in tester.widgetList<Container>(find.byType(Container))) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration) {
        if (decoration.color != null) found.add(decoration.color!);
        // Blocks v6 paints the primary action as a gradient (the accent lit
        // from above), so a fill is read from the gradient too.
        if (decoration.gradient case final Gradient gradient) {
          found.addAll(gradient.colors);
        }
        final border = decoration.border;
        if (border is Border) found.add(border.top.color);
      }
      if (box.color != null) found.add(box.color!);
    }
    for (final box in tester.widgetList<ColoredBox>(find.byType(ColoredBox))) {
      found.add(box.color);
    }
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final colour = text.style?.color;
      if (colour != null) found.add(colour);
    }
    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      if (icon.color != null) found.add(icon.color!);
    }
    return found;
  }

  group('the accent is a promise: it marks what you can act on', () {
    // Six of eleven accent uses were on things the reader cannot touch: the
    // streaming caret, a progress fill, a tracker dot, a chart's peak, a
    // donut's largest slice, a series colour. A signal spent on everything
    // signals nothing.
    final theme = RendelTheme.paper();

    final readouts = <String, Map<String, dynamic>>{
      'progress': {
        'items': [
          {'label': 'Photos', 'value': 3, 'max': 10},
        ],
      },
      'order_tracker': {
        'steps': [
          {'label': 'Packed', 'status': 'done'},
          {'label': 'Shipped', 'status': 'current'},
          {'label': 'Delivered', 'status': 'pending'},
        ],
      },
      // A line, where this was a single series of bars: blocks v6 lights the
      // latest bar the way the primary action is lit, by design
      // (`design/BLOCKS-v6.md`, "Chart (bar)"). A line chart still spends
      // nothing.
      'chart': {
        'kind': 'line',
        'labels': ['Mar', 'Apr', 'May'],
        'series': [
          {'data': [1, 4, 2]},
        ],
      },
      'stat_group': {
        'items': [
          {'label': 'Spent', 'value': r'$1,284', 'delta': '18%', 'trend': 'up'},
        ],
      },
      'receipt': {
        'title': 'Order 1042',
        'lines': [
          {'label': 'Aero Glide 2', 'amount': r'$129.00'},
        ],
        'total': r'$129.00',
      },
    };

    readouts.forEach((type, props) {
      testWidgets('$type is drawn in ink', (tester) async {
        await pump(
          tester,
          Builder(
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
        );
        expect(
          paintedColours(tester),
          isNot(contains(theme.colors.accent)),
          reason: '$type spends the accent on something you cannot touch',
        );
      });
    });

    testWidgets('a block that offers a control does spend it', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => ComponentRegistry.build(
            context,
            WireBlock(
              id: 'b_info',
              type: 'info_card',
              fallbackText: 'Returns.',
              props: {
                'title': 'Free returns',
                'body': 'Thirty days.',
                'cta': {
                  'label': 'Start a return',
                  'action': {'kind': 'reply', 'text': 'return'},
                },
              },
            )..ready = true,
            dispatch,
          ),
        ),
      );
      // The rule is not "never use the accent". It is "the accent means this".
      expect(paintedColours(tester), contains(theme.colors.accent));
    });
  });

  group('every plate is the same glass', () {
    // Blocks v6 (`design/BLOCKS-v6.md`, "Plate") moved the material a fourth
    // time, and this time it stopped saying anything about the block.
    //
    // Before, a readout RESTED on the thread and a block waiting on an answer
    // FLOATED on `surfaceHigh` with the `float` elevation. v6 makes every
    // plate one object: the raised surface at 82% so the thread's light comes
    // through it, a hairline drawn inside it, and one long soft shadow. A
    // question is told from a record by what is on it — a lit primary, the
    // chips — and a destructive one by its words, not by its plate.
    final theme = raisedOf(RendelTheme.paper());

    testWidgets('by default a plate is the glass alone (flat)', (tester) async {
      await pump(tester, Builder(builder: (c) => buildSkeleton(c, 'receipt')));
      final plate = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(plate.color, RendelTheme.paper().glass);
      expect(plate.boxShadow ?? const <BoxShadow>[], isEmpty,
          reason: 'a flat plate casts no shadow');
    });

    for (final type in [...asking, 'receipt', 'stat_group', 'table', 'chart']) {
      testWidgets(type, (tester) async {
        await pump(tester, Builder(builder: (context) {
          return buildSkeleton(context, type);
        }), theme: theme);

        final plate = tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .first;

        expect(plate.color, theme.glass, reason: '$type is not on the glass');
        // A hairline, never an ink outline.
        expect(plate.border, Border.all(color: theme.hairline),
            reason: '$type has an edge other than the hairline');
        expect(plate.boxShadow, theme.plateShadow,
            reason: '$type does not cast the plate shadow');
      });
    }

    testWidgets('a change that cannot be taken back says so in words',
        (tester) async {
      // The one meaning in this system that is not the accent, and it lives on
      // TYPE. It was a 1.5px ink border, then a wash of danger across the
      // whole plate; a tinted surface reads as an alarm and this card is a
      // question asked calmly about something serious. What makes it a colour
      // rather than a decoration is that it is measured — `contrast_test.dart`
      // holds `danger` to 4.5:1 on every surface it is drawn on — and there is
      // now exactly one place it is drawn: the overline.
      expect(theme.danger, isNot(theme.colors.accent),
          reason: 'danger and the accent must not be the same mark');
      expect(RendelTheme.deep().danger,
          isNot(RendelTheme.deep().colors.accent));
    });

    testWidgets('a deep plate carries the light a deep shadow cannot',
        (tester) async {
      // On a deep ground the shadow has nothing lighter to fall on, so the
      // plate's hairline is what separates it from the thread. Before v6 that
      // was a white top edge (`innerHighlight`) on deep plates only; the v6
      // plate draws its hairline — the ink at 10%, which on a deep theme is
      // the paper — all the way round on every ground, and its shadow goes
      // to black there.
      final deep = raisedOf(RendelTheme.deep());

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RendelThemeScope(
            theme: deep,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(builder: (c) => buildSkeleton(c, 'receipt')),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final plate = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(plate.border, Border.all(color: deep.hairline));
      expect(deep.hairline.computeLuminance(),
          greaterThan(deep.colors.surface.computeLuminance()),
          reason: 'the hairline is lighter than the deep ground');
      expect(plate.boxShadow!.single.color.r, 0,
          reason: 'a deep shadow is black, not the ink');
    });

    testWidgets('a readout and an asking block are not the same elevation',
        (tester) async {
      // Since blocks v6 the catalog's plates use neither (they cast the v6
      // plate shadow); the scale stays published, mirrored by rdui.css, for
      // hosts that read it. The assertion below still holds of it.
      //
      // The two are told apart by depth, so the two depths must differ. A
      // system where `raise` and `float` resolved to the same shadow list
      // would pass every assertion above and say nothing on screen.
      //
      // This is now the WHOLE of the distinction. It used to also require the
      // two surfaces to be different colours, and satisfying that on a light
      // theme meant putting the floating one at 98.7% luminance — a plate that
      // read as plain white and, being the surface every asking block uses,
      // read as white on the most important card in the product. The colours
      // are the same and the shadow does the work it was always doing.
      expect(theme.raise, isNot(equals(theme.float)));
    });
  });

  testWidgets('a block and its skeleton are the same material', (tester) async {
    // Otherwise hydration changes the block's material under the reader, which
    // is a flash rather than a swap.
    final theme = raisedOf(RendelTheme.paper());
    for (final type in ComponentRegistry.registeredTypes) {
      if (type == 'text') continue;
      await pump(tester, Builder(builder: (c) => buildSkeleton(c, type)), theme: theme);
      final skeleton = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstOrNull;
      if (skeleton == null) continue;
      // Blocks v6: one glass plate for every block, so one for every
      // skeleton too (it was `surfaceHigh` for an asking block and
      // `surfaceRaised` for a readout, with no edge).
      expect(skeleton.border, Border.all(color: theme.hairline),
          reason: "$type's skeleton has another edge than its block");
      expect(skeleton.color, theme.glass,
          reason: "$type's skeleton disagrees with its block");
    }
  });
}
