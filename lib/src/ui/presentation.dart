import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../protocol/protocol.dart' show NavigateAction;
import 'theme.dart';

/// Where the thread is, as `Rendel.open` presents it.
enum _Phase {
  /// In the sheet over the app.
  sheet,

  /// Shrinking into the bubble, over the app as it opens a screen.
  leaving,

  /// Out of sight, with the bubble standing in for it.
  bubble,

  /// Growing back out of the bubble, with the sheet pushed under it.
  returning,

  /// Closed for good.
  closed,
}

/// The copilot as `Rendel.open` presents it (`design/NAVIGATE.md`): a sheet
/// over the app, which shrinks into a bubble while a screen of the app an
/// answer opened is in front, and grows back out of it as it was left.
///
/// One thread in two places. The thread is keyed, and moves between the sheet
/// and the overlay above the app within a single frame, so it is never torn
/// down: its page, its scroll, a card open over it and what was typed come
/// back because they never went anywhere, not because something remembered
/// them. The sheet itself has to go, so that the app's own navigation lands
/// on the app's navigator rather than over the copilot.
class RendelPresentation extends ChangeNotifier {
  RendelPresentation({
    required BuildContext context,
    required this.thread,
    required this.openRoute,
    required this.theme,
    required this.label,
    required this.bubbleOffset,
  })  : _origin = context,
        _navigator = Navigator.of(context),
        _overlay = Overlay.of(context, rootOverlay: true);

  /// Builds the thread wherever it is drawn. The key that keeps it one
  /// thread is added here, not by the caller.
  final Widget Function() thread;

  /// The route's own `open`, through the controller.
  final Future<bool> Function(NavigateAction action) openRoute;
  final RendelTheme Function(BuildContext context) theme;

  /// What a screen reader says the bubble does.
  final String label;

  /// `RendelConfig.bubbleOffset`.
  final double bubbleOffset;

  final BuildContext _origin;
  final NavigatorState _navigator;

  /// The root overlay, so a screen the app pushes on a navigator of its own
  /// does not cover the bubble.
  final OverlayState _overlay;
  final GlobalKey _key = GlobalKey(debugLabel: 'rendel thread');

  /// The thread's own primary scroll controller, the same wherever it is.
  ///
  /// A page's list takes the nearest one. In a sheet that is the route's, a
  /// new controller in every route and none at all in the overlay, and a list
  /// whose controller changes is a new list, back at the top. Not disposed:
  /// the sheet that closes last still holds the thread while it slides away.
  final ScrollController _scroll = ScrollController();

  /// Whether the thread is drawn in the overlay rather than in the sheet.
  final ValueNotifier<bool> _aloft = ValueNotifier(false);

  _Phase _phase = _Phase.sheet;
  OverlayEntry? _entry;

  /// The sheet now on screen, and which presentation of it that is: a sheet
  /// still sliding away must not take the thread back.
  BuildContext? _sheet;
  int _shows = 0;
  Completer<void>? _back;

  /// Where the sheet's thread was when it left, in the overlay's coordinates.
  Rect _from = Rect.zero;

  /// Where the bubble rests: the side it was dropped on and how high, which
  /// the next bubble keeps. Null height is the default.
  bool _right = true;
  double? _lift;

  static const double _size = 56;
  static const double _edge = 14;

  /// Whether the bubble is up, waiting to be tapped.
  bool get minimised => _phase == _Phase.bubble;

  /// Presents the thread, and completes when it is closed rather than
  /// shrunk into the bubble.
  Future<void> get done => _done ??= _run();
  Future<void>? _done;

  Future<void> _run() async {
    var back = false;
    try {
      while (true) {
        await _present(back: back);
        // Closed by its ✕, the scrim, a drag or the system back. A sheet
        // popped by a navigate has left the thread with the bubble instead.
        if (_phase != _Phase.leaving && _phase != _Phase.bubble) return;
        final returned = _back = Completer<void>();
        await returned.future;
        back = true;
      }
    } finally {
      _phase = _Phase.closed;
      _drop();
    }
  }

  Future<void> _present({required bool back}) {
    final show = ++_shows;
    final context = _origin.mounted ? _origin : _navigator.context;
    final still = MediaQuery.disableAnimationsOf(context);
    final corner = Radius.circular(theme(context).radius.hero);
    // An iOS page sheet: from a little under the top safe area to the bottom
    // edge, its top corners rounded and its bottom ones square, over the app
    // dimmed by a quarter. Never square at the top, however tall the phone.
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: _scrim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: corner)),
      clipBehavior: Clip.antiAlias,
      // Coming back, the panel grows out of the bubble above the app, and the
      // sheet under it brings only the scrim, in the same time.
      sheetAnimationStyle: back
          ? AnimationStyle(duration: still ? Duration.zero : _Aloft.grow)
          : null,
      builder: (context) {
        if (show == _shows) _sheet = context;
        return LayoutBuilder(
          // Below the safe area already (`useSafeArea`); the gap is the
          // page sheet's own, so the app shows behind its top edge.
          builder: (context, box) => SizedBox(
            height: math.max(0.0, box.maxHeight - _gap),
            child: _seated(aloft: false, show: show),
          ),
        );
      },
    );
  }

  /// The page sheet's gap under the top safe area, and its scrim.
  static const double _gap = 8;
  static const Color _scrim = Color(0x40000000);

  /// The thread where it is now, or nothing where it is not. Only the newest
  /// sheet seats it, so two sheets on the navigator at once cannot both ask
  /// for the same key.
  Widget _seated({required bool aloft, int? show}) => ValueListenableBuilder<bool>(
        valueListenable: _aloft,
        builder: (context, at, _) => at == aloft && (show == null || show == _shows)
            ? KeyedSubtree(
                key: _key,
                child: PrimaryScrollController(controller: _scroll, child: thread()),
              )
            : const SizedBox.shrink(),
      );

  /// A screen card tapped: the thread moves into the overlay and starts
  /// shrinking toward the bubble, the sheet goes, and the app opens its
  /// screen underneath.
  Future<bool> navigate(NavigateAction action) async {
    final sheet = _sheet;
    final box = _key.currentContext?.findRenderObject();
    final ground = _overlay.context.findRenderObject();
    if (_phase != _Phase.sheet ||
        sheet == null ||
        !sheet.mounted ||
        box is! RenderBox ||
        !box.hasSize ||
        ground == null) {
      return openRoute(action);
    }
    _from = box.localToGlobal(Offset.zero, ancestor: ground) & box.size;
    _phase = _Phase.leaving;
    final entry = _entry = OverlayEntry(builder: (_) => _Aloft(presentation: this));
    _overlay.insert(entry);
    _aloft.value = true;
    _sheet = null;
    Navigator.of(sheet).pop();
    // After the pop, so `open` pushes onto the app's navigator where the
    // sheet was rather than over it.
    return openRoute(action);
  }

  /// The bubble tapped, or the app's own launcher pressed while it is up.
  void restore() {
    if (_phase != _Phase.bubble) return;
    _phase = _Phase.returning;
    notifyListeners();
    _back?.complete();
  }

  void _shrunk() {
    if (_phase != _Phase.leaving) return;
    _phase = _Phase.bubble;
    notifyListeners();
  }

  /// The panel is full size again: the thread goes back into the sheet now
  /// under it, in the same frame the overlay lets it go.
  void _grown() {
    if (_phase != _Phase.returning) return;
    final sheet = _sheet;
    if (sheet == null || !sheet.mounted) {
      // The sheet is built in the frame after its push, which under reduced
      // motion is after this.
      WidgetsBinding.instance.addPostFrameCallback((_) => _grown());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _phase = _Phase.sheet;
    _aloft.value = false;
    _drop();
  }

  void _drop() {
    final entry = _entry;
    _entry = null;
    entry
      ?..remove()
      ..dispose();
  }

  /// Where the bubble rests: on its side, 14 from the edge, and clear of the
  /// app's bottom bar and the safe area.
  Rect _rest(Size size, EdgeInsets padding) {
    final floor = math.max(bubbleOffset, padding.bottom + _edge);
    final ceiling = math.max(floor, size.height - padding.top - _size - _edge);
    final lift = (_lift ?? floor).clamp(floor, ceiling);
    final left = _right ? size.width - padding.right - _edge - _size : padding.left + _edge;
    return Rect.fromLTWH(left, size.height - lift - _size, _size, _size);
  }

  /// A drag let go with the bubble's centre at [centre]: the nearer side, at
  /// that height.
  void _dropAt(Offset centre, Size size) {
    _right = centre.dx >= size.width / 2;
    _lift = size.height - centre.dy - _size / 2;
  }
}

/// The overlay above the app while the thread is out of its sheet: the panel
/// shrinking or growing, and the bubble.
class _Aloft extends StatefulWidget {
  const _Aloft({required this.presentation});

  final RendelPresentation presentation;

  /// The panel's motion either way.
  static const Duration grow = Duration(milliseconds: 480);

  @override
  State<_Aloft> createState() => _AloftState();
}

class _AloftState extends State<_Aloft> with TickerProviderStateMixin {
  /// Leaving: the panel's 480ms, and the bubble arriving 300ms in over 360.
  late final AnimationController _leave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 660));
  late final AnimationController _return = AnimationController(vsync: this, duration: _Aloft.grow);
  bool _started = false;

  /// A press on the bubble, and where it has been dragged to, if anywhere.
  Offset? _press;
  bool _moved = false;
  Offset? _drag;

  RendelPresentation get _p => widget.presentation;

  @override
  void initState() {
    super.initState();
    _p.addListener(_onPhase);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // No scale and no fade: the bubble is simply there.
      _leave.value = 1;
      scheduleMicrotask(_p._shrunk);
    } else {
      _leave.forward().then((_) => _p._shrunk());
    }
  }

  void _onPhase() {
    if (!mounted) return;
    if (_p._phase == _Phase.returning) {
      _press = null;
      _drag = null;
      if (MediaQuery.disableAnimationsOf(context)) {
        _return.value = 1;
        scheduleMicrotask(_p._grown);
      } else {
        _return.forward().then((_) => _p._grown());
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _p.removeListener(_onPhase);
    _leave.dispose();
    _return.dispose();
    super.dispose();
  }

  Offset _local(Offset global) => (context.findRenderObject()! as RenderBox).globalToLocal(global);

  /// A press that moves less than 6 points is a tap.
  void _down(PointerDownEvent event) {
    if (_p._phase != _Phase.bubble) return;
    _press = event.position;
    _moved = false;
  }

  void _move(PointerMoveEvent event) {
    final press = _press;
    if (press == null) return;
    if (!_moved && (event.position - press).distance < 6) return;
    _moved = true;
    setState(() => _drag = _local(event.position));
  }

  void _up(PointerUpEvent event) {
    final press = _press;
    _press = null;
    if (press == null) return;
    if (!_moved) return _p.restore();
    _p._dropAt(_local(event.position), MediaQuery.sizeOf(context));
    setState(() => _drag = null);
  }

  void _cancel(PointerCancelEvent event) {
    final drag = _drag;
    _press = null;
    if (drag != null) _p._dropAt(drag, MediaQuery.sizeOf(context));
    setState(() => _drag = null);
  }

  static double _clamp(double value) => value.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final theme = p.theme(context);
    final size = MediaQuery.sizeOf(context);
    final rest = p._rest(size, MediaQuery.paddingOf(context));
    final still = MediaQuery.disableAnimationsOf(context);
    final gone = p._phase == _Phase.bubble;
    final growing = p._phase == _Phase.returning || p._phase == _Phase.sheet;

    // The thread as the sheet held it: the safe area the sheet kept clear is
    // already outside [p._from], and Material is what the sheet's own
    // BottomSheet gave it.
    final thread = MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeLeft: true,
      removeRight: true,
      child: Material(type: MaterialType.transparency, child: p._seated(aloft: true)),
    );

    return Stack(
      children: [
        Positioned.fromRect(
          rect: p._from,
          // Not a control, and not read, while it is anywhere but the sheet.
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Offstage(
                offstage: gone,
                child: TickerMode(
                  enabled: !gone,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_leave, _return]),
                    child: thread,
                    builder: (context, child) {
                      // Elapsed milliseconds into whichever way it is going.
                      final double shrink;
                      final double opacity;
                      if (growing) {
                        final ms = _return.value * 480;
                        shrink = 1 - rendelEase.transform(_return.value);
                        opacity = rendelEase.transform(_clamp((ms - 140) / 300));
                      } else {
                        final ms = _leave.value * 660;
                        shrink = rendelEase.transform(_clamp(ms / 480));
                        opacity = 1 - Curves.easeIn.transform(_clamp((ms - 120) / 260));
                      }
                      final hero = theme.radius.hero;
                      return Transform.scale(
                        scale: lerpDouble(1, 0.12, shrink)!,
                        // Toward the bubble's centre, wherever it is.
                        origin: rest.center - p._from.center,
                        child: Opacity(
                          opacity: opacity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(lerpDouble(hero, 280, shrink)!),
                              bottom: Radius.circular(lerpDouble(0, 280, shrink)!),
                            ),
                            child: child,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: _drag != null || still ? Duration.zero : const Duration(milliseconds: 320),
          curve: rendelEase,
          left: (_drag?.dx ?? rest.center.dx) - RendelPresentation._size / 2,
          top: (_drag?.dy ?? rest.center.dy) - RendelPresentation._size / 2,
          width: RendelPresentation._size,
          height: RendelPresentation._size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_leave, _return]),
            builder: (context, child) {
              final double opacity;
              final double scale;
              if (growing) {
                final ms = _return.value * 480;
                opacity = 1 - rendelEase.transform(_clamp(ms / 220));
                scale = lerpDouble(1, 0.6, rendelEase.transform(_clamp(ms / 360)))!;
              } else {
                final ms = _leave.value * 660 - 300;
                opacity = rendelEase.transform(_clamp(ms / 220));
                scale = lerpDouble(0.6, 1, rendelEase.transform(_clamp(ms / 360)))!;
              }
              return Opacity(
                opacity: opacity,
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: Semantics(
              button: true,
              label: p.label,
              onTap: gone ? p.restore : null,
              excludeSemantics: true,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _cancel,
                child: _Bubble(theme: theme),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A · Nokta: the primary button's fill, the assistant's mark, and a dot that
/// says the answer is still there.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.theme});

  final RendelTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: theme.litFill,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            offset: Offset(0, 14),
            blurRadius: 30,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(child: Icon(Icons.auto_awesome, size: 20, color: theme.mark)),
          // 9 across, ringed in the fill it sits on.
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: theme.mark,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colors.accent, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
