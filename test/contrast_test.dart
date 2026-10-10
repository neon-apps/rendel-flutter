// The contrast floors, held against the themes the product actually ships
// and against a customer brand chosen to be as hostile as a real one gets.
//
// `auditContrast` reports these in debug, which means it reports them to
// whoever happens to be looking at a console. A floor nobody asserts on is a
// floor that fails quietly: the dark map the example used to ship failed its
// own audit for exactly as long as nothing checked it.
//
// The numbers below moved with the system rebuild. The rules did not: AA for
// every text role, and 3:1 for the boundary of a control. What changed is
// which boundary gets measured. The old audit asked whether the accent FILL
// cleared 3:1 against the background; WCAG 1.4.11 asks it of the boundary
// that identifies the control, which is the rim, and on the new tinted ground
// the raw accent is 2.8:1 — it would have failed while looking deliberate.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';


/// The `--rd-*` colours `packages/ui/src/styles/rdui.css` declares, so the
/// lockstep between the SDK's renderer and the browser's rendering of the same
/// blocks is checked against the file rather than against a copy of it.
///
/// Only opaque hex values are read. The two translucent roles (`line`,
/// `line-strong`, `line-control`) carry an alpha and are asserted by ratio in
/// the derivation tests instead.
Map<String, int> _rduiTokens({bool deep = false}) {
  // Resolved as a URI rather than joined with `package:path`, so this test
  // adds no dependency to a package whose whole argument is that it has none.
  final file = File.fromUri(
    Directory.current.uri.resolve('../../../packages/ui/src/styles/rdui.css'),
  );
  // Loud, not skipped. A lockstep test that quietly passes when it cannot
  // find the other side is the same bug it exists to catch.
  if (!file.existsSync()) {
    throw StateError(
      'rdui.css not found at ${file.path}. This test reads the CSS the web '
      'renders these blocks with; if the workspace moved, fix the path rather '
      'than deleting the test.',
    );
  }

  // Comments are stripped FIRST. A commented-out declaration is not a
  // declaration, and a parser that cannot tell the difference will happily
  // assert a value the browser never paints — which it did, when the correct
  // value sat in a comment after the wrong live one.
  final source = file
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  // The exact block, found by its selector and read to its own closing brace.
  //
  // Scanning "everything before `.dark .rdui`" was wrong twice over: a
  // declaration in any LATER rule in that prefix won the last-wins rule as if
  // it were in this block, and the `.rdui` guard was a substring test that
  // `.rdui-plate` satisfies — so renaming the real selector left the parser
  // reading tokens from somewhere else entirely and the suite green.
  // `:root` and `.dark`, not `.rdui`. The roles moved off the wrapper because
  // `.rdui` nests — `BlockPreview` puts one around every block — and a nested
  // copy re-declared the defaults and threw away the theme an ancestor had
  // set. They are declared on the document now and inherited everywhere.
  final selector = deep ? '.dark' : ':root';
  final start = _selectorStart(source, selector);
  if (start < 0) {
    throw StateError(
      'no `$selector { … }` rule in rdui.css. If the selector was renamed, '
      'rename it here too — this test is the only thing holding the SDK and '
      'the browser to the same values.',
    );
  }
  final open = source.indexOf('{', start);
  if (open < 0) {
    throw StateError('the `$selector` rule in rdui.css is not closed');
  }
  // The MATCHING brace, counted, not the first one. A nested block inside the
  // rule would otherwise truncate the scope and hide every token after it.
  var depth = 0;
  var close = -1;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) {
        close = i;
        break;
      }
    }
  }
  if (close < 0) {
    throw StateError('the `$selector` rule in rdui.css is not closed');
  }
  final scope = source.substring(open, close);

  final tokens = <String, int>{};
  final pattern = RegExp(r'--rd-([a-z-]+):\s*#([0-9a-fA-F]{6})\s*;');
  for (final match in pattern.allMatches(scope)) {
    // LAST declaration wins, which is what the cascade does within a block.
    tokens[match.group(1)!] = int.parse(match.group(2)!, radix: 16);
  }
  return tokens;
}

/// Every `--rd-*` declaration in the light block, as raw text.
///
/// The colour reader above only sees six-digit hex, which was the whole story
/// while colour was the only thing that could drift. It is not: the radius
/// scale and the two shadows are stated as literals on both sides too, and a
/// plate that rounds to 14px in Flutter and 12px in the browser is the same
/// class of bug as an accent in two oranges — just harder to see in a
/// screenshot and therefore likelier to ship.
Map<String, String> _rduiRawTokens() {
  final file = File.fromUri(
    Directory.current.uri.resolve('../../../packages/ui/src/styles/rdui.css'),
  );
  final source = file
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  // `:root`, for the same reason the block above reads it: the roles moved off
  // `.rdui` because that class nests and a nested copy reset them.
  final start = _selectorStart(source, ':root');
  final open = source.indexOf('{', start);
  var depth = 0;
  var close = -1;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) {
        close = i;
        break;
      }
    }
  }
  final scope = source.substring(open, close);
  final out = <String, String>{};
  for (final match
      in RegExp(r'--rd-([a-z-]+):\s*([^;]+);', dotAll: true).allMatches(scope)) {
    out[match.group(1)!] = match.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  return out;
}

/// `0 1px 2px rgba(38, 32, 27, 0.05), 0 8px 20px -10px rgba(…)` → the four
/// numbers each layer carries, in the order [RendelShadowSpec] declares them.
List<({double y, double blur, double spread, double alpha})> _parseShadows(
  String value,
) {
  final layers = <({double y, double blur, double spread, double alpha})>[];
  final pattern = RegExp(
    r'0\s+(-?[\d.]+)px\s+(-?[\d.]+)px(?:\s+(-?[\d.]+)px)?\s+rgba\([^,]+,[^,]+,[^,]+,\s*([\d.]+)\s*\)',
  );
  for (final match in pattern.allMatches(value)) {
    layers.add((
      y: double.parse(match.group(1)!),
      blur: double.parse(match.group(2)!),
      spread: double.parse(match.group(3) ?? '0'),
      alpha: double.parse(match.group(4)!),
    ));
  }
  return layers;
}

/// The offset of a rule whose selector is EXACTLY [selector].
///
/// `indexOf('.rdui')` matches `.rdui-plate`, and `indexOf('.dark .rdui')`
/// matches `.dark .rdui-plate`. The character after the selector has to be
/// whitespace or the opening brace for it to be the rule we mean.
int _selectorStart(String source, String selector) {
  var from = 0;
  while (true) {
    final at = source.indexOf(selector, from);
    if (at < 0) return -1;
    // TOP LEVEL only.
    //
    // "whitespace before it on its line" is satisfied by an indented rule
    // inside `@media`, so a complete and correct `.rdui` block nested in
    // `@media (prefers-contrast: more)` was taken as THE block — and the
    // top-level rule, the one every ordinary browser paints, could then say
    // anything at all and the suite stayed green. Counting braces is the
    // whole fix: a rule at depth zero is a rule that always applies.
    var depth = 0;
    for (var i = 0; i < at; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') depth--;
    }
    if (depth != 0) {
      from = at + 1;
      continue;
    }
    final after = at + selector.length;
    // And nothing but whitespace before it on its own line, so `.rdui` does
    // not match the tail of `.dark .rdui`. Without this, renaming the light
    // selector silently fell through to the deep block and the failure said
    // "the SDK draws #ECE9E8 and rdui.css draws #1F1A19" — true, loud, and
    // about the wrong thing.
    final lineStart = source.lastIndexOf('\n', at) + 1;
    final indent = source.substring(lineStart, at);
    if (indent.trim().isNotEmpty) {
      from = at + 1;
      continue;
    }
    if (after < source.length) {
      final next = source[after];
      if (next == '{' || next == ' ' || next == '\n' || next == '\r' || next == '\t') {
        // And it must reach a `{` before any `,` or `}` — otherwise it is one
        // selector in a list, or a descendant of something else.
        final brace = source.indexOf('{', after);
        final comma = source.indexOf(',', after);
        if (brace >= 0 && (comma < 0 || comma > brace)) return at;
      }
    }
    from = at + 1;
  }
}

/// `6.0` -> `6`, so a Dart double compares against a CSS `6px`.
String _trim(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

void main() {
  final themes = <String, RendelTheme>{
    'paper': RendelTheme.paper(),
    'deep': RendelTheme.deep(),
    // A brand that maps colours no accessibility-minded designer would pick:
    // a mid-saturation orange on an off-white, with white asked to sit on the
    // accent. Every derived role has to rescue it, and if one cannot, the
    // audit has to say so rather than the catalog shipping it.
    'hostile brand': RendelTheme.fromTokens(
      surface: const Color(0xFFFFF6F0),
      onSurface: const Color(0xFF2A1B12),
      accent: const Color(0xFFFF9A3D),
      onAccent: const Color(0xFF2A1B12),
    ),
    // The same hostility on a dark ground.
    'hostile brand, deep': RendelTheme.fromTokens(
      surface: const Color(0xFF120E1A),
      onSurface: const Color(0xFFEDE7FF),
      accent: const Color(0xFF7C5BFF),
      onAccent: const Color(0xFFFFFFFF),
    ),
  };

  themes.forEach((name, theme) {
    final colors = theme.colors;
    final surfaces = <(String, Color)>[
      ('surface', colors.surface),
      ('surfaceRaised', colors.surfaceRaised),
      ('surfaceSunk', colors.surfaceSunk),
      ('surfaceHigh', colors.surfaceHigh),
    ];

    group(name, () {
      test('every text role clears 4.5:1 on every surface', () {
        for (final (surfaceName, background) in surfaces) {
          for (final row in [
            ('onSurface', colors.onSurface),
            ('onSurfaceSoft', colors.onSurfaceSoft),
            ('onSurfaceFaint', colors.onSurfaceFaint),
            ('accentText', theme.accentText),
          ]) {
            expect(
              contrastRatio(row.$2, background),
              greaterThanOrEqualTo(4.5),
              reason: '$name: ${row.$1} on $surfaceName',
            );
          }
        }
      });

      test('the label on an accent fill clears 4.5:1', () {
        // At 13.5pt or less this is small text, not WCAG large, so it is held
        // to the text threshold rather than the graphic one.
        expect(
          contrastRatio(colors.onAccent, colors.accent),
          greaterThanOrEqualTo(4.5),
          reason: '$name: onAccent on accent',
        );
      });

      // WCAG 1.4.11. Both of these identify a control and both are derived
      // rather than chosen, so each is solved against every surface at once:
      // a value tuned to the easiest one fails on the hardest by half a point.
      test('accentEdge clears 3:1 on every surface', () {
        for (final (surfaceName, background) in surfaces) {
          expect(
            contrastRatio(theme.accentEdge, background),
            greaterThanOrEqualTo(2.995),
            reason: '$name: accentEdge on $surfaceName',
          );
        }
      });

      test('lineControl clears 3:1 on every surface', () {
        for (final (surfaceName, background) in surfaces) {
          expect(
            contrastRatio(theme.lineControl, background),
            greaterThanOrEqualTo(2.995),
            reason: '$name: lineControl on $surfaceName',
          );
        }
      });

      test('the elevation model has somewhere to go', () {
        // The ramp must lift off the ground and must never step back down.
        //
        // `surfaceHigh` is deliberately NOT required to differ from
        // `surfaceRaised`: on the published themes they are the same colour,
        // and the shadow is what separates a readout from a block that is
        // waiting on you — `design_test.dart` holds `raise` and `float` apart
        // for exactly that reason. The old assertion here demanded a third
        // light value above a plate that already sat at 97.5% luminance, and
        // the only place left to put it was against white. That is how the
        // brightest surface in the product got there.
        expect(colors.surfaceRaised, isNot(colors.surface));
        expect(colors.surfaceSunk, isNot(colors.surface));
        expect(colors.surfaceRaised.computeLuminance(),
            greaterThanOrEqualTo(colors.surface.computeLuminance()));
        expect(colors.surfaceHigh.computeLuminance(),
            greaterThanOrEqualTo(colors.surfaceRaised.computeLuminance()));
        expect(colors.surfaceSunk.computeLuminance(),
            lessThanOrEqualTo(colors.surface.computeLuminance()));
      });
    });
  });

  group('the published defaults', () {
    // The published themes are literals rather than derivations, because
    // `rdui.css` renders these same blocks in the browser and CSS cannot run
    // the bisections. Two sets of literals in two languages drift, so this
    // group READS the CSS and asserts against what it actually says.
    //
    // The test this replaces restated the Dart's own constants back to
    // itself, under a comment claiming they were "the values `rdui.css`
    // renders in the browser". They were not: `accentText` and `accentEdge`
    // had been deepened on the web and left alone here, so the SDK drew every
    // accent mark in a different orange from the browser preview of the same
    // block — and its values measured 4.51 and 3.01 against `surfaceSunk`,
    // margins of a hundredth on a system that keeps five. A lockstep test
    // that pins one side to itself passes forever and checks nothing.
    test('paper and deep are exactly what rdui.css renders', () {
      String rgb(int v) =>
          '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

      for (final (scope, theme) in [
        ('light', RendelTheme.paper()),
        ('deep', RendelTheme.deep()),
      ]) {
        final css = _rduiTokens(deep: scope == 'deep');
        expect(css, isNotEmpty,
            reason: 'no `--rd-*` colour parsed out of the $scope block of '
                'rdui.css, which would leave this test checking nothing');

        final roles = <String, Color>{
          'surface': theme.colors.surface,
          'raised': theme.colors.surfaceRaised,
          'sunk': theme.colors.surfaceSunk,
          'high': theme.colors.surfaceHigh,
          'ink': theme.colors.onSurface,
          'ink-soft': theme.colors.onSurfaceSoft,
          'ink-faint': theme.colors.onSurfaceFaint,
          'accent': theme.colors.accent,
          'accent-text': theme.accentText,
          'accent-edge': theme.accentEdge,
          'on-accent': theme.colors.onAccent,
        };

        roles.forEach((token, dart) {
          expect(css[token], isNotNull,
              reason: '`--rd-$token` is not declared in the $scope block of '
                  'rdui.css, so nothing pins the SDK to it');
          expect(
            rgb(dart.toARGB32()),
            rgb(css[token]!),
            reason: '$scope `$token`: the SDK draws ${rgb(dart.toARGB32())} '
                'and rdui.css draws ${rgb(css[token]!)}. The same block would '
                'render in two colours.',
          );
        });
      }
    });

    test('the published accent roles clear their floors with the margin', () {
      // The derivation path keeps `_floorMargin`; a published literal
      // bypasses it entirely, which is how a value measuring 3.01 shipped.
      final theme = RendelTheme.paper();
      for (final background in [
        theme.colors.surface,
        theme.colors.surfaceRaised,
        theme.colors.surfaceSunk,
        theme.colors.surfaceHigh,
      ]) {
        expect(contrastRatio(theme.accentText, background),
            greaterThanOrEqualTo(4.5 + 0.03));
        expect(contrastRatio(theme.accentEdge, background),
            greaterThanOrEqualTo(3.0 + 0.03));
      }
    });

    test('the radius scale is the one rdui.css rounds to', () {
      // The scale is stated in three places: `RendelRadiusScale`'s defaults here,
      // `--rd-radius-*` in the CSS, and `NEON_DEFAULT_RADIUS` in the console
      // (which its own suite pins to the CSS). A plate that rounds to 14 in
      // Flutter and 12 in the browser is the same bug as an accent in two
      // oranges, and much harder to catch by eye.
      final css = _rduiRawTokens();
      const radius = RendelRadiusScale();
      final pairs = <String, double>{
        'radius-xs': radius.xs,
        'radius-sm': radius.sm,
        'radius-card': radius.card,
        'radius-control': radius.control,
      };
      pairs.forEach((token, dart) {
        expect(css[token], isNotNull,
            reason: '`--rd-$token` is not declared in rdui.css, so nothing '
                'pins the SDK to it');
        expect(css[token], '${_trim(dart)}px',
            reason: '$token: the SDK rounds to $dart and rdui.css rounds to '
                '${css[token]}');
      });
    });

    test('the two shadows are the ones rdui.css casts', () {
      // Elevation is meaning in this system (SYSTEM.md §2): raised is what
      // the copilot handed you, floating is something waiting on an answer.
      // Two sets of literals in two languages drift, and a shadow drifting is
      // a level of the hierarchy quietly stopping being one.
      final css = _rduiRawTokens();
      const elevation = RendelElevationScale();
      for (final (token, dartLayers) in [
        ('raise', elevation.raise),
        ('float', elevation.float),
      ]) {
        final cssLayers = _parseShadows(css[token] ?? '');
        expect(cssLayers, hasLength(dartLayers.length),
            reason: '`--rd-$token` parses to ${cssLayers.length} layers and '
                'the SDK casts ${dartLayers.length}');
        for (var i = 0; i < dartLayers.length; i++) {
          final dart = dartLayers[i];
          final web = cssLayers[i];
          expect(web.y, dart.y, reason: '$token layer $i: y offset');
          expect(web.blur, dart.blur, reason: '$token layer $i: blur');
          expect(web.spread, dart.spread, reason: '$token layer $i: spread');
          expect(web.alpha, closeTo(dart.alpha, 0.0001),
              reason: '$token layer $i: alpha');
        }
      }
    });

    test('shadows are tinted with the ink, never black', () {
      // The one rule that makes elevation read as air rather than as weight:
      // a shadow belongs to the ground it falls on.
      //
      // The hue is read from the theme rather than written here, so the next
      // retheme cannot leave this asserting the previous ink.
      final ink = RendelTheme.paper().colors.shadow;
      int byte(double channel) => (channel * 255).round();
      final hue = 'rgba(${byte(ink.r)}, ${byte(ink.g)}, ${byte(ink.b)}';
      final css = _rduiRawTokens();
      for (final token in ['raise', 'float']) {
        expect(css[token], contains(hue),
            reason: '`--rd-$token` is not the ink hue, so it will read as a '
                'grey drop shadow on a tinted ground');
      }
    });

    test('the action takes one brand colour per ground', () {
      // v4 held one brand fill on both grounds, an ultramarine that needed a
      // lifted rim to be read in the dark. The v5 brand is two colours, and
      // each ground takes the one it can carry: black on paper, where the
      // yellow is 1.1:1 and would not even read as a button, and the yellow
      // on the deep ground, where black would vanish. It is the split the
      // landing page draws between its light sections and its dark band.
      final light = RendelTheme.paper();
      final deep = RendelTheme.deep();
      expect(light.colors.accent, const Color(0xFF0A0A0A),
          reason: 'the action on paper is the brand black');
      expect(deep.colors.accent, const Color(0xFFFEF7AF),
          reason: 'the action on the deep ground is the brand yellow');

      for (final (name, theme) in [('light', light), ('deep', deep)]) {
        for (final ground in [
          theme.colors.surface,
          theme.colors.surfaceRaised,
          theme.colors.surfaceSunk,
          theme.colors.surfaceHigh,
        ]) {
          expect(contrastRatio(theme.accentEdge, ground),
              greaterThanOrEqualTo(3.0),
              reason: '$name: the rim of a filled control');
        }
        expect(contrastRatio(theme.colors.onAccent, theme.colors.accent),
            greaterThanOrEqualTo(4.5),
            reason: '$name: the label on a filled control');
      }
    });

    test('the grounds carry hue, and the only white is a plate', () {
      // v4 held every surface off white, because a white plate beside a
      // tinted one read as a different material. v5 reverses half of that on
      // purpose: a plate IS white paper on a warm ground, the way the landing
      // page, the console and the docs draw every object, and the floating
      // plate is the same white, separated from a raised one by elevation.
      //
      // The other half of the rule stands: a GROUND with no hue is the grey
      // the brief rejected. The thread's surface and its wells carry hue in
      // both themes, and nothing on the deep ground is a neutral grey.
      final light = RendelTheme.paper();
      expect(light.colors.surfaceRaised, const Color(0xFFFFFFFF),
          reason: 'a plate on paper is white');
      expect(light.colors.surfaceHigh, light.colors.surfaceRaised,
          reason: 'elevation, not a second white, separates a floating plate');
      for (final (name, surface) in <(String, Color)>[
        ('light surface', light.colors.surface),
        ('light sunk', light.colors.surfaceSunk),
        ('deep surface', RendelTheme.deep().colors.surface),
        ('deep raised', RendelTheme.deep().colors.surfaceRaised),
        ('deep sunk', RendelTheme.deep().colors.surfaceSunk),
        ('deep high', RendelTheme.deep().colors.surfaceHigh),
      ]) {
        final channels = [surface.r, surface.g, surface.b];
        final spread =
            channels.reduce((a, b) => a > b ? a : b) -
                channels.reduce((a, b) => a < b ? a : b);
        expect(
          spread,
          greaterThan(0.0075),
          reason:
              '$name: a surface with no hue at all is the grey being replaced',
        );
      }
    });

    test('body ink is above AA without being harsh', () {
      // The old system put near-black on near-white at 18.6:1, which is what
      // the client reacted to. The floor is still AA and the ceiling stays a
      // ceiling: the 18.6 the client called harsh has to remain out of reach.
      //
      // The number is 17, not 16. 16 was a description of where the value
      // happened to sit rather than a derived limit, and the ground has since
      // been lifted — to close the gap between it and the raised surfaces,
      // which was reading as white cards popping off a grey page — which
      // moved body ink from 15.49 to 16.04 as a side effect. Fitting the
      // ceiling to the new value would make it meaningless; 17 leaves it
      // guarding the thing it was written to guard.
      final theme = RendelTheme.paper();
      final ratio =
          contrastRatio(theme.colors.onSurface, theme.colors.surface);
      expect(ratio, greaterThanOrEqualTo(7.0));
      expect(ratio, lessThan(17.0));
    });
  });
}
