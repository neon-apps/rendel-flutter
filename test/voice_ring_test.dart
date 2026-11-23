import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/ring_voice_mode.dart';
import 'package:rendel/src/ui/theme.dart' show RendelVoiceRing;

/// The voice ring's colours (Tuna 2026-11-23): the app's own by default, a
/// preset, two to four of the app's pick, or the page's ink.
void main() {
  RendelTheme theme({Color accent = const Color(0xFF3C6939), RendelVoiceRing? ring, bool dark = false}) =>
      RendelTheme.fromTokens(
        surface: dark ? const Color(0xFF0B0C0E) : const Color(0xFFF7FBF1),
        onSurface: dark ? const Color(0xFFF1F0EC) : const Color(0xFF191D17),
        accent: accent,
        onAccent: const Color(0xFFFFFFFF),
        voiceRing: ring,
      );

  /// The hue of [c], in degrees.
  double hue(Color c) => HSVColor.fromColor(c).hue;

  test("the presets are the protocol's, colour for colour", () {
    final source = File('../../../packages/protocol/src/appconfig.ts').readAsStringSync();
    final table = RegExp(r'export const VOICE_RING_PRESETS = \{([\s\S]*?)\} as const').firstMatch(source)!.group(1)!;
    final wire = {
      for (final m in RegExp(r'(\w+): \[([^\]]*)\]').allMatches(table))
        m.group(1)!: [for (final h in RegExp(r'#([0-9A-F]{6})').allMatches(m.group(2)!)) 0xFF000000 | int.parse(h.group(1)!, radix: 16)],
    };
    expect(wire.remove('mono'), isEmpty);
    expect(wire, ringPresets);
  });

  test("by default it is the app's own: Grove's green runs green", () {
    final palette = RingPalette.ground(theme());
    for (var k = 0.0; k < 1; k += 0.05) {
      expect(hue(palette.at(k)), inInclusiveRange(60, 190), reason: '$k');
    }
  });

  test('an accent with no hue takes the spectrum', () {
    final grey = RingPalette.ground(theme(accent: const Color(0xFF1C1B19)));
    final spectrum = RingPalette.ground(theme(ring: const RendelVoiceRing(preset: 'spectrum')));
    expect(grey.at(0.3), spectrum.at(0.3));
  });

  test('a preset is drawn as it is on a dark ground and deepened on a light one', () {
    final darkOcean = RingPalette.ground(theme(dark: true, ring: const RendelVoiceRing(preset: 'ocean')));
    expect(darkOcean.at(0), const Color(0xFF2DD4BF));
    final lightOcean = RingPalette.ground(theme(ring: const RendelVoiceRing(preset: 'ocean')));
    expect(lightOcean.at(0).computeLuminance(), lessThan(const Color(0xFF2DD4BF).computeLuminance()));
    expect((hue(lightOcean.at(0)) - hue(const Color(0xFF2DD4BF))).abs(), lessThan(12));
  });

  test("the app's own colours win over a preset, and keep their hue", () {
    final palette = RingPalette.ground(theme(ring: const RendelVoiceRing(preset: 'ocean', colors: [Color(0xFFE11D48), Color(0xFFF97316)])));
    final first = hue(palette.at(0));
    expect(math.min(first, 360 - first), lessThan(20), reason: 'red, not ocean');
  });

  test("mono is the page's ink", () {
    final light = theme(ring: const RendelVoiceRing(preset: 'mono'));
    expect(RingPalette.ground(light).at(0.4), light.colors.onSurface);
  });

  test('every colour of every palette reads on its ground', () {
    for (final dark in [false, true]) {
      for (final ring in [null, ...[...ringPresets.keys, 'mono'].map((p) => RendelVoiceRing(preset: p))]) {
        final t = theme(dark: dark, ring: ring);
        final palette = RingPalette.ground(t);
        for (var k = 0.0; k < 1; k += 0.1) {
          expect(contrastRatio(palette.at(k), t.colors.surface), greaterThanOrEqualTo(1.8), reason: '${ring?.preset} dark=$dark $k');
        }
      }
    }
  });
}
