// The soft lights behind a question are the app's own colours (Tuna
// 2026-10-22). Pinned to exact hex because `brandLights` is written twice:
// here and in the web SDK's `config.ts`, whose test holds these same inputs to
// these same values.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/src/ui/theme.dart';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

RendelColors _colors(Color accent, {Color? composer}) =>
    RendelTheme.fromTokens(
      surface: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFF111111),
      accent: accent,
      onAccent: const Color(0xFFFFFFFF),
      composer: composer,
    ).colors;

void main() {
  test('a navy accent lights the wash in its blue and the hues beside it', () {
    final lights = brandLights(_colors(const Color(0xFF1E2A78)))!;
    expect(lights.map(_hex), ['#ADDEEB', '#CEADEB', '#ADB6EB']);
  });

  test('a composer with a hue of its own is the second light', () {
    final lights = brandLights(
      _colors(const Color(0xFF1E2A78), composer: const Color(0xFFE85D3A)),
    )!;
    expect(lights.map(_hex), ['#ADDEEB', '#F4B4A4', '#ADB6EB']);
  });

  test('a black, white or grey brand keeps the pastels', () {
    expect(brandLights(_colors(const Color(0xFF0A0A0A))), isNull);
    expect(brandLights(_colors(const Color(0xFF808080))), isNull);
  });
}
