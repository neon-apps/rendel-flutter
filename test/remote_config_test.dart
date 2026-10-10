// Remote config is an OVERRIDE, never a dependency.
//
// The whole feature is only safe if every failure mode lands on "the copilot
// renders exactly what the host compiled in". These are those failure modes:
// no config, empty config, garbage, half-garbage, a payload from a newer
// server, hostile values, and a customer brand that would be illegible if it
// were applied verbatim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

RendelTheme _base() => RendelTheme.paper();

RendelRemoteConfig? _parse(String source) => RendelRemoteConfig.tryParse(source);

void main() {
  const code = RendelConfig(
    assistantName: 'Kicks Copilot',
    launcherLabel: 'Ask',
    suggestions: ['Where is my order?'],
    emptyStateBody: 'Ask in your own words.',
  );

  group('a payload the SDK cannot read leaves the code config standing', () {
    for (final source in <String, String>{
      'not json': 'this is not json at all',
      'json, but not an object': '[1, 2, 3]',
      'an object with no config': '{"channel":"published","version":3}',
      'config is a string': '{"config":"nope"}',
      'theme is a list': '{"config":{"theme":[1,2,3]}}',
      'truncated': '{"config":{"theme":{"surface":"#F5E',
    }.entries) {
      test(source.key, () {
        final parsed = _parse(source.value);
        // Either it fails to parse at all, or it parses to something empty.
        // Both mean the same thing downstream.
        if (parsed == null) return;
        expect(parsed.applyTo(_base()).colors.surface, _base().colors.surface);
        expect(parsed.applyToConfig(code).assistantName, 'Kicks Copilot');
      });
    }
  });

  test('an empty published config changes nothing', () {
    final parsed = _parse('{"channel":"published","version":1,"config":{}}')!;
    expect(parsed.isEmpty, isTrue);
    final theme = parsed.applyTo(_base());
    expect(theme.colors.surface, _base().colors.surface);
    expect(identical(parsed.applyToConfig(code), code), isTrue);
  });

  test('a payload from a newer server keeps the keys this build knows', () {
    // Old binaries ignore unknown keys, and never fatally: this is that rule
    // as a test. `theme.gradient` and `copilot.mood` do not exist in this
    // build and must simply not be read.
    final parsed = _parse('''
      {"channel":"published","version":9,"config":{
        "theme":{"accent":"#2E6BE6","gradient":{"from":"#000","to":"#fff"}},
        "copilot":{"assistantName":"Helper","mood":"cheerful"},
        "future_section":{"anything":true}
      }}
    ''')!;
    final theme = parsed.applyTo(_base());
    expect(theme.colors.accent, const Color(0xFF2E6BE6));
    expect(parsed.applyToConfig(code).assistantName, 'Helper');
  });

  group('values outside their bounds are dropped, not clamped into nonsense',
      () {
    test('a font size of 900 does not reach the type scale', () {
      final parsed = _parse(
        '{"config":{"theme":{"type":{"body":900,"label":11}}}}',
      )!;
      final theme = parsed.applyTo(_base());
      expect(theme.type.body, _base().type.body, reason: '900 is out of range');
      expect(theme.type.label, 11, reason: '11 is in range and applies');
    });

    test('a negative radius does not reach the radius scale', () {
      final parsed = _parse('{"config":{"theme":{"radius":{"card":-4}}}}')!;
      expect(parsed.applyTo(_base()).radius.card, _base().radius.card);
    });

    test('a colour that is not a colour is ignored', () {
      final parsed = _parse(
        '{"config":{"theme":{"accent":"javascript:alert(1)"}}}',
      )!;
      expect(parsed.applyTo(_base()).colors.accent, _base().colors.accent);
    });

    test('a font family that looks like a URL is refused', () {
      // The SDK never fetches a font, and this keeps it impossible for a
      // payload to make it look like it might.
      final parsed = _parse(
        '{"config":{"theme":{"fontFamily":"https://evil.example/f.ttf"}}}',
      )!;
      expect(parsed.applyTo(_base()).fontFamily, isNull);
    });

    test('an over-long assistant name is ignored', () {
      final long = 'x' * 200;
      final parsed = _parse('{"config":{"copilot":{"assistantName":"$long"}}}')!;
      expect(parsed.applyToConfig(code).assistantName, 'Kicks Copilot');
    });

    test('suggestions are capped and cleaned', () {
      final parsed = _parse('''
        {"config":{"copilot":{"suggestions":["a","b","c","d","e",42,""]}}}
      ''')!;
      final applied = parsed.applyToConfig(code);
      expect(applied.suggestions, ['a', 'b', 'c', 'd']);
    });

    test('an empty suggestion list means "show none", not "keep mine"', () {
      final parsed = _parse('{"config":{"copilot":{"suggestions":[]}}}')!;
      expect(parsed.applyToConfig(code).suggestions, isEmpty);
    });
  });

  group('a customer brand is applied through the derivation, not around it',
      () {
    test('a new accent re-derives its own readable and boundary forms', () {
      // The shipped default pins `accentText` and `accentEdge` to published
      // literals. If a published accent were layered onto that theme without
      // rebuilding, the badge ink would still be the vermilion derivation and
      // would have nothing to do with the customer's blue.
      final parsed = _parse('{"config":{"theme":{"accent":"#2E6BE6"}}}')!;
      final theme = parsed.applyTo(_base());
      expect(theme.accentText, isNot(_base().accentText));
      expect(
        contrastRatio(theme.accentText, theme.colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(theme.accentEdge, theme.colors.surfaceSunk),
        greaterThanOrEqualTo(2.995),
      );
    });

    test('white on a mid-value brand orange is rescued, not shipped', () {
      // 3.3:1 as published. The console refuses to publish it; the device
      // refuses to render it even if something else does.
      final parsed = _parse(
        '{"config":{"theme":{"accent":"#FF9A3D","onAccent":"#FFFFFF"}}}',
      )!;
      final theme = parsed.applyTo(_base());
      expect(
        contrastRatio(theme.colors.onAccent, theme.colors.accent),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('a full brand map clears every floor the audit checks', () {
      final parsed = _parse('''
        {"config":{"theme":{
          "surface":"#101014","onSurface":"#F2F2F7",
          "accent":"#7C5BFF","onAccent":"#FFFFFF"
        }}}
      ''')!;
      final theme = parsed.applyTo(_base());
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
          theme.accentText,
        ]) {
          expect(contrastRatio(ink, background), greaterThanOrEqualTo(4.5));
        }
        expect(
          contrastRatio(theme.accentEdge, background),
          greaterThanOrEqualTo(2.995),
        );
        expect(
          contrastRatio(theme.lineControl, background),
          greaterThanOrEqualTo(2.995),
        );
      }
    });

    test('a payload that touches no colour keeps the published accent roles',
        () {
      // The published themes state `accentText` and `accentEdge` as literals,
      // because `rdui.css` has to name the same value in the browser. They are
      // `late final` fields that fall back to the derivation when the
      // constructor is not given them — and the no-colour path rebuilt the
      // theme without them, so `paper()`'s #A23922/#DB4E2E came back as
      // #AC3D24/#DB4E2E: one byte from the pair that was removed as a lockstep
      // drift, and 3.05 against the sunk surface.
      //
      // `LookEditor` always writes a radius, so this fired on every save,
      // including one that changed nothing but the launcher label.
      final base = RendelTheme.paper();
      for (final payload in [
        '{"config":{"theme":{"radius":{"card":8}}}}',
        '{"config":{"theme":{"fontFamily":"Inter"}}}',
        '{"config":{"theme":{"type":{"body":15}}}}',
      ]) {
        final theme = _parse(payload)!.applyTo(base);
        expect(theme.accentText, base.accentText, reason: payload);
        expect(theme.accentEdge, base.accentEdge, reason: payload);
        expect(contrastRatio(theme.accentText, theme.colors.surfaceSunk),
            greaterThanOrEqualTo(4.53));
        expect(contrastRatio(theme.accentEdge, theme.colors.surfaceSunk),
            greaterThanOrEqualTo(3.03));
      }
    });

    test('a translucent ground is discarded, not measured as if opaque', () {
      // The hole the schema now closes at the other end, kept here because
      // the other end of the wire is a database row.
      //
      // `contrastRatio` composites a translucent FOREGROUND over its
      // background and reads the background's own luminance as given — there
      // is nothing behind a background to composite it against. So
      // `#00FFFFFF` scored as opaque white, cleared every check in the
      // console and every check in this gate, and painted the thread at alpha
      // zero: a transparent sheet over the host's app, with ink chosen for a
      // ground that is never drawn.
      for (final ground in ['#00FFFFFF', '#80000000', '#40ECE9E8']) {
        final parsed = _parse('''
          {"config":{"theme":{
            "surface":"$ground","onSurface":"#111111",
            "accent":"#0B5FFF","onAccent":"#FFFFFF"
          }}}
        ''')!;
        final base = _base();
        final theme = parsed.applyTo(base);
        expect(theme.colors.surface, base.colors.surface,
            reason: '$ground should have been discarded whole');
        expect(theme.colors.surface.a, 1.0);
      }
    });

    test('the payload that used to render an illegible accent now holds', () {
      // The device gate measured `onSurface` alone, on the stated grounds that
      // the accent roles "are derived to clear their floors whatever the host
      // maps". They were not: both were solved against ONE surface and drawn
      // on four. This exact payload was ACCEPTED and rendered `accentText` at
      // 1.71:1 on the surface and `accentEdge` at 1.15:1 as a control
      // boundary — a legible thread with unreadable marks in it.
      //
      // The fix is in the derivation rather than in the gate, so the outcome
      // is better than a rejection: the customer keeps their palette and every
      // role clears. `_isLegible` checks all of them now anyway, because a
      // guard that trusts the thing it guards is not a guard.
      final parsed = _parse('''
        {"config":{"theme":{
          "surface":"#A27A5C","onSurface":"#974C95",
          "accent":"#E0EB3E","onAccent":"#CEAE71"
        }}}
      ''')!;
      final base = _base();
      final theme = parsed.applyTo(base);
      expect(theme.colors.surface, isNot(base.colors.surface),
          reason: 'this palette is legible once derived, so it is applied');
      for (final background in [
        theme.colors.surface,
        theme.colors.surfaceRaised,
        theme.colors.surfaceSunk,
        theme.colors.surfaceHigh,
      ]) {
        expect(contrastRatio(theme.colors.onSurface, background),
            greaterThanOrEqualTo(4.5));
        expect(contrastRatio(theme.accentText, background),
            greaterThanOrEqualTo(4.5));
        expect(contrastRatio(theme.accentEdge, background),
            greaterThanOrEqualTo(2.995));
      }
    });

    test('the accent roles hold on all four surfaces, not just the hardest', () {
      // `_legible` stops at the first ground it is given, and which ground is
      // hardest moves as the value moves. Solved per surface and reconciled,
      // both roles clear everywhere they are actually drawn.
      for (final accent in ['#E0EB3E', '#8BB5A6', '#D1AEC5', '#2E6BE6']) {
        final parsed = _parse('''
          {"config":{"theme":{
            "surface":"#ECE9E8","onSurface":"#2E2A29",
            "accent":"$accent","onAccent":"#1F1A19"
          }}}
        ''')!;
        final theme = parsed.applyTo(_base());
        for (final background in [
          theme.colors.surface,
          theme.colors.surfaceRaised,
          theme.colors.surfaceSunk,
          theme.colors.surfaceHigh,
        ]) {
          expect(contrastRatio(theme.accentText, background),
              greaterThanOrEqualTo(4.5),
              reason: 'accentText on $accent');
          expect(contrastRatio(theme.accentEdge, background),
              greaterThanOrEqualTo(2.995),
              reason: 'accentEdge on $accent');
        }
      }
    });
  });

  // The logo is the one field that becomes a REQUEST. Everything else in a
  // payload is drawn; this one decides whether the device goes and asks for
  // something. `appconfig.ts` refuses URLs for that reason, and the SDK has to
  // refuse anything that is not the shape it was promised — a payload that
  // could put a path or a scheme in here would be a payload that chooses the
  // host a device talks to.
  group('the logo is an id or it is nothing', () {
    String withLogo(String value) =>
        '{"config":{"theme":{"logoAssetId":$value}}}';

    test('a uuid is read', () {
      final remote = _parse(withLogo('"3f6b0b8e-6b0e-4a5f-9a1a-2c8f0d5e7a11"'));
      expect(remote!.logoAssetId, '3f6b0b8e-6b0e-4a5f-9a1a-2c8f0d5e7a11');
    });

    test('surrounding whitespace does not make it a different id', () {
      final remote =
          _parse(withLogo('"  3f6b0b8e-6b0e-4a5f-9a1a-2c8f0d5e7a11  "'));
      expect(remote!.logoAssetId, '3f6b0b8e-6b0e-4a5f-9a1a-2c8f0d5e7a11');
    });

    test('anything that is not a uuid is refused', () {
      for (final value in <String>[
        '"https://evil.example/pixel.png"',
        '"../../../etc/passwd"',
        '"not-a-uuid"',
        '""',
        '123',
        'true',
        'null',
        '{"id":"3f6b0b8e-6b0e-4a5f-9a1a-2c8f0d5e7a11"}',
      ]) {
        expect(_parse(withLogo(value))?.logoAssetId, isNull, reason: value);
      }
    });

    test('a payload with no theme has no logo', () {
      expect(_parse('{"config":{}}')?.logoAssetId, isNull);
    });
  });

  group('the kill switch', () {
    test('a published false turns the copilot off', () {
      final parsed = _parse('{"config":{"copilot":{"enabled":false}}}')!;
      expect(parsed.applyToConfig(code).enabled, isFalse);
    });

    test('a published true cannot turn on a copilot the host disabled', () {
      // The local switch is the floor, not a default. A host that shipped the
      // copilot behind its own flag does not lose that flag to a publish.
      const off = RendelConfig(enabled: false);
      final parsed = _parse('{"config":{"copilot":{"enabled":true}}}')!;
      expect(parsed.applyToConfig(off).enabled, isFalse);
    });
  });

  group('the cache round-trips', () {
    test('what is written is what comes back, etag included', () {
      final fetched = RendelRemoteConfig.tryParse(
        '{"channel":"draft","version":4,"config":{"theme":{"accent":"#2E6BE6"},'
        '"copilot":{"launcherLabel":"Help"}}}',
        etag: '"abc123"',
      )!;
      final restored = RendelRemoteConfig.tryParse(fetched.toCache())!;
      expect(restored.etag, '"abc123"');
      expect(restored.version, 4);
      expect(restored.channel, 'draft');
      expect(restored.applyTo(_base()).colors.accent, const Color(0xFF2E6BE6));
      expect(restored.applyToConfig(code).launcherLabel, 'Help');
    });

    test('the in-memory store is a store', () async {
      final store = RendelMemoryConfigStore();
      expect(await store.read(), isNull);
      await store.write('{"config":{}}');
      expect(await store.read(), '{"config":{}}');
    });
  });

  /// The message box: two colours and three glyph names.
  ///
  /// The colours travel with the rest of the palette and are rescued on the
  /// box rather than on the thread. The glyphs travel alone, because each is a
  /// complete statement — and a name this build does not carry has to read as
  /// "said nothing", not as an error, or the console can never add one without
  /// breaking every device already in the field.
  group('the composer', () {
    String payload(String theme, [String copilot = '{}']) =>
        '{"config":{"theme":$theme,"copilot":$copilot}}';

    const palette = '"surface":"#FFFFFF","onSurface":"#111111",'
        '"accent":"#2E40EA","onAccent":"#FFFFFF"';

    test('is the floating surface when the payload says nothing', () {
      final theme = _parse(payload('{$palette}'))!.applyTo(_base());
      expect(theme.colors.composer, theme.colors.surfaceHigh);
      expect(theme.colors.onComposer, theme.colors.onSurface);
      expect(theme.colors.composerIsMapped, isFalse);
    });

    test('takes the box and rescues the words onto it', () {
      final theme =
          _parse(payload('{$palette,"composer":"#141414"}'))!.applyTo(_base());
      expect(theme.colors.composer, const Color(0xFF141414));
      expect(theme.colors.composerIsMapped, isTrue);
      // The published ink is #111111, which is 1.1:1 on that box.
      expect(contrastRatio(theme.colors.onComposer, theme.colors.composer),
          greaterThanOrEqualTo(4.5));
      expect(contrastRatio(theme.onComposerFaint, theme.colors.composer),
          greaterThanOrEqualTo(4.5));
      expect(contrastRatio(theme.composerEdge, theme.colors.composer),
          greaterThanOrEqualTo(3.0));
    });

    test('refuses a translucent box and keeps the built theme', () {
      final theme =
          _parse(payload('{$palette,"composer":"#80141414"}'))!.applyTo(_base());
      expect(theme.colors.surface, _base().colors.surface);
    });

    test('takes a stated prompt colour and rescues it on the box', () {
      final theme = _parse(
        payload('{$palette,"composer":"#141414","onComposerFaint":"#3A3A3A"}'),
      )!
          .applyTo(_base());
      // A dark grey placeholder is 1.6:1 on a near-black box. The device
      // draws the nearest value on that hue that can be read instead.
      expect(theme.onComposerFaint, isNot(const Color(0xFF3A3A3A)));
      expect(contrastRatio(theme.onComposerFaint, theme.colors.composer),
          greaterThanOrEqualTo(4.5));
    });

    test('lets a prompt colour stand on a box nobody changed', () {
      final theme =
          _parse(payload('{$palette,"onComposerFaint":"#5F5F5F"}'))!
              .applyTo(_base());
      expect(theme.onComposerFaint, const Color(0xFF5F5F5F));
      // And it does not move the words the user types.
      expect(theme.colors.onComposer, theme.colors.onSurface);
    });

    test('carries the words in the box before anyone types', () {
      final applied = _parse(payload('{}', '{"composerHint":"Siparişini sor"}'))!
          .applyToConfig(code);
      expect(applied.composerHint, 'Siparişini sor');
    });

    test('leaves the prompt to the SDK when the payload says nothing', () {
      final applied = _parse(payload('{}', '{"enabled":true}'))!.applyToConfig(code);
      // Null, not an empty string: `RendelStrings.composerHint` is translated, and
      // it is a better empty state than no hint at all.
      expect(applied.composerHint, isNull);
    });

    test('takes each glyph by name', () {
      final applied = _parse(payload(
        '{}',
        '{"attachIcon":"image","voiceIcon":"off","sendIcon":"paper-plane"}',
      ))!
          .applyToConfig(code);
      expect(applied.attachIcon, RendelAttachIcon.image);
      expect(applied.voiceIcon, RendelVoiceIcon.off);
      expect(applied.sendIcon, RendelSendIcon.paperPlane);
    });

    test('keeps the host\'s own glyph when the name is one it does not carry',
        () {
      const host = RendelConfig(attachIcon: RendelAttachIcon.plus);
      final applied =
          _parse(payload('{}', '{"attachIcon":"rocket"}'))!.applyToConfig(host);
      expect(applied.attachIcon, RendelAttachIcon.plus);
    });

    test('refuses a glyph name long enough to be something else', () {
      final applied = _parse(
        payload('{}', '{"attachIcon":"${'paperclip' * 12}"}'),
      )!
          .applyToConfig(code);
      expect(applied.attachIcon, RendelAttachIcon.plus);
    });
  });

  group('the look', () {
    test('is what every build drew before it existed when the payload says '
        'nothing', () {
      final theme = _parse('{"config":{"theme":{"radius":{"card":20}}}}')!
          .applyTo(_base());
      expect(theme.style.card, RendelCardStyle.flat);
      expect(theme.style.button, RendelButtonStyle.filled);
      expect(theme.style.product, RendelProductStyle.tile);
      expect(theme.style.tracker, RendelTrackerStyle.vertical);
    });

    test('takes each of the four by name', () {
      final theme = _parse('''
        {"config":{"theme":{"style":{
          "card":"outlined","button":"outlined",
          "product":"photo","tracker":"bar"
        }}}}
      ''')!
          .applyTo(_base());
      expect(theme.style.card, RendelCardStyle.outlined);
      expect(theme.style.button, RendelButtonStyle.outlined);
      expect(theme.style.product, RendelProductStyle.photo);
      expect(theme.style.tracker, RendelTrackerStyle.bar);
      // And nothing else moves with it.
      expect(theme.accentText, _base().accentText);
      expect(theme.radius.card, _base().radius.card);
    });

    test('comes through a payload that re-derives the colours too', () {
      final theme = _parse('''
        {"config":{"theme":{
          "surface":"#FFFFFF","onSurface":"#111111",
          "accent":"#2E40EA","onAccent":"#FFFFFF",
          "style":{"card":"flat","tracker":"horizontal"}
        }}}
      ''')!
          .applyTo(_base());
      expect(theme.colors.accent, const Color(0xFF2E40EA));
      expect(theme.style.card, RendelCardStyle.flat);
      expect(theme.style.tracker, RendelTrackerStyle.horizontal);
      expect(theme.style.product, RendelProductStyle.tile);
    });

    test('a value it does not know is the default, never an error', () {
      final theme = _parse('''
        {"config":{"theme":{"style":{
          "card":"glass","button":7,"product":null,"tracker":["bar"],
          "shape":"blob"
        }}}}
      ''')!
          .applyTo(_base());
      expect(theme.style.card, RendelCardStyle.flat);
      expect(theme.style.button, RendelButtonStyle.filled);
      expect(theme.style.product, RendelProductStyle.tile);
      expect(theme.style.tracker, RendelTrackerStyle.vertical);
    });

    test('is matched exactly: no case folding, no trimming', () {
      final theme = _parse(
        '{"config":{"theme":{"style":{"card":"Outlined","product":" row"}}}}',
      )!
          .applyTo(_base());
      expect(theme.style.card, RendelCardStyle.flat);
      expect(theme.style.product, RendelProductStyle.tile);
    });

    test('a style that is not an object is ignored', () {
      for (final style in ['"outlined"', '[1,2]', '42', 'null']) {
        final theme = _parse('{"config":{"theme":{"style":$style}}}')!
            .applyTo(_base());
        expect(theme.style.card, RendelCardStyle.flat, reason: style);
        expect(theme.style.tracker, RendelTrackerStyle.vertical, reason: style);
      }
    });

    test('keeps the host\'s own choice where the payload says nothing', () {
      final host = RendelTheme(
        colors: _base().colors,
        style: const RendelStyle(card: RendelCardStyle.raised, product: RendelProductStyle.row),
      );
      final theme =
          _parse('{"config":{"theme":{"style":{"tracker":"bar","card":"x"}}}}')!
              .applyTo(host);
      expect(theme.style.card, RendelCardStyle.raised);
      expect(theme.style.product, RendelProductStyle.row);
      expect(theme.style.tracker, RendelTrackerStyle.bar);
    });

    /* Cilt365, 2026-10-09: a host setting came back as its default.
       `applyToConfig` rebuilds the host's config through `copyWith`, and a
       field that method forgets to carry goes back to its default a few
       hundred milliseconds after `init` — silently, because nothing is
       wrong with either half on its own. */
    test('keeps what the console publishes nothing about', () {
      // What is carried has to differ from what a dropped field would fall
      // back to.
      const host = RendelConfig(streamIdleTimeout: Duration(seconds: 7));
      final applied =
          _parse('{"config":{"theme":{"style":{"button":"outlined"}}}}')!
              .applyToConfig(host);
      expect(applied.streamIdleTimeout, const Duration(seconds: 7));
    });

    test('survives the cache', () {
      final parsed = _parse(
        '{"config":{"theme":{"style":{"button":"outlined"}}}}',
      )!;
      final again = RendelRemoteConfig.tryParse(parsed.toCache())!;
      expect(again.applyTo(_base()).style.button, RendelButtonStyle.outlined);
    });
  });
}
