// The derivation, pinned to exact values.
//
// `packages/ui/src/theme/derive.ts` is a line-for-line mirror of the theme
// derivation in this package, because the console has to refuse a failing
// colour pair at edit time and the only honest way to do that is to run the
// arithmetic the device will run. A mirror is only worth having if it is
// checked, so both sides assert the SAME hex values for the SAME inputs:
// `packages/ui/test/derive.test.ts` holds the list below verbatim.
//
// If you change a lerp factor, a bisection count or a threshold, both files
// fail together. That is the point.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

String _hex(Color color) {
  final value = (color.r * 255).round() << 16 |
      (color.g * 255).round() << 8 |
      (color.b * 255).round();
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

void main() {
  test('the Neon roles derive to the values the console mirrors', () {
    final theme = RendelTheme.fromTokens(
      surface: const Color(0xFFECE9E8),
      onSurface: const Color(0xFF2E2A29),
      accent: const Color(0xFFF55733),
      onAccent: const Color(0xFF1F1A19),
    );
    expect(_hex(theme.colors.surface), '#ECE9E8');
    expect(_hex(theme.colors.surfaceRaised), '#F4F2F2');
    expect(_hex(theme.colors.surfaceSunk), '#DFDCDB');
    expect(_hex(theme.colors.surfaceHigh), '#F9F8F8');
    expect(_hex(theme.colors.onSurfaceSoft), '#4E4B4A');
    expect(_hex(theme.colors.onSurfaceFaint), '#64605F');
    expect(_hex(theme.accentText), '#AA3C23');
  });

  test('a dark brand derives to the values the console mirrors', () {
    final theme = RendelTheme.fromTokens(
      surface: const Color(0xFF101014),
      onSurface: const Color(0xFFF2F2F7),
      accent: const Color(0xFF7C5BFF),
      onAccent: const Color(0xFFFFFFFF),
    );
    expect(_hex(theme.colors.surfaceRaised), '#1C1C20');
    expect(_hex(theme.colors.surfaceSunk), '#0B0B0E');
    expect(_hex(theme.colors.surfaceHigh), '#262629');
    // White on #7C5BFF is 4.38:1, so it is rescued rather than shipped.
    expect(_hex(theme.colors.onAccent), '#090909');
  });

  test('a hostile light brand derives to the values the console mirrors', () {
    final theme = RendelTheme.fromTokens(
      surface: const Color(0xFFFFF6F0),
      onSurface: const Color(0xFF2A1B12),
      accent: const Color(0xFFFF9A3D),
      onAccent: const Color(0xFFFFFFFF),
    );
    expect(_hex(theme.colors.onAccent), '#454545');
    expect(_hex(theme.colors.onSurfaceSoft), '#564840');
    expect(_hex(theme.colors.onSurfaceFaint), '#74675F');
  });

  test('a brand whose own ink fails is rescued, not shipped', () {
    // A warm mid-grey on a warm off-white is an entirely ordinary pairing and
    // it fails AA. `onAccent` was rescued and `onSurface` was not, so all
    // three ink steps collapsed onto one failing colour and shipped.
    final theme = RendelTheme.fromTokens(
      surface: const Color(0xFFFFF7E6),
      onSurface: const Color(0xFF8A7A62),
      accent: const Color(0xFFF55733),
      onAccent: const Color(0xFF000000),
    );
    expect(theme.colors.onSurface, isNot(const Color(0xFF8A7A62)));
    for (final background in [
      theme.colors.surface,
      theme.colors.surfaceRaised,
      theme.colors.surfaceSunk,
      theme.colors.surfaceHigh,
    ]) {
      for (final ink in [
        theme.colors.onSurface,
        theme.colors.onSurfaceSoft,
        theme.colors.onSurfaceFaint,
      ]) {
        expect(contrastRatio(ink, background), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('lineControl is solved on the RESCUED ink, on both sides', () {
    // The one role the mirror got wrong. `lineControl` reads
    // `colors.onSurface`, which `fromTokens` has already replaced with the
    // rescued ink; the console passed the raw value and reported a boundary
    // failure on a theme the device draws correctly — and a reported failure
    // disables Save and Publish, so the editor locked for exactly the brands
    // the rescue exists for. Both cases below are ink-rescue cases.
    for (final probe in [
      (
        const Color(0xFFFFF7E6),
        const Color(0xFF8A7A62),
        const Color(0xFFF55733),
        const Color(0xFF000000),
        '#756753',
        0.7805,
      ),
      (
        const Color(0xFFFFFFFF),
        const Color(0xFFCCCCCC),
        const Color(0xFF1155CC),
        const Color(0xFFFFFFFF),
        '#6D6D6D',
        0.7817,
      ),
    ]) {
      final theme = RendelTheme.fromTokens(
        surface: probe.$1,
        onSurface: probe.$2,
        accent: probe.$3,
        onAccent: probe.$4,
      );
      expect(_hex(theme.lineControl), probe.$5);
      expect(theme.lineControl.a, closeTo(probe.$6, 0.0002));
      // And it is the rescued ink it was solved from, not the mapped one.
      expect(_hex(theme.lineControl), _hex(theme.colors.onSurface));
    }
  });

  test('every derived role clears its floor by more than 8-bit rounding', () {
    // A bisection lands ON the floor, and the compositor then rounds to eight
    // bits per channel — worth about 0.02 of ratio, which is how a derivation
    // passes its own test and the pixels fail. Every solver carries a margin.
    for (final tokens in [
      (const Color(0xFFECE9E8), const Color(0xFF2E2A29)),
      (const Color(0xFFFFF6F0), const Color(0xFF2A1B12)),
      (const Color(0xFF101014), const Color(0xFFF2F2F7)),
    ]) {
      final theme = RendelTheme.fromTokens(
        surface: tokens.$1,
        onSurface: tokens.$2,
        accent: const Color(0xFFF55733),
        onAccent: const Color(0xFF000000),
      );
      for (final background in [
        theme.colors.surface,
        theme.colors.surfaceRaised,
        theme.colors.surfaceSunk,
        theme.colors.surfaceHigh,
      ]) {
        expect(contrastRatio(theme.lineControl, background),
            greaterThanOrEqualTo(3.03));
        expect(contrastRatio(theme.accentEdge, background),
            greaterThanOrEqualTo(3.03));
        expect(contrastRatio(theme.accentText, background),
            greaterThanOrEqualTo(4.53));
      }
    }
  });

  test('the two quiet ink steps stay visibly apart', () {
    // They used to be clamped separately, which fixed the floor and broke the
    // hierarchy: on the Neon ground both landed within two points of each
    // other and the catalog lost its tertiary ink entirely.
    for (final tokens in [
      (const Color(0xFFECE9E8), const Color(0xFF2E2A29)),
      (const Color(0xFFFFF6F0), const Color(0xFF2A1B12)),
      (const Color(0xFF101014), const Color(0xFFF2F2F7)),
    ]) {
      final theme = RendelTheme.fromTokens(
        surface: tokens.$1,
        onSurface: tokens.$2,
        accent: const Color(0xFFF55733),
        onAccent: const Color(0xFF000000),
      );
      final soft = contrastRatio(theme.colors.onSurfaceSoft, theme.colors.surface);
      final faint = contrastRatio(theme.colors.onSurfaceFaint, theme.colors.surface);
      expect(faint, greaterThanOrEqualTo(4.5));
      expect(
        soft / faint,
        greaterThan(1.25),
        reason: 'soft and faint collapsed into one step',
      );
    }
  });

  // The bubble pair, held to the same values the console mirrors in
  // `packages/ui/test/derive.test.ts`.
  //
  // The default matters more than the override here: naming a role that was
  // previously an unnamed inversion is only safe if an app that says nothing
  // about it renders exactly as it did before.
  test('a bubble nobody sets is a surface with ink on it', () {
    final theme = RendelTheme.fromTokens(
      surface: const Color(0xFFECE9E8),
      onSurface: const Color(0xFF2E2A29),
      accent: const Color(0xFFF55733),
      onAccent: const Color(0xFF1F1A19),
    );
    // A step of the ground, not the ink. It was the other way round for a day
    // and the field called "Text" repainted the bubble, which is the same
    // complaint the product card had about the same shortcut.
    expect(_hex(theme.colors.bubble), _hex(theme.colors.surfaceSunk));
    expect(_hex(theme.colors.onBubble), _hex(theme.colors.onSurface));
  });

  test('a bubble nobody sets does not move when the text colour does', () {
    String bubbleFor(Color ink) => _hex(
          RendelTheme.fromTokens(
            surface: const Color(0xFFECE9E8),
            onSurface: ink,
            accent: const Color(0xFFF55733),
            onAccent: const Color(0xFF1F1A19),
          ).colors.bubble,
        );
    expect(bubbleFor(const Color(0xFF2E2A29)), bubbleFor(const Color(0xFF000000)));
    expect(bubbleFor(const Color(0xFF2E2A29)), bubbleFor(const Color(0xFF6B3010)));
  });

  test('a bubble a brand names keeps its colour, and its text is rescued', () {
    final legible = RendelTheme.fromTokens(
      surface: const Color(0xFFECE9E8),
      onSurface: const Color(0xFF2E2A29),
      accent: const Color(0xFFF55733),
      onAccent: const Color(0xFF1F1A19),
      bubble: const Color(0xFF1D4ED8),
      onBubble: const Color(0xFFFFFFFF),
    );
    expect(_hex(legible.colors.bubble), '#1D4ED8');
    expect(_hex(legible.colors.onBubble), '#FFFFFF');

    // White on mid-yellow is about 1.3:1. The device rescues it rather than
    // drawing text nobody can read, and the console derives the same rescue.
    final rescued = RendelTheme.fromTokens(
      surface: const Color(0xFFECE9E8),
      onSurface: const Color(0xFF2E2A29),
      accent: const Color(0xFFF55733),
      onAccent: const Color(0xFF1F1A19),
      bubble: const Color(0xFFF5C542),
      onBubble: const Color(0xFFFFFFFF),
    );
    expect(_hex(rescued.colors.onBubble), isNot('#FFFFFF'));
  });

  /// The message box, pinned on both sides.
  ///
  /// `packages/ui/test/derive.test.ts` asserts the same four values for the
  /// same three inputs. The first case is the one that matters most: a
  /// palette that says nothing about the box must derive exactly what it
  /// derived before the pair existed, or every theme already published moves.
  group('the composer', () {
    final neon = RendelTheme.fromTokens(
      surface: const Color(0xFFECE9E8),
      onSurface: const Color(0xFF2E2A29),
      accent: const Color(0xFFF55733),
      onAccent: const Color(0xFF1F1A19),
    );

    test('is the floating surface until somebody says otherwise', () {
      expect(_hex(neon.colors.composer), _hex(neon.colors.surfaceHigh));
      expect(_hex(neon.colors.onComposer), _hex(neon.colors.onSurface));
      expect(_hex(neon.onComposerFaint), _hex(neon.colors.onSurfaceFaint));
      expect(_hex(neon.composerEdge), _hex(neon.lineControl));
      expect(neon.composerEdge.a, neon.lineControl.a);
      // And the values themselves, so "unchanged" cannot be satisfied by both
      // sides moving together.
      expect(_hex(neon.colors.composer), '#F9F8F8');
      expect(_hex(neon.onComposerFaint), '#64605F');
    });

    test('rescues the thread ink onto a dark box', () {
      final theme = RendelTheme.fromTokens(
        surface: const Color(0xFFECE9E8),
        onSurface: const Color(0xFF2E2A29),
        accent: const Color(0xFFF55733),
        onAccent: const Color(0xFF1F1A19),
        composer: const Color(0xFF141414),
      );
      expect(_hex(theme.colors.composer), '#141414');
      expect(_hex(theme.colors.onComposer), '#807E7D');
      // No room left to quiet it: the rescue lands just above the floor, so
      // `_quietRoom` correctly returns nothing and the placeholder is the ink.
      expect(_hex(theme.onComposerFaint), '#807E7D');
      expect(_hex(theme.composerEdge), '#807E7D');
      expect((theme.composerEdge.a * 10000).round(), 7407);
    });

    test('keeps the words the customer picked for the box', () {
      final theme = RendelTheme.fromTokens(
        surface: const Color(0xFFECE9E8),
        onSurface: const Color(0xFF2E2A29),
        accent: const Color(0xFFF55733),
        onAccent: const Color(0xFF1F1A19),
        composer: const Color(0xFF141414),
        onComposer: const Color(0xFFFFFFFF),
      );
      expect(_hex(theme.colors.onComposer), '#FFFFFF');
      expect(_hex(theme.onComposerFaint), '#9C9C9C');
      expect(_hex(theme.composerEdge), '#FFFFFF');
      expect((theme.composerEdge.a * 10000).round(), 3347);
    });

    test('solves the box on its own ground even when only the ink is set', () {
      final theme = RendelTheme.fromTokens(
        surface: const Color(0xFFECE9E8),
        onSurface: const Color(0xFF2E2A29),
        accent: const Color(0xFFF55733),
        onAccent: const Color(0xFF1F1A19),
        onComposer: const Color(0xFF5A5A5A),
      );
      expect(_hex(theme.colors.composer), '#F9F8F8');
      expect(_hex(theme.colors.onComposer), '#5A5A5A');
      expect(_hex(theme.onComposerFaint), '#727272');
      expect(_hex(theme.composerEdge), '#5A5A5A');
      expect((theme.composerEdge.a * 10000).round(), 6650);
    });
  });
}
