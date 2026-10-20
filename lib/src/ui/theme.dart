import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Color roles, not color names — hosts map their brand once and every
/// component follows. Component code consumes tokens only.
///
/// Four surfaces, because depth means something in this system:
///
///   * [surfaceSunk] is data at rest: a chart plot, a table body, a code
///     field. A well is not an object and casts no shadow.
///   * [surface] is the ground the thread sits on.
///   * [surfaceRaised] is what the copilot handed you: every block plate.
///   * [surfaceHigh] floats over the page: option sheets, menus, the pickers.
///
/// [shadow] is the hue every elevation is tinted with. A black shadow on a
/// tinted ground reads as dirt, so a host's shadow takes the host's own ink.
class RendelColors {
  const RendelColors({
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunk,
    required this.surfaceHigh,
    required this.onSurface,
    required this.onSurfaceSoft,
    required this.onSurfaceFaint,
    required this.accent,
    required this.onAccent,
    required this.line,
    required this.lineStrong,
    required this.shadow,
    Color? bubble,
    Color? onBubble,
    Color? composer,
    Color? onComposer,
    Color? onComposerFaint,
  })  : _bubble = bubble,
        _onBubble = onBubble,
        _composer = composer,
        _onComposer = onComposer,
        _onComposerFaint = onComposerFaint;

  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunk;
  final Color surfaceHigh;
  final Color onSurface;
  final Color onSurfaceSoft;
  final Color onSurfaceFaint;
  final Color accent;
  final Color onAccent;
  final Color line;
  final Color lineStrong;
  final Color shadow;

  final Color? _bubble;
  final Color? _onBubble;
  final Color? _composer;
  final Color? _onComposer;
  final Color? _onComposerFaint;

  /// The same roles with a card's own plate and well, for [RendelTheme.forCard].
  ///
  /// The plate is both the raised and the floating surface inside the card: a
  /// confirmation floats where a product card is raised, and "this card's
  /// colour" has to mean the plate either way.
  RendelColors _withPlates({Color? raised, Color? sunk}) => RendelColors(
        surface: surface,
        surfaceRaised: raised ?? surfaceRaised,
        surfaceSunk: sunk ?? surfaceSunk,
        surfaceHigh: raised ?? surfaceHigh,
        onSurface: onSurface,
        onSurfaceSoft: onSurfaceSoft,
        onSurfaceFaint: onSurfaceFaint,
        accent: accent,
        onAccent: onAccent,
        line: line,
        lineStrong: lineStrong,
        shadow: shadow,
        bubble: _bubble,
        onBubble: _onBubble,
        composer: _composer,
        onComposer: _onComposer,
        onComposerFaint: _onComposerFaint,
      );

  /// The user's own message, and the words in it.
  ///
  /// The bubble is a SURFACE and its words are INK, which is the whole point
  /// of splitting them. The first version had the bubble default to the ink
  /// and its words to the ground — a good-looking near-black bubble, and a
  /// field called "Text" that repainted a container. Now each does what its
  /// name says, and a brand that wants the near-black bubble says so in one
  /// field instead of getting it as a side effect of its text colour.
  ///
  /// Nullable fields behind getters rather than required arguments, so every
  /// existing construction of this class — in this package and in a host's own
  /// code — keeps compiling.
  Color get bubble => _bubble ?? surfaceSunk;
  Color get onBubble => _onBubble ?? onSurface;

  /// Whether a brand named its own bubble. Unnamed, the thread draws the
  /// user's turn as a 6% tint of the ink over the thread rather than as
  /// [bubble]'s filled surface (blocks v6, `design/BLOCKS-v6.md`).
  bool get bubbleIsMapped => _bubble != null;

  /// The box the user types in, and the words they type into it.
  ///
  /// A pair of its own rather than a fifth surface. The composer is the one
  /// element that stays put while the thread scrolls past it, and "a dark bar
  /// under a light thread" is a pairing the surface ladder cannot express: the
  /// ink is solved across four grounds at once, so putting a dark box among
  /// them either fails the audit or drags the ink on every other surface with
  /// it.
  ///
  /// [surfaceHigh] and [onSurface] until a brand says otherwise, which is
  /// every app that has not asked for anything else — so nothing moves for a
  /// theme that leaves them out.
  Color get composer => _composer ?? surfaceHigh;
  Color get onComposer => _onComposer ?? onSurface;

  /// The prompt in that box, if a brand stated one.
  ///
  /// Null is the ordinary case and means "derive it": a placeholder is
  /// normally a quieter step of whatever the user types, and the arithmetic
  /// for that is in [RendelTheme.onComposerFaint]. A brand that wants it at
  /// a particular value — louder, or a different hue entirely — says so, and
  /// what they say is rescued against the box like any other text.
  Color? get mappedOnComposerFaint => _onComposerFaint;

  /// Whether the composer was given a colour of its own.
  ///
  /// [RendelTheme] reads it to decide where to solve the box's placeholder
  /// and its boundary. While the box IS the floating surface, the thread's own
  /// answers are the right ones and solving them on the box alone would be a
  /// silent change to every theme published before this pair existed: the
  /// placeholder quieted against one ground instead of four, and the boundary
  /// dropping the heaviest of the four answers.
  bool get composerIsMapped => _composer != null || _onComposer != null;
}

/// The radius scale. The previous system was 4pt on everything and read as
/// unstyled.
///
/// Four steps, not the web's five: the system's `tray` step is a *nested
/// enclosure*, and the SDK renders inside someone else's app, where a second
/// enclosure around a block competes with the host's own chrome rather than
/// adding to it. The catalog's plates sit directly on the thread. A step
/// nothing draws is a step that drifts, so it is not declared here.
class RendelRadiusScale {
  const RendelRadiusScale({
    this.xs = 6,
    this.sm = 10,
    this.card = 14,
    this.hero = 24,
    this.control = 999,
  });

  /// Inline marks, swatches, the smallest chips.
  final double xs;

  /// Fields, list rows, small plates.
  final double sm;

  /// Block plates and cards.
  final double card;

  /// The largest frame: the top corners of the page sheet the thread is
  /// presented in, 24 as an iOS page sheet's.
  final double hero;

  /// Pills survive on controls only: buttons, chips, slots.
  final double control;
}

/// One layer of an elevation, in the abstract. Resolved against
/// [RendelColors.shadow] by [RendelTheme], so a host's brand tints its own depth.
@immutable
class RendelShadowSpec {
  const RendelShadowSpec({
    required this.y,
    required this.blur,
    required this.spread,
    required this.alpha,
  });

  final double y;
  final double blur;
  final double spread;
  final double alpha;

  @override
  bool operator ==(Object other) =>
      other is RendelShadowSpec &&
      other.y == y &&
      other.blur == blur &&
      other.spread == spread &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(y, blur, spread, alpha);
}

/// The elevation model. Two layers each: a tight contact shadow that says the
/// surface is really sitting on something, and a wide ambient one that gives
/// it air. One layer alone reads either as a sticker or as a smudge.
class RendelElevationScale {
  const RendelElevationScale({
    this.raise = const [
      RendelShadowSpec(y: 1, blur: 2, spread: 0, alpha: 0.05),
      RendelShadowSpec(y: 8, blur: 20, spread: -10, alpha: 0.14),
    ],
    this.float = const [
      RendelShadowSpec(y: 2, blur: 6, spread: 0, alpha: 0.06),
      RendelShadowSpec(y: 24, blur: 48, spread: -20, alpha: 0.22),
    ],
    this.lift = const [
      RendelShadowSpec(y: 3, blur: 8, spread: 0, alpha: 0.07),
      RendelShadowSpec(y: 32, blur: 64, spread: -24, alpha: 0.26),
    ],
  });

  /// A block plate resting on the thread.
  final List<RendelShadowSpec> raise;

  /// A surface over the page: a sheet, a menu.
  final List<RendelShadowSpec> float;

  /// The launcher, and a card the user is dragging or pressing into.
  final List<RendelShadowSpec> lift;
}

/// The type scale. Seven steps, one job each, and no renderer writes a raw
/// font size.
///
/// [display] pulled away from [title] deliberately: at 20 against 17 the one
/// figure a block exists to report was barely louder than the block's own
/// name, which is most of what "weak hierarchy" meant.
class RendelTypeScale {
  const RendelTypeScale({
    this.display = 24,
    this.title = 18,
    this.heading = 15.5,
    this.body = 14,
    this.label = 13.5,
    this.caption = 12.5,
    // 11.5 rather than 11: blocks v6 took every small label a step up.
    this.overline = 11.5,
  });

  /// The single dominant number in a block: a KPI value, a total.
  final double display;

  /// A block's own name.
  final double title;

  /// Thread prose, and the lede inside a card, at regular weight.
  final double heading;

  /// Supporting paragraphs inside a block.
  final double body;

  /// Controls, chips, list-row titles.
  final double label;

  /// Metadata, secondary values, timestamps.
  final double caption;

  /// The quiet label that opens a block. Sentence case, not tracked
  /// uppercase: the web surfaces set this step condensed rather than
  /// letterspaced, and a label should be a different voice rather than the
  /// same voice shouting.
  final double overline;
}

/// The design language's one arrive curve, in Flutter's vocabulary.
///
/// `cubic-bezier(0.2, 0.9, 0.24, 1)` — the same curve the web surfaces use.
/// It leaves faster than `Curves.easeOutCubic` and settles without the long
/// tail of the old `(0.16, 1, 0.3, 1)`, which made every arrival feel like it
/// was being placed rather than delivered.
const Curve rendelEase = Cubic(0.2, 0.9, 0.24, 1);

/// The motion scale. Every animation in the SDK reads its timing from here.
class RendelMotionScale {
  const RendelMotionScale({
    this.enter = const Duration(milliseconds: 380),
    this.swap = const Duration(milliseconds: 180),
    this.settle = const Duration(milliseconds: 240),
    this.press = const Duration(milliseconds: 120),
    this.follow = const Duration(milliseconds: 250),
    this.breath = const Duration(milliseconds: 1100),
    this.caret = const Duration(milliseconds: 600),
    this.enterTravel = 10,
  });

  /// A block arriving in the thread. The only entrance in the catalog.
  final Duration enter;

  /// One thing replacing another in place: a skeleton hydrating, a form
  /// locking, a confirm card resolving.
  final Duration swap;

  /// A surface changing size around content that swapped.
  final Duration settle;

  /// A finger landing on a target.
  final Duration press;

  /// The thread following the live edge after a discrete arrival.
  final Duration follow;

  /// The pulse that means "not content yet": skeletons, loading images, and
  /// a file still uploading.
  final Duration breath;

  /// The streaming caret. Faster than [breath] on purpose — the two motions
  /// are the most common on screen and must not say the same thing.
  final Duration caret;

  /// How far a block rises as it arrives, in logical pixels.
  ///
  /// A constant, not a fraction of the block's own height: a one-line `text`
  /// block travelling 6% rises about a point and says nothing, while a
  /// product rail travelling 6% lurches two dozen. The entrance is one
  /// sentence and it should be spoken at one volume.
  final double enterTravel;

  /// Arrivals and settles.
  Curve get curve => rendelEase;

  /// A press, which is shorter and shallower than an arrival.
  Curve get pressCurve => const Cubic(0.34, 0.01, 0.2, 1);

  /// The breath is symmetric, so it eases in and out rather than arriving.
  /// Not `Curves.easeInOut`: the most-repeated motion in the product should
  /// not be the framework's default.
  Curve get breathCurve => const Cubic(0.37, 0, 0.63, 1);

  /// One thing replacing another, as a fade-through rather than a crossfade.
  ///
  /// Both intervals sit at the far end on purpose. `AnimatedSwitcher` drives
  /// the outgoing child with a parent running 1 to 0, so the interval nearest
  /// 1.0 is the *earliest* real time: the outgoing child leaves first, the
  /// incoming one arrives after it, and the two never sit at half opacity
  /// washing each other out.
  Curve get swapOut => const Interval(0.55, 1, curve: Curves.easeIn);
  Curve get swapIn => const Interval(0.55, 1, curve: Curves.easeOut);
}

/// The spacing scale. A 4pt grid, six steps. [plate] is the one padding a
/// block enclosure uses, so every plated component has the same inset.
class RendelSpaceScale {
  const RendelSpaceScale({
    this.hair = 2,
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
  });

  final double hair;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  /// Inset for a plated block: [lg] and a [hair], the 18 the v6 plate takes.
  double get plate => lg + hair;
}

/// Component dimensions.
///
/// Every dimension a second implementation must match to look like the same
/// product is named here, and the skeletons read the same fields as the
/// blocks they stand in for, so a placeholder cannot drift from its block.
class RendelSizeScale {
  const RendelSizeScale({
    this.rowThumb = 40,
    this.cardWidth = 160,
    this.cardImageWidth = 128,
    this.cardImageHeight = 84,
    this.cardRowImage = 64,
    this.cardPhotoHeight = 150,
    this.heroHeight = 128,
    this.plotHeight = 132,
    this.donut = 104,
    this.donutStroke = 18,
    this.trackHeight = 8,
    this.stepDot = 9,
    this.stepBar = 6,
    this.tileWidth = 216,
    this.tileHeight = 168,
    this.stickyColumn = 92,
    this.column = 96,
    this.swatch = 8,
    this.trailing = 120,
  });

  /// The leading image on an `item_list` row.
  final double rowThumb;

  /// A `product_cards` card and the image inside it.
  final double cardWidth;
  final double cardImageWidth;
  final double cardImageHeight;

  /// The square image at the side of a `product_cards` row, and the
  /// photograph across the top of a photo card. See [RendelProductStyle].
  final double cardRowImage;
  final double cardPhotoHeight;

  /// The full-bleed image at the top of a `booking_card`.
  final double heroHeight;

  /// The `chart` plot area, and the donut's ring and its thickness.
  final double plotHeight;
  final double donut;
  final double donutStroke;

  /// The `progress` bar.
  final double trackHeight;

  /// The `order_tracker` step marker, and the bar it draws instead of its
  /// steps under [RendelTrackerStyle.bar].
  final double stepDot;
  final double stepBar;

  /// A `media_gallery` carousel tile.
  final double tileWidth;
  final double tileHeight;

  /// `table` columns: the pinned one, then the others at their least. The
  /// others share whatever the plate has left and scroll only when they
  /// cannot fit at this width.
  final double stickyColumn;
  final double column;

  /// A chart legend's colour mark.
  final double swatch;

  /// The widest a trailing value may grow before it ellipsises.
  ///
  /// A cap rather than a flex share: the schema allows 40 characters in a
  /// trailing slot, and letting it take an even split of the row leaves the
  /// title wrapping to two lines for the sake of a price.
  final double trailing;
}

/// How a block plate or a card is set off from the thread.
enum RendelCardStyle {
  /// Surface and shadow.
  raised,

  /// The same surface inside a 1px [RendelColors.lineStrong] edge, and no shadow.
  outlined,

  /// The surface alone.
  flat,
}

/// How the filled button inside a block is drawn. A quiet button keeps its
/// own look under either.
enum RendelButtonStyle {
  /// The accent fill.
  filled,

  /// No fill: a 1.5px [RendelTheme.accentEdge] rim round a
  /// [RendelTheme.accentText] label.
  outlined,
}

/// How `product_cards` lays its items out.
enum RendelProductStyle {
  /// Upright cards in a horizontal rail.
  tile,

  /// A list: the picture at the side, the price at the end of the line.
  row,

  /// A list: the photograph across the top, the words under it.
  photo,
}

/// How `order_tracker` draws a parcel's progress.
enum RendelTrackerStyle {
  /// Steps down the plate, each with its time.
  vertical,

  /// Steps across, one row of dots with the names under them.
  horizontal,

  /// One bar, with the step it is on and `k/N` under it.
  bar,
}

/// The glyph on the page's back and forward steps, in the family the host's
/// own navigation uses.
enum RendelArrowStyle {
  /// A chevron: ‹ ›.
  chevron,

  /// An arrow with a shaft: ← →.
  arrow,

  /// The thin iOS back chevron.
  ios,
}

/// How the parts are built, not only what colour they are: `theme.style` on
/// the wire. Each is a closed set. Since 0.31 a card is flat unless a style
/// asks otherwise: flat and filled are the one look (v6, design/BLOCKS-v6.md);
/// raised and outlined are still drawn for a config that names them.
class RendelStyle {
  const RendelStyle({
    this.card = RendelCardStyle.flat,
    this.button = RendelButtonStyle.filled,
    this.product = RendelProductStyle.tile,
    this.tracker = RendelTrackerStyle.vertical,
    this.arrows = RendelArrowStyle.chevron,
  });

  final RendelCardStyle card;
  final RendelButtonStyle button;
  final RendelProductStyle product;
  final RendelTrackerStyle tracker;
  final RendelArrowStyle arrows;
}

/// The page's ground as the host's own screens paint theirs: a gradient of
/// two to four opaque colours, where a single colour would leave every app
/// on a plain white sheet. `theme.backdrop` on the wire.
///
/// A colour, so it belongs to one brightness: a light theme's backdrop is
/// never carried to the dark one.
class RendelBackdrop {
  const RendelBackdrop({
    required this.colors,
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
    this.stops,
  });

  final List<Color> colors;
  final Alignment begin;
  final Alignment end;

  /// One per colour, 0 to 1, rising. Null spreads them evenly.
  final List<double>? stops;

  LinearGradient get gradient =>
      LinearGradient(begin: begin, end: end, colors: colors, stops: stops);
}

/// One kind of card set apart from the rest: `theme.cards` in the console.
///
/// Every field is optional and a null one is the theme's own, so an empty
/// look is exactly the card every other block draws. Applied per block by
/// [RendelTheme.forCard], which is how a product card can be flat and dark
/// while the info card beside it keeps its shadow.
class RendelCardLook {
  const RendelCardLook({
    this.surfaceRaised,
    this.surfaceSunk,
    this.radius,
    this.style,
    this.parts = const {},
  });

  /// The plate the card sits on, raised or floating.
  final Color? surfaceRaised;

  /// The well behind its pictures.
  final Color? surfaceSunk;

  /// Its corner, in logical pixels.
  final double? radius;

  /// How it is set off from the thread.
  final RendelCardStyle? style;

  /// Its parts by name — `title`, `price`, `stars`… — each with its own
  /// colour and size. The names are `CARD_PARTS` in the protocol package.
  final Map<String, RendelPartLook> parts;
}

/// One part inside a card: its colour and its size, and for a button its
/// fill and corner — a button's words are a part of their own,
/// `<button>_text`. Null is what the renderer draws.
class RendelPartLook {
  const RendelPartLook({this.color, this.size, this.fill, this.radius});

  final Color? color;

  /// In logical pixels.
  final double? size;

  /// A button's background.
  final Color? fill;

  /// A button's corner, in logical pixels.
  final double? radius;
}

/// Resolved text styles: the type scale bound to the theme's ink roles.
///
/// Renderers read `theme.text.heading` rather than assembling a [TextStyle],
/// which is what keeps the catalog looking like one system. Built once per
/// theme instance and cached, so this costs nothing per frame.
class RendelTextStyles {
  RendelTextStyles._({
    required RendelColors colors,
    required RendelTypeScale scale,
    required String? fontFamily,
    required String? displayFontFamily,
  })  : display = TextStyle(
          fontFamily: displayFontFamily ?? fontFamily,
          color: colors.onSurface,
          fontSize: scale.display,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
          height: 1.08,
        ),
        title = TextStyle(
          fontFamily: displayFontFamily ?? fontFamily,
          color: colors.onSurface,
          fontSize: scale.title,
          fontWeight: FontWeight.w600,
          height: 1.22,
          letterSpacing: -0.3,
        ),
        heading = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurface,
          fontSize: scale.heading,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        prose = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurface,
          fontSize: scale.heading,
          height: 1.55,
        ),
        body = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurfaceSoft,
          fontSize: scale.body,
          height: 1.5,
        ),
        label = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurface,
          fontSize: scale.label,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
        labelSoft = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurfaceSoft,
          fontSize: scale.label,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
        caption = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurfaceFaint,
          fontSize: scale.caption,
          height: 1.35,
        ),
        // Only legible on an accent fill: that is what `onAccent` is for. A
        // control that wants weight on an ordinary surface wants
        // [labelEmphasis], not this.
        labelStrong = TextStyle(
          fontFamily: fontFamily,
          color: colors.onAccent,
          fontSize: scale.label,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        labelEmphasis = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurface,
          fontSize: scale.label,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        captionSoft = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurfaceSoft,
          fontSize: scale.caption,
          height: 1.35,
        ),
        // Sentence case, not uppercase. The web sets this step at 75% width;
        // Flutter has no width axis to reach for without shipping a font, so
        // it takes the same job with weight and quiet ink instead. What both
        // have in common is that neither shouts.
        overline = TextStyle(
          fontFamily: fontFamily,
          color: colors.onSurfaceFaint,
          fontSize: scale.overline,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          height: 1.25,
        ) {
    // Tabular variants are resolved here rather than through the `.tabular`
    // extension at each call site: a receipt at its 20-line cap reads a
    // numeric style 20 times per rebuild, and a `copyWith` per read is the
    // one place the "built once per theme" guarantee would leak back out.
    displayTabular = display.tabular;
    labelTabular = label.tabular;
    labelSoftTabular = labelSoft.tabular;
    captionTabular = caption.tabular;
    captionSoftTabular = captionSoft.tabular;
  }

  /// The one dominant number in a block.
  final TextStyle display;

  /// A block's own name: `_BlockTitle`, a card's headline, a receipt's order.
  final TextStyle title;

  final TextStyle heading;

  /// Assistant prose in the thread.
  final TextStyle prose;

  /// A supporting paragraph inside a block.
  final TextStyle body;

  /// A control or list-row label, at full ink.
  final TextStyle label;

  /// The same weight and size, quieted: secondary controls, inactive rows.
  final TextStyle labelSoft;

  /// The label on a filled accent control. The one place [RendelColors.onAccent]
  /// is used as type, named here so the button and the launcher cannot drift.
  final TextStyle labelStrong;

  /// The same weight in ordinary ink: the chosen row of a list, a picked
  /// option. Weight without spending the accent, and legible whatever the
  /// host mapped `onAccent` to.
  final TextStyle labelEmphasis;

  /// Metadata: timestamps, units, counts beside a label.
  final TextStyle caption;

  /// Metadata that still has to be read rather than skimmed.
  final TextStyle captionSoft;

  /// The quiet label that opens a block.
  final TextStyle overline;

  /// Numeric variants. Any price, count, quantity, percentage or timestamp
  /// uses one of these, so a figure that updates never shifts its column.
  late final TextStyle displayTabular;
  late final TextStyle labelTabular;
  late final TextStyle labelSoftTabular;
  late final TextStyle captionTabular;
  late final TextStyle captionSoftTabular;
}

/// Numbers are tabular, always: a column of prices that re-flows as it
/// streams reads as a bug rather than as an update.
///
/// Built-in renderers read the pre-resolved variants on [RendelTextStyles]; this
/// extension is for host-registered components, which have no way to add a
/// field to the theme.
extension RendelNumericText on TextStyle {
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

class RendelTheme {
  RendelTheme({
    required this.colors,
    this.radius = const RendelRadiusScale(),
    this.type = const RendelTypeScale(),
    this.space = const RendelSpaceScale(),
    this.motion = const RendelMotionScale(),
    this.size = const RendelSizeScale(),
    this.elevation = const RendelElevationScale(),
    this.style = const RendelStyle(),
    this.cards = const {},
    this.parts = const {},
    this.fontFamily,
    this.displayFontFamily,
    this.backdrop,
    Color? accentText,
    Color? accentEdge,
    Color? danger,
  })  : _accentText = accentText,
        _accentEdge = accentEdge,
        _danger = danger;

  /// Set only by the shipped defaults, where the exact value is published in
  /// `design/SYSTEM.md` and mirrored by `rdui.css` in the web preview kit. A
  /// host that maps its own accent leaves these null and gets the derivation.
  final Color? _accentText;
  final Color? _accentEdge;
  final Color? _danger;

  final RendelColors colors;
  final RendelRadiusScale radius;
  final RendelTypeScale type;
  final RendelSpaceScale space;
  final RendelMotionScale motion;
  final RendelSizeScale size;
  final RendelElevationScale elevation;
  final RendelStyle style;

  /// The page's ground, where the host paints its screens with a gradient.
  /// Null is the plain [RendelColors.surfaceRaised] it has always been.
  final RendelBackdrop? backdrop;

  /// Kinds of card set apart from the rest, by catalog type
  /// (`product_cards`, `info_card`, …). See [forCard].
  final Map<String, RendelCardLook> cards;

  final Map<String, RendelTheme> _cardThemes = {};

  /// The parts of the card this theme draws, when [forCard] made it.
  final Map<String, RendelPartLook> parts;

  /// [base], in the colour and size the card being drawn sets for its part
  /// [name]. Outside a card, or for a part nobody set, it is [base].
  TextStyle part(String name, TextStyle base) {
    final look = parts[name];
    if (look == null) return base;
    return base.copyWith(color: look.color, fontSize: look.size);
  }

  /// The theme a block of [kind] is drawn in: this one, with that kind of
  /// card's own plate, well, corner and build where [cards] sets them.
  ///
  /// Built once per type and kept, so a thread of forty product cards is one
  /// theme and not forty, and [RendelThemeScope] sees the same instance on
  /// every rebuild.
  RendelTheme forCard(String kind) {
    final look = cards[kind];
    if (look == null) return this;
    return _cardThemes[kind] ??= RendelTheme(
      colors: colors._withPlates(raised: look.surfaceRaised, sunk: look.surfaceSunk),
      radius: look.radius == null
          ? radius
          : RendelRadiusScale(
              xs: radius.xs,
              sm: radius.sm,
              card: look.radius!,
              hero: radius.hero,
              control: radius.control,
            ),
      type: type,
      space: space,
      motion: motion,
      size: size,
      elevation: elevation,
      style: look.style == null
          ? style
          : RendelStyle(
              card: look.style!,
              button: style.button,
              product: style.product,
              tracker: style.tracker,
              arrows: style.arrows,
            ),
      fontFamily: fontFamily,
      displayFontFamily: displayFontFamily,
      backdrop: backdrop,
      // A literal accent pair stays; a derived one is derived again against
      // this card's plate, so an outlined button's word still reads on it.
      parts: look.parts,
      accentText: _accentText,
      accentEdge: _accentEdge,
      danger: _danger,
    );
  }

  /// The face everything but the two display steps is set in. Null means the
  /// host app's own default, which is usually the right answer for an SDK.
  final String? fontFamily;

  /// The face `display` and `title` are set in. Null falls back to
  /// [fontFamily]. A host with a brand display face maps it once here and the
  /// whole catalog picks it up.
  final String? displayFontFamily;

  /// Resolved once per theme, on first read.
  late final RendelTextStyles text = RendelTextStyles._(
    colors: colors,
    scale: type,
    fontFamily: fontFamily,
    displayFontFamily: displayFontFamily,
  );

  /// The elevation specs, resolved against [RendelColors.shadow].
  late final List<BoxShadow> raise = _shadows(elevation.raise);
  late final List<BoxShadow> float = _shadows(elevation.float);
  late final List<BoxShadow> lift = _shadows(elevation.lift);

  List<BoxShadow> _shadows(List<RendelShadowSpec> specs) => [
        for (final spec in specs)
          BoxShadow(
            color: colors.shadow.withValues(alpha: spec.alpha),
            offset: Offset(0, spec.y),
            blurRadius: spec.blur,
            spreadRadius: spec.spread,
          ),
      ];

  /// The hairline of the surface's own light along the top edge of a raised
  /// plate, which is what makes it read as a material rather than as a
  /// lighter rectangle.
  ///
  /// Null on a light ground, and that is the point rather than an omission.
  /// A white highlight over a surface that is already near-white is invisible
  /// — there the tinted shadow does the whole job. On a deep ground the
  /// shadow has nothing lighter to fall on, so the highlight is the only
  /// thing separating a plate from the thread under it.
  late final BorderSide? innerHighlight = _lightOnDark
      ? BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1)
      : null;

  bool get _lightOnDark =>
      _relativeLuminance(colors.onSurface) > _relativeLuminance(colors.surface);

  // ———— v6: the soft-glass finish (`design/BLOCKS-v6.md`) ————
  //
  // Every role below is mixed from the colour roles above, never written as a
  // literal, so a customer's palette and the deep ground carry through. They
  // soften fills, lines and shadows only: no text is drawn in any of them, so
  // the contrast guarantees on the ink roles are untouched.

  /// Ink at 7% over whatever is under it: a progress track, a halo.
  late final Color tint = colors.onSurface.withValues(alpha: 0.07);

  /// Ink at 4% over the plate. Marks a state (the tracker's current step, the
  /// status pill); it never holds anything.
  late final Color highlight = Color.alphaBlend(
    colors.onSurface.withValues(alpha: 0.04),
    colors.surfaceRaised,
  );

  /// The hairline: ink at 10%.
  late final Color hairline = colors.onSurface.withValues(alpha: 0.10);

  /// The tracker's road and an inactive bar: ink at 16%.
  late final Color rail = colors.onSurface.withValues(alpha: 0.16);

  /// What a marked phrase sits on (`==x==` in a text block) and the round
  /// behind a way-on card's mark (`design/PAGES.md`): the brand's yellow on a
  /// light ground, mixed 22% into the surface on a deep one. A fill only; the
  /// words on it keep the ink, so their contrast is the ink's.
  late final Color mark = _lightOnDark
      ? Color.lerp(colors.surface, const Color(0xFFFEF7AF), 0.22)!
      : const Color(0xFFFEF7AF);

  /// What a readout is filled with — a progress value, the tracker's current
  /// mark: the ink 72% of the way from the ground. Soft, never the solid ink.
  late final Color readoutFill =
      Color.lerp(colors.surface, colors.onSurface, 0.72)!;

  /// The plate's ground: the raised surface at 82% over the thread's ground.
  ///
  /// Composited here rather than left translucent. A Flutter [BoxShadow] is
  /// painted under the whole box, not only outside it as a CSS box-shadow
  /// is, so a translucent plate shows its own shadow through itself as a
  /// grey slab. The thread under a plate is [RendelColors.surface], so the
  /// composite is the colour the web's glass shows on a plain ground.
  late final Color glass = Color.alphaBlend(
    colors.surfaceRaised.withValues(alpha: colors.surfaceRaised.a * 0.82),
    colors.surface,
  );

  /// A plate rounds 8 more than a card, so a card-radius row inside it is
  /// concentric; a product card 4 more.
  double get plateRadius => radius.card + 8;
  double get cardRadius => radius.card + 4;

  /// The long soft shadow under a plate, tinted with the theme's shadow hue
  /// (black on a deep ground, where nothing is lighter to fall on).
  late final List<BoxShadow> plateShadow = [
    BoxShadow(
      color: colors.shadow.withValues(alpha: _lightOnDark ? 0.55 : 0.32),
      offset: const Offset(0, 18),
      blurRadius: 36,
      spreadRadius: -20,
    ),
  ];

  /// The same shadow, shorter, under a product card.
  late final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: colors.shadow.withValues(alpha: _lightOnDark ? 0.55 : 0.32),
      offset: const Offset(0, 12),
      blurRadius: 26,
      spreadRadius: -18,
    ),
  ];

  /// The primary action's fill: the accent lit from above, from the accent
  /// mixed 82% into the plate down to the accent itself.
  late final Gradient litFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color.lerp(colors.surfaceRaised, colors.accent, 0.82)!, colors.accent],
  );

  /// The 1px highlight along the top of a lit fill.
  static const Color litEdge = Color(0x29FFFFFF);

  /// The soft shadow under a lit fill.
  static const List<BoxShadow> litShadow = [
    BoxShadow(
      color: Color(0x73000000),
      offset: Offset(0, 10),
      blurRadius: 22,
      spreadRadius: -12,
    ),
  ];

  /// Where a picture goes and there is none (or it is still loading): a pale
  /// wash turned from the accent's own hue rather than a grey box. The hue
  /// family is kept (a wider turn made a violet theme olive on a dark ground)
  /// and the lightness and saturation are floored, so a black accent still
  /// gives a tint and not grey.
  late final Gradient wash = () {
    final accent = HSLColor.fromColor(colors.accent);
    Color tone(double turn) => Color.lerp(
          colors.surfaceRaised,
          HSLColor.fromAHSL(
            1,
            (accent.hue + turn) % 360,
            math.max(accent.saturation, 0.6),
            math.max(accent.lightness, 0.86),
          ).toColor(),
          0.26,
        )!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [tone(0), tone(320)],
    );
  }();

  /// The accent, darkened until it is legible AS TEXT.
  ///
  /// The brand orange as text on the light canvas is 2.8:1, so a badge or an
  /// inline mark painted in the raw accent fails AA while looking perfectly
  /// deliberate. Hosts map one accent; this derives the readable form of it
  /// rather than asking for a second token.
  ///
  /// Solved on every surface, not on the one the RAW accent is hardest
  /// against. Which ground is hardest changes as the value moves: darkening
  /// an orange for a cream ground can take it past the sunk surface it also
  /// has to hold on, and `_legible` stops the moment it clears the one ground
  /// it was given. On a sweep of random brands a quarter of the themes the
  /// device accepted had this role below 4.5:1 on at least one surface it is
  /// actually drawn on.
  late final Color accentText = _accentText ?? _legibleOnAll(colors.accent, 4.5);

  /// The BOUNDARY of an accent fill, and the focus ring.
  ///
  /// WCAG 1.4.11 asks 3:1 of the visual boundary that identifies a control.
  /// The old system asked whether the accent *fill* cleared 3:1 against the
  /// background, which is a different question and the wrong one: a filled
  /// button is identified by its edge. On the tinted ground the raw accent
  /// measures 2.8:1 and would have failed silently, so every accent fill in
  /// the catalog carries a 1px rim in this colour. Where the accent already
  /// clears 3:1 on its own — any dark theme — this resolves to the accent.
  ///
  /// Solved on all four surfaces, for the reason [accentText] gives.
  late final Color accentEdge = _accentEdge ?? _legibleOnAll(colors.accent, 3.0);

  /// The one thing in this system that is not the accent and still means
  /// something: a change that cannot be taken back.
  ///
  /// For three revisions the rule was that severity is carried by the words
  /// and by the confirmation, never by a hue — and what that produced was a
  /// destructive confirmation announcing itself with a 1.5px ink border, a
  /// hard edge doing the job of a warning on the softest surface in the
  /// product. This is that edge, as a colour.
  ///
  /// It is not a status palette. There is no success green and no warning
  /// amber; a status banner still carries its tone in its glyph and its
  /// words. A host that maps its own brand gets this solved against their
  /// surfaces the same way [accentText] is, so a dark host does not get a
  /// crimson nobody can read.
  late final Color danger = _danger ?? _legibleOnAll(const Color(0xFFB92D45), 4.5);

  /// The boundary of an interactive control.
  ///
  /// The decorative hairlines ([RendelColors.line], [RendelColors.lineStrong]) stay
  /// as light as the design language intends; this is a separate role for the
  /// edges that have a job to do.
  ///
  /// The LIGHTEST ink that still clears the threshold on every surface, not
  /// the ink itself: asking "does onSurface pass 3:1" answers yes at 12:1 and
  /// hands every text field a solid near-black border.
  late final Color lineControl = _heaviest([
    _boundary(colors.onSurface, colors.surface, 3.0),
    _boundary(colors.onSurface, colors.surfaceRaised, 3.0),
    _boundary(colors.onSurface, colors.surfaceSunk, 3.0),
    _boundary(colors.onSurface, colors.surfaceHigh, 3.0),
  ]);

  /// The placeholder in the composer, quieted as far as AA allows ON THE BOX.
  ///
  /// [RendelColors.onSurfaceFaint] is quieted toward the thread's ground and held
  /// above the floor on the four surfaces the thread is made of. None of that
  /// is true of a box the brand painted a different colour, which is the
  /// entire reason [RendelColors.composer] exists — so once the box is its own
  /// colour its placeholder is solved on it, and until then the thread's own
  /// answer is handed back untouched.
  late final Color onComposerFaint = colors.mappedOnComposerFaint ??
      (colors.composerIsMapped
          ? Color.lerp(
              colors.onComposer,
              colors.composer,
              _quietRoom(
                colors.onComposer,
                colors.composer,
                [colors.composer],
                0.42,
                4.5,
              ),
            )!
          : colors.onSurfaceFaint);

  /// The boundary of the composer, for the same reason and under the same
  /// rule: WCAG 1.4.11 asks 3:1 of the edge that identifies a control, and
  /// [lineControl] is the heaviest answer across the thread's four surfaces
  /// rather than an answer about this box.
  late final Color composerEdge = colors.composerIsMapped
      ? _boundary(colors.onComposer, colors.composer, 3.0)
      : lineControl;

  /// The solution that holds on every surface, out of the four per-surface
  /// solutions.
  ///
  /// [_legible] takes one background, and the four candidates it returns are
  /// not interchangeable: each clears the threshold on the ground it was
  /// solved for and may sit under it on the others. Solving all four and
  /// keeping whichever has the highest WORST ratio across the set gives the
  /// one value that holds everywhere — the same shape as [lineControl]'s
  /// `_heaviest`, which has always done this correctly.
  ///
  /// If no candidate clears on all four, the best available is returned
  /// rather than a failure: the palette is the customer's, the console tells
  /// them the number before they can publish it, and the device still draws
  /// the most legible value on their own hue.
  Color _legibleOnAll(Color ink, double minimum) => _legibleOnGrounds(
        ink,
        [
          colors.surface,
          colors.surfaceRaised,
          colors.surfaceSunk,
          colors.surfaceHigh,
          // The page's words sit on every colour of its backdrop too.
          ...?backdrop?.colors,
        ],
        minimum,
      );

  static RendelTheme? _paper;
  static RendelTheme? _deep;

  /// The Neon design language, light — visual system v5, the landing page's.
  ///
  /// A warm paper ground, white plates, a warm near-black ink, and black as
  /// the one colour that means "you can act on this". The brand's other
  /// colour, the soft yellow, is a fill that cannot be type or a boundary on
  /// a light ground (about 1.1:1 on white), so it is not spent here: on paper
  /// the action is black, and the yellow takes the action on the deep ground,
  /// in [RendelTheme.deep] — the same split the landing page draws.
  factory RendelTheme.paper() => _paper ??= RendelTheme(
        colors: const RendelColors(
          surface: Color(0xFFF4F2EE),
          // White, and on purpose. v4 held every surface off white because a
          // white plate beside a tinted one read as a different material. In
          // v5 that IS the material: white plates on a warm ground, the way
          // the landing page, the console and the docs draw every object.
          surfaceRaised: Color(0xFFFFFFFF),
          surfaceSunk: Color(0xFFEDE9E6),
          // The same white as a raised plate. Elevation, not a second white,
          // is what separates a block waiting on an answer from a readout.
          surfaceHigh: Color(0xFFFFFFFF),
          // A hair off the brand black. #0A0A0A on this ground is 17.7:1, over
          // the ceiling `contrast_test.dart` holds body ink under; this is
          // 16.2 and reads as the same black.
          onSurface: Color(0xFF171615),
          onSurfaceSoft: Color(0xFF605F5F),
          // 5.04 on the sunk surface, the hardest of the four.
          onSurfaceFaint: Color(0xFF64625E),
          accent: Color(0xFF0A0A0A),
          // White, at 19.8.
          onAccent: Color(0xFFFFFFFF),
          line: Color(0x14171615),
          lineStrong: Color(0x24171615),
          shadow: Color(0xFF171615),
        ),
        // Published values, not derivations: `rdui.css` renders these same
        // blocks in the browser and has to name a literal, so these are the
        // literals it names. `contrast_test.dart` reads them out of `rdui.css`
        // rather than restating them, so the two sides cannot drift under a
        // green test.
        //
        // Both are the black itself: 16.4 at worst as type and as a boundary,
        // so a second value would be a token that exists to say "unchanged".
        accentText: const Color(0xFF0A0A0A),
        accentEdge: const Color(0xFF0A0A0A),
        // The landing page's red. 5.22 on the ground, 4.84 on the sunk
        // surface, 5.84 on a plate, as type and as a boundary alike. White on
        // it is 5.84.
        danger: const Color(0xFFC4202F),
      );

  /// The same language on a deep ground, for hosts whose own app is dark.
  /// Not a mode the SDK switches into by itself: the host maps it.
  ///
  /// The ground is the landing page's one dark object, the code plate, warmed
  /// just enough to keep a hue, and the ink is the paper. The action is the
  /// yellow here, as it is on the landing's dark band: black cannot mark an
  /// action on a near-black ground, and the yellow, which fails as type on
  /// paper, is 14.9:1 at worst on these surfaces.
  factory RendelTheme.deep() => _deep ??= RendelTheme(
        colors: const RendelColors(
          surface: Color(0xFF12110F),
          surfaceRaised: Color(0xFF1B1A17),
          surfaceSunk: Color(0xFF0C0B09),
          // Held here rather than at a lighter step so `onSurfaceFaint` still
          // clears AA on it, at 5.58.
          surfaceHigh: Color(0xFF21201D),
          onSurface: Color(0xFFF4F2EE),
          onSurfaceSoft: Color(0xFFB8B5AE),
          onSurfaceFaint: Color(0xFF9A978F),
          accent: Color(0xFFFEF7AF),
          // The brand black on the brand yellow, at 18.0.
          onAccent: Color(0xFF0A0A0A),
          line: Color(0x24F4F2EE),
          lineStrong: Color(0x33F4F2EE),
          shadow: Color(0xFF000000),
        ),
        // The yellow does all three jobs on this ground, as the black does on
        // paper: 14.85 at worst as type and as a boundary.
        accentText: const Color(0xFFFEF7AF),
        accentEdge: const Color(0xFFFEF7AF),
        // 8.12 at worst across the four deep surfaces.
        danger: const Color(0xFFFF9AAC),
      );

  @Deprecated('Use RendelTheme.paper(). Renamed in 0.32.0.')
  factory RendelTheme.neonDefault() => RendelTheme.paper();

  @Deprecated('Use RendelTheme.deep(). Renamed in 0.32.0.')
  factory RendelTheme.neonDeep() => RendelTheme.deep();

  /// The same theme in another family.
  ///
  /// The one part of a look a host knows better than the console. A font the
  /// app bundles has the name it is bundled under, and the console can carry
  /// it; a font `google_fonts` fetches is registered as `Family_variant`
  /// (`BaiJamjuree_regular`), which only the app's own font object can give —
  /// name it by hand and Flutter falls back to the system face without a
  /// word. So `RendelConfig.fontFamily` comes through here, under whatever
  /// the console publishes.
  RendelTheme withFont(String? family, {String? display}) =>
      family == null && display == null
          ? this
          : RendelTheme(
              colors: colors,
              radius: radius,
              type: type,
              space: space,
              motion: motion,
              size: size,
              elevation: elevation,
              style: style,
              cards: cards,
              parts: parts,
              fontFamily: family ?? fontFamily,
              displayFontFamily: display ?? displayFontFamily,
              backdrop: backdrop,
              accentText: _accentText,
              accentEdge: _accentEdge,
              danger: _danger,
            );

  /// A host maps four colours and the whole catalog follows. The surfaces
  /// that carry depth are derived from the ground, moving away from the ink
  /// for a raised surface and toward it for a well, so a brand that maps a
  /// dark ground gets a dark elevation model rather than an inverted one.
  factory RendelTheme.fromTokens({
    required Color surface,
    required Color onSurface,
    required Color accent,
    required Color onAccent,
    Color? surfaceRaised,
    Color? surfaceSunk,
    Color? surfaceHigh,
    Color? bubble,
    Color? onBubble,
    Color? composer,
    Color? onComposer,
    Color? onComposerFaint,
    Color? shadow,
    RendelRadiusScale radius = const RendelRadiusScale(),
    RendelTypeScale type = const RendelTypeScale(),
    RendelSpaceScale space = const RendelSpaceScale(),
    RendelMotionScale motion = const RendelMotionScale(),
    RendelSizeScale size = const RendelSizeScale(),
    RendelElevationScale elevation = const RendelElevationScale(),
    RendelStyle style = const RendelStyle(),
    Map<String, RendelCardLook> cards = const {},
    String? fontFamily,
    String? displayFontFamily,
    RendelBackdrop? backdrop,
  }) {
    Color blend(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);

    // Elevation is a property of the GROUND, and of nothing else.
    //
    // This used to be decided by which of the ground and the ink was lighter,
    // and the surfaces were then mixed toward the ink. That let the text
    // colour move the product card: on a coloured ground, dragging the ink
    // past the ground's own lightness flipped the whole elevation model, and
    // a customer who touched a field called "Text" watched every plate jump.
    //
    // A plate is raised off the ground and a well is sunk into it; neither is
    // a statement about the words on top. So the poles are white and black,
    // the amounts come from whether the ground is light, and the ink is not
    // consulted.
    final light = contrastRatio(surface, black) > contrastRatio(surface, white);

    final raised = surfaceRaised ?? blend(surface, white, light ? 0.42 : 0.05);
    final sunk = surfaceSunk ?? blend(surface, black, light ? 0.055 : 0.3);
    final high = surfaceHigh ?? blend(surface, white, light ? 0.68 : 0.09);
    // A backdrop's colours are grounds the page's words are read on, so the
    // ink and its quiet steps are solved on them as on the plates.
    final grounds = [surface, raised, sunk, high, ...?backdrop?.colors];

    // A label on a filled control is small text, so it is held to 4.5:1. A
    // host that maps white onto a mid-value brand orange gets 3.3:1, and the
    // catalog would have shipped it. The mapped value is honoured wherever it
    // clears the floor and rescued where it does not, and the developer is
    // told on their own machine rather than in a review.
    final legibleOnAccent = _legible(onAccent, accent, 4.5);
    if (kDebugMode && legibleOnAccent != onAccent) {
      debugPrint(
        '[rendel] onAccent was '
        '${contrastRatio(onAccent, accent).toStringAsFixed(2)}:1 on the '
        'accent, below the 4.5:1 floor for a control label. Darkened to keep '
        'the label readable; map a legible pair to keep your exact colour.',
      );
    }

    // The same rescue for the host's own ink, and for the same reason.
    //
    // `onAccent` was rescued and `onSurface` was not, which meant a brand that
    // mapped a warm mid-grey onto its warm off-white ground — a completely
    // ordinary pairing — had all THREE ink steps collapse onto one failing
    // colour and ship. `_quietRoom` correctly returns zero when nothing holds,
    // and zero room applied to a failing base is still a failing base.
    //
    // Solved on ALL FOUR grounds, not against whichever one the raw ink is
    // hardest against.
    //
    // Picking the hardest ground and calling `_legible` once was the same
    // mistake the accent roles carried until it was fixed there, and it is
    // worse for the ink because the ink is what the thread is made of. A white
    // ink on a mid violet, already clearing 4.50 to 8.85 on all four surfaces,
    // tripped the rescue on the 4.50 and came back as `#040404` — 2.32 on the
    // raised surface, three of four failing, and `_quietRoom` returning zero
    // so all three ink steps collapsed onto it. The direction is the trap: it
    // is chosen from one ground's luminance, and near the 0.18 switch the
    // bisection walks straight across that ground's own value.
    var hardestForInk = surface;
    for (final ground in grounds) {
      if (contrastRatio(onSurface, ground) <
          contrastRatio(onSurface, hardestForInk)) {
        hardestForInk = ground;
      }
    }
    final legibleInk = _legibleOnGrounds(onSurface, grounds, 4.5);
    if (kDebugMode && legibleInk != onSurface) {
      debugPrint(
        '[rendel] onSurface was '
        '${contrastRatio(onSurface, hardestForInk).toStringAsFixed(2)}:1 on '
        'the surface it is hardest against, below the 4.5:1 floor for body '
        'text. Deepened to keep the thread readable; map a legible pair to '
        'keep your exact colour.',
      );
    }

    // The largest step toward the ground that still clears AA on every
    // surface. Capped at 0.42, which is where the ink stops reading as ink.
    final quietRoom = _quietRoom(legibleInk, surface, grounds, 0.42, 4.5);

    return RendelTheme(
      colors: RendelColors(
        surface: surface,
        surfaceRaised: raised,
        surfaceSunk: sunk,
        surfaceHigh: high,
        onSurface: legibleInk,
        // Quieted toward the ground, but only as far as AA allows on every
        // surface at once, and then SPLIT rather than clamped. A flat 28% and
        // 42% is the right *look* and the wrong *guarantee*: on a light ground
        // it put the faint step at 4.07:1, a failing token the SDK derived for
        // the host itself. Clamping each step separately fixed the floor and
        // broke the hierarchy instead — both landed within two points of each
        // other and the catalog lost its tertiary ink.
        //
        // So the room is measured once and the two steps divide it. The faint
        // step takes all of it; the soft step takes 60%, which keeps the gap
        // between them proportional to whatever the brand actually allows.
        onSurfaceSoft: blend(legibleInk, surface, quietRoom * 0.6),
        onSurfaceFaint: blend(legibleInk, surface, quietRoom),
        accent: accent,
        onAccent: legibleOnAccent,
        // Rescued against the bubble the way the label on a control is
        // rescued against the accent: a brand that picks its own blue and
        // leaves the text alone should not have to find 2.9:1 for itself.
        bubble: bubble,
        onBubble: bubble == null
            ? (onBubble == null ? null : _legible(onBubble, sunk, 4.5))
            : _legible(onBubble ?? legibleInk, bubble, 4.5),
        // Same shape one field over, and the same reason: a brand that
        // darkens the message box and leaves the words alone should not have
        // to discover 1.4:1 for itself. Null stays null so `composerIsMapped`
        // can tell a choice from a default.
        composer: composer,
        onComposer: composer == null
            ? (onComposer == null ? null : _legible(onComposer, high, 4.5))
            : _legible(onComposer ?? legibleInk, composer, 4.5),
        // A stated prompt colour is text on the box, so it is rescued on the
        // box. Null stays null: the derivation is the default and it is a
        // better one than any single literal.
        onComposerFaint: onComposerFaint == null
            ? null
            : _legible(onComposerFaint, composer ?? high, 4.5),
        line: legibleInk.withValues(alpha: light ? 0.10 : 0.14),
        lineStrong: legibleInk.withValues(alpha: light ? 0.16 : 0.20),
        // A shadow on a dark ground has nothing lighter to fall on, so it
        // goes to black rather than to the host's ink.
        shadow: shadow ?? (light ? legibleInk : const Color(0xFF000000)),
      ),
      radius: radius,
      type: type,
      space: space,
      motion: motion,
      size: size,
      elevation: elevation,
      style: style,
      cards: cards,
      fontFamily: fontFamily,
      displayFontFamily: displayFontFamily,
      backdrop: backdrop,
    );
  }

  /// The theme [light] is drawn in when the device is in dark mode, for a
  /// host that maps one theme and not two (design/AI-SETUP.md §9.5).
  ///
  /// [paper] is [deep], the published pair. A theme that is already dark is
  /// its own dark theme: nothing is inverted. Any other gets the four roles
  /// [rendelDarkRoles] derives from its own, and every surface, quiet ink and
  /// accent role is then solved from those exactly as [fromTokens] solves a
  /// light palette — so the dark theme is held to the same floors. Its sizes,
  /// faces and builds are the light theme's; a card's own colours are not,
  /// because they were chosen for a light plate.
  ///
  /// Pass `darkTheme` to `Rendel.init` to choose it yourself instead.
  factory RendelTheme.darkFrom(RendelTheme light) {
    if (identical(light, RendelTheme.paper())) return RendelTheme.deep();
    if (light._lightOnDark) return light;
    final roles = rendelDarkRoles(
      surface: light.colors.surface,
      onSurface: light.colors.onSurface,
      accent: light.colors.accent,
      onAccent: light.colors.onAccent,
    );
    return RendelTheme.fromTokens(
      surface: roles.surface,
      onSurface: roles.onSurface,
      accent: roles.accent,
      onAccent: roles.onAccent,
      radius: light.radius,
      type: light.type,
      space: light.space,
      motion: light.motion,
      size: light.size,
      elevation: light.elevation,
      style: light.style,
      cards: {
        for (final MapEntry(key: kind, value: look) in light.cards.entries)
          kind: RendelCardLook(
            radius: look.radius,
            style: look.style,
            parts: {
              for (final MapEntry(key: name, value: part) in look.parts.entries)
                name: RendelPartLook(size: part.size, radius: part.radius),
            },
          ),
      },
      fontFamily: light.fontFamily,
      displayFontFamily: light.displayFontFamily,
    );
  }
}

// ———————————————————————— dark mode ————————————————————————
//
// One derivation, written three times: `deriveDarkTokens` in
// `packages/protocol/src/appconfig.ts` (the reference, and the console's),
// `sdk/web/src/config.ts`, and this. Byte channels rounded to the nearest
// integer throughout, so the three agree to the byte; `dark_test.dart` pins
// the same inputs to the same hex as the protocol's own test.

/// The four roles a dark theme is derived in: whatever the dark palette
/// states ([darkSurface] and the rest), and for each one it leaves out, a
/// derivation from the light four.
///
///   * A light palette that is already dark (its ink lighter than its
///     ground) is its own dark palette.
///   * Otherwise the ground and the ink are [RendelTheme.deep]'s.
///   * The accent is kept where it reads on that ground as a boundary (3:1)
///     and lightened along its own hue where it does not. A grey accent has
///     no hue to keep — a light theme's black button is that theme's ink — so
///     it becomes the dark ink. The brand's own palette takes the brand's
///     yellow, so `paper()` derives to exactly `deep()`.
///   * The label on the accent is the light one where it still clears 4.5:1,
///     and otherwise whichever of near-black and white reads better.
({Color surface, Color onSurface, Color accent, Color onAccent})
    rendelDarkRoles({
  required Color surface,
  required Color onSurface,
  required Color accent,
  required Color onAccent,
  Color? darkSurface,
  Color? darkOnSurface,
  Color? darkAccent,
  Color? darkOnAccent,
}) {
  const deepSurface = Color(0xFF12110F);
  const deepInk = Color(0xFFF4F2EE);
  const brandYellow = Color(0xFFFEF7AF);
  const nearBlack = Color(0xFF0A0A0A);
  const white = Color(0xFFFFFFFF);

  final alreadyDark =
      _relativeLuminance(onSurface) > _relativeLuminance(surface);
  final ground = darkSurface ?? (alreadyDark ? surface : deepSurface);
  final ink = darkOnSurface ?? (alreadyDark ? onSurface : deepInk);
  final paper = RendelTheme.paper().colors;
  final brandDefault = _byte(surface) == _byte(paper.surface) &&
      _byte(onSurface) == _byte(paper.onSurface) &&
      _byte(accent) == _byte(paper.accent) &&
      _byte(onAccent) == _byte(paper.onAccent);
  final action = darkAccent ??
      (alreadyDark
          ? accent
          : brandDefault
              ? brandYellow
              : _darkAccent(accent, ground, ink));
  final label = darkOnAccent ??
      (contrastRatio(onAccent, action) >= 4.5
          ? onAccent
          : contrastRatio(nearBlack, action) >= contrastRatio(white, action)
              ? nearBlack
              : white);
  return (surface: ground, onSurface: ink, accent: action, onAccent: label);
}

/// A colour as its 24-bit RGB, for comparing two by value.
int _byte(Color color) =>
    (color.r * 255).round() << 16 |
    (color.g * 255).round() << 8 |
    (color.b * 255).round();

/// [accent] on a dark [ground]; see [rendelDarkRoles].
Color _darkAccent(Color accent, Color ground, Color ink) {
  if (contrastRatio(accent, ground) >= 3) return accent;
  final channels = [accent.r, accent.g, accent.b]
      .map((v) => (v * 255).round())
      .toList();
  final max = channels.reduce(math.max) / 255;
  final min = channels.reduce(math.min) / 255;
  final lightness = (max + min) / 2;
  final saturation =
      max == min ? 0.0 : (max - min) / (1 - (2 * lightness - 1).abs());
  if (saturation < 0.15) return ink;
  // Toward white in whole bytes, as the console's mirror does, so the two
  // land on the same value rather than a rounding apart.
  Color toward(double t) => Color.fromARGB(
        255,
        (channels[0] + (255 - channels[0]) * t).round(),
        (channels[1] + (255 - channels[1]) * t).round(),
        (channels[2] + (255 - channels[2]) * t).round(),
      );
  // To the floor plus the margin every other rescue here keeps, so the
  // rounding cannot land it at 2.99.
  final wanted = 3 + _floorMargin;
  var found = toward(1);
  if (contrastRatio(found, ground) < wanted) return ink;
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 12; i++) {
    final mid = (low + high) / 2;
    final candidate = toward(mid);
    if (contrastRatio(candidate, ground) >= wanted) {
      found = candidate;
      high = mid;
    } else {
      low = mid;
    }
  }
  return found;
}

/// How far [ink] may move toward [ground] before it stops clearing [minimum]
/// against every one of [backgrounds], capped at [target].
///
/// The quiet ink steps are a *look* — a soft secondary, a fainter tertiary —
/// but the look is not allowed to cost legibility. Measuring the room once
/// and dividing it is what keeps both facts true at the same time: nothing
/// derived falls below the floor, and the two steps stay visibly apart even
/// on a brand that leaves very little room between them.
double _quietRoom(
  Color ink,
  Color ground,
  List<Color> backgrounds,
  double target,
  double minimum,
) {
  bool holds(double t) {
    final candidate = Color.lerp(ink, ground, t)!;
    return backgrounds.every((background) =>
        contrastRatio(candidate, background) >= minimum + _floorMargin);
  }

  if (holds(target)) return target;

  var low = 0.0;
  var high = target;
  var best = 0.0;
  for (var i = 0; i < 12; i++) {
    final mid = (low + high) / 2;
    if (holds(mid)) {
      best = mid;
      low = mid;
    } else {
      high = mid;
    }
  }
  return best;
}

/// The most opaque of several candidate line colours.
///
/// `lineControl` has to clear 3:1 on every surface at once, and solving for
/// each one separately then keeping the heaviest answer cannot be wrong on
/// any of them.
Color _heaviest(List<Color> candidates) =>
    candidates.reduce((a, b) => a.a >= b.a ? a : b);

/// Debug-mode contrast audit for a host's token map.
///
/// The docs promise that a failing token pair surfaces on the developer's own
/// machine rather than in a review, so this runs at init and names the exact
/// pair that fails. Release builds skip it entirely: it is a lint, not a
/// runtime guard, and it never changes what is rendered.
///
/// Thresholds follow WCAG 2.1: 4.5:1 for every text role, including the label
/// on a filled control — at 13.5pt or less that is small text, not WCAG large
/// — and 3:1 for the boundary of a control.
void auditContrast(RendelTheme theme) {
  if (!kDebugMode) return;
  final colors = theme.colors;
  final surfaces = <(String, Color)>[
    ('surface', colors.surface),
    ('surfaceRaised', colors.surfaceRaised),
    ('surfaceSunk', colors.surfaceSunk),
    ('surfaceHigh', colors.surfaceHigh),
  ];

  final checks = <(String, Color, Color, double)>[
    for (final (name, background) in surfaces) ...[
      ('onSurface / $name', colors.onSurface, background, 4.5),
      ('onSurfaceSoft / $name', colors.onSurfaceSoft, background, 4.5),
      ('onSurfaceFaint / $name', colors.onSurfaceFaint, background, 4.5),
      ('accentText / $name', theme.accentText, background, 4.5),
      // The BOUNDARY of an accent fill, which is what identifies the control.
      // Asking this of the fill instead is the question the old audit asked,
      // and it is not the one WCAG 1.4.11 poses.
      ('accentEdge / $name', theme.accentEdge, background, 3.0),
      ('lineControl / $name', theme.lineControl, background, 3.0),
    ],
    // onAccent is a label on a filled control at 13.5pt or less, which is not
    // WCAG "large" — so it is held to the text threshold, not the graphic one.
    ('onAccent / accent', colors.onAccent, colors.accent, 4.5),
    // The composer, but only once it is a colour of its own. Unmapped, every
    // one of these three resolves to a pair the loop above has already
    // measured, and a lint that reports the same fact twice is a lint people
    // stop reading.
    if (colors.composerIsMapped) ...[
      ('onComposer / composer', colors.onComposer, colors.composer, 4.5),
      ('composerEdge / composer', theme.composerEdge, colors.composer, 3.0),
    ],
    // The prompt separately: a brand may state it on a box it left alone, and
    // a placeholder is text whoever chose it.
    if (colors.composerIsMapped || colors.mappedOnComposerFaint != null)
      (
        'onComposerFaint / composer',
        theme.onComposerFaint,
        colors.composer,
        4.5
      ),
  ];

  for (final (label, foreground, background, minimum) in checks) {
    final ratio = contrastRatio(foreground, background);
    if (ratio < minimum) {
      debugPrint(
        '[rendel] contrast warning: $label is '
        '${ratio.toStringAsFixed(2)}:1, below the ${minimum.toStringAsFixed(1)}:1 '
        'minimum. Adjust the token pair before shipping.',
      );
    }
  }
}

/// WCAG relative-luminance contrast ratio between two colors.
///
/// A translucent foreground is composited over the background first. Scoring a
/// 10%-alpha hairline as if it were opaque reported 15.9:1 for a line that is
/// really 1.5:1, which is how an audit passes a design that fails.
double contrastRatio(Color foreground, Color background) {
  final a = _relativeLuminance(_flatten(foreground, background));
  final b = _relativeLuminance(background);
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _flatten(Color foreground, Color background) {
  if (foreground.a >= 1) return foreground;
  return Color.lerp(background, foreground.withValues(alpha: 1), foreground.a)!;
}

/// Every derived role clears its floor by at least this much.
///
/// A bisection converges on the floor exactly, and then the compositor rounds
/// the result to eight bits per channel. That rounding is worth up to about
/// 0.02 of ratio, so a value derived to land on 3.0000 renders at 2.99 — the
/// derivation passes its own test and the pixels do not. Everything below
/// solves for the floor plus this margin instead, which is the difference
/// between measuring the intent and measuring the paint.
const double _floorMargin = 0.05;

/// The lightest opacity of [ink] over [background] that still clears
/// [minimum]. For boundaries, where the goal is the quietest line that is
/// still legible rather than the strongest one available.
Color _boundary(Color ink, Color background, double minimum) {
  final target = minimum + _floorMargin;
  var low = 0.0;
  var high = 1.0;
  var best = ink;
  for (var i = 0; i < 12; i++) {
    final mid = (low + high) / 2;
    final candidate = ink.withValues(alpha: mid);
    if (contrastRatio(candidate, background) >= target) {
      best = candidate;
      high = mid;
    } else {
      low = mid;
    }
  }
  return best;
}

/// The value that clears [minimum] on EVERY one of [grounds], not just on the
/// one it was handed.
///
/// [_legible] takes a single background and stops the moment it clears that
/// one, which is wrong twice over when a role is drawn on four surfaces. It
/// can stop short — the value clears the ground it was solved for and sits
/// under the floor on the others. And it can walk the wrong way entirely: the
/// direction is chosen from one ground's luminance, and when that ground sits
/// near the 0.18 switch the bisection crosses the ground's own value on its
/// way and lands further from legible than it started. A white ink on a mid
/// violet, already clearing 4.50 to 8.85 on all four, came back as `#040404`
/// at 2.32 on the surface it is most often drawn on.
///
/// Both ends of the value range are tried, and the answer is the one whose
/// WORST ratio across the whole set clears. Where two clear, the shorter step
/// wins, because it keeps more of the customer's colour. Where neither does,
/// the least bad is returned and the caller's audit reports it.
Color _legibleOnGrounds(Color ink, List<Color> grounds, double minimum) {
  double worstAgainstAll(Color candidate) {
    var worst = double.infinity;
    for (final ground in grounds) {
      final ratio = contrastRatio(candidate, ground);
      if (ratio < worst) worst = ratio;
    }
    return worst;
  }

  final wanted = minimum + _floorMargin;
  if (worstAgainstAll(ink) >= wanted) return ink;

  var best = ink;
  var bestWorst = worstAgainstAll(ink);
  var bestStep = 2.0;
  for (final target in const [Color(0xFF000000), Color(0xFFFFFFFF)]) {
    final end = Color.lerp(ink, target, 1)!;
    final endWorst = worstAgainstAll(end);
    if (endWorst < wanted) {
      if (bestWorst < wanted && endWorst > bestWorst) {
        bestWorst = endWorst;
        best = end;
      }
      continue;
    }
    var low = 0.0;
    var high = 1.0;
    var found = end;
    var step = 1.0;
    for (var i = 0; i < 12; i++) {
      final mid = (low + high) / 2;
      final candidate = Color.lerp(ink, target, mid)!;
      if (worstAgainstAll(candidate) >= wanted) {
        found = candidate;
        step = mid;
        high = mid;
      } else {
        low = mid;
      }
    }
    if (bestWorst < wanted || step < bestStep) {
      best = found;
      bestWorst = worstAgainstAll(found);
      bestStep = step;
    }
  }
  return best;
}

/// Steps [ink] toward the far end of the value range until it clears [minimum]
/// against [background], so a host's brand colour keeps its hue and gains the
/// contrast. Returns the closest it can get if even black or white cannot.
Color _legible(Color ink, Color background, double minimum) {
  final wanted = minimum + _floorMargin;
  if (contrastRatio(ink, background) >= wanted) return ink;
  final target = _relativeLuminance(background) > 0.18
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
  var low = 0.0;
  var high = 1.0;
  var best = Color.lerp(ink, target, 1)!;
  for (var i = 0; i < 12; i++) {
    final mid = (low + high) / 2;
    final candidate = Color.lerp(ink, target, mid)!;
    if (contrastRatio(candidate, background) >= wanted) {
      best = candidate;
      high = mid;
    } else {
      low = mid;
    }
  }
  return best;
}

double _relativeLuminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

class RendelThemeScope extends InheritedWidget {
  const RendelThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final RendelTheme theme;

  static RendelTheme of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RendelThemeScope>();
    return scope?.theme ?? RendelTheme.paper();
  }

  @override
  bool updateShouldNotify(RendelThemeScope oldWidget) => oldWidget.theme != theme;
}
