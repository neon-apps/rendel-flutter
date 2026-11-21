import 'dart:math' as math;
import 'dart:ui' show FragmentProgram, FragmentShader, ImageFilter;

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// The panel's look (`design/plans/sdk-look-a.md`): glass controls, a pale
/// two-colour ground light, suggestion cards over an 80-point message card.
///
/// Internal. `look` is `a`, the panel since 0.93.0, unless a lab sets it to
/// `today`, the look before it, to set one beside the other.
abstract final class RendelLab {
  static final ValueNotifier<Map<String, String>> picks = ValueNotifier(const {});

  static set surfaces(Map<String, String> value) => picks.value = Map.unmodifiable(value);

  static String of(String surface) => picks.value[surface] ?? (surface == 'look' ? 'a' : 'today');

  /// A question the thread asks as it opens, once: the lab's screenshots.
  static String? autoAsk;

  static String? takeAutoAsk() {
    final q = autoAsk;
    autoAsk = null;
    return q;
  }

}

/// How the panel looks, beyond the theme.
abstract final class RendelLook {
  /// The two colours of the light behind the panel, left then right: your
  /// app's own, drawn as pale pastels. Unset, both are the theme's accent.
  static (Color, Color)? groundLight;

  /// A suggestion drawn as a card: its short title, the line under it and a
  /// picture (an asset path, or an https URL), keyed by the suggestion's text. A suggestion
  /// without one is drawn with its own words.
  static Map<String, RendelSuggestionCard> suggestionCards = const {};

  /// The console's line under a suggestion (Persona › Opening), keyed by its
  /// words; set from the published config. A card in [suggestionCards] wins.
  static Map<String, String> consoleLines = const {};

  /// The card a suggestion is drawn as: the app's own, else one of its own
  /// words over the console's line (Helix, 2026-11-21), else none.
  static RendelSuggestionCard? cardFor(String suggestion) {
    final own = suggestionCards[suggestion];
    if (own != null) return own;
    final line = consoleLines[suggestion];
    return line == null ? null : RendelSuggestionCard(title: suggestion, line: line);
  }
}

/// Whether the theme draws light on dark.
bool _darkOf(RendelTheme theme) => theme.colors.onSurface.computeLuminance() > theme.colors.surface.computeLuminance();

/// A · frosted glass as in Tuna's reference (Bevel), kept minimal: a flat,
/// see-through white over a blur of what is behind, one thin grey line
/// round it and barely a shadow.
class LabGlass extends StatelessWidget {
  const LabGlass({super.key, required this.child, this.radius = 22, this.circle = false, this.width, this.height, this.padding, this.constraints, this.alignment});
  final Widget child;
  final double radius;
  final bool circle;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final AlignmentGeometry? alignment;

  /// The glass's tint where nothing is blurred, and its line.
  static Color fillOf(RendelTheme theme) => _darkOf(theme) ? const Color(0x1AFFFFFF) : const Color(0x9EFFFFFF);
  static Color lineOf(RendelTheme theme) => _darkOf(theme) ? const Color(0x1FFFFFFF) : const Color(0x14000000);

  /// The same glass as a plain decoration, for a card drawn on the page
  /// itself, where there is nothing to blur but the page's own ground.
  static BoxDecoration decorationOf(RendelTheme theme, double radius) => BoxDecoration(
        color: fillOf(theme),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: lineOf(theme), width: 0.8),
        boxShadow: _darkOf(theme) ? const [BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 4), spreadRadius: -6)] : shadow,
      );

  static const shadow = [BoxShadow(color: Color(0x0D000000), blurRadius: 14, offset: Offset(0, 4), spreadRadius: -6)];

  /// The glass's light, our own shader (shaders/lab_glass.frag), loaded once.
  static FragmentProgram? _program;
  static final ValueNotifier<bool> _ready = ValueNotifier(false);
  static bool _loading = false;

  static void _load() {
    if (_loading) return;
    _loading = true;
    FragmentProgram.fromAsset('packages/rendel/shaders/lab_glass.frag').then((p) {
      _program = p;
      _ready.value = true;
    }, onError: (Object _) {});
  }

  /// What is behind, frosted and a touch more saturated, as glass makes it.
  static final ImageFilter _frost = ImageFilter.compose(
    outer: const ColorFilter.matrix(<double>[
      1.1575, -0.1430, -0.0144, 0, 0, //
      -0.0425, 1.0570, -0.0144, 0, 0, //
      -0.0425, -0.1430, 1.1856, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
    inner: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
  );

  @override
  Widget build(BuildContext context) {
    _load();
    final theme = RendelThemeScope.of(context);
    final dark = _darkOf(theme);
    final shape = circle ? null : BorderRadius.circular(radius);
    // While it fades or moves, no blur: a blur under a changing opacity is
    // worked out again on every frame in a layer of its own, and that is
    // what made + hitch. Back to frosted the moment it stands still.
    final still = !LabMoving.of(context);
    final glass = BackdropFilter(
      filter: still ? _frost : ImageFilter.blur(),
      enabled: still,
      child: Container(
        width: width,
        height: height,
        constraints: constraints,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: switch ((still, dark)) {
              (true, false) => const [Color(0x8AFFFFFF), Color(0x6BFFFFFF)],
              (false, false) => const [Color(0xD9FFFFFF), Color(0xC7FFFFFF)],
              (true, true) => const [Color(0x1AFFFFFF), Color(0x0FFFFFFF)],
              (false, true) => const [Color(0x2EFFFFFF), Color(0x24FFFFFF)],
            },
          ),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: shape,
          border: Border.all(color: lineOf(theme), width: 0.8),
        ),
        // The light lies on the glass and under what is on it, in the glass's own
        // coordinates: nothing about where it is on screen.
        child: CustomPaint(
          painter: _GlassLight(radius: circle ? 9999 : radius, strength: dark ? 0.55 : 1),
          child: Container(padding: padding, alignment: alignment, child: child),
        ),
      ),
    );
    // The shadow only outside the glass: under see-through glass a box shadow
    // shows as a grey smudge in the middle.
    return CustomPaint(
      painter: _OutsideShadow(radius: circle ? 9999 : radius, color: dark ? const Color(0x59000000) : const Color(0x14000000)),
      child: circle ? ClipOval(child: glass) : ClipRRect(borderRadius: shape!, child: glass),
    );
  }
}

class _OutsideShadow extends CustomPainter {
  const _OutsideShadow({required this.radius, required this.color});
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final r = math.min(radius, size.shortestSide / 2);
    final body = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect((Offset.zero & size).inflate(40)), Path()..addRRect(body)));
    canvas.drawRRect(
      body.shift(const Offset(0, 4)).deflate(2),
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OutsideShadow old) => old.radius != radius || old.color != color;
}

class _GlassLight extends CustomPainter {
  _GlassLight({required this.radius, required this.strength}) : super(repaint: LabGlass._ready);
  final double radius;
  final double strength;
  FragmentShader? _shader;

  @override
  void paint(Canvas canvas, Size size) {
    final program = LabGlass._program;
    if (program == null || size.isEmpty) return;
    final shader = _shader ??= program.fragmentShader();
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, radius)
      ..setFloat(3, strength);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GlassLight old) => old.radius != radius || old.strength != strength;
}

/// A · the ground's light: the app's two colours as pale pastels, one from
/// each side, meeting softly. Full on the opening, [faint] on a page.
class LabWash extends StatelessWidget {
  const LabWash({super.key, required this.ground, required this.accent, this.faint = false});
  final Color ground;
  final Color accent;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    // The console's ground light (Appearance › Ground): its colours over the
    // host's own, and how strongly — off is the plain ground, soft half of
    // it, strong a deeper pastel of the same hue.
    final published = theme.groundLight;
    final strength = published?.strength ?? RendelGroundStrength.normal;
    if (strength == RendelGroundStrength.off) return const SizedBox.shrink();
    final strong = strength == RendelGroundStrength.strong;
    final (left, right) = published?.colors ?? RendelLook.groundLight ?? (accent, accent);
    final dark = _darkOf(theme);
    final lightness = dark ? (strong ? 0.34 : 0.26) : (strong ? 0.76 : 0.84);
    Color pastel(Color c) {
      final hsl = HSLColor.fromColor(c);
      return hsl.withLightness(lightness).withSaturation(hsl.saturation.clamp(0.4, 0.7)).toColor();
    }

    final l = pastel(left), r = pastel(right);
    // On a dark ground the same light reads twice as strong: half of it.
    final k = (faint ? 0.45 : 1.0) * (dark ? 0.5 : 1.0) * (strength == RendelGroundStrength.soft ? 0.5 : 1.0);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.lerp(ground, l, 0.6 * k)!,
              Color.lerp(ground, l, 0.3 * k)!,
              Color.lerp(ground, Color.lerp(l, r, 0.5)!, 0.18 * k)!,
              Color.lerp(ground, r, 0.3 * k)!,
              Color.lerp(ground, r, 0.6 * k)!,
            ],
            stops: const [0, 0.25, 0.5, 0.75, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [ground.withValues(alpha: 0.55), ground.withValues(alpha: 0), ground.withValues(alpha: 0), ground.withValues(alpha: 0.45)],
              stops: const [0, 0.22, 0.8, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// A suggestion as a card on the opening: the same three fields as the web
/// SDK's `suggestionCards`.
class RendelSuggestionCard {
  const RendelSuggestionCard({required this.title, this.line, this.image});

  /// At most 40 characters.
  final String title;

  /// The line under the title, at most 60.
  final String? line;

  /// An asset path, or an https URL.
  final String? image;
}

/// Set over glass that is fading or moving: it is drawn without its blur
/// until it stands still (`motion=full` in the lab keeps the blur, to
/// measure one against the other).
class LabMoving extends InheritedWidget {
  const LabMoving({super.key, required this.moving, required super.child});
  final bool moving;

  static bool of(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<LabMoving>()?.moving ?? false) && RendelLab.of('motion') != 'full';

  @override
  bool updateShouldNotify(LabMoving oldWidget) => oldWidget.moving != moving;
}

/// A fade in place that tells the glass under it while it runs.
class LabFade extends StatefulWidget {
  const LabFade({super.key, required this.visible, required this.child, this.duration = const Duration(milliseconds: 160), this.onHidden});
  final bool visible;
  final Widget child;
  final Duration duration;
  final VoidCallback? onHidden;

  @override
  State<LabFade> createState() => _LabFadeState();
}

class _LabFadeState extends State<LabFade> {
  bool _moving = false;

  @override
  void didUpdateWidget(LabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _moving = true;
  }

  @override
  Widget build(BuildContext context) => LabMoving(
        moving: _moving || !widget.visible,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1 : 0,
          duration: widget.duration,
          onEnd: () {
            if (!mounted) return;
            setState(() => _moving = false);
            if (!widget.visible) widget.onHidden?.call();
          },
          child: widget.child,
        ),
      );
}

/// A · how a control arrives, as the SDK's own composer does: a fade, a
/// short rise and a slight grow from [alignment].
class LabArrive extends StatefulWidget {
  const LabArrive({super.key, required this.child, this.alignment = Alignment.bottomCenter});
  final Widget child;
  final Alignment alignment;

  @override
  State<LabArrive> createState() => _LabArriveState();
}

class _LabArriveState extends State<LabArrive> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late final CurvedAnimation _curve = CurvedAnimation(parent: _controller, curve: rendelEase);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller.duration = RendelThemeScope.of(context).motion.settle;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curve,
        alwaysIncludeSemantics: true,
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, child) => LabMoving(
            moving: _controller.value < 1,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - _curve.value)),
              child: Transform.scale(scale: 0.96 + 0.04 * _curve.value, alignment: widget.alignment, child: child),
            ),
          ),
          child: widget.child,
        ),
      );
}

/// A · a menu that opens over [child] (the message card), anchored at its
/// lower left, in the overlay: nothing under it moves as it opens or closes.
/// While it is open the card under it is hidden but keeps its place. Taps on
/// the menu count as inside [groupId]'s tap region.
class LabPopover extends StatefulWidget {
  const LabPopover({super.key, required this.open, required this.popover, required this.groupId, required this.child});
  final bool open;
  final Widget popover;
  final Object groupId;
  final Widget child;

  /// Whether a menu is open: what sits under it (the suggestion cards) steps
  /// back meanwhile, keeping its place.
  static final ValueNotifier<bool> anyOpen = ValueNotifier(false);

  @override
  State<LabPopover> createState() => _LabPopoverState();
}

class _LabPopoverState extends State<LabPopover> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  /// Still drawn while it fades out after closing, so nothing blinks.
  late bool _drawn = widget.open;

  @override
  void didUpdateWidget(LabPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open) _drawn = true;
    // After the frame: a notifier set while building would rebuild its listeners mid-build.
    if (oldWidget.open != widget.open) {
      final open = widget.open;
      WidgetsBinding.instance.addPostFrameCallback((_) => LabPopover.anyOpen.value = open);
    }
  }

  @override
  void dispose() {
    if (widget.open) WidgetsBinding.instance.addPostFrameCallback((_) => LabPopover.anyOpen.value = false);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_portal.isShowing) _portal.show();
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (context) => !_drawn
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.topLeft,
                    child: CompositedTransformFollower(
                      link: _link,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.bottomLeft,
                      followerAnchor: Alignment.bottomLeft,
                      child: IgnorePointer(
                        ignoring: !widget.open,
                        child: LabFade(
                          visible: widget.open,
                          onHidden: () {
                            if (!widget.open && mounted) setState(() => _drawn = false);
                          },
                          child: TapRegion(
                            groupId: widget.groupId,
                            child: SizedBox(width: constraints.maxWidth, child: widget.popover),
                          ),
                        ),
                      ),
                    ),
                  ),
            child: IgnorePointer(
              ignoring: widget.open,
              child: LabFade(
                visible: !widget.open,
                duration: const Duration(milliseconds: 120),
                child: widget.child,
              ),
            ),
          ),
        ),
      );
}
