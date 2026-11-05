import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

import '../core/batteries.dart' show RendelPreferencesStore;
import '../core/config.dart' show RendelLauncherStyle;
import '../core/copilot.dart';
import '../core/device_id.dart' show RendelDeviceId;
import '../core/events.dart';
import '../core/followups.dart';
import 'followup_card.dart';
import 'launcher_icons.dart';
import 'renderer/blocks.dart' show RendelPressable;
import 'theme.dart';

/// The entry point button. You place it: a `floatingActionButton`, a row in a
/// settings list, anywhere the affordance belongs in your own layout. The SDK
/// positions nothing of its own but the bubble it shrinks into while a screen
/// it opened is in front; this hides itself while the bubble is up, so one
/// way in is on screen. A button of your own should do the same, listening
/// to [Rendel.minimised].
///
/// It presses like every other control in the SDK, because it is the same
/// control: an [RendelPressable], not a Material ripple.
///
/// It carries its icon and its word, as the web SDK's does, or the icon alone
/// in a round button (`RendelConfig.launcherStyle`); the icon is one of the
/// console's set or the customer's own (`launcherIcon`).
///
/// With `RendelConfig.launcherDraggable` on, people may drag it: it then
/// draws itself once, over the app, at the place this device last left it
/// (the first time, where the first placement put it), and every placement
/// keeps an empty slot. It shows on the screens that place it, as the
/// undragged one does, not on a screen pushed over one.
///
/// An "In the app" message waiting for this person (`Rendel.followup`) shows
/// on the app's screen while the thread is closed, as its send chose: over the
/// launcher, anchored to it in the app's overlay, or as a banner across the
/// top of the screen.
///
/// With [builder], the button is your own widget and Rendel does the rest:
/// the tap, its spoken label, stepping aside for the bubble, the message
/// over it, the count or dot on its corner, and the drag.
class RendelLauncher extends StatefulWidget {
  const RendelLauncher({super.key, this.label, this.builder});

  /// Overrides both the code config's `launcherLabel` and anything the console
  /// published. Pass it only when this particular placement needs a different
  /// word from the rest of the app.
  final String? label;

  /// Draws the button as your own widget, in place of Rendel's and of
  /// Appearance's launcher look. Return the visual only: Rendel makes it
  /// pressable, says [RendelLauncherStatus.label] to a screen reader and
  /// puts its own count or dot on the corner.
  final RendelLauncherBuilder? builder;

  @override
  State<RendelLauncher> createState() => _RendelLauncherState();
}

/// Draws a launcher of your own; see [RendelLauncher.builder].
typedef RendelLauncherBuilder = Widget Function(BuildContext context, RendelLauncherStatus status);

/// What a launcher of your own can show.
class RendelLauncherStatus {
  const RendelLauncherStatus({required this.label, required this.unread, required this.waiting});

  /// The launcher's word: the published or coded `launcherLabel`, or this placement's own.
  final String label;

  /// Unread lines from the team, 0 when none.
  final int unread;

  /// An answer that finished unseen or a card that waits for this person.
  final RendelWaiting waiting;
}

class _RendelLauncherState extends State<RendelLauncher> {
  final _link = LayerLink();
  OverlayEntry? _popup;
  OverlayEntry? _banner;

  /// The team's reply while Rendel is closed, across the top.
  OverlayEntry? _reply;

  /// Every half minute while this is on screen: a reply from the team comes in as a banner.
  Timer? _supportBeat;
  StreamSubscription<RendelEvent>? _events;

  /// Whether the popup and the banner were placed for the dragged launcher.
  bool _floating = false;

  /// Whether this placement's screen is the one in front. Dragged, only such
  /// a placement brings the launcher: a home screen's under a pushed screen
  /// that places none kept it on every screen (inSepo, 2026-11-01).
  bool _current = true;

  @override
  void initState() {
    super.initState();
    _Floating.states.add(this);
    RendelFollowups.instance.current.addListener(_schedule);
    Rendel.minimised.addListener(_schedule);
    Rendel.configRevision.addListener(_schedule);
    Rendel.supportReply.addListener(_schedule);
    _events = Rendel.events.listen((_) => _schedule());
    _supportBeat = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(Rendel.supportTick()));
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current == _current) return;
    _current = current;
    // Another placement may be the host now, with the popup to carry, and
    // the launcher over the app shows or goes (after the frame, in _sync).
    for (final state in _Floating.states) {
      state._schedule();
    }
  }

  @override
  void dispose() {
    RendelFollowups.instance.current.removeListener(_schedule);
    Rendel.minimised.removeListener(_schedule);
    Rendel.configRevision.removeListener(_schedule);
    Rendel.supportReply.removeListener(_schedule);
    _events?.cancel();
    _supportBeat?.cancel();
    _popup?.remove();
    _popup = null;
    _banner?.remove();
    _banner = null;
    _reply?.remove();
    _reply = null;
    _Floating.leave(this);
    super.dispose();
  }

  /// After the frame: an overlay is not changed while the tree builds.
  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

  /// The popup or the banner is up while an "In the app" message waits and
  /// the thread is closed; inside the thread it is one of the cards.
  void _sync() {
    if (!mounted) return;
    _Floating.sync();
    _Floating.front.value = _Floating.host;
    // Dragged, there is one launcher over the app, and the first placement
    // shows the message over it, in the root overlay with it.
    final floating = Rendel.config.launcherDraggable;
    if (floating != _floating) {
      _floating = floating;
      _place(false, () => _popup, (entry) => _popup = entry, _buildPopup);
      _place(false, () => _banner, (entry) => _banner = entry, _buildBanner);
      _place(false, () => _reply, (entry) => _reply = entry, _buildReply);
    }
    // The team's reply takes the top first: it is the person's own conversation.
    final reply = (!floating || _Floating.host == this) && Rendel.supportReply.value != null && Rendel.isInitialized && !Rendel.isOpen;
    _place(reply, () => _reply, (entry) => _reply = entry, _buildReply);
    final waiting = RendelFollowups.instance.current.value;
    final show = (!floating || _Floating.host == this) &&
        waiting != null &&
        Rendel.isInitialized &&
        Rendel.isEnabled &&
        !Rendel.isOpen &&
        !Rendel.minimised.value;
    final banner = show && waiting.isBanner && !reply;
    _place(show && !banner, () => _popup, (entry) => _popup = entry, _buildPopup);
    _place(banner, () => _banner, (entry) => _banner = entry, _buildBanner);
    if (show) RendelFollowups.instance.shown();
  }

  /// One overlay entry, up or down.
  void _place(bool up, OverlayEntry? Function() entry, void Function(OverlayEntry?) keep, WidgetBuilder builder) {
    final current = entry();
    if (!up) {
      current?.remove();
      keep(null);
      return;
    }
    if (current != null) return current.markNeedsBuild();
    final overlay = Overlay.maybeOf(context, rootOverlay: _floating);
    if (overlay == null) return;
    final added = OverlayEntry(builder: builder);
    keep(added);
    overlay.insert(added, above: _floating ? _Floating.entry : null);
  }

  /// Across the top of the app's screen, below the status bar.
  Widget _buildBanner(BuildContext overlayContext) {
    final waiting = RendelFollowups.instance.current.value;
    if (waiting == null || !mounted) return const SizedBox.shrink();
    final theme = context.dependOnInheritedWidgetOfExactType<RendelThemeScope>()?.theme ?? Rendel.themeOf(context);
    final top = MediaQuery.paddingOf(overlayContext).top;
    return Positioned(
      top: top + theme.space.sm,
      left: theme.space.lg,
      right: theme.space.lg,
      child: Material(
        type: MaterialType.transparency,
        child: RendelFollowupCard(
          followup: waiting,
          theme: theme,
          raised: true,
          closeLabel: Rendel.strings.closeDetail,
          onOpen: () => unawaited(Rendel.openFollowup(context)),
          onDismiss: Rendel.dismissFollowup,
        ),
      ),
    );
  }

  /// The team wrote back while Rendel was closed: who, what, and Open, which goes to the line.
  Widget _buildReply(BuildContext overlayContext) {
    final reply = Rendel.supportReply.value;
    if (reply == null || !mounted) return const SizedBox.shrink();
    final theme = context.dependOnInheritedWidgetOfExactType<RendelThemeScope>()?.theme ?? Rendel.themeOf(context);
    final strings = Rendel.strings;
    final top = MediaQuery.paddingOf(overlayContext).top;
    final initial = reply.name.trim().isEmpty ? '·' : reply.name.trim().characters.first.toUpperCase();
    return Positioned(
      top: top + theme.space.sm,
      left: theme.space.lg,
      right: theme.space.lg,
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: theme.colors.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: theme.colors.onSurface.withValues(alpha: 0.06), spreadRadius: 1),
                BoxShadow(color: theme.colors.shadow.withValues(alpha: 0.3), offset: const Offset(0, 18), blurRadius: 44, spreadRadius: -12),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Color.alphaBlend(theme.colors.accent.withValues(alpha: 0.14), theme.colors.surfaceRaised)),
                  child: Text(initial, style: theme.text.caption.copyWith(color: theme.accentText, fontWeight: FontWeight.w700, fontSize: 14, height: 1)),
                ),
                SizedBox(width: theme.space.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(strings.supportRepliedOf(reply.name), style: theme.text.labelEmphasis, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (reply.text.isNotEmpty) Text(reply.text, style: theme.text.labelSoft, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: null,
                  onPressed: () => Rendel.supportReply.value = null,
                  icon: Icon(Icons.close_rounded, size: 18, color: theme.colors.onSurfaceSoft, semanticLabel: strings.closeDetail),
                ),
                RendelPressable(
                  semanticLabel: strings.supportShow,
                  onTap: () {
                    Rendel.supportReply.value = null;
                    unawaited(Rendel.openSupport(context));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: theme.colors.accent, borderRadius: BorderRadius.circular(999)),
                    child: Text(strings.supportShow, style: theme.text.caption.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, color: theme.colors.onAccent)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopup(BuildContext overlayContext) {
    final waiting = RendelFollowups.instance.current.value;
    if (waiting == null || !mounted) return const SizedBox.shrink();
    final theme = context.dependOnInheritedWidgetOfExactType<RendelThemeScope>()?.theme ?? Rendel.themeOf(context);
    // Over the launcher, opening toward the screen: from its right edge in a
    // left-to-right app, from its left in a right-to-left one, and from the
    // side a dragged launcher sits on.
    final rtl = _floating ? !_Floating.right : Directionality.of(context) == TextDirection.rtl;
    final width = (MediaQuery.sizeOf(overlayContext).width - 2 * theme.space.lg).clamp(0.0, 320.0);
    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: _floating ? _Floating.link : _link,
        showWhenUnlinked: false,
        targetAnchor: rtl ? Alignment.topLeft : Alignment.topRight,
        followerAnchor: rtl ? Alignment.bottomLeft : Alignment.bottomRight,
        offset: Offset(0, -theme.space.md),
        child: Material(
          type: MaterialType.transparency,
          child: RendelFollowupCard(
            followup: waiting,
            theme: theme,
            raised: true,
            closeLabel: Rendel.strings.closeDetail,
            onOpen: () => unawaited(Rendel.openFollowup(context)),
            onDismiss: Rendel.dismissFollowup,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(link: _link, child: _launcher(context));

  Widget _launcher(BuildContext context) {
    // Rebuilds when a published config lands, so a kill switch or a renamed
    // launcher takes effect without a relaunch. The notifier ticks at most
    // once per fetch, so this costs nothing per frame.
    return ValueListenableBuilder<int>(
      valueListenable: Rendel.configRevision,
      // Hidden while the bubble is up: it is the way back then, and one way
      // in is all a screen shows (Tuna, 2026-10-13).
      builder: (context, _, __) => Rendel.config.launcherDraggable
          // Drawn over the app instead (_Floating); this keeps the slot,
          // empty, and says where it is.
          ? const _Slot()
          : ValueListenableBuilder<bool>(
              valueListenable: Rendel.minimised,
              builder: (context, minimised, _) => minimised ? const SizedBox.shrink() : _build(context),
            ),
    );
  }

  Widget _build(BuildContext context) {
    // The launcher lives in the HOST's tree, outside the sheet that carries
    // the RendelThemeScope — so `of(context)` here always hit the scope's
    // paper() fallback, and a custom `fromTokens` brand or a
    // console-published palette never reached the one control that is always
    // on screen. The two shipped presets used to share an accent, which is
    // why every internal demo looked fine. Scope first (a host may wrap its own), then
    // the live static theme.
    final theme =
        context.dependOnInheritedWidgetOfExactType<RendelThemeScope>()?.theme ??
            Rendel.themeOf(context);
    // Nothing at all when the copilot is off: an affordance that opens a sheet
    // the SDK will refuse to present is worse than no affordance. A conversation
    // with the team stays reachable with the assistant paused (K7).
    if (!Rendel.isInitialized || !(Rendel.isEnabled || Rendel.supportOpen)) {
      return const SizedBox.shrink();
    }
    return _button(theme, widget.label ?? Rendel.config.launcherLabel, () => _tap(context), widget.builder);
  }
}

/// A tap on the launcher: the thread, or the team's page while a conversation with them is open.
void _tap(BuildContext context) {
  if (Rendel.supportUnread.value > 0 || Rendel.supportOpen) {
    unawaited(Rendel.openSupport(context));
  } else {
    unawaited(Rendel.open(context));
  }
}

/// The launcher as drawn, wherever it is: in its slot, or over the app, with
/// the count of the team's unread lines on its corner (human support), or a
/// dot while an answer finished unseen or a card waits ([Rendel.waiting]).
Widget _button(RendelTheme theme, String word, VoidCallback onTap, [RendelLauncherBuilder? builder]) {
  Rendel.launcherDrawn(own: builder != null);
  return ValueListenableBuilder<RendelWaiting>(
    valueListenable: Rendel.waiting,
    builder: (context, waiting, _) => ValueListenableBuilder<int>(
      valueListenable: Rendel.supportUnread,
      builder: (context, unread, _) => _marked(theme, word, onTap, unread: unread, waiting: waiting, builder: builder),
    ),
  );
}

Widget _marked(RendelTheme theme, String word, VoidCallback onTap, {required int unread, required RendelWaiting waiting, RendelLauncherBuilder? builder}) {
  final drawn = builder == null
      ? _plainButton(theme, word, onTap, unread: unread, waiting: waiting)
      // The host's own button, pressable and spoken as the icon-only one is.
      : Builder(
          builder: (context) => RendelPressable(
            semanticLabel: _spoken(word, unread, waiting),
            onTap: onTap,
            child: builder(context, RendelLauncherStatus(label: word, unread: unread, waiting: waiting)),
          ),
        );
  if (unread <= 0 && waiting == RendelWaiting.none) return drawn;
  return Stack(
    clipBehavior: Clip.none,
    children: [
      drawn,
      // The team's count says more than the dot, and stands in its place.
      if (unread > 0)
        PositionedDirectional(
          top: -4,
          end: -4,
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.danger,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: theme.colors.surface, width: 1.5),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: theme.text.caption.copyWith(color: theme.onDanger, fontSize: 11, height: 1),
              ),
            ),
          ),
        )
      else
        PositionedDirectional(
          top: 0,
          end: 0,
          child: ExcludeSemantics(
            child: Container(
              key: const ValueKey('rendel-launcher-dot'),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: theme.danger,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colors.surface, width: 2),
              ),
            ),
          ),
        ),
    ],
  );
}

/// What a screen reader says for the launcher: [said], then what waits.
String _spoken(String said, int unread, RendelWaiting waiting) => unread > 0
    ? '$said. ${Rendel.strings.supportUnreadOf(unread)}'
    : switch (waiting) {
        RendelWaiting.answer => '$said. ${Rendel.strings.answerWaiting}',
        RendelWaiting.approval => '$said. ${Rendel.strings.approvalWaiting}',
        RendelWaiting.none => said,
      };

Widget _plainButton(RendelTheme theme, String word, VoidCallback onTap, {required int unread, RendelWaiting waiting = RendelWaiting.none}) {
  final config = Rendel.config;
  final iconOnly = config.launcherStyle == RendelLauncherStyle.icon;
  // The round launcher's size, ring included; its icon keeps the 20 it has
  // at the 46 the padding below makes.
  final size = iconOnly ? config.launcherSize : null;
  final icon = _LauncherIcon(color: theme.colors.onAccent, size: config.launcherIconSize ?? (size == null ? 20 : size * 20 / 46));
  // The customer's fill, where its icon (3:1) or word (4.5:1) reads on it;
  // the accent otherwise. The icon alone covers the middle of a round
  // launcher (its 20 of 46), so the colours there; a word runs end to end,
  // so every colour of it. The web SDK weighs it the same way.
  final fill = config.launcherFill;
  final grounds = fill == null ? const <Color>[] : (iconOnly ? [0.3, 0.5, 0.7].map((t) => _fillAt(fill, t)) : fill.colors);
  final filled = fill != null && grounds.every((ground) => contrastRatio(theme.colors.onAccent, ground) >= (iconOnly ? 3 : 4.5));
  final ring = config.launcherRing;
  final ringWidth = ring == null ? 1.0 : config.launcherRingWidth ?? 3;
  final glow = config.launcherGlow;
  // The customer's light, over the fill and under the icon, inside the ring.
  final light = config.launcherLight;
  return RendelPressable(
    // The icon alone says nothing to a screen reader, so the word does.
    semanticLabel: _spoken(iconOnly ? word : Rendel.strings.openCopilot, unread, waiting),
    onTap: onTap,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? null : theme.colors.accent,
        gradient: filled ? fill : null,
        shape: iconOnly ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: iconOnly ? null : BorderRadius.circular(theme.radius.control),
        // The one control in the product that is always on screen is the
        // one that earns the deepest elevation. `accentEdge` is the
        // boundary WCAG 1.4.11 asks 3:1 of, which a host's raw accent often
        // does not clear against its own ground. A ring or a glow the
        // customer chose takes the place of each.
        border: Border.all(color: ring ?? theme.accentEdge, width: ringWidth),
        boxShadow: glow == null
            ? theme.lift
            : [BoxShadow(color: glow.withValues(alpha: config.launcherGlowStrength ?? 0.45), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 4))],
      ),
      child: Container(
        alignment: size == null ? null : Alignment.center,
        // Round, as tall as the button with its word: the same 12 above and
        // below the 20 the icon takes, and on each side of it. A size of its
        // own centres the icon instead.
        padding: iconOnly
            ? (size == null ? EdgeInsets.all(theme.space.md) : EdgeInsets.zero)
            // The web launcher's 16 before the icon and 20 after the word.
            : EdgeInsetsDirectional.only(
                start: theme.space.lg,
                end: theme.space.lg + theme.space.xs,
                top: theme.space.md,
                bottom: theme.space.md,
              ),
        decoration: light == null
            ? null
            : BoxDecoration(
                gradient: light,
                shape: iconOnly ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: iconOnly ? null : BorderRadius.circular(math.max(0, theme.radius.control - ringWidth)),
              ),
        child: iconOnly
          ? icon
          // Grows with the reader's text size, but never past 1.5×: at the
          // largest sizes it covered the app it floats over (QA R7, iPhone SE).
          : MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  // The web's gap between the two.
                  SizedBox(width: theme.space.sm),
                  Text(word, style: theme.text.labelStrong),
                ],
              ),
            ),
      ),
    ),
  );
}

/// The colour [t] of the way along [fill], its stops or evenly spaced.
Color _fillAt(Gradient fill, double t) {
  final colors = fill.colors;
  final stops = fill.stops ?? [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
  if (t <= stops.first) return colors.first;
  for (var i = 1; i < colors.length; i++) {
    if (t <= stops[i]) {
      final span = stops[i] - stops[i - 1];
      return Color.lerp(colors[i - 1], colors[i], span > 0 ? (t - stops[i - 1]) / span : 1)!;
    }
  }
  return colors.last;
}

/// The launcher's icon, 20 square like the web's: one of [launcherIconPaths],
/// or the customer's own, fetched like the logo and drawn in [color]. The
/// sparkle stands in while their own loads, and for good if it cannot.
class _LauncherIcon extends StatelessWidget {
  const _LauncherIcon({required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Glyph(Rendel.config.launcherIcon, color)),
    );
    final url = Rendel.launcherIconUrl;
    if (url == null) return glyph;
    // A mask: white on transparent, so `srcIn` makes it the launcher's ink.
    return Image.network(
      url,
      headers: Rendel.logoHeaders,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, _) => frame == null ? glyph : child,
      errorBuilder: (_, __, ___) => glyph,
    );
  }
}

/// One of [launcherIconPaths], scaled from Phosphor's 256 grid to the size it
/// is given. An id this build does not carry, or `custom`, is the sparkle.
class _Glyph extends CustomPainter {
  _Glyph(String id, this.color) : id = launcherIconPaths.containsKey(id) ? id : 'sparkle';

  final String id;
  final Color color;

  /// Parsed once per icon.
  static final _parsed = <String, List<Path>>{};

  static List<Path> _paths(String id) => _parsed[id] ??= [
        for (final data in launcherIconPaths[id]!) (_PathProxy()..parse(data)).path,
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas
      ..save()
      ..scale(size.width / 256, size.height / 256);
    for (final path in _paths(id)) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Glyph old) => old.id != id || old.color != color;
}

class _PathProxy implements PathProxy {
  final path = Path();

  void parse(String data) => writeSvgPathDataToPath(data, this);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}

/// Where a placement would have drawn the launcher, while the dragged one is
/// drawn over the app: nothing, at no size, reporting its place once so the
/// launcher's first appearance is where the app put it.
class _Slot extends StatefulWidget {
  const _Slot();

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return const SizedBox.shrink();
  }

  void _report() {
    if (!mounted || _Floating.slot.value != null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _Floating.slot.value = box.localToGlobal(Offset.zero);
  }
}

/// The dragged launcher: one, over the app, in its root overlay, while at
/// least one [RendelLauncher] is mounted, however many screens place one. It
/// shows while the screen in front places one, and only then.
abstract final class _Floating {
  /// Every mounted placement, oldest first. The oldest on the screen in front
  /// is the host: its label, its theme scope and its context to open from.
  static final states = <_RendelLauncherState>[];
  static _RendelLauncherState? get host {
    for (final state in states) {
      if (state._current) return state;
    }
    return null;
  }

  /// [host] as the launcher over the app last drew it, so it redraws when
  /// the screen in front changes.
  static final front = ValueNotifier<_RendelLauncherState?>(null);

  static OverlayEntry? entry;

  /// What the follow-up popup anchors to while the launcher is dragged.
  static final link = LayerLink();

  /// Which side it rests on, for the popup to open toward the screen.
  static bool right = true;

  /// Where the first placement's slot is, until the launcher has a place of
  /// its own on this device.
  static final slot = ValueNotifier<Offset?>(null);

  /// Up while dragging is on and anything places a launcher, on whichever
  /// screen; down otherwise. [host] decides whether it shows.
  static void sync() {
    final host = Rendel.config.launcherDraggable && states.isNotEmpty ? states.first : null;
    if (host == null) {
      entry
        ?..remove()
        ..dispose();
      entry = null;
      return;
    }
    if (entry != null) return;
    final overlay = Overlay.maybeOf(host.context, rootOverlay: true);
    if (overlay == null) return;
    // A new launcher over the app takes its first place from the slots now
    // on screen, not from ones gone with an earlier app.
    slot.value = null;
    overlay.insert(entry = OverlayEntry(builder: (_) => const _FloatingLauncher()));
  }

  static void leave(_RendelLauncherState state) {
    states.remove(state);
    // Another placement may be the host now, with the popup to carry.
    for (final other in states) {
      other._schedule();
    }
    if (states.isEmpty) {
      sync();
      // Not while the tree unmounts: after the frame, holding no gone state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (states.isEmpty) front.value = null;
      });
    }
  }
}

/// The launcher over the app: where it was left, dragged, and let go.
class _FloatingLauncher extends StatefulWidget {
  const _FloatingLauncher();

  /// From the side it rests on: the web launcher's.
  static const double inset = 20;

  /// A press that moves less than this is a tap, as on the bubble.
  static const double slop = 6;

  @override
  State<_FloatingLauncher> createState() => _FloatingLauncherState();
}

class _FloatingLauncherState extends State<_FloatingLauncher> with SingleTickerProviderStateMixin {
  final _key = GlobalKey();
  late final AnimationController _settle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);
  StreamSubscription<RendelEvent>? _events;

  /// The place this device keeps, once read: the side, and the top as a
  /// fraction of the screen's height. Null for none yet.
  var _read = false;
  bool? _right;
  double? _top;

  /// A press, the launcher's top left when it began, and where a drag has
  /// it now. [_moved] outlives the release by a microtask, so the press that
  /// ended a drag does not also open the thread.
  Offset? _press;
  Offset? _grab;
  Offset? _drag;
  bool _moved = false;

  /// Where a drop let go, for the settle to start from.
  Offset? _from;

  @override
  void initState() {
    super.initState();
    Rendel.configRevision.addListener(_changed);
    Rendel.minimised.addListener(_changed);
    _Floating.slot.addListener(_changed);
    _Floating.front.addListener(_changed);
    _events = Rendel.events.listen((_) => _changed());
    unawaited(_load());
  }

  @override
  void dispose() {
    Rendel.configRevision.removeListener(_changed);
    Rendel.minimised.removeListener(_changed);
    _Floating.slot.removeListener(_changed);
    _Floating.front.removeListener(_changed);
    _events?.cancel();
    _settle.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  RendelPreferencesStore? get _store {
    final key = Rendel.launcherPlaceKey;
    return key == null ? null : RendelPreferencesStore(key);
  }

  /// `{"side":"left"|"right","y":0..1}`, y the top over the screen's height.
  /// Anything else is no place: the slot's stands.
  Future<void> _load() async {
    try {
      final stored = await _store?.read().timeout(RendelDeviceId.storeTimeout);
      final place = stored == null ? null : jsonDecode(stored);
      if (place is Map && (place['side'] == 'left' || place['side'] == 'right') && place['y'] is num) {
        _right = place['side'] == 'right';
        _top = (place['y'] as num).toDouble().clamp(0.0, 1.0);
      }
    } catch (_) {
      // No store, or a broken value: the launcher starts where it is placed.
    }
    _read = true;
    _changed();
  }

  void _save() {
    final store = _store;
    if (store == null) return;
    final place = jsonEncode({'side': _right! ? 'right' : 'left', 'y': _top});
    unawaited(store.write(place).timeout(RendelDeviceId.storeTimeout).catchError((_) {}));
  }

  /// The safe area, the keyboard included, that the launcher stays inside.
  EdgeInsets get _safe {
    final media = MediaQuery.of(context);
    return media.padding + EdgeInsets.only(bottom: media.viewInsets.bottom);
  }

  void _down(PointerDownEvent event) {
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    _press = event.position;
    _grab = box.localToGlobal(Offset.zero);
    _moved = false;
  }

  void _move(PointerMoveEvent event) {
    final press = _press;
    if (press == null) return;
    if (!_moved && (event.position - press).distance < _FloatingLauncher.slop) return;
    _moved = true;
    setState(() => _drag = _grab! + (event.position - press));
  }

  /// Let go: to the nearer side, at the height it was let go, inside the
  /// safe area, and kept.
  void _up(PointerEvent event) {
    final drag = _drag;
    _press = null;
    scheduleMicrotask(() => _moved = false);
    if (drag == null) return;
    final screen = MediaQuery.sizeOf(context);
    final size = (_key.currentContext!.findRenderObject()! as RenderBox).size;
    final top = _clampTop(drag.dy, screen, size, _safe, _Floating.slot.value);
    setState(() {
      _right = drag.dx + size.width / 2 >= screen.width / 2;
      _top = screen.height == 0 ? 0 : top / screen.height;
      _from = drag;
      _drag = null;
    });
    _Floating.right = _right!;
    // The popup opens toward the screen from whichever side this is now.
    for (final state in _Floating.states) {
      state._schedule();
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _settle.value = 1;
    } else {
      _settle.forward(from: 0);
    }
    _save();
  }

  /// Inside the safe area, and never lower than the slot the app placed it
  /// in when that slot is in the lower half: a `floatingActionButton` sits
  /// above the app's bottom bar, and a launcher let go below it covered a tab
  /// (QA R2-14). A slot near the top (an app bar) limits nothing.
  static double _clampTop(double top, Size screen, Size size, EdgeInsets safe, Offset? slot) {
    final floor = safe.top + _FloatingLauncher.inset;
    var lowest = screen.height - safe.bottom - _FloatingLauncher.inset - size.height;
    if (slot != null && slot.dy > screen.height / 2) lowest = math.min(lowest, slot.dy - size.height);
    final ceiling = math.max(floor, lowest);
    return top.clamp(floor, ceiling);
  }

  @override
  Widget build(BuildContext context) {
    final host = _Floating.host;
    // Hidden while the thread is up, in its sheet or its bubble, as the
    // placed launcher is under the sheet and steps aside for the bubble.
    final hidden = !_read ||
        host == null ||
        !Rendel.isInitialized ||
        !(Rendel.isEnabled || Rendel.supportOpen) ||
        Rendel.isOpen ||
        Rendel.minimised.value;
    if (hidden) return const SizedBox.shrink();
    final theme = host.context.getInheritedWidgetOfExactType<RendelThemeScope>()?.theme ?? Rendel.themeOf(context);
    final slot = _Floating.slot.value;
    final screen = MediaQuery.sizeOf(context);
    final safe = _safe;
    // The side it rests on, and the popup opens from: kept, or the slot's.
    final right = _Floating.right = _right ?? (slot == null || slot.dx >= screen.width / 2);
    return CustomSingleChildLayout(
      delegate: _Place(
        settle: _settle,
        drag: _drag,
        from: _from,
        rest: (size) {
          final left = right
              ? screen.width - safe.right - _FloatingLauncher.inset - size.width
              : safe.left + _FloatingLauncher.inset;
          // Saved, or with its bottom where the slot is: a zero-size
          // `floatingActionButton` sits at the corner the button's would.
          final top = _top != null
              ? _top! * screen.height
              : slot != null
                  ? slot.dy - size.height
                  : screen.height;
          return Offset(left, _clampTop(top, screen, size, safe, slot));
        },
      ),
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: CompositedTransformTarget(
          link: _Floating.link,
          child: KeyedSubtree(
            key: _key,
            child: _button(theme, host.widget.label ?? Rendel.config.launcherLabel, () {
              if (!_moved) _tap(host.context);
            }, host.widget.builder),
          ),
        ),
      ),
    );
  }
}

/// Where the dragged launcher is: under the finger, settling from where it
/// was let go, or at rest.
class _Place extends SingleChildLayoutDelegate {
  _Place({required this.settle, required this.drag, required this.from, required this.rest})
      : super(relayout: settle);

  final Animation<double> settle;
  final Offset? drag;
  final Offset? from;
  final Offset Function(Size size) rest;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final drag = this.drag;
    if (drag != null) return drag;
    final at = rest(childSize);
    final from = this.from;
    if (from == null || settle.value >= 1) return at;
    return Offset.lerp(from, at, rendelEase.transform(settle.value))!;
  }

  @override
  bool shouldRelayout(_Place old) => true;
}
