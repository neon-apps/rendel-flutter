// The lit fill tweened to and from a ring. Its highlight is one top edge, and
// in a BoxDecoration that edge could not be rounded with three others in
// another colour: a filled button turning disabled, or a chosen chip let go,
// threw "A borderRadius can only be given on borders with uniform colors" on
// every frame between, in debug, and left the control blank (inSepo, 0.63.4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

void main() {
  final theme = RendelTheme.paper();

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: theme,
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  /// Every frame of a 180ms swap, each one painted.
  Future<void> swap(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
  }

  for (final style in RendelButtonStyle.values) {
    testWidgets('a ${style.name} button turning disabled and back paints every frame', (tester) async {
      final styled = RendelTheme(colors: theme.colors, style: RendelStyle(button: style));
      Widget button(bool enabled) => RendelThemeScope(
            theme: styled,
            child: RendelActionButton(label: 'Send', onTap: enabled ? () {} : null),
          );
      await pump(tester, button(true));
      final size = tester.getSize(find.byType(RendelActionButton));
      await pump(tester, button(false));
      await swap(tester);
      // The lit fill and the ring keep the same inset: no jump in size.
      expect(tester.getSize(find.byType(RendelActionButton)), size);
      await pump(tester, button(true));
      await swap(tester);
    });
  }

  // Protein Ocean, 2026-11-06: a confirm button armed by a quantity stepped up
  // from 0 drew a dark smudge with no fill for a frame, then jumped to the
  // accent. Its shadow grew out of a point at full darkness while its fill
  // faded in from nothing.
  testWidgets('a button arming blends its fill and darkens its shadow in place', (tester) async {
    Widget button(bool enabled) => RendelActionButton(label: 'Add to cart', onTap: enabled ? () {} : null);
    BoxDecoration painted() => tester
        .widget<DecoratedBox>(find.descendant(
          of: find.byType(AnimatedContainer),
          matching: find.byType(DecoratedBox),
        ))
        .decoration as BoxDecoration;
    final lit = RendelTheme.litShadow.single;

    await pump(tester, button(false));
    await pump(tester, button(true));
    var shade = 0.0;
    var fill = theme.tint.a;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final box = painted();
      final shadow = box.boxShadow!.single;
      expect(shadow.blurRadius, lit.blurRadius);
      expect(shadow.spreadRadius, lit.spreadRadius);
      expect(shadow.offset, lit.offset);
      expect(shadow.color.a, greaterThanOrEqualTo(shade));
      shade = shadow.color.a;
      final least = (box.gradient! as LinearGradient).colors.map((c) => c.a).reduce((a, b) => a < b ? a : b);
      expect(least, greaterThanOrEqualTo(fill - 1e-6));
      fill = least;
    }
    expect(shade, lit.color.a);
    expect(fill, 1);
  });

  testWidgets('a chip chosen and let go paints every frame', (tester) async {
    Widget chip(bool selected) => RendelChip(label: 'Size 42', selected: selected, onTap: () {});
    await pump(tester, chip(false));
    await pump(tester, chip(true));
    await swap(tester);
    await pump(tester, chip(false));
    await swap(tester);
  });
}
