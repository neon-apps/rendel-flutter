// `theme.style`: how the parts are built, not only what colour they are.
//
// Each theme here arrives the way a device gets one, through a published
// payload applied over the shipped default, so the wire and the drawing are
// tested together.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

RendelTheme _styled(Map<String, String> style) => RendelRemoteConfig.tryParse(
      jsonEncode({
        'config': {
          'theme': {'style': style},
        },
      }),
    )!
        .applyTo(RendelTheme.paper());

void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  Future<void> pump(
    WidgetTester tester,
    RendelTheme theme,
    String type,
    Map<String, dynamic> props,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final block = WireBlock(
      id: 'b_$type',
      type: type,
      fallbackText: 'A $type block.',
      props: Map<String, dynamic>.from(props),
    )..ready = true;
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: theme,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (context) =>
                    ComponentRegistry.build(context, block, dispatch),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  final horizontalScroll = find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
  );

  const tap = {'kind': 'reply', 'text': 'Tell me more'};
  const products = {
    'items': [
      {'title': 'Aero Glide 2', 'price': r'$129', 'badge': 'Best seller', 'action': tap},
      {'title': 'Court Low', 'subtitle': 'Bone leather', 'price': r'$95', 'action': tap},
      {'title': 'Trail Circuit', 'rating': 4.2, 'action': tap},
    ],
  };

  group('product', () {
    testWidgets('tile is the rail it always was', (tester) async {
      await pump(tester, _styled({}), 'product_cards', products);
      expect(horizontalScroll, findsOneWidget);
    });

    for (final look in ['row', 'photo']) {
      testWidgets('$look is a list, one full-width card per item',
          (tester) async {
        await pump(tester, _styled({'product': look}), 'product_cards', products);
        expect(horizontalScroll, findsNothing);
        expect(find.text('Aero Glide 2'), findsOneWidget);
        expect(find.text(r'$95'), findsOneWidget);
        expect(find.text('Best seller'), findsOneWidget);
        // One under the other, each as wide as the thread.
        final first = find.ancestor(
          of: find.text('Aero Glide 2'),
          matching: find.byType(RendelPressable),
        );
        final second = find.ancestor(
          of: find.text('Court Low'),
          matching: find.byType(RendelPressable),
        );
        expect(tester.getTopLeft(second).dy,
            greaterThan(tester.getBottomLeft(first).dy));
        expect(tester.getSize(first).width, 320);
        // Every item keeps its action.
        expect(find.byType(RendelPressable), findsNWidgets(3));
      });
    }

    testWidgets('row puts the price at the end of the line', (tester) async {
      await pump(tester, _styled({'product': 'row'}), 'product_cards', products);
      final title = tester.getCenter(find.text('Aero Glide 2'));
      final price = tester.getCenter(find.text(r'$129'));
      expect(price.dx, greaterThan(title.dx));
    });

    testWidgets('photo puts the picture across the top', (tester) async {
      final theme = _styled({'product': 'photo'});
      await pump(tester, theme, 'product_cards', products);
      // No image_url, so each card draws the placeholder at full height.
      final placeholder = find.byIcon(Icons.image_not_supported_outlined).first;
      final box = find.ancestor(of: placeholder, matching: find.byType(Container)).first;
      expect(tester.getSize(box).height, theme.size.cardPhotoHeight);
      expect(
        tester.getTopLeft(find.text('Aero Glide 2')).dy,
        greaterThan(tester.getBottomLeft(box).dy),
      );
    });
  });

  group('tracker', () {
    const steps = {
      'title': 'Order 1042',
      'steps': [
        {'label': 'Ordered', 'status': 'done', 'timestamp': '22 Aug, 09:14'},
        {'label': 'Packed', 'status': 'done', 'timestamp': '23 Aug, 17:02'},
        {'label': 'Out for delivery', 'status': 'current', 'timestamp': '26 Aug'},
        {'label': 'Delivered', 'status': 'pending'},
      ],
    };

    // Blocks v6 says the position in words, "Step k of N" rather than
    // "k/N", and keeps the status pill in the head on every tracker style —
    // so the current step's name is drawn twice: in the pill and on the bar.
    testWidgets('bar says which step it is on, as Step k of N', (tester) async {
      await pump(tester, _styled({'tracker': 'bar'}), 'order_tracker', steps);
      expect(find.text('Order 1042'), findsOneWidget);
      expect(find.text('Step 3 of 4'), findsOneWidget);
      expect(find.text('Out for delivery'), findsNWidgets(2));
      expect(find.text('26 Aug'), findsOneWidget);
      // One step, not the list.
      expect(find.text('Ordered'), findsNothing);
    });

    testWidgets('bar fills as far as the steps reached', (tester) async {
      await pump(tester, _styled({'tracker': 'bar'}), 'order_tracker', steps);
      final fill = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fill.widthFactor, 3 / 4);
    });

    testWidgets('bar with nothing under way names the last step finished',
        (tester) async {
      await pump(tester, _styled({'tracker': 'bar'}), 'order_tracker', {
        'steps': [
          {'label': 'Ordered', 'status': 'done'},
          {'label': 'Packed', 'status': 'done'},
          {'label': 'Delivered', 'status': 'pending'},
        ],
      });
      expect(find.text('Packed'), findsOneWidget);
      // "Step k of N", not "k/N" (blocks v6).
      expect(find.text('Step 2 of 3'), findsOneWidget);
    });

    testWidgets('bar with nothing reached names the first step',
        (tester) async {
      await pump(tester, _styled({'tracker': 'bar'}), 'order_tracker', {
        'steps': [
          {'label': 'Ordered', 'status': 'pending'},
          {'label': 'Delivered', 'status': 'pending'},
        ],
      });
      expect(find.text('Ordered'), findsOneWidget);
      // "Step k of N", not "k/N" (blocks v6).
      expect(find.text('Step 1 of 2'), findsOneWidget);
    });

    testWidgets('horizontal is one row of steps, without their times',
        (tester) async {
      await pump(tester, _styled({'tracker': 'horizontal'}), 'order_tracker', steps);
      // `.last`: blocks v6 also names the current step in the head's status
      // pill, which comes first in the tree; the step's own label is last.
      final rows = {
        for (final label in ['Ordered', 'Packed', 'Out for delivery', 'Delivered'])
          tester.getTopLeft(find.text(label).last).dy,
      };
      expect(rows, hasLength(1), reason: 'every label on the same line');
      expect(find.text('22 Aug, 09:14'), findsNothing);
      expect(
        tester.getCenter(find.text('Delivered')).dx,
        greaterThan(tester.getCenter(find.text('Ordered')).dx),
      );
    });
  });

  group('card', () {
    BoxDecoration plate(WidgetTester tester) => tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
        .decoration! as BoxDecoration;

    // A block waiting on an answer, which is the plate that floats.
    const confirm = {
      'summary': 'Cancel order 1042?',
      'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
      'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
    };

    // Blocks v6: every plate is the same glass (the raised surface at 82%),
    // whatever the block is for. Raised adds the inset hairline and the long
    // soft shadow, outlined keeps its strong line without a shadow, flat is
    // the glass alone. A plate waiting on an answer no longer floats on
    // `surfaceHigh` with the `float` elevation.
    testWidgets('raised is the glass plate: hairline and long shadow',
        (tester) async {
      // Named: since 0.31 a card is flat unless the style says raised.
      final theme = _styled({'card': 'raised'});
      await pump(tester, theme, 'confirm_card', confirm);
      final decoration = plate(tester);
      expect(decoration.color, theme.glass);
      expect(decoration.border, Border.all(color: theme.hairline));
      expect(decoration.boxShadow, theme.plateShadow);
    });

    testWidgets('outlined takes the strong line and drops the shadow',
        (tester) async {
      final theme = _styled({'card': 'outlined'});
      await pump(tester, theme, 'confirm_card', confirm);
      final decoration = plate(tester);
      expect(decoration.color, theme.glass);
      expect(decoration.border, Border.all(color: theme.colors.lineStrong));
      expect(decoration.boxShadow, isEmpty);
    });

    testWidgets('flat has neither', (tester) async {
      final theme = _styled({'card': 'flat'});
      await pump(tester, theme, 'confirm_card', confirm);
      final decoration = plate(tester);
      expect(decoration.color, theme.glass);
      expect(decoration.border, isNull);
      expect(decoration.boxShadow, isEmpty);
    });

    testWidgets('outlined reaches the product cards too', (tester) async {
      final theme = _styled({'card': 'outlined'});
      await pump(tester, theme, 'product_cards', products);
      final cards = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          // v6: a product card is the plate's glass, not the bare plate.
          .where((d) => d.color == theme.glass);
      expect(cards, hasLength(3));
      for (final card in cards) {
        expect(card.border, Border.all(color: theme.colors.lineStrong));
        expect(card.boxShadow, isEmpty);
      }
    });
  });

  // `theme.cards`: one kind of card set apart, the rest left as they are.
  group('one kind of card', () {
    RendelTheme withCards(Map<String, dynamic> theme) => RendelRemoteConfig.tryParse(
          jsonEncode({
            'config': {'theme': theme},
          }),
        )!
            .applyTo(RendelTheme.paper());

    const palette = {
      'surface': '#241A1E',
      'onSurface': '#F6E8EC',
      'accent': '#F2A0BE',
      'onAccent': '#2A1017',
    };
    const confirm = {
      'summary': 'Cancel order 1042?',
      'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
      'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
    };

    test('reads each kind on its own and keeps the theme for the others', () {
      final theme = withCards({
        ...palette,
        'cards': {
          'product_cards': {'surfaceRaised': '#3A2A30', 'radius': 4, 'style': 'flat'},
          'info_card': {'style': 'glass', 'radius': 90},
          'chart': {'radius': 2},
        },
      });
      final product = theme.forCard('product_cards');
      expect(product.colors.surfaceRaised, const Color(0xFF3A2A30));
      expect(product.colors.surfaceHigh, const Color(0xFF3A2A30));
      expect(product.radius.card, 4);
      expect(product.style.card, RendelCardStyle.flat);
      expect(identical(theme.forCard('product_cards'), product), isTrue);
      // A kind with nothing it can draw, and a kind it does not know, are the theme.
      expect(theme.forCard('info_card').radius.card, theme.radius.card);
      expect(identical(theme.forCard('chart'), theme), isTrue);
      expect(identical(theme.forCard('item_list'), theme), isTrue);
    });

    test("drops a card's colours when no palette is published", () {
      final theme = withCards({
        'cards': {
          'item_list': {'surfaceRaised': '#3A2A30', 'radius': 6},
        },
      });
      final list = theme.forCard('item_list');
      expect(list.colors.surfaceRaised, theme.colors.surfaceRaised);
      expect(list.radius.card, 6);
    });

    testWidgets('the confirmation takes its own plate and build', (tester) async {
      final theme = withCards({
        ...palette,
        'cards': {
          'confirm_card': {'surfaceRaised': '#3A2A30', 'style': 'outlined', 'radius': 3},
        },
      });
      await pump(tester, theme, 'confirm_card', confirm);
      final decoration = tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
          .decoration! as BoxDecoration;
      // v6: the plate is the card's own colour as glass (82% over the
      // thread's ground), and rounds 8 more than the card radius so what sits
      // inside it is concentric.
      expect(
        decoration.color,
        Color.alphaBlend(
          const Color(0xFF3A2A30).withValues(alpha: 0.82),
          theme.colors.surface,
        ),
      );
      expect(decoration.border, Border.all(color: theme.colors.lineStrong));
      expect(decoration.boxShadow, isEmpty);
      expect((decoration.borderRadius! as BorderRadiusDirectional).topStart, const Radius.circular(3 + 8));
    });

    testWidgets("a product card's parts take their own colour and size", (tester) async {
      final theme = withCards({
        ...palette,
        'cards': {
          'product_cards': {
            'parts': {
              'price': {'color': '#F2A0BE', 'size': 19},
              'stars': {'color': '#E3A008'},
              'info': {'size': 30},
            },
          },
        },
      });
      await pump(tester, theme, 'product_cards', products);
      final price = tester.widget<Text>(find.text(r'$129').first);
      expect(price.style!.color, const Color(0xFFF2A0BE));
      expect(price.style!.fontSize, 19);
      final stars = tester.widgetList<Text>(find.text('★★★★★')).map((t) => t.style!.color).toList();
      expect(stars, contains(const Color(0xFFE3A008)));
      // The title is a part nobody set: the theme's.
      final title = tester.widget<Text>(find.text('Aero Glide 2').first);
      expect(title.style!.fontSize, theme.text.label.fontSize);
    });

    testWidgets("a confirmation's buttons and their words are parts of their own", (tester) async {
      final theme = withCards({
        ...palette,
        'cards': {
          'confirm_card': {
            'parts': {
              'cancel': {'fill': '#3A5A7A', 'radius': 4},
              'cancel_text': {'color': '#FFFFFF', 'size': 15},
            },
          },
        },
      });
      await pump(tester, theme, 'confirm_card', confirm);
      final words = tester.widget<AnimatedDefaultTextStyle>(
        find.ancestor(of: find.text('Go back'), matching: find.byType(AnimatedDefaultTextStyle)).first,
      );
      expect(words.style.color, const Color(0xFFFFFFFF));
      expect(words.style.fontSize, 15);
      final box = tester
          .widget<AnimatedContainer>(
            find.ancestor(of: find.text('Go back'), matching: find.byType(AnimatedContainer)).first,
          )
          .decoration! as BoxDecoration;
      expect(box.color, const Color(0xFF3A5A7A));
      expect(box.borderRadius, BorderRadius.circular(4));
      // The other button keeps the theme.
      final confirmWords = tester.widget<AnimatedDefaultTextStyle>(
        find.ancestor(of: find.text('Confirm'), matching: find.byType(AnimatedDefaultTextStyle)).first,
      );
      expect(confirmWords.style.fontSize, theme.text.labelStrong.fontSize);
    });

    test("drops a part's colour but keeps its size with no palette", () {
      final theme = withCards({
        'cards': {
          'info_card': {
            'parts': {
              'title': {'color': '#F2A0BE', 'size': 20},
            },
          },
        },
      });
      final part = theme.forCard('info_card').parts['title']!;
      expect(part.color, isNull);
      expect(part.size, 20);
    });

    testWidgets('a block of another kind keeps the theme', (tester) async {
      // The theme's cards are raised, the product card alone is flat: the
      // confirm card must keep the theme's plate and its shadow.
      final theme = withCards({
        ...palette,
        'style': {'card': 'raised'},
        'cards': {
          'product_cards': {'surfaceRaised': '#3A2A30', 'style': 'flat'},
        },
      });
      await pump(tester, theme, 'confirm_card', confirm);
      final decoration = tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
          .decoration! as BoxDecoration;
      expect(decoration.color, theme.glass);
      expect(decoration.boxShadow, theme.plateShadow);
    });
  });

  group('button', () {
    Future<void> pumpButtons(WidgetTester tester, RendelTheme theme) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: theme,
            child: Scaffold(
              body: Column(
                children: [
                  RendelActionButton(label: 'Confirm', onTap: () {}),
                  RendelActionButton(label: 'Go back', quiet: true, onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      );
    }

    BoxDecoration decorationOf(WidgetTester tester, String label) => tester
        .widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .decoration! as BoxDecoration;

    // Blocks v6: the outlined (legacy) button is white with a soft ring of
    // the accent at 45% and a small lift, never a heavy dark ring; its words
    // stay in the accent's legible form.
    testWidgets('outlined is white with a soft accent ring round accent text',
        (tester) async {
      final theme = _styled({'button': 'outlined'});
      await pumpButtons(tester, theme);
      final decoration = decorationOf(tester, 'Confirm');
      expect(decoration.color, theme.colors.surfaceHigh);
      expect(decoration.boxShadow, isNotEmpty);
      expect(
        decoration.border,
        Border.all(color: theme.colors.accent.withValues(alpha: 0.45), width: 1.5),
      );
      // The nearest one: Material sets its own further up.
      final label = tester.widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.text('Confirm'),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      );
      expect(label.style.color, theme.accentText);
    });

    testWidgets('outlined is the same size as filled', (tester) async {
      await pumpButtons(tester, _styled({}));
      final filled = tester.getSize(find.byType(RendelActionButton).first);
      await pumpButtons(tester, _styled({'button': 'outlined'}));
      expect(tester.getSize(find.byType(RendelActionButton).first), filled);
    });

    testWidgets('a quiet button keeps its own look', (tester) async {
      await pumpButtons(tester, _styled({}));
      final before = decorationOf(tester, 'Go back');
      await pumpButtons(tester, _styled({'button': 'outlined'}));
      expect(decorationOf(tester, 'Go back'), before);
    });
  });
}
