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
/// keeps an empty slot.
///
/// An "In the app" message waiting for this person (`Rendel.followup`) shows
/// on the app's screen while the thread is closed, as its send chose: over the
/// launcher, anchored to it in the app's overlay, or as a banner across the
/// top of the screen.
class RendelLauncher extends StatefulWidget {
  const RendelLauncher({super.key, this.label});

  /// Overrides both the code config's `launcherLabel` and anything the console
  /// published. Pass it only when this particular placement needs a different
  /// word from the rest of the app.
  final String? label;

  @override
  State<RendelLauncher> createState() => _RendelLauncherState();
}

class _RendelLauncherState extends State<RendelLauncher> {
  final _link = LayerLink();
  OverlayEntry? _popup;
  OverlayEntry? _banner;
  StreamSubscription<RendelEvent>? _events;

  /// Whether the popup and the banner were placed for the dragged launcher.
  bool _floating = false;

  @override
  void initState() {
    super.initState();
    _Floating.states.add(this);
    RendelFollowups.instance.current.addListener(_schedule);
    Rendel.minimised.addListener(_schedule);
    Rendel.configRevision.addListener(_schedule);
    _events = Rendel.events.listen((_) => _schedule());
    _schedule();
  }

  @override
  void dispose() {
    RendelFollowups.instance.current.removeListener(_schedule);
    Rendel.minimised.removeListener(_schedule);
    Rendel.configRevision.removeListener(_schedule);
    _events?.cancel();
    _popup?.remove();
    _popup = null;
    _banner?.remove();
    _banner = null;
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
    // Dragged, there is one launcher over the app, and the first placement
    // shows the message over it, in the root overlay with it.
    final floating = Rendel.config.launcherDraggable;
    if (floating != _floating) {
      _floating = floating;
      _place(false, () => _popup, (entry) => _popup = entry, _buildPopup);
      _place(false, () => _banner, (entry) => _banner = entry, _buildBanner);
    }
    final waiting = RendelFollowups.instance.current.value;
    final show = (!floating || _Floating.host == this) &&
        waiting != null &&
        Rendel.isInitialized &&
        Rendel.isEnabled &&
        !Rendel.isOpen &&
        !Rendel.minimised.value;
    final banner = show && waiting.isBanner;
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
    // the SDK will refuse to present is worse than no affordance.
    if (!Rendel.isInitialized || !Rendel.isEnabled) {
      return const SizedBox.shrink();
    }
    return _button(theme, widget.label ?? Rendel.config.launcherLabel, () => Rendel.open(context));
  }
}

/// The launcher as drawn, wherever it is: in its slot, or over the app.
Widget _button(RendelTheme theme, String word, VoidCallback onTap) {
  final iconOnly = Rendel.config.launcherStyle == RendelLauncherStyle.icon;
  final icon = _LauncherIcon(color: theme.colors.onAccent);
  return RendelPressable(
    // The icon alone says nothing to a screen reader, so the word does.
    semanticLabel: iconOnly ? word : Rendel.strings.openCopilot,
    onTap: onTap,
    child: Container(
      // Round, as tall as the button with its word: the same 12 above and
      // below the 20 the icon takes, and on each side of it.
      padding: iconOnly
          ? EdgeInsets.all(theme.space.md)
          // The web launcher's 16 before the icon and 20 after the word.
          : EdgeInsetsDirectional.only(
              start: theme.space.lg,
              end: theme.space.lg + theme.space.xs,
              top: theme.space.md,
              bottom: theme.space.md,
            ),
      decoration: BoxDecoration(
        color: theme.colors.accent,
        shape: iconOnly ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: iconOnly ? null : BorderRadius.circular(theme.radius.control),
        // The one control in the product that is always on screen is the
        // one that earns the deepest elevation. `accentEdge` is the
        // boundary WCAG 1.4.11 asks 3:1 of, which a host's raw accent often
        // does not clear against its own ground.
        border: Border.all(color: theme.accentEdge),
        boxShadow: theme.lift,
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
  );
}

/// The launcher's icon, 20 square like the web's: one of [launcherIconPaths],
/// or the customer's own, fetched like the logo and drawn in [color]. The
/// sparkle stands in while their own loads, and for good if it cannot.
class _LauncherIcon extends StatelessWidget {
  const _LauncherIcon({required this.color});

  final Color color;

  static const double size = 20;

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
/// least one [RendelLauncher] is mounted, however many screens place one.
abstract final class _Floating {
  /// Every mounted placement, oldest first. The oldest is the host: its
  /// label, its theme scope and its context to open from.
  static final states = <_RendelLauncherState>[];
  static _RendelLauncherState? get host => states.isEmpty ? null : states.first;

  static OverlayEntry? entry;

  /// What the follow-up popup anchors to while the launcher is dragged.
  static final link = LayerLink();

  /// Which side it rests on, for the popup to open toward the screen.
  static bool right = true;

  /// Where the first placement's slot is, until the launcher has a place of
  /// its own on this device.
  static final slot = ValueNotifier<Offset?>(null);

  /// Up while dragging is on and anything places a launcher; down otherwise.
  static void sync() {
    final host = Rendel.config.launcherDraggable ? _Floating.host : null;
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
    if (states.isEmpty) sync();
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
    _events = Rendel.events.listen((_) => _changed());
    unawaited(_load());
  }

  @override
  void dispose() {
    Rendel.configRevision.removeListener(_changed);
    Rendel.minimised.removeListener(_changed);
    _Floating.slot.removeListener(_changed);
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
        !Rendel.isEnabled ||
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
              if (!_moved) unawaited(Rendel.open(host.context));
            }),
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
