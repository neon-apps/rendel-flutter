import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart'
    show CupertinoButton, CupertinoCheckbox, CupertinoListTile, CupertinoSwitch, CupertinoTabBar, CupertinoTextField;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'analytics.dart';
import 'log.dart';
import 'screens.dart';

/// Tap autocapture (design/plans/product-analytics.md §2.4): what the person
/// tapped, by kind of control, with its caption when it is a button, a link
/// or a tab, and a locator that stays the same across launches. Never what
/// was typed, never a row's text, never where on the screen.
///
/// One global pointer route sees every pointer without joining the gesture
/// arena; it keeps the hit path of a pointer that went down and, when it
/// comes up as a tap, leaves the reading for after the frame.

/// Gives the control under it a stable name: its locator and its label.
///
/// ```dart
/// RendelName('add_to_cart', child: FilledButton(onPressed: add, child: Text('Add')))
/// ```
class RendelName extends SingleChildRenderObjectWidget {
  const RendelName(this.name, {super.key, super.child});

  final String name;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMark(_Mark.name, name);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) => (renderObject as _RenderMark).name = name;
}

/// Taps under it are counted without any text: no label, whatever the
/// control says. For screens that show balances, names or messages.
class RendelMask extends SingleChildRenderObjectWidget {
  const RendelMask({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMark(_Mark.mask, null);
}

/// Taps under it are not counted at all.
class RendelIgnore extends SingleChildRenderObjectWidget {
  const RendelIgnore({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMark(_Mark.ignore, null);
}

enum _Mark { name, mask, ignore }

/// A proxy that draws and lays out nothing of its own: the hit path finds it.
class _RenderMark extends RenderProxyBox {
  _RenderMark(this.kind, this.name);

  final _Mark kind;
  String? name;
}

/// A pointer that went down, until it comes up.
class _Down {
  _Down(this.hits, this.at, this.time);

  final HitTestResult hits;
  final Offset at;
  final Duration time;
}

/// A tap, waiting to be read.
class _Tap {
  _Tap(this.hits, this.screen, this.rage, this.at);

  final HitTestResult hits;
  final String screen;
  final bool rage;
  final DateTime at;
}

class RendelTaps {
  RendelTaps._();

  static final RendelTaps instance = RendelTaps._();

  /// A tap is a pointer up within this long of its down…
  static const Duration tapWithin = Duration(milliseconds: 500);

  /// …three of them within this long, this close together, are rage.
  static const Duration rageWithin = Duration(seconds: 1);
  static const double ragePx = 30;
  static const int rageTaps = 3;

  /// Taps waiting to be read, at most; the oldest go first.
  static const int _maxPending = 50;

  /// Whether `init` attaches the route. Off under `flutter test`, where a
  /// task left on the scheduler at the end of a host's own widget test would
  /// fail it, as for [RendelScreens.timed].
  @visibleForTesting
  bool attachable = kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');

  /// The device id, for the sample.
  String? Function()? deviceId;

  bool _attached = false;
  final Map<int, _Down> _downs = {};
  final List<_Tap> _pending = [];
  final List<({Offset at, Duration time})> _recent = [];
  bool _scheduled = false;
  bool _toldNoScreen = false;
  ({String id, double share})? _sample;

  bool get attached => _attached;

  /// Starts seeing taps. Safe to call again.
  void attach() {
    if (_attached || !attachable) return;
    try {
      GestureBinding.instance.pointerRouter.addGlobalRoute(route);
      _attached = true;
      RendelScreens.instance.whenHidden(drain);
    } catch (_) {
      // No binding: `init` ran before `runApp` without ensureInitialized.
    }
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    try {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(route);
    } catch (_) {
      // The binding is gone with the route.
    }
  }

  /// Whether taps from this device are counted now.
  bool get _counting {
    final analytics = RendelAnalytics.instance;
    final capture = analytics.capture;
    if (!analytics.enabled || capture.taps == 'off') return false;
    if (capture.sample >= 1) return true;
    final id = deviceId?.call() ?? '';
    final sample = _sample?.id == id ? _sample! : (_sample = (id: id, share: sampleOf(id)));
    return sample.share < capture.sample;
  }

  /// The global route. Keeps what is under a pointer as it goes down and,
  /// when it comes up as a tap, queues it to be read after the frame.
  /// Nothing else happens here: it runs for every pointer event in the app.
  @visibleForTesting
  void route(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryMouseButton) return;
      if (!_counting) return;
      final hits = HitTestResult();
      GestureBinding.instance.hitTestInView(hits, event.position, event.viewId);
      _downs[event.pointer] = _Down(hits, event.position, event.timeStamp);
    } else if (event is PointerMoveEvent) {
      final down = _downs[event.pointer];
      if (down != null && (event.position - down.at).distance > kTouchSlop) _downs.remove(event.pointer);
    } else if (event is PointerUpEvent) {
      final down = _downs.remove(event.pointer);
      if (down == null) return;
      if ((event.position - down.at).distance > kTouchSlop || event.timeStamp - down.time > tapWithin) return;
      final screen = RendelScreens.instance.current;
      if (screen == null) {
        if (!_toldNoScreen) {
          _toldNoScreen = true;
          RendelLog.report(
            RendelLogLevel.debug,
            'taps_no_screen',
            'taps are counted on a screen: add Rendel.navigatorObserver to your navigator, or call Rendel.setScreen',
          );
        }
        return;
      }
      _pending.add(_Tap(down.hits, screen, _rage(event.position, event.timeStamp), DateTime.now()));
      if (_pending.length > _maxPending) _pending.removeAt(0);
      if (!_scheduled) {
        _scheduled = true;
        scheduleMicrotask(_afterFrame);
      }
    } else if (event is PointerCancelEvent) {
      _downs.remove(event.pointer);
    }
  }

  /// The third tap within a second and 30 px of the two before it, and any
  /// after. The points never leave the device.
  bool _rage(Offset at, Duration time) {
    _recent.removeWhere((tap) => time - tap.time > rageWithin);
    final near = _recent.where((tap) => (tap.at - at).distance <= ragePx).length;
    _recent.add((at: at, time: time));
    return near + 1 >= rageTaps;
  }

  /// Once the tap's own handlers have run: after the frame they asked for,
  /// or now when they asked for none, as a scheduler task.
  ///
  /// At animation priority rather than idle: an idle task waits for every
  /// animation to end, so a page popped by the tap (a back button) was
  /// already disposed when it ran, and a screen with a spinner never let it
  /// run at all, while the scheduler spun the event loop meanwhile.
  void _afterFrame() {
    final scheduler = SchedulerBinding.instance;
    void task() => scheduler.scheduleTask(drain, Priority.animation, debugLabel: 'rendel taps');
    if (scheduler.hasScheduledFrame || scheduler.schedulerPhase != SchedulerPhase.idle) {
      scheduler.addPostFrameCallback((_) => task());
    } else {
      task();
    }
  }

  /// Reads every tap waiting and queues what it found.
  void drain() {
    _scheduled = false;
    final taps = List.of(_pending);
    _pending.clear();
    for (final tap in taps) {
      try {
        final item = read(tap.hits, screen: tap.screen);
        if (item == null) continue;
        RendelScreens.instance.add({
          ...item,
          if (tap.rage) 'rage': true,
          'at': tap.at.toUtc().toIso8601String(),
        });
      } catch (err) {
        RendelLog.warn('tap_unreadable', 'a tap could not be read', error: err);
      }
    }
  }

  /// What a hit path says: the tap's item without its time, or null for a
  /// tap that is not counted.
  @visibleForTesting
  Map<String, dynamic>? read(HitTestResult hits, {required String screen}) {
    RenderObject? deepest;
    for (final entry in hits.path) {
      if (entry.target is RenderObject) {
        deepest = entry.target as RenderObject;
        break;
      }
    }
    if (deepest == null || !deepest.attached) return null;

    // The render objects from the finger up to the root, transforms
    // included (a transform hit-tests its child without adding itself).
    final up = <RenderObject>[for (RenderObject? o = deepest; o != null; o = o.parent) o];
    var mask = false;
    String? name;
    for (final o in up) {
      if (o is! _RenderMark) continue;
      switch (o.kind) {
        case _Mark.ignore:
          return null;
        case _Mark.mask:
          mask = true;
        case _Mark.name:
          name ??= o.name;
      }
    }

    final chain = _descend(up.toSet());
    var control = _control(chain, up);
    // A button or link that holds more than one text inside a list is the
    // row itself: its text is content.
    final render = control.render;
    if ((control.role == 'button' || control.role == 'link') &&
        render != null &&
        _inList(chain) &&
        _texts(render, stopAt: 2).length >= 2) {
      control = (role: 'row', element: control.element, render: render, fieldLabel: null);
    }
    final capture = RendelAnalytics.instance.capture;
    final textless = mask || capture.taps == 'no_text' || capture.mask.contains(screen);

    String? label;
    if (name != null && name.trim().isNotEmpty) {
      label = name;
    } else if (control.role == 'field') {
      label = control.fieldLabel;
    } else if (const {'button', 'link', 'tab'}.contains(control.role) && control.render != null) {
      label = _label(control.render!, up);
    }
    label = textless || label == null ? null : _clean(label, maxLabelChars);

    final locator = name != null && name.trim().isNotEmpty
        ? _clip(name.trim(), 200)
        : _locator(chain, control.element, control.role);
    return {
      'type': 'tap',
      'screen': screen,
      'role': name != null && control.role == 'other' && control.element == null ? 'button' : control.role,
      if (label != null && label.isNotEmpty) 'label': label,
      'locator': locator,
      'platform': platform,
    };
  }

  /// The platform as the protocol names it.
  static String get platform {
    if (kIsWeb) return 'flutter_web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux || TargetPlatform.fuchsia => 'linux',
    };
  }

  /// From the root element down, only into the child that holds the next
  /// render object on the path: some hundreds of elements, not the tree.
  /// Content shown through an [OverlayPortal] is not under its element here,
  /// so the walk stops at the overlay for it.
  List<Element> _descend(Set<RenderObject> path) {
    final chain = <Element>[];
    Element? at = WidgetsBinding.instance.rootElement;
    while (at != null) {
      chain.add(at);
      Element? next;
      at.visitChildren((child) {
        if (next == null && path.contains(child.renderObject)) next = child;
      });
      at = next;
    }
    return chain;
  }

  /// The control the tap was on: the nearest widget the SDK knows the kind
  /// of; else the nearest Semantics that says it can be tapped; else the
  /// nearest GestureDetector with a tap.
  ({String role, Element? element, RenderObject? render, String? fieldLabel}) _control(
    List<Element> chain,
    List<RenderObject> up,
  ) {
    for (var i = chain.length - 1; i >= 0; i--) {
      final widget = chain[i].widget;
      final role = _known(widget);
      if (role == null) continue;
      var element = chain[i];
      if (widget is EditableText) {
        // A TextField's or CupertinoTextField's own: the field is that one.
        for (var j = i - 1; j >= 0 && j >= i - 40; j--) {
          final outer = chain[j].widget;
          if (outer is TextField || outer is CupertinoTextField) {
            element = chain[j];
            break;
          }
        }
      }
      var render = element.renderObject;
      if (_isBar(widget) && render != null) {
        // A whole bar: the item under the finger is the outermost tappable
        // thing inside it.
        final bar = up.indexOf(render);
        for (var j = bar - 1; j >= 0; j--) {
          if (_tappable(up[j])) {
            render = up[j];
            break;
          }
        }
      }
      return (role: role, element: element, render: render, fieldLabel: role == 'field' ? _fieldLabel(element.widget) : null);
    }

    if (up.any((o) => o is RenderEditable)) {
      return (role: 'field', element: chain.isEmpty ? null : chain.last, render: null, fieldLabel: null);
    }

    // The nearest annotation that can be tapped, and the ones around it that
    // say what it is, up to the one that does.
    for (var i = 0; i < up.length; i++) {
      final o = up[i];
      if (o is! RenderSemanticsAnnotations || !_actionable(o.properties)) continue;
      var outer = o;
      var button = false, link = false, radio = false;
      bool? toggled, checked;
      var tap = false;
      for (var j = i; j < up.length; j++) {
        final a = up[j];
        // Past a render object that holds several things, it is no longer
        // this control.
        if (j > i && (a is RenderSliver || _children(a) > 1)) break;
        if (a is! RenderSemanticsAnnotations) continue;
        final p = a.properties;
        if (p.onTap != null) {
          if (tap && j != i) break;
          tap = true;
        }
        button |= p.button == true;
        link |= p.link == true;
        radio |= p.inMutuallyExclusiveGroup == true;
        toggled ??= p.toggled;
        checked ??= p.checked;
        outer = a;
        if (p.button == true || p.link == true || p.toggled != null || p.checked != null || a.container) break;
      }
      final element = _owner(chain, outer);
      final String role;
      if (toggled != null) {
        role = 'switch';
      } else if (checked != null) {
        role = radio ? 'radio' : 'checkbox';
      } else if (link) {
        role = 'link';
      } else if (button) {
        role = 'button';
      } else {
        role = _generic(outer, chain);
      }
      return (role: role, element: element, render: outer, fieldLabel: null);
    }

    for (var i = chain.length - 1; i >= 0; i--) {
      final widget = chain[i].widget;
      if (widget is GestureDetector && (widget.onTap != null || widget.onTapUp != null || widget.onTapDown != null)) {
        final render = chain[i].renderObject;
        return (role: render == null ? 'other' : _generic(render, chain), element: chain[i], render: render, fieldLabel: null);
      }
    }
    return (role: 'other', element: null, render: null, fieldLabel: null);
  }

  /// The kind of a control the SDK knows by its widget.
  static String? _known(Widget w) {
    if (w is TextField || w is CupertinoTextField || w is EditableText) return 'field';
    if (w is ListTile ||
        w is CheckboxListTile ||
        w is SwitchListTile ||
        w is RadioListTile ||
        w is CupertinoListTile ||
        w is ExpansionTile) {
      return 'row';
    }
    if (w is Tab || w is NavigationDestination || _isBar(w)) return 'tab';
    if (w is PopupMenuItem || w is MenuItemButton || w is SubmenuButton) return 'menuitem';
    if (w is DropdownMenuItem) return 'option';
    if (w is Switch || w is CupertinoSwitch) return 'switch';
    if (w is Checkbox || w is CupertinoCheckbox) return 'checkbox';
    if (w is Radio) return 'radio';
    if (w is ButtonStyleButton || w is IconButton || w is FloatingActionButton || w is CupertinoButton) return 'button';
    return null;
  }

  static int _children(RenderObject o) {
    var n = 0;
    o.visitChildren((_) => n++);
    return n;
  }

  static bool _isBar(Widget w) =>
      w is TabBar || w is BottomNavigationBar || w is NavigationBar || w is NavigationRail || w is CupertinoTabBar;

  static bool _actionable(SemanticsProperties p) =>
      p.button == true || p.link == true || p.toggled != null || p.checked != null || p.selected != null || p.onTap != null;

  static bool _tappable(RenderObject o) => o is RenderSemanticsAnnotations && _actionable(o.properties);

  /// A field's caption, never its value.
  static String? _fieldLabel(Widget w) => switch (w) {
        TextField(:final decoration) => decoration?.labelText ?? decoration?.hintText,
        CupertinoTextField(:final placeholder) => placeholder,
        _ => null,
      };

  /// The element that made [render], when the walk reached it.
  static Element? _owner(List<Element> chain, RenderObject render) {
    for (var i = chain.length - 1; i >= 0; i--) {
      if (chain[i] is RenderObjectElement && chain[i].renderObject == render) return chain[i];
    }
    return chain.isEmpty ? null : chain.last;
  }

  /// A tappable thing that does not say what it is: a button when it holds
  /// at most one text, else a row inside a list (its text is content) or
  /// something else outside one.
  static String _generic(RenderObject render, List<Element> chain) {
    if (_texts(render, stopAt: 2).length < 2) return 'button';
    return _inList(chain) ? 'row' : 'other';
  }

  static bool _inList(List<Element> chain) => chain.any((e) => e.widget is SliverMultiBoxAdaptorWidget);

  /// A button's, link's or tab's caption: a Semantics label or tooltip; else
  /// the text under it; else an icon's semantic label.
  static String? _label(RenderObject control, List<RenderObject> up) {
    String? semantic;
    String? icon;
    final texts = <String>[];
    _visit(control, (o) {
      if (o is RenderSemanticsAnnotations) {
        final p = o.properties;
        final said = _first(p.label, p.tooltip);
        if (said != null) {
          // An Icon is `Semantics(label:, child: ExcludeSemantics(glyph))`.
          if (o.child is RenderExcludeSemantics) {
            icon ??= said;
          } else {
            semantic ??= said;
          }
        }
      } else if (o is RenderParagraph) {
        final text = _plain(o);
        if (text.isNotEmpty) texts.add(text);
      }
    });
    // A caption given just around it: Semantics(label:) or a Tooltip.
    final at = up.indexOf(control);
    if (semantic == null && at >= 0) {
      for (var j = at + 1; j < up.length && j <= at + 6; j++) {
        final o = up[j];
        if (o is! RenderSemanticsAnnotations) continue;
        final p = o.properties;
        if (p.onTap != null || p.button == true) break;
        final said = _first(p.label, p.tooltip);
        if (said != null) {
          semantic = said;
          break;
        }
      }
    }
    if (semantic != null) return semantic;
    if (texts.isNotEmpty) return texts.join(' ');
    return icon;
  }

  static String? _first(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty) return a;
    if (b != null && b.trim().isNotEmpty) return b;
    return null;
  }

  /// The texts under [render], in order, icon glyphs left out.
  static List<String> _texts(RenderObject render, {int stopAt = 1 << 30}) {
    final texts = <String>[];
    _visit(render, (o) {
      if (o is RenderParagraph && texts.length < stopAt) {
        final text = _plain(o);
        if (text.isNotEmpty) texts.add(text);
      }
    });
    return texts;
  }

  /// [render] and what is under it, at most 300 render objects.
  static void _visit(RenderObject render, void Function(RenderObject o) visit) {
    final stack = <RenderObject>[render];
    var left = 300;
    while (stack.isNotEmpty && left-- > 0) {
      final o = stack.removeLast();
      visit(o);
      final children = <RenderObject>[];
      o.visitChildren(children.add);
      stack.addAll(children.reversed);
    }
  }

  /// A paragraph's words: no icon glyphs (the private use area), no
  /// placeholders for inline widgets.
  static String _plain(RenderParagraph paragraph) => paragraph.text
      .toPlainText(includeSemanticsLabels: false, includePlaceholders: false)
      .replaceAll(RegExp('[-￼]|[\u{F0000}-\u{10FFFF}]', unicode: true), '')
      .trim();

  static String _clean(String text, int max) =>
      _clip(maskText(text.replaceAll(RegExp(r'\s+'), ' ').trim()), max).trim();

  static String _clip(String text, int max) => text.length > max ? text.substring(0, max) : text;

  /// The control's place: a Key on it when it has one; else the public
  /// widget types from its screen's route down to it, layout and plumbing
  /// left out, list positions never in it.
  static String _locator(List<Element> chain, Element? control, String role) {
    final end = control == null ? chain.length - 1 : chain.lastIndexOf(control);
    if (end < 0) return role;
    final render = control?.renderObject;
    // A Key on the control, or on a widget of the app's that is nothing but
    // the control.
    for (var i = end; i >= 0 && render != null && chain[i].renderObject == render; i--) {
      final key = chain[i].widget.key;
      if (key is ValueKey<String> && _stableKey(key.value)) return _clip(key.value, 200);
    }
    var start = 0;
    for (var i = end; i >= 0; i--) {
      if (chain[i].widget is Navigator) {
        start = i + 1;
        break;
      }
    }
    final types = <String>[];
    for (var i = start; i <= end; i++) {
      final widget = chain[i].widget;
      if (widget is! StatelessWidget && widget is! StatefulWidget) continue;
      final type = widget.runtimeType.toString().split('<').first;
      if (type.startsWith('_') || _plumbing(type)) continue;
      if (types.isNotEmpty && types.last == type) continue;
      types.add(type);
    }
    if (types.isEmpty) return role;
    while (types.length > 2 && types.join(' > ').length > 200) {
      types.removeAt(1);
    }
    return _clip(types.join(' > '), 200);
  }

  /// A key that names the control, not an item: no ids, nothing personal.
  static bool _stableKey(String value) =>
      value.isNotEmpty && value.length <= 200 && maskText(value) == value && screenName('/$value') == '/$value';

  /// Widgets that place, paint or wire things rather than being something.
  static bool _plumbing(String type) =>
      _plumbingTypes.contains(type) ||
      type.startsWith('Animated') ||
      type.startsWith('Default') ||
      type.startsWith('Primary') ||
      type.endsWith('Transition') ||
      type.endsWith('Builder') ||
      type.endsWith('Scope') ||
      type.endsWith('Region') ||
      type.endsWith('Listener') ||
      type.endsWith('Theme') ||
      type.endsWith('Provider') ||
      type.endsWith('Notifier');

  static const Set<String> _plumbingTypes = {
    'Actions',
    'InputDecorator',
    'MaterialApp',
    'CupertinoApp',
    'NavigationToolbar',
    'RawView',
    'ScrollNotificationObserver',
    'SharedAppData',
    'StretchEffect',
    'TextSelectionGestureDetector',
    'View',
    'WidgetsApp',
    'AutomaticKeepAlive',
    'BackButtonListener',
    'Card',
    'Center',
    'Consumer',
    'Container',
    'Directionality',
    'Focus',
    'FocusTrap',
    'FocusTrapArea',
    'FocusTraversalGroup',
    'GestureDetector',
    'GlowingOverscrollIndicator',
    'Hero',
    'Icon',
    'IconTheme',
    'Image',
    'Ink',
    'InkResponse',
    'InkWell',
    'KeyedSubtree',
    'Localizations',
    'Material',
    'MediaQuery',
    'ModalBarrier',
    'NavigatorPopHandler',
    'NotificationListener',
    'Overlay',
    'PageStorage',
    'PopScope',
    'RawGestureDetector',
    'RawMaterialButton',
    'RawScrollbar',
    'RepaintBoundary',
    'Scrollable',
    'Scrollbar',
    'CupertinoScrollbar',
    'SafeArea',
    'ScrollConfiguration',
    'Selector',
    'SelectableRegion',
    'SelectionArea',
    'SelectionContainer',
    'Semantics',
    'Shortcuts',
    'SliverSafeArea',
    'SnapshotWidget',
    'StretchingOverscrollIndicator',
    'Text',
    'Title',
    'TickerMode',
    'Tooltip',
    'Visibility',
    'WillPopScope',
  };

  /// For `Rendel.resetForTest`.
  void resetForTest() {
    detach();
    attachable = kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');
    deviceId = null;
    _downs.clear();
    _pending.clear();
    _recent.clear();
    _scheduled = false;
    _toldNoScreen = false;
    _sample = null;
  }
}
