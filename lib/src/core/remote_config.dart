import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/launcher_icons.dart';
import '../ui/theme.dart';
import 'analytics.dart' show RendelCapture;
import 'config.dart';

/// Where the SDK keeps the last config it fetched successfully.
///
/// The package takes no storage dependency, for the same reason it hand-rolls
/// SSE rather than pulling in a client: a plugin in an SDK is a plugin in
/// every host's build. So this is an interface with a process-lifetime
/// default, and a host that wants an instant second launch wires three lines:
///
/// ```dart
/// class PrefsConfigStore implements RendelConfigStore {
///   @override
///   Future<String?> read() async =>
///       (await SharedPreferences.getInstance()).getString('nc_config');
///   @override
///   Future<void> write(String value) async =>
///       (await SharedPreferences.getInstance()).setString('nc_config', value);
/// }
/// ```
///
/// Without one the copilot still launches correctly every time; it simply
/// paints the code-provided config for the few hundred milliseconds before
/// the first fetch resolves, on every cold start rather than only the first.
abstract class RendelConfigStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// The default. Survives a `reset()`, not a relaunch.
class RendelMemoryConfigStore implements RendelConfigStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async => _value = value;
}

/// The published appearance and opening surface for one app.
///
/// Every field is optional and every absence falls back to what the host
/// passed to `init()`. A payload the SDK cannot read at all is discarded whole
/// and the code config stands: remote config is an override, never a
/// dependency.
@immutable
class RendelRemoteConfig {
  const RendelRemoteConfig({
    required this.channel,
    required this.version,
    required this.theme,
    required this.copilot,
    required this.etag,
    this.themeDark = const {},
    this.parallelReads = true,
    this.capture = RendelCapture.defaults,
  });

  /// What the server says about tap capture (`capture`, sent only when it is
  /// not the default): kept in the cache like [parallelReads], so a 304 keeps
  /// it too.
  final RendelCapture capture;

  /// False while the server has parallel reads off (`parallel_reads: false`):
  /// context providers and device reads then run one after another. Its
  /// switch for the parallel path, kept in the cache so a 304 keeps it too.
  final bool parallelReads;

  /// 'published' for a live key, 'draft' for a test key.
  final String channel;
  final int? version;
  final Map<String, dynamic> theme;

  /// The theme for a device in dark mode, as published. Partial: what it
  /// leaves out is derived from the light palette — see [applyToDark].
  final Map<String, dynamic> themeDark;
  final Map<String, dynamic> copilot;

  /// The ETag the payload arrived with, so the next launch can ask for a 304.
  final String? etag;

  bool get isEmpty => theme.isEmpty && themeDark.isEmpty && copilot.isEmpty;

  /// Parses a stored or fetched envelope. Returns null rather than throwing:
  /// a payload from a newer server, a truncated cache file or a hand-edited
  /// row must all degrade to "no remote config", never to a crash on launch.
  static RendelRemoteConfig? tryParse(String source, {String? etag}) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      final config = map['config'];
      final body = config is Map ? config.cast<String, dynamic>() : const <String, dynamic>{};
      return RendelRemoteConfig(
        channel: body.isEmpty && map['channel'] is! String
            ? 'published'
            : (map['channel'] as String? ?? 'published'),
        version: map['version'] is num ? (map['version'] as num).toInt() : null,
        theme: _submap(body['theme']),
        themeDark: _submap(body['themeDark']),
        copilot: _submap(body['copilot']),
        // A cached envelope carries its own etag; a fresh one is handed the
        // header's.
        etag: etag ?? (map['_etag'] as String?),
        parallelReads: map['parallel_reads'] != false,
        capture: RendelCapture.parse(map['capture']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Serialised for the store, with the ETag folded in so a cached launch can
  /// still revalidate rather than re-downloading.
  String toCache() => jsonEncode({
        'channel': channel,
        'version': version,
        if (etag != null) '_etag': etag,
        if (!parallelReads) 'parallel_reads': false,
        if (!capture.isDefault) 'capture': capture.toJson(),
        'config': {
          if (theme.isNotEmpty) 'theme': theme,
          if (themeDark.isNotEmpty) 'themeDark': themeDark,
          if (copilot.isNotEmpty) 'copilot': copilot,
        },
      });

  static Map<String, dynamic> _submap(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};

  // ————————————————————————— applying —————————————————————————

  /// The host's theme with whatever the customer published layered over it.
  ///
  /// If any of the four mapped roles is present the theme is rebuilt through
  /// [RendelTheme.fromTokens], which is what re-derives `accentText`,
  /// `accentEdge`, `lineControl` and the quiet ink steps against the new
  /// values. Layering a new accent onto a theme that had already derived its
  /// readable form from the old one is how a "themeable" SDK ends up with an
  /// unreadable badge.
  /// The customer's logo, as an id and never as an address.
  ///
  /// The payload carries no URL by design — see `logoAssetId` in
  /// `appconfig.ts`. This is joined onto the API base the host already
  /// configured, and fetched with the key the host already holds, so a
  /// published theme can never point a device at a host of somebody else's
  /// choosing.
  ///
  /// A uuid or nothing. Anything else is a payload this SDK will not build a
  /// request out of.
  String? get logoAssetId {
    final value = theme['logoAssetId'];
    if (value is! String) return null;
    final trimmed = value.trim();
    final looksLikeId = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(trimmed);
    return looksLikeId ? trimmed : null;
  }

  /// The customer's own launcher icon, as an id, for the logo's reason: the
  /// device builds the address from its own `apiBaseUrl`
  /// (`/v1/apps/launcher-icon`). A uuid or nothing.
  String? get launcherIconAssetId {
    final value = copilot['launcherIconAssetId'];
    if (value is! String) return null;
    final trimmed = value.trim();
    final looksLikeId = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(trimmed);
    return looksLikeId ? trimmed : null;
  }

  RendelTheme applyTo(RendelTheme base) {
    final built = _build(base);
    if (identical(built, base)) return base;

    // The device's own floor, and it runs in RELEASE.
    //
    // `auditContrast` is a debug lint that compiles out, which is right for a
    // theme the host wrote and wrong for one that arrived over the network.
    // A payload naming only `surfaceRaised` used to be audited by the console
    // against the DEFAULT ink and then applied over the HOST's — a deep-themed
    // app could be published a white plate and render its own pale ink on it
    // at 1.16:1, with every card in the catalog blank and nothing on the
    // device to stop it.
    //
    // The console now refuses a partial colour payload, so this should never
    // fire. It fires anyway, because "should never" is not a guarantee when
    // the other end of the wire is a database row.
    if (!_isLegible(built)) {
      debugPrint(
        '[rendel] the published theme is not legible on this device; '
        'keeping the theme this build was compiled with.',
      );
      return base;
    }
    return built;
  }

  /// The host's dark theme with whatever the customer published for the dark
  /// ground layered over it, under the same release-mode floor as [applyTo].
  ///
  /// Where the payload names any colour, light or dark, the dark theme is
  /// rebuilt from the PUBLISHED palette: the four roles `themeDark` states,
  /// the rest derived from the published light four by [rendelDarkRoles] —
  /// the derivation the console ran when it measured them, so the console
  /// and the device draw one theme. Other colours come only from
  /// `themeDark`; a light theme's white plate is no plate on a dark ground.
  /// Where it names none, [codeDark] keeps its colours. Either way the sizes,
  /// faces and builds are `themeDark`'s, else the light theme's.
  ///
  /// [codeLight] is only read when a dark colour arrives without the light
  /// palette the schema requires beside it — a hand-edited row.
  RendelTheme applyToDark(RendelTheme codeLight, RendelTheme codeDark) {
    if (theme.isEmpty && themeDark.isEmpty) return codeDark;
    final merged = <String, dynamic>{
      for (final MapEntry(:key, :value) in theme.entries)
        if (!_darkOwnKeys.contains(key)) key: value,
      if (theme['cards'] is Map) 'cards': _shapesOnly(_submap(theme['cards'])),
      ...themeDark,
    };
    if (_colourKeys.any(theme.containsKey) ||
        _colourKeys.any(themeDark.containsKey)) {
      Color role(String key, Color code) => _color(theme[key]) ?? code;
      final roles = rendelDarkRoles(
        surface: role('surface', codeLight.colors.surface),
        onSurface: role('onSurface', codeLight.colors.onSurface),
        accent: role('accent', codeLight.colors.accent),
        onAccent: role('onAccent', codeLight.colors.onAccent),
        darkSurface: _color(themeDark['surface']),
        darkOnSurface: _color(themeDark['onSurface']),
        darkAccent: _color(themeDark['accent']),
        darkOnAccent: _color(themeDark['onAccent']),
      );
      // Only where `themeDark` is silent: a value it states and this build
      // cannot read must still discard the theme in `_build`, not be papered
      // over by a derivation.
      merged.putIfAbsent('surface', () => _hex(roles.surface));
      merged.putIfAbsent('onSurface', () => _hex(roles.onSurface));
      merged.putIfAbsent('accent', () => _hex(roles.accent));
      merged.putIfAbsent('onAccent', () => _hex(roles.onAccent));
    }
    final dark = RendelRemoteConfig(
      channel: channel,
      version: version,
      theme: merged,
      copilot: const {},
      etag: etag,
    );
    final built = dark._build(codeDark);
    if (identical(built, codeDark)) return codeDark;
    if (!_isLegible(built)) {
      debugPrint(
        '[rendel] the published dark theme is not legible on this device; '
        'keeping the dark theme this build was compiled with.',
      );
      return codeDark;
    }
    return built;
  }

  /// What a dark theme never takes from the light one: its colours (and a
  /// card's, which [_shapesOnly] strips), and the logo, which is one file.
  static const _darkOwnKeys = {
    ..._colourKeys,
    'bubble',
    'onBubble',
    'backdrop',
    'cards',
    'logoAssetId',
  };

  /// A card's corner, build and part sizes, without the colours that were
  /// chosen for the light plate.
  static Map<String, dynamic> _shapesOnly(Map<String, dynamic> cards) => {
        for (final MapEntry(:key, :value) in cards.entries)
          if (value is Map)
            key: {
              for (final field in const ['radius', 'style'])
                if (value[field] != null) field: value[field],
              if (value['parts'] is Map)
                'parts': {
                  for (final MapEntry(key: name, value: part)
                      in (value['parts'] as Map).entries)
                    if (part is Map)
                      '$name': {
                        for (final field in const ['size', 'radius'])
                          if (part[field] != null) field: part[field],
                      },
                },
            },
      };

  static String _hex(Color color) =>
      '#${((color.r * 255).round() << 16 | (color.g * 255).round() << 8 | (color.b * 255).round()).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Whether the roles that carry meaning clear their floors on every surface
  /// they are drawn on.
  ///
  /// This used to check `onSurface` alone, under a comment saying `accentText`
  /// and `accentEdge` "are derived to clear their floors whatever the host
  /// maps, so they cannot be the reason a theme is rejected". They were not:
  /// both were solved against a single ground and then drawn on four, so a
  /// quarter of the payloads this gate ADMITTED had one of them below its
  /// floor somewhere. [RendelTheme] now solves them on all four, which makes
  /// the old comment true for every palette that has a solution at all — and
  /// leaves the ones that do not, which is exactly what a gate is for.
  ///
  /// Measuring what is drawn rather than trusting what derives it is also the
  /// cheaper contract: if the derivation regresses again, this catches it on
  /// the device instead of shipping it.
  static bool _isLegible(RendelTheme candidate) {
    final colors = candidate.colors;
    for (final background in [
      colors.surface,
      colors.surfaceRaised,
      colors.surfaceSunk,
      colors.surfaceHigh,
    ]) {
      if (contrastRatio(colors.onSurface, background) < 4.5) return false;
      // The two quiet steps as well. They are derived from `onSurface`, and
      // `_quietRoom` holds them above the floor by construction — but by
      // construction in floating point, and two of twenty thousand sampled
      // brands landed at 4.499 once the result was rounded to eight bits per
      // channel. A gate that measures what is drawn does not care how the
      // value was arrived at.
      if (contrastRatio(colors.onSurfaceSoft, background) < 4.5) return false;
      if (contrastRatio(colors.onSurfaceFaint, background) < 4.5) return false;
      if (contrastRatio(candidate.accentText, background) < 4.5) return false;
      // The boundary threshold, per WCAG 1.4.11, not the text one.
      if (contrastRatio(candidate.accentEdge, background) < 3.0) return false;
    }
    // The label on a filled control is small text on the accent itself.
    if (contrastRatio(colors.onAccent, colors.accent) < 4.5) return false;
    // The composer, once it is a ground the loop above never visited. Every
    // one of these clears by construction in `fromTokens` — by construction in
    // floating point, which is exactly the qualification this gate exists to
    // drop.
    if (colors.composerIsMapped) {
      if (contrastRatio(colors.onComposer, colors.composer) < 4.5) return false;
      if (contrastRatio(candidate.composerEdge, colors.composer) < 3.0) {
        return false;
      }
    }
    // The prompt separately: a brand may state it on a box it left alone.
    if (colors.composerIsMapped || colors.mappedOnComposerFaint != null) {
      if (contrastRatio(candidate.onComposerFaint, colors.composer) < 4.5) {
        return false;
      }
    }
    return true;
  }

  /// The seven colour keys, in the order the schema requires them together.
  static const _colourKeys = [
    'surface',
    'onSurface',
    'accent',
    'onAccent',
    'surfaceRaised',
    'surfaceSunk',
    'surfaceHigh',
    'composer',
    'onComposer',
    'onComposerFaint',
  ];

  RendelTheme _build(RendelTheme base) {
    if (theme.isEmpty) return base;

    // A colour key that is present and does not parse to an OPAQUE colour
    // discards the whole theme block.
    //
    // Alpha is the dangerous half. `contrastRatio` composites a translucent
    // FOREGROUND over its background, but it reads the background's own
    // luminance without compositing it against anything — there is nothing
    // behind it to composite against. So a published `#00FFFFFF` surface
    // scored as opaque white, cleared every check in the console and every
    // check in this gate, and then painted the thread at alpha zero: a
    // transparent sheet over the host's app with ink chosen for a ground that
    // is never drawn. `#80000000` behaved the same way.
    //
    // The schema refuses eight-digit hex now. This is the second lock,
    // because the other end of the wire is a database row.
    for (final key in _colourKeys) {
      if (!theme.containsKey(key)) continue;
      final parsed = _color(theme[key]);
      if (parsed == null || parsed.a < 1) {
        if (kDebugMode) {
          debugPrint(
            '[rendel] the published theme sets `$key` to a value that '
            'is not an opaque colour; keeping the theme this build was '
            'compiled with.',
          );
        }
        return base;
      }
    }

    final surface = _color(theme['surface']) ?? base.colors.surface;
    final onSurface = _color(theme['onSurface']) ?? base.colors.onSurface;
    final accent = _color(theme['accent']) ?? base.colors.accent;
    final onAccent = _color(theme['onAccent']) ?? base.colors.onAccent;

    final touchesColour = theme.containsKey('surface') ||
        theme.containsKey('onSurface') ||
        theme.containsKey('accent') ||
        theme.containsKey('onAccent') ||
        theme.containsKey('surfaceRaised') ||
        theme.containsKey('surfaceSunk') ||
        theme.containsKey('surfaceHigh') ||
        theme.containsKey('composer') ||
        theme.containsKey('onComposer') ||
        theme.containsKey('onComposerFaint');

    final radius = _radius(base.radius);
    final type = _type(base.type);
    final style = _style(base.style);
    // A card's own colours come with a published palette or not at all, like
    // every other colour; its corner and build stand on their own.
    final cards = _cards(base.cards, colour: touchesColour);
    final fontFamily = _font(theme['fontFamily']) ?? base.fontFamily;
    final displayFontFamily =
        _font(theme['displayFontFamily']) ?? base.displayFontFamily;
    RendelTheme build(RendelBackdrop? backdrop) => _built(
          base,
          surface: surface,
          onSurface: onSurface,
          accent: accent,
          onAccent: onAccent,
          touchesColour: touchesColour,
          radius: radius,
          type: type,
          style: style,
          cards: cards,
          fontFamily: fontFamily,
          displayFontFamily: displayFontFamily,
          backdrop: backdrop,
        );
    if (!theme.containsKey('backdrop')) return build(base.backdrop);
    final backdrop = _backdrop(theme['backdrop']);
    if (backdrop != null) {
      final built = build(backdrop);
      // The ink is solved on the backdrop's colours along with the plates, so
      // this holds for every backdrop that has a solution at all; the one
      // that does not is dropped, and only it — the rest of the theme stands.
      if (_readsOn(built, backdrop.colors)) return built;
    }
    if (kDebugMode) {
      debugPrint(
        '[rendel] the published backdrop is not a gradient the page can be '
        'read on; drawing the plain ground.',
      );
    }
    return build(null);
  }

  /// [_build]'s theme before its backdrop is weighed.
  RendelTheme _built(
    RendelTheme base, {
    required Color surface,
    required Color onSurface,
    required Color accent,
    required Color onAccent,
    required bool touchesColour,
    required RendelRadiusScale radius,
    required RendelTypeScale type,
    required RendelStyle style,
    required Map<String, RendelCardLook> cards,
    required String? fontFamily,
    required String? displayFontFamily,
    required RendelBackdrop? backdrop,
  }) {
    if (!touchesColour) {
      // The accent roles come across too.
      //
      // `accentText` and `accentEdge` are `late final` fields that fall back
      // to the derivation when the constructor is not given them, and the
      // published themes state them as literals precisely because `rdui.css`
      // has to name the same value. Rebuilding without them re-derived
      // `paper()`'s `#A23922`/`#DB4E2E` into `#AC3D24`/`#DB4E2E` — one
      // byte from the pair a lockstep drift was fixed for, and 3.05 against
      // the sunk surface. `LookEditor` always writes a radius, so this fired
      // on every save, including one that only renamed the launcher.
      //
      // Forwarding the RESOLVED values is right in both cases: `colors` is
      // unchanged here, so a derived base resolves to exactly what it
      // resolved to before, and a published base keeps its literal.
      return RendelTheme(
        colors: base.colors,
        radius: radius,
        type: type,
        space: base.space,
        motion: base.motion,
        size: base.size,
        elevation: base.elevation,
        style: style,
        cards: cards,
        fontFamily: fontFamily,
        displayFontFamily: displayFontFamily,
        backdrop: backdrop,
        accentText: base.accentText,
        accentEdge: base.accentEdge,
      );
    }

    return RendelTheme.fromTokens(
      surface: surface,
      onSurface: onSurface,
      accent: accent,
      onAccent: onAccent,
      surfaceRaised: _color(theme['surfaceRaised']),
      surfaceSunk: _color(theme['surfaceSunk']),
      surfaceHigh: _color(theme['surfaceHigh']),
      bubble: _color(theme['bubble']),
      onBubble: _color(theme['onBubble']),
      composer: _color(theme['composer']),
      onComposer: _color(theme['onComposer']),
      onComposerFaint: _color(theme['onComposerFaint']),
      radius: radius,
      type: type,
      space: base.space,
      motion: base.motion,
      size: base.size,
      elevation: base.elevation,
      style: style,
      cards: cards,
      fontFamily: fontFamily,
      displayFontFamily: displayFontFamily,
      backdrop: backdrop,
    );
  }

  /// Whether the page's ink, its two quiet steps and the accent's words clear
  /// 4.5:1 on every colour of a backdrop, as [_isLegible] holds them on every
  /// surface.
  static bool _readsOn(RendelTheme theme, List<Color> grounds) {
    for (final ground in grounds) {
      for (final ink in [
        theme.colors.onSurface,
        theme.colors.onSurfaceSoft,
        theme.colors.onSurfaceFaint,
        theme.accentText,
      ]) {
        if (contrastRatio(ink, ground) < 4.5) return false;
      }
    }
    return true;
  }

  /// `theme.backdrop`: two to four opaque colours, a direction from the
  /// closed set, and stops that rise from 0 to 1, one per colour. Anything
  /// else is no backdrop at all rather than half of one.
  static RendelBackdrop? _backdrop(Object? value) {
    final map = _submap(value);
    final raw = map['colors'];
    if (raw is! List || raw.length < 2 || raw.length > 4) return null;
    final colors = <Color>[];
    for (final entry in raw) {
      final color = _color(entry);
      if (color == null) return null;
      colors.add(color);
    }
    final direction = map['direction'] ?? 'to-bottom';
    final ends = _directions[direction];
    if (ends == null) return null;
    List<double>? stops;
    final rawStops = map['stops'];
    if (rawStops != null) {
      if (rawStops is! List || rawStops.length != colors.length) return null;
      stops = [];
      for (final entry in rawStops) {
        final stop = _size(entry, 0, 1);
        if (stop == null || (stops.isNotEmpty && stop < stops.last)) return null;
        stops.add(stop);
      }
    }
    return RendelBackdrop(colors: colors, begin: ends.$1, end: ends.$2, stops: stops);
  }

  /// Where each named direction starts and ends: CSS's `to bottom right` is
  /// Flutter's top-left to bottom-right.
  static const _directions = {
    'to-bottom': (Alignment.topCenter, Alignment.bottomCenter),
    'to-top': (Alignment.bottomCenter, Alignment.topCenter),
    'to-right': (Alignment.centerLeft, Alignment.centerRight),
    'to-left': (Alignment.centerRight, Alignment.centerLeft),
    'to-bottom-right': (Alignment.topLeft, Alignment.bottomRight),
    'to-bottom-left': (Alignment.topRight, Alignment.bottomLeft),
    'to-top-right': (Alignment.bottomLeft, Alignment.topRight),
    'to-top-left': (Alignment.bottomRight, Alignment.topLeft),
  };

  /// The host's `RendelConfig` with the published opening surface layered over it.
  RendelConfig applyToConfig(RendelConfig base) {
    if (copilot.isEmpty) return base;
    return base.copyWith(
      assistantName: _text(copilot['assistantName'], 40),
      launcherLabel: _text(copilot['launcherLabel'], 24),
      launcherStyle: RendelLauncherStyle.fromName(_iconName(copilot['launcherStyle'])),
      // Like the composer's glyphs: a name this build does not draw is "said
      // nothing", and the host's icon stays.
      launcherIcon: _launcherIcon(copilot['launcherIcon']),
      launcherDraggable: copilot['launcherDraggable'] is bool ? copilot['launcherDraggable'] as bool : null,
      // Clearable, unlike the two above. A name and a launcher label are
      // things the copilot cannot do without, so an empty one means "I said
      // nothing about this". A subtitle is something a customer may genuinely
      // want gone, so an empty string here means the empty string.
      //
      // Nothing sends one today: the console REMOVES the key when the field is
      // blank, so a cleared subtitle hands the line back to the host's Dart
      // rather than deleting it — which is what its own hint promises and what
      // "code config is the floor" requires. This branch exists for a caller
      // that means it, and for the hand-edited row.
      emptyStateTitle: _clearableText(copilot['emptyStateTitle'], 80),
      emptyStateBody: _clearableText(copilot['emptyStateBody'], 160),
      suggestions: _suggestions(copilot['suggestions']),
      enabled: copilot['enabled'] is bool ? copilot['enabled'] as bool : null,
      // A name this package does not carry reads as "said nothing about it",
      // not as an error: `fromName` returns null and `copyWith` keeps the
      // host's own choice. That is the same contract every other field here
      // has, and it is what lets the console add a glyph to the list before
      // every device in the field is running a build that knows it.
      // The words in the box before anyone types. Not clearable: the SDK's own
      // translated hint is a better empty state than no hint at all, so a
      // blank here means "said nothing", like the name and the launcher label.
      composerHint: _text(copilot['composerHint'], 60),
      attachIcon: RendelAttachIcon.fromName(_iconName(copilot['attachIcon'])),
      voiceIcon: RendelVoiceIcon.fromName(_iconName(copilot['voiceIcon'])),
      sendIcon: RendelSendIcon.fromName(_iconName(copilot['sendIcon'])),
      feedback: copilot['feedback'] is bool ? copilot['feedback'] as bool : null,
      // The console's voice switch (Settings › Voice), laid over the config by the API.
      readAloud: copilot['readAloud'] is bool ? copilot['readAloud'] as bool : null,
    );
  }

  /// One of the launcher icons this build carries, or `custom`, or nothing.
  static String? _launcherIcon(Object? value) {
    final name = _iconName(value);
    return name == 'custom' || launcherIconPaths.containsKey(name) ? name : null;
  }

  /// A glyph name off the wire: a short plain string, or nothing.
  ///
  /// Bounded like every other read in this file. The enums refuse anything
  /// they do not know, so the length cap is belt on braces — but the value
  /// arrives from a database row, and an unbounded string from a database row
  /// is the one thing this file never passes on.
  static String? _iconName(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 24) return null;
    return trimmed;
  }

  RendelRadiusScale _radius(RendelRadiusScale base) {
    final map = _submap(theme['radius']);
    if (map.isEmpty) return base;
    return RendelRadiusScale(
      xs: _size(map['xs'], 0, 64) ?? base.xs,
      sm: _size(map['sm'], 0, 64) ?? base.sm,
      card: _size(map['card'], 0, 64) ?? base.card,
      hero: _size(map['hero'], 0, 96) ?? base.hero,
      control: _size(map['control'], 0, 999) ?? base.control,
    );
  }

  RendelTypeScale _type(RendelTypeScale base) {
    final map = _submap(theme['type']);
    if (map.isEmpty) return base;
    return RendelTypeScale(
      display: _size(map['display'], 12, 48) ?? base.display,
      title: _size(map['title'], 11, 40) ?? base.title,
      heading: _size(map['heading'], 10, 32) ?? base.heading,
      body: _size(map['body'], 9, 28) ?? base.body,
      label: _size(map['label'], 9, 24) ?? base.label,
      caption: _size(map['caption'], 8, 22) ?? base.caption,
      overline: _size(map['overline'], 8, 20) ?? base.overline,
    );
  }

  /// The kinds of card the console can set apart; any other key is ignored.
  static const _cardParts = {
    'product_cards': ['badge', 'title', 'subtitle', 'stars', 'reviews', 'price'],
    'info_card': ['title', 'body', 'button', 'button_text'],
    'item_list': ['title', 'subtitle', 'trailing'],
    'order_tracker': ['title', 'step', 'time'],
    'confirm_card': ['summary', 'details', 'warning', 'confirm', 'confirm_text', 'cancel', 'cancel_text'],
  };

  /// `theme.cards`, kind by kind, over the host's own. A value out of bounds
  /// or a build this one does not draw is dropped, and the host's stays.
  Map<String, RendelCardLook> _cards(Map<String, RendelCardLook> base, {required bool colour}) {
    final map = _submap(theme['cards']);
    if (map.isEmpty) return base;
    final out = Map<String, RendelCardLook>.of(base);
    for (final MapEntry(key: kind, value: names) in _cardParts.entries) {
      final look = _submap(map[kind]);
      if (look.isEmpty) continue;
      final own = base[kind];
      final partsMap = _submap(look['parts']);
      final parts = Map<String, RendelPartLook>.of(own?.parts ?? const {});
      for (final name in names) {
        final part = _submap(partsMap[name]);
        if (part.isEmpty) continue;
        parts[name] = RendelPartLook(
          color: (colour ? _color(part['color']) : null) ?? own?.parts[name]?.color,
          size: _size(part['size'], 8, 40) ?? own?.parts[name]?.size,
          fill: (colour ? _color(part['fill']) : null) ?? own?.parts[name]?.fill,
          radius: _size(part['radius'], 0, 999) ?? own?.parts[name]?.radius,
        );
      }
      out[kind] = RendelCardLook(
        surfaceRaised: (colour ? _color(look['surfaceRaised']) : null) ?? own?.surfaceRaised,
        surfaceSunk: (colour ? _color(look['surfaceSunk']) : null) ?? own?.surfaceSunk,
        radius: _size(look['radius'], 0, 64) ?? own?.radius,
        style: _choice(RendelCardStyle.values, look['style']) ?? own?.style,
        parts: parts,
      );
    }
    return out;
  }

  /// A name this build does not know keeps the host's choice, like a glyph
  /// name does — which is the first of each set unless the host set one.
  RendelStyle _style(RendelStyle base) {
    final map = _submap(theme['style']);
    if (map.isEmpty) return base;
    return RendelStyle(
      card: _choice(RendelCardStyle.values, map['card']) ?? base.card,
      button: _choice(RendelButtonStyle.values, map['button']) ?? base.button,
      product: _choice(RendelProductStyle.values, map['product']) ?? base.product,
      tracker: _choice(RendelTrackerStyle.values, map['tracker']) ?? base.tracker,
      arrows: _choice(RendelArrowStyle.values, map['arrows']) ?? base.arrows,
    );
  }
}

// ————————————————————————— validation —————————————————————————
//
// Every read below is a coercion with a bound, never a cast. The bounds are
// the ones `packages/protocol/src/appconfig.ts` enforces on the way in; they
// are enforced again here because a device must never be the only thing
// standing between a bad row and a thread nobody can read.

/// The shape the wire accepts, and nothing wider.
///
/// `#rgb` or `#rrggbb`, hash required, no surrounding whitespace, opaque only.
/// It used to trim, tolerate a missing hash and read eight digits — so
/// `" #FFFFFF"`, `"FFFFFF"` and `"#00FFFFFF"` were applied on a device and
/// refused by `appConfigPayload`, which is the second lock being looser than
/// the first. Anything the console cannot publish is something this should not
/// accept from a hand-edited row either.
final _publishableHex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');

Color? _color(Object? value) {
  if (value is! String) return null;
  if (!_publishableHex.hasMatch(value)) return null;
  final raw = value.substring(1);
  final normalised = raw.length == 3
      ? 'FF${raw[0]}${raw[0]}${raw[1]}${raw[1]}${raw[2]}${raw[2]}'
      : 'FF$raw';
  final parsed = int.tryParse(normalised, radix: 16);
  return parsed == null ? null : Color(parsed);
}

double? _size(Object? value, double min, double max) {
  if (value is! num) return null;
  final size = value.toDouble();
  if (size.isNaN || size < min || size > max) return null;
  return size;
}

/// One name out of a closed set, matched exactly, or nothing.
T? _choice<T extends Enum>(List<T> values, Object? value) =>
    value is String ? values.asNameMap()[value] : null;

/// Like [_text], but an empty string is a value rather than an absence.
String? _clearableText(Object? value, int maxLength) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.length > maxLength ? null : trimmed;
}

String? _text(Object? value, int maxLength) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > maxLength) return null;
  return trimmed;
}

/// A font FAMILY NAME, never a URL. The SDK does not fetch fonts, so naming
/// one the binary does not carry is harmless: Flutter falls back. Rejecting
/// anything with a slash or a colon keeps it that way even if the field is
/// ever misused.
String? _font(Object? value) {
  final name = _text(value, 64);
  if (name == null) return null;
  if (name.contains('/') || name.contains(':')) return null;
  return name;
}

List<String>? _suggestions(Object? value) {
  if (value is! List) return null;
  final items = <String>[];
  for (final entry in value) {
    final text = _text(entry, 60);
    if (text != null) items.add(text);
    if (items.length == 4) break;
  }
  // An empty list is meaningful — "show no openers" — so it is returned as
  // one rather than folded into null, which would mean "keep the host's".
  return items;
}
