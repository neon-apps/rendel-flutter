import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/strings.dart';
import 'lab/lab.dart' show RendelLook;
import 'theme.dart';

/// Voice mode as a ring that listens (Tuna 2026-11-22, the lab at
/// /lab/voice-ring; every app's from 2026-11-23). It takes the place of the
/// sphere while the microphone is held.
///
/// Drawn as the lab draws it (RingVoice.tsx), second pass 2026-11-23 (Tuna:
/// "labdaki gibi"): 96 ticks over the app's ground, the ring's colours faint
/// across the screen as loud as the voice is; under it "Listening" with its
/// live light, and the words, large, as they are heard. The composer stays,
/// dimmed, its microphone wearing the ring's colours, turning. Let go, the
/// ring shrinks where it is with a light running round it, then flies into
/// the turn's pill, where a small ring of the same ticks goes on working
/// ([RingSpot]); while the answer is read aloud a small ring moves with the
/// voice over the composer ([RingReading]).
class RingVoiceMode extends StatefulWidget {
  const RingVoiceMode({
    super.key,
    required this.heard,
    required this.sent,
    required this.leaving,
    required this.falls,
    required this.listening,
    required this.level,
    required this.onCancel,
    this.onStop,
    this.wide = false,
  });

  /// How long it stays after it is sent or let go, for the ring to land.
  static const leave = Duration(milliseconds: 720);

  final String heard;
  final ValueListenable<bool> sent;
  final ValueListenable<bool> leaving;
  final ValueListenable<bool> falls;
  final bool listening;
  final ValueListenable<double>? level;
  final VoidCallback onCancel;

  /// Stops listening and sends what was heard; null when the recogniser
  /// cannot be stopped. The microphone's place takes it while the ring
  /// listens, for a screen reader, which opens voice mode with a tap and
  /// cannot hold: its way to send, as the sphere's stop pill was.
  final VoidCallback? onStop;

  /// The microphone is the wide pill in the composer's middle (voice first).
  final bool wide;

  @override
  State<RingVoiceMode> createState() => _RingVoiceModeState();
}

/// Where the turn's pill draws its small ring, in global coordinates, for the
/// big one to fly into. Null when no pill is up.
final ringLanding = ValueNotifier<Rect?>(null);

/// True while the big ring is flying into the pill: the pill's own small
/// ring waits, so there are never two.
final ringFlying = ValueNotifier<bool>(false);

enum _Phase { listening, leaving, sent, falls }

class _Ring {
  const _Ring(
    this.cx,
    this.cy,
    this.r,
    this.w,
    this.reach,
    this.mini,
    this.alpha,
  );
  final double cx, cy, r, w, reach, mini, alpha;

  _Ring at(Offset c, {double? alpha}) =>
      _Ring(c.dx, c.dy, r, w, reach, mini, alpha ?? this.alpha);

  static _Ring lerp(_Ring a, _Ring b, double m) => _Ring(
    _mix(a.cx, b.cx, m),
    _mix(a.cy, b.cy, m),
    _mix(a.r, b.r, m),
    _mix(a.w, b.w, m),
    _mix(a.reach, b.reach, m),
    _mix(a.mini, b.mini, m),
    _mix(a.alpha, b.alpha, m),
  );
}

double _mix(double a, double b, double k) => a + (b - a) * k;

const _big = _Ring(0, 0, 74, 2.1, 44, 0, 1);
const _small = _Ring(0, 0, 7.5, 1.7, 4.5, 1, 1);
const _ticks = 96;
const _moveMs = 620.0;
const _tau = math.pi * 2;

/// Each tick its own small offset, so the ring's edge is never a clean curve.
final _jitter = List.generate(
  _ticks,
  (i) => 0.75 + 0.25 * math.sin(i * 12.9898) * math.sin(i * 78.233),
);

class _RingVoiceModeState extends State<RingVoiceMode>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;

  /// Milliseconds since it opened.
  double now = 0;

  /// The voice's loudness, eased so the ring does not flicker.
  double level = 0;

  /// Its entrance, 0 to 1.
  double born = 0;

  /// The ground's glow going, 0 to 1, once it is let go.
  double dimmed = 0;

  /// The ground itself going, 0 to 1, once the question is sent.
  double cleared = 0;
  bool still = false;

  _Phase _phase = _Phase.listening;

  /// How far it has flown into the turn's pill, 0 to 1: its colours turn to
  /// the pill's ink (white on Grove's green) as it lands.
  double landed = 0;
  _Ring? ring;
  _Ring? _from;
  double _moveStart = 0;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    widget.sent.addListener(_go);
    widget.leaving.addListener(_go);
    widget.falls.addListener(_go);
    _go();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    still = MediaQuery.disableAnimationsOf(context);
  }

  void _go() {
    // Once it falls or is sent it only goes: the next press has its own.
    if (_phase == _Phase.falls || _phase == _Phase.sent) return;
    final next =
        widget.sent.value
            ? _Phase.sent
            : widget.falls.value
            ? _Phase.falls
            : widget.leaving.value
            ? _Phase.leaving
            : _Phase.listening;
    if (next == _phase) return;
    _phase = next;
    _from = ring;
    _moveStart = now;
    if (next == _Phase.sent) ringFlying.value = true;
  }

  Offset get _anchor => Offset(_size.width / 2, _size.height * 0.28);

  _Ring _goal() {
    switch (_phase) {
      case _Phase.listening:
        return _big.at(_anchor);
      case _Phase.leaving:
        // Let go, it first shrinks where it is, with a light running round it.
        return _small.at(_anchor);
      case _Phase.sent:
        // Then it flies into the turn's pill.
        final spot = ringLanding.value;
        final box = context.findRenderObject() as RenderBox?;
        if (spot == null || box == null || !box.hasSize) {
          return _small.at(_anchor, alpha: 0);
        }
        return _small.at(box.globalToLocal(spot.center));
      case _Phase.falls:
        return (ring ?? _big.at(_anchor)).at(
          Offset(ring?.cx ?? _anchor.dx, ring?.cy ?? _anchor.dy),
          alpha: 0,
        );
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    now = elapsed.inMicroseconds / 1e3;
    final raw =
        widget.listening && _phase == _Phase.listening
            ? (widget.level?.value ?? 0)
            : 0.0;
    level += (raw - level) * (1 - math.exp(-dt * 14));
    // A quick tap shows no ring: it comes in once the press has lasted a moment.
    if (now > 120 || still) born = still ? 1 : math.min(1, born + dt / 0.3);
    if (_phase != _Phase.listening) {
      dimmed = still ? 1 : math.min(1, dimmed + dt / 0.6);
    }
    if (_phase == _Phase.sent) {
      cleared = still ? 1 : math.min(1, cleared + dt / 0.45);
    }
    if (_size != Size.zero) {
      final goal = _goal();
      final from = _from;
      final m =
          still || from == null
              ? 1.0
              : Curves.easeInOutCubic.transform(
                math.min(1, (now - _moveStart) / _moveMs),
              );
      ring = from == null ? goal : _Ring.lerp(from, goal, m);
      landed = _phase == _Phase.sent ? m : 0;
      // Landed: the pill's own ring takes over.
      if (_phase == _Phase.sent && m >= 1) {
        ringFlying.value = false;
        ring = goal.at(Offset(goal.cx, goal.cy), alpha: 0);
      }
    }
    _frame.value++;
  }

  @override
  void dispose() {
    ringFlying.value = false;
    widget.sent.removeListener(_go);
    widget.leaving.removeListener(_go);
    widget.falls.removeListener(_go);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final colors = theme.colors;
    final strings = RendelStringsScope.of(context);
    final dark = colors.surface.computeLuminance() < 0.4;
    final palette = RingPalette.ground(theme);
    final words =
        widget.heard.trim().isEmpty
            ? const <String>[]
            : widget.heard.trim().split(RegExp(r'\s+'));
    final base = DefaultTextStyle.of(context).style;

    return ValueListenableBuilder<bool>(
      valueListenable: widget.sent,
      builder:
          (context, sent, _) => IgnorePointer(
            ignoring: sent,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // A tap away from it while it listens: nothing is sent.
              onTap: widget.onCancel,
              child: LayoutBuilder(
                builder: (context, box) {
                  _size = box.biggest;
                  final centre = _anchor;
                  return AnimatedBuilder(
                    animation: _frame,
                    builder: (context, _) {
                      final shown = Curves.easeOut.transform(born);
                      // The ground goes as the ring lands; a cancel takes it all at once.
                      final ground =
                          shown *
                          (_phase == _Phase.falls ? (1 - dimmed) : 1) *
                          (1 - Curves.easeIn.transform(cleared));
                      final up = _phase == _Phase.listening;
                      // Let go, the words stay while the last of them are made out.
                      final said = up || _phase == _Phase.leaving;
                      return Stack(
                        children: [
                          // The app's ground over the conversation, the ring's
                          // colours faint across it, brighter as the voice is louder.
                          Positioned.fill(
                            child: Opacity(
                              opacity: ground.clamp(0.0, 1.0),
                              child: ClipRect(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 22,
                                    sigmaY: 22,
                                  ),
                                  child: ColoredBox(
                                    color: colors.surface.withValues(
                                      alpha: 0.97,
                                    ),
                                    child: CustomPaint(
                                      painter: _GlowPainter(
                                        palette: palette,
                                        centre: centre,
                                        opacity:
                                            (0.55 +
                                                0.45 * (0.14 + 0.86 * level)) *
                                            (1 - dimmed),
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RingPainter(
                                this,
                                palette,
                                colors.onAccent,
                              ),
                            ),
                          ),
                          // "Listening", with its live light, once the microphone
                          // is open: not before, behind a permission prompt.
                          if (widget.listening && !sent)
                            Positioned(
                              top: centre.dy + 150,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Opacity(
                                  opacity: up ? shown : 0,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: still ? 1 : 0, end: 1),
                                    duration: const Duration(milliseconds: 350),
                                    curve: const Cubic(0.2, 0, 0, 1),
                                    builder:
                                        (context, k, child) => Opacity(
                                          opacity: k,
                                          child: Transform.translate(
                                            offset: Offset(0, 4 * (1 - k)),
                                            child: child,
                                          ),
                                        ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 13,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.surfaceRaised.withValues(
                                          alpha: 0.82,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        boxShadow:
                                            dark
                                                ? null
                                                : const [
                                                  BoxShadow(
                                                    color: Color(0x0F281E14),
                                                    offset: Offset(0, 1),
                                                    blurRadius: 2,
                                                  ),
                                                  BoxShadow(
                                                    color: Color(0x0F281E14),
                                                    offset: Offset(0, 6),
                                                    blurRadius: 18,
                                                  ),
                                                ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _LiveLight(still: still),
                                          const SizedBox(width: 7),
                                          Text(
                                            strings.listening,
                                            style: base.copyWith(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: colors.onSurface
                                                  .withValues(alpha: 0.72),
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // The words, large, as they are heard; gone the moment
                          // the question is written in their place.
                          // The microphone's place, under the composer's own (which
                          // lets taps through while the ring listens): a tap there
                          // stops listening and sends, and a screen reader finds
                          // it by name. Let go with words, it says the turn thinks.
                          if (!sent)
                            Positioned(
                              left:
                                  widget.wide
                                      ? box.maxWidth / 2 - 64
                                      : (Directionality.of(context) ==
                                              TextDirection.rtl
                                          ? 13
                                          : box.maxWidth - 61),
                              width: widget.wide ? 128 : 48,
                              bottom:
                                  math.max(
                                    MediaQuery.paddingOf(context).bottom,
                                    18,
                                  ) +
                                  6,
                              height: 48,
                              child:
                                  _phase == _Phase.leaving
                                      ? Semantics(
                                        liveRegion: true,
                                        label: strings.statusThinking,
                                        child: const SizedBox.expand(),
                                      )
                                      : Semantics(
                                        button: true,
                                        enabled: widget.onStop != null,
                                        label: strings.stopListening,
                                        onTap: widget.onStop,
                                        excludeSemantics: true,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          excludeFromSemantics: true,
                                          // Taken here, never by the ground's cancel.
                                          onTap: widget.onStop ?? () {},
                                        ),
                                      ),
                            ),
                          if (!sent)
                            Positioned(
                              top: centre.dy + 206,
                              left: 30,
                              right: 30,
                              child: Opacity(
                                opacity: said ? shown : 0,
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 7,
                                  runSpacing: 0,
                                  children: [
                                    for (var i = 0; i < words.length; i++)
                                      _Word(
                                        key: ValueKey(i),
                                        text: words[i],
                                        last: i == words.length - 1,
                                        style: base.copyWith(
                                          fontSize: 27,
                                          fontWeight: FontWeight.w500,
                                          height: 1.28,
                                          letterSpacing: -0.54,
                                          decoration: TextDecoration.none,
                                        ),
                                        ink: colors.onSurface,
                                        still: still,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
    );
  }
}

/// The microphone is open: a live light, the one dot on the screen, a pulse
/// going out of it.
class _LiveLight extends StatefulWidget {
  const _LiveLight({required this.still});
  final bool still;

  @override
  State<_LiveLight> createState() => _LiveLightState();
}

class _LiveLightState extends State<_LiveLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.still) _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3DDC84);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final k = math.min(1.0, _pulse.value / 0.7);
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: green,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: green.withValues(alpha: 0.5 * (1 - k)),
                spreadRadius: 6 * k,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One heard word: it comes in from a blur, and greys once the next arrives.
class _Word extends StatelessWidget {
  const _Word({
    super.key,
    required this.text,
    required this.last,
    required this.style,
    required this.ink,
    required this.still,
  });

  final String text;
  final bool last;
  final TextStyle style;
  final Color ink;
  final bool still;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: const Cubic(0.2, 0, 0, 1),
      builder:
          (context, k, child) => Opacity(
            opacity: k,
            child: Transform.translate(
              offset: Offset(0, 6 * (1 - k)),
              child:
                  k >= 1
                      ? child
                      : ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: 8 * (1 - k),
                          sigmaY: 8 * (1 - k),
                        ),
                        child: child,
                      ),
            ),
          ),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 450),
        style: style.copyWith(color: last ? ink : ink.withValues(alpha: 0.46)),
        child: Text(text),
      ),
    );
  }
}

// The ring's colours, as the lab makes them.

double _toLinear(int c) {
  final v = c / 255;
  return v <= 0.04045
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

int _toByte(double c) {
  final v = c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  return (v.clamp(0.0, 1.0) * 255).round();
}

double _cbrt(double x) =>
    x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

/// The colour's hue and chroma (OKLCH).
({double h, double c}) _hueChroma(List<int> rgb) {
  final r = _toLinear(rgb[0]), g = _toLinear(rgb[1]), b = _toLinear(rgb[2]);
  final l1 = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m1 = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s1 = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  final a = 1.9779984951 * l1 - 2.428592205 * m1 + 0.4505937099 * s1;
  final bb = 0.0259040371 * l1 + 0.7827717662 * m1 - 0.808675766 * s1;
  return (h: math.atan2(bb, a), c: math.sqrt(a * a + bb * bb));
}

/// The colour's hue at lightness [l] and chroma enough to read on its
/// ground (OKLCH), as the lab's `vivid`; [turn] moves the hue, in radians.
List<int> _vivid(List<int> rgb, double l, {double turn = 0}) {
  final hc = _hueChroma(rgb);
  final c = math.max(hc.c * 2, 0.13);
  final h = hc.h + turn;
  final a2 = c * math.cos(h), b2 = c * math.sin(h);
  final l3 = math.pow(l + 0.3963377774 * a2 + 0.2158037573 * b2, 3).toDouble();
  final m3 = math.pow(l - 0.1055613458 * a2 - 0.0638541728 * b2, 3).toDouble();
  final s3 = math.pow(l - 0.0894841775 * a2 - 1.291485548 * b2, 3).toDouble();
  return [
    _toByte(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
    _toByte(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
    _toByte(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.707614701 * s3),
  ];
}

/// 360 colours round the ring, blending the stops in a loop.
List<Color> _wheel(List<List<int>> stops) => List.generate(360, (i) {
  final p = i / 360 * stops.length;
  final a = stops[p.floor() % stops.length];
  final b = stops[(p.floor() + 1) % stops.length];
  final k = (1 - math.cos((p % 1) * math.pi)) / 2;
  return Color.fromARGB(
    255,
    _mix(a[0] * 1.0, b[0] * 1.0, k).round(),
    _mix(a[1] * 1.0, b[1] * 1.0, k).round(),
    _mix(a[2] * 1.0, b[2] * 1.0, k).round(),
  );
});

List<int> _rgb(Color c) => [
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
];

/// The voice ring's presets, as the protocol's `VOICE_RING_PRESETS` has them
/// (a test holds the two together). "mono" is the page's ink.
const ringPresets = <String, List<int>>{
  'spectrum': [0xFF4FE3D6, 0xFF5AA8FF, 0xFF9B7BFF, 0xFFFF6FAE],
  'ocean': [0xFF2DD4BF, 0xFF38BDF8, 0xFF3B82F6, 0xFF6366F1],
  'sunset': [0xFFFDBA74, 0xFFFB7185, 0xFFF472B6, 0xFFC084FC],
  'forest': [0xFFA3E635, 0xFF4ADE80, 0xFF10B981, 0xFF14B8A6],
  'ember': [0xFFFDE047, 0xFFFB923C, 0xFFF43F5E, 0xFFE11D48],
};

/// The ring's colours round it (Tuna 2026-11-23: in the app's own colours,
/// with presets and a pick of its own in Appearance), as the lab's "lights"
/// and "accent" choices make them. `theme.voiceRing`'s colours win; else its
/// preset; else the app's own: the ground light's two (the console's, or the
/// host's own pair), else the accent's hue a little either side of itself
/// (Grove's green runs from lime through leaf to sea green). An accent with
/// no hue (black, white, grey) takes the spectrum. "mono" is the page's ink.
///
/// Each ground makes its own legible shade: a preset is drawn as it is on a
/// dark ground and deepened on a light one; the app's colours are brought to
/// the ground's lightness either way. Mirrors the web SDK's palette.
class RingPalette {
  RingPalette._(this._colours);

  final List<Color> _colours;

  /// Its colour [k] of the way round (0 to 1).
  Color at(double k) => _colours[(((k % 1) + 1) % 1 * 360).floor() % 360];

  static final _cache = <String, RingPalette>{};

  /// One colour all the way round.
  static RingPalette solid(Color colour) =>
      _cache['solid-${colour.toARGB32()}'] ??= RingPalette._(
        List.filled(360, colour),
      );

  /// For [theme] on its own ground.
  static RingPalette ground(RendelTheme theme) {
    final dark = theme.colors.surface.computeLuminance() < 0.4;
    final l = dark ? 0.8 : 0.62;
    final ring = theme.voiceRing;
    final custom = ring?.colors;
    if (custom != null && custom.length >= 2) {
      return _keep(
        'custom-${custom.map((c) => c.toARGB32()).join('-')}-$l',
        () => [for (final c in custom) _vivid(_rgb(c), l)],
      );
    }
    final preset = ring?.preset;
    if (preset == 'mono') return solid(theme.colors.onSurface);
    final table = ringPresets[preset];
    if (table != null) return _preset(preset!, table, dark);
    final lights = theme.groundLight?.colors ?? RendelLook.groundLight;
    if (lights != null) {
      return _keep(
        'lights-${lights.$1.toARGB32()}-${lights.$2.toARGB32()}-$l',
        () => [_vivid(_rgb(lights.$1), l), _vivid(_rgb(lights.$2), l)],
      );
    }
    final rgb = _rgb(theme.colors.accent);
    if (_hueChroma(rgb).c < 0.03) {
      return _preset('spectrum', ringPresets['spectrum']!, dark);
    }
    return _keep(
      'accent-${theme.colors.accent.toARGB32()}-$l',
      () => [
        _vivid(rgb, l, turn: -0.5),
        _vivid(rgb, l),
        _vivid(rgb, l, turn: 0.5),
        _vivid(rgb, l),
      ],
    );
  }

  static RingPalette _preset(String name, List<int> table, bool dark) => _keep(
    'preset-$name-$dark',
    () => [
      for (final c in table)
        dark ? _rgb(Color(c)) : _vivid(_rgb(Color(c)), 0.62),
    ],
  );

  static RingPalette _keep(String key, List<List<int>> Function() stops) =>
      _cache[key] ??= RingPalette._(_wheel(stops()));
}

/// The colours turn slowly, in radians: a full turn in about 39 seconds, as
/// the lab and the web SDK turn them.
double _turn(double ms) => ms * 0.00016;

/// The lab's three soft lights behind the ring, in its colours.
class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.palette,
    required this.centre,
    required this.opacity,
  });

  final RingPalette palette;
  final Offset centre;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;
    final k = size.width / 402;
    final rect = Offset.zero & size;
    void light(Offset at, double radius, Color colour, double alpha) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(
              (at.dx / size.width) * 2 - 1,
              (at.dy / size.height) * 2 - 1,
            ),
            radius: radius / size.shortestSide,
            colors: [
              colour.withValues(alpha: alpha * opacity),
              colour.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    light(
      Offset(size.width * 0.62, centre.dy - 20 * k),
      255 * k,
      palette.at(0.1),
      0.14,
    );
    light(
      Offset(size.width * 0.38, centre.dy + 50 * k),
      243 * k,
      palette.at(0.75),
      0.12,
    );
    // The lab's wide ellipse, as a wide circle.
    light(
      Offset(size.width * 0.5, centre.dy + 10 * k),
      400 * k,
      palette.at(0.45),
      0.08,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.opacity != opacity || old.palette != palette || old.centre != centre;
}

/// How loud a voice reading aloud is at [ms]: a syllable about every 210 ms,
/// unevenly loud, as the lab plays it.
double _reading(double ms) {
  var e = 0.0;
  final at0 = (ms / 210).floor();
  for (var i = at0 - 2; i <= at0 + 1; i++) {
    final at = i * 210 + ((i * 37) % 60).abs();
    final d = ms - at;
    if (d > -120 && d < 420) {
      e = math.max(e, math.exp(-math.pow(d - 70, 2) / (2 * 105 * 105)));
    }
  }
  return e;
}

/// The lab's ticks, drawn round [ring] at [ms].
void _paintTicks(
  Canvas canvas,
  _Ring ring,
  double ms, {
  required RingPalette palette,
  required bool still,
  required String mode,
  double level = 0,
  Color? tint,
  double tintK = 0,
}) {
  if (ring.alpha < 0.01) return;
  final turn = still ? 0.0 : _turn(ms);
  Color colour(double a) {
    final c = palette.at((a + turn) / _tau);
    return tint == null || tintK <= 0 ? c : Color.lerp(c, tint, tintK)!;
  }

  final glow = Paint()..strokeCap = StrokeCap.round;
  final line = Paint()..strokeCap = StrokeCap.round;
  final dot = Paint();
  final centre = Offset(ring.cx, ring.cy);

  // Depth, while it is large: a faint row of dots inside and a fainter one outside.
  final depth = (1 - ring.mini) * ring.alpha;
  if (depth > 0.02) {
    for (var i = 0; i < _ticks; i += 2) {
      final a = i / _ticks * _tau - math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      dot.color = colour(a).withValues(alpha: 0.2 * depth);
      canvas.drawCircle(centre + dir * (ring.r - 14), 0.9, dot);
      dot.color = colour(a).withValues(alpha: 0.09 * depth);
      canvas.drawCircle(centre + dir * (ring.r + ring.reach + 16), 0.8, dot);
    }
  }

  for (var i = 0; i < _ticks; i++) {
    // Small, every fourth tick: 96 would run together into a line.
    final shown = i % 4 == 0 ? 1.0 : 1 - ring.mini;
    if (shown * ring.alpha < 0.01) continue;
    final a = i / _ticks * _tau - math.pi / 2;
    // Neighbouring ticks move together: slow waves round the ring.
    final wave =
        still
            ? 0.6
            : 0.5 +
                0.5 *
                    (0.45 * math.sin(a * 3 + ms * 0.0042) +
                        0.3 * math.sin(a * 5 - ms * 0.0063) +
                        0.25 *
                            math.sin(
                              a * 2 + ms * 0.0021 + math.sin(ms * 0.0011),
                            ));
    double len;
    double lit;
    if (mode == 'working') {
      // Working: a light runs round the ring.
      final b = math.pow(math.max(0, math.cos(a - ms * 0.0075)), 4).toDouble();
      len = 1.5 + ring.reach * (0.3 + 0.7 * b);
      lit = 0.22 + 0.78 * b;
    } else if (mode == 'reading') {
      final e = 0.15 + 0.85 * (still ? 0.4 : _reading(ms));
      len = 1.5 + ring.reach * e * (0.4 + 0.6 * wave);
      lit = 0.35 + 0.65 * e;
    } else if (mode == 'listening') {
      final e = still ? 0.35 : level * (0.2 + 0.8 * wave) * _jitter[i];
      len = 5 + ring.reach * e;
      lit = 0.4 + 0.6 * math.min(1, e * 1.8);
    } else {
      // Before the microphone opens: short, dim ticks, a band of colour turning round them.
      final band = still ? 0.5 : 0.5 + 0.5 * math.sin(a * 2 - ms * 0.0009);
      len = 5 + 3 * wave * _jitter[i];
      lit = 0.18 + 0.4 * band;
    }
    final inner = ring.mini > 0.5 ? 0.0 : len * 0.28;
    final dir = Offset(math.cos(a), math.sin(a));
    final p1 = centre + dir * (ring.r - inner);
    final p2 = centre + dir * (ring.r + len - inner);
    final c = colour(a);
    final alpha = (lit * shown * ring.alpha).clamp(0.0, 1.0);
    // A soft glow under each lit tick, then the tick itself.
    if (alpha > 0.3 && ring.mini < 0.5) {
      glow
        ..color = c.withValues(alpha: alpha * 0.16)
        ..strokeWidth = ring.w * 3.6;
      canvas.drawLine(p1, p2, glow);
    }
    line
      ..color = c.withValues(alpha: alpha)
      ..strokeWidth = ring.w;
    canvas.drawLine(p1, p2, line);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.s, this.palette, this.ink);

  final _RingVoiceModeState s;
  final RingPalette palette;

  /// The pill's ink, which it turns to as it lands.
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = s.ring;
    if (ring == null) return;
    final shown = Curves.easeOut.transform(s.born);
    final mode = switch (s._phase) {
      _Phase.listening => s.widget.listening ? 'listening' : 'rest',
      _Phase.falls => s.widget.listening ? 'listening' : 'rest',
      _ => 'working',
    };
    _paintTicks(
      canvas,
      ring.at(Offset(ring.cx, ring.cy), alpha: ring.alpha * shown),
      s.still ? 0 : s.now,
      palette: palette,
      tint: ink,
      tintK: Curves.easeIn.transform(s.landed),
      still: s.still,
      mode: mode,
      level: 0.14 + 0.86 * s.level,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}

/// The small ring the big one lands as: in the turn's pill a light runs
/// round it ([reading] false); over the composer while an answer is read
/// aloud, it moves with the voice ([reading] true).
class RingSpot extends StatefulWidget {
  const RingSpot({
    super.key,
    this.solid,
    this.reading = false,
    this.landing = false,
  });

  /// Drawn in this one colour rather than the ring's: the pill's ink, on
  /// the turn's lit pill (Tuna 2026-11-23: white on Grove's green).
  final Color? solid;
  final bool reading;

  /// The big ring flies into this one: it says where it is, and waits.
  final bool landing;

  @override
  State<RingSpot> createState() => _RingSpotState();
}

class _RingSpotState extends State<RingSpot>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _ms = ValueNotifier<double>(0);
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _ms.value = elapsed.inMicroseconds / 1e3;
      if (widget.landing) _report();
    })..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
  }

  void _report() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (ringLanding.value != rect) ringLanding.value = rect;
  }

  @override
  void dispose() {
    if (widget.landing) ringLanding.value = null;
    _ticker.dispose();
    _ms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final solid = widget.solid;
    final palette =
        solid != null ? RingPalette.solid(solid) : RingPalette.ground(theme);
    final spot = SizedBox.square(
      dimension: 22,
      child: CustomPaint(
        painter: _SpotPainter(
          _ms,
          palette: palette,
          still: _still,
          reading: widget.reading,
        ),
      ),
    );
    if (!widget.landing) return spot;
    return ValueListenableBuilder<bool>(
      valueListenable: ringFlying,
      builder:
          (context, flying, child) =>
              Opacity(opacity: flying ? 0 : 1, child: child),
      child: spot,
    );
  }
}

class _SpotPainter extends CustomPainter {
  _SpotPainter(
    this.ms, {
    required this.palette,
    required this.still,
    required this.reading,
  }) : super(repaint: ms);

  final ValueListenable<double> ms;
  final RingPalette palette;
  final bool still;
  final bool reading;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    _paintTicks(
      canvas,
      _small.at(c),
      still ? 0 : ms.value,
      palette: palette,
      still: still,
      mode: reading ? 'reading' : 'working',
    );
  }

  @override
  bool shouldRepaint(_SpotPainter old) =>
      old.palette != palette || old.still != still || old.reading != reading;
}

/// Held, the microphone wears the ring's colours, turning, as loud as the
/// voice: a band round it, the middle cut away.
class RingMicHalo extends StatefulWidget {
  const RingMicHalo({
    super.key,
    required this.on,
    required this.level,
    this.hint,
    this.wide = false,
    required this.child,
  });

  final bool on;
  final ValueListenable<double>? level;

  /// Counts quick taps on the microphone: each one shows how it is used
  /// (Tuna 2026-11-23: a tap let go at once, people may not know to hold).
  /// The microphone presses in, a band of the ring's colours fills round it
  /// as if it were held, and a line over it says to hold it while speaking.
  final ValueListenable<int>? hint;

  /// The microphone is the wide pill (voice first): the line sits over its
  /// middle rather than its end.
  final bool wide;
  final Widget child;

  @override
  State<RingMicHalo> createState() => _RingMicHaloState();
}

class _RingMicHaloState extends State<RingMicHalo>
    with TickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );
  bool _still = false;

  @override
  void initState() {
    super.initState();
    widget.hint?.addListener(_teach);
  }

  @override
  void didUpdateWidget(RingMicHalo old) {
    super.didUpdateWidget(old);
    if (old.hint != widget.hint) {
      old.hint?.removeListener(_teach);
      widget.hint?.addListener(_teach);
    }
    _spin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _spin();
  }

  /// The band turns only while it is worn: a microphone at rest draws nothing
  /// and asks for no frames.
  void _spin() {
    if (_still || !widget.on) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  void _teach() {
    if (_still) {
      // Still: the line alone, for as long.
      _show.value = 0.3;
      Future<void>.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) _show.value = 0;
      });
      return;
    }
    _show.forward(from: 0);
  }

  @override
  void dispose() {
    widget.hint?.removeListener(_teach);
    _turn.dispose();
    _show.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final palette = RingPalette.ground(theme);
    final base = DefaultTextStyle.of(context).style;
    return AnimatedBuilder(
      animation: Listenable.merge([
        _turn,
        _show,
        if (widget.level != null) widget.level!,
      ]),
      builder: (context, child) {
        final t = _show.value;
        final teaching = _show.isAnimating || (t > 0 && t < 1);
        // Pressed in as a finger would, held while the band fills, let go.
        final press =
            !teaching || _still
                ? 1.0
                : t < 0.06
                ? _mix(1, 0.9, Curves.easeOut.transform(t / 0.06))
                : t < 0.42
                ? 0.9
                : t < 0.5
                ? _mix(0.9, 1, Curves.easeOutBack.transform((t - 0.42) / 0.08))
                : 1.0;
        final fill =
            teaching && !_still
                ? Curves.easeInOut.transform(
                  ((t - 0.04) / 0.38).clamp(0.0, 1.0),
                )
                : 0.0;
        final fillAlpha =
            !teaching || _still
                ? 0.0
                : (t < 0.5 ? 1.0 : (1 - (t - 0.5) / 0.12).clamp(0.0, 1.0));
        final lineAlpha =
            !teaching
                ? 0.0
                : (t < 0.1
                    ? t / 0.1
                    : t > 0.86
                    ? (1 - t) / 0.14
                    : 1.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.scale(
              scale: press,
              child: CustomPaint(
                foregroundPainter: _HaloPainter(
                  on: widget.on,
                  turn: _turn.value,
                  level: widget.on ? (widget.level?.value ?? 0) : 0,
                  palette: palette,
                  fill: fill,
                  fillAlpha: fillAlpha,
                ),
                child: child,
              ),
            ),
            if (lineAlpha > 0)
              Positioned(
                bottom: 58,
                right: widget.wide ? -120 : -2,
                left: widget.wide ? -120 : null,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: lineAlpha,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        6 *
                            (1 -
                                Curves.easeOut.transform(math.min(1, t / 0.1))),
                      ),
                      child: Align(
                        alignment:
                            widget.wide
                                ? Alignment.bottomCenter
                                : AlignmentDirectional.bottomEnd,
                        child: _HoldLine(
                          text: strings.holdToSpeak,
                          style: base.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: theme.colors.surface,
                            decoration: TextDecoration.none,
                          ),
                          ground: theme.colors.onSurface,
                          tailFromEnd: widget.wide ? null : 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// The line over the microphone saying to hold it, with a tail pointing at it.
class _HoldLine extends StatelessWidget {
  const _HoldLine({
    required this.text,
    required this.style,
    required this.ground,
    required this.tailFromEnd,
  });

  final String text;
  final TextStyle style;
  final Color ground;

  /// The tail's middle from the line's end; null, under its middle.
  final double? tailFromEnd;

  @override
  Widget build(BuildContext context) {
    final tail = CustomPaint(
      size: const Size(14, 7),
      painter: _TailPainter(ground),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            tailFromEnd == null
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: ground,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16000000),
                  offset: Offset(0, 4),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Text(text, style: style, textAlign: TextAlign.center),
          ),
          if (tailFromEnd case final end?)
            Padding(
              padding: EdgeInsetsDirectional.only(end: end - 7),
              child: tail,
            )
          else
            tail,
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.colour != colour;
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required this.on,
    required this.turn,
    required this.level,
    required this.palette,
    this.fill = 0,
    this.fillAlpha = 0,
  });

  final bool on;
  final double turn;
  final double level;
  final RingPalette palette;

  /// Teaching a quick tap: how much of the band has filled round it, and how
  /// strongly it is drawn.
  final double fill;
  final double fillAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (!on && fill > 0 && fillAlpha > 0) {
      final band = (Offset.zero & size).deflate(1).inflate(3.25);
      final rrect = RRect.fromRectAndRadius(
        band,
        Radius.circular(band.height / 2),
      );
      // From the top, clockwise.
      final path = Path()..addRRect(rrect);
      final metric = path.computeMetrics().first;
      final top = band.width / 2 - band.height / 2;
      final length = metric.length;
      final from = (top % length + length) % length;
      final drawn = length * fill;
      final trace =
          Path()..addPath(
            metric.extractPath(from, math.min(length, from + drawn)),
            Offset.zero,
          );
      if (from + drawn > length) {
        trace.addPath(
          metric.extractPath(0, from + drawn - length),
          Offset.zero,
        );
      }
      final colours = [
        palette.at(0.1),
        palette.at(0.45),
        palette.at(0.75),
        palette.at(0.1),
      ];
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = palette.at(0.45).withValues(alpha: 0.14 * fillAlpha),
      );
      canvas.drawPath(
        trace,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [for (final c in colours) c.withValues(alpha: fillAlpha)],
            transform: GradientRotation(-math.pi / 2),
          ).createShader(band),
      );
      return;
    }
    if (!on) return;
    // The pill is drawn 1 inside its target; the band starts 1.5 outside it, 3.5 wide.
    final pill = (Offset.zero & size).deflate(1);
    final scale = 1 + level.clamp(0.0, 1.0) * 0.12;
    final c = pill.center;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(scale);
    canvas.translate(-c.dx, -c.dy);
    final band = pill.inflate(1.5 + 1.75);
    final colours = [
      palette.at(0.1),
      palette.at(0.45),
      palette.at(0.75),
      palette.at(0.1),
    ];
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..shader = SweepGradient(
            colors: colours,
            transform: GradientRotation(turn * _tau),
          ).createShader(band);
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, Radius.circular(band.height / 2)),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.on != on ||
      old.turn != turn ||
      old.level != level ||
      old.palette != palette ||
      old.fill != fill ||
      old.fillAlpha != fillAlpha;
}

/// Above the composer while an answer is read aloud: the small ring moving
/// with the voice, and a way to stop it, as the lab has it.
class RingReading extends StatelessWidget {
  const RingReading({super.key, required this.on, required this.onStop});

  final bool on;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final colors = theme.colors;
    final strings = RendelStringsScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final base = DefaultTextStyle.of(context).style;
    return IgnorePointer(
      ignoring: !on,
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: Duration(milliseconds: still ? 0 : 300),
        child: AnimatedSlide(
          offset: on ? Offset.zero : const Offset(0, 0.25),
          duration: Duration(milliseconds: still ? 0 : 420),
          curve: const Cubic(0.2, 0, 0, 1),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(7, 5, 6, 5),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F281E14),
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
                BoxShadow(
                  color: Color(0x0F281E14),
                  offset: Offset(0, 6),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (on)
                  const RingSpot(reading: true)
                else
                  const SizedBox.square(dimension: 22),
                const SizedBox(width: 8),
                // A narrow phone with large text cuts the words short, never
                // the stop.
                Flexible(
                  child: Text(
                    strings.readingAloud,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: base.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceSoft,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  button: true,
                  label: strings.stopReading,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onStop,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.stop_rounded,
                          size: 13,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
