import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

/// Which screen of the app the person is on (design/plans/screens-goals.md):
/// a view for every screen the app shows, whether or not Rendel is opened,
/// and the name each turn carries as `context.current_screen`. The screen's
/// name only, with its ids taken out. Never a tap.
///
/// The rules are the web SDK's (`sdk/web/src/screens.ts`), so a screen is
/// called the same thing whichever SDK counted it.

/// The server keeps 120 characters of a name.
const int maxScreenName = 120;

/// Views wait at most this long to go, and go at once at this many (the
/// server takes 50).
const Duration _flushEvery = Duration(seconds: 15);
const int _batch = 40;

/// What waits for `init` at most: one batch the server takes whole. The
/// oldest go first.
const int _held = 50;

/// A route pushed this soon after Rendel opened a registered screen is that
/// screen.
const Duration _openedWithin = Duration(seconds: 2);

/// A segment that names one thing rather than a kind of screen.
final List<RegExp> _ids = [
  RegExp(r'^\d+$'),
  RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false),
  RegExp(r'^[0-9a-f]{16,}$', caseSensitive: false),
  RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$'),
];

/// A long run of letters and digits that is not words joined by dashes: a
/// token, a cuid, a nanoid.
bool _token(String s) =>
    s.length >= 20 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s) &&
    RegExp(r'\d').hasMatch(s) &&
    RegExp(r'[A-Za-z]').hasMatch(s) &&
    !RegExp(r'^[a-z]+(?:[-_][a-z0-9]+)*$').hasMatch(s);

bool _isId(String segment) {
  var text = segment;
  try {
    text = Uri.decodeComponent(segment);
  } catch (_) {
    // Not valid percent-encoding: read it as it is.
  }
  return _ids.any((id) => id.hasMatch(text)) || _token(text);
}

String _clip(String name) => name.length > maxScreenName ? name.substring(0, maxScreenName) : name;

/// A route's name as a screen's: a path has each id replaced by `:id`, its
/// query and fragment dropped and a trailing slash trimmed, so
/// `/orders/8812/?tab=2` is `/orders/:id`. Any other name (`orderDetail`) is
/// kept as it is. At most 120 characters; null for no name.
String? screenName(String? routeName) {
  final name = routeName?.trim() ?? '';
  if (name.isEmpty) return null;
  if (!name.startsWith('/')) return _clip(name);
  final path = name.split(RegExp('[?#]')).first;
  final named = path
      .split('/')
      .map((segment) => segment.isNotEmpty && _isId(segment) ? ':id' : segment)
      .join('/')
      .replaceFirst(RegExp(r'/+$'), '');
  return _clip(named.isEmpty ? '/' : named);
}

/// The screen on top of the app's navigator, the views waiting to go, and
/// when they go.
class RendelScreens {
  RendelScreens._();

  static final RendelScreens instance = RendelScreens._();

  /// Sends one batch to `/v1/events`, fire and forget: a batch that did not
  /// land is only a count. Wired by `init` once the client has its device
  /// id; until then views wait, so nothing leaves before it.
  void Function(List<Map<String, dynamic>> views)? _send;

  set send(void Function(List<Map<String, dynamic>> views)? send) {
    _send = send;
    if (send != null && _queue.isNotEmpty) _queued();
  }

  /// Whether views wait on the 15-second timer. Off under `flutter test`, as
  /// the default store is memory there: a timer the test clock was never told
  /// about fails a host's own widget test that has the observer and calls
  /// `init`. They still go at 40 and when the app goes to the background.
  @visibleForTesting
  bool timed = !Platform.environment.containsKey('FLUTTER_TEST');

  /// The navigator's pages, bottom first, as the observer saw them come and
  /// go. Dialogs, sheets and menus are not among them (Rendel's own sheet
  /// included): the screen under one is still the screen.
  final List<Route<dynamic>> _pages = [];

  /// The page on top of [_pages] when it was last looked at.
  Route<dynamic>? _top;

  /// [_top]'s name as a screen's.
  String? _auto;

  /// The name the app gave the screen on top, or the title of a registered
  /// screen Rendel opened there. Kept on the route itself, so going back to
  /// a screen goes back to its name: a screen that names itself in
  /// `initState` is not built again on the way back.
  String? _named;
  final Expando<String> _names = Expando('rendel screen name');

  /// The titles of registered screens, by the route name each opened on.
  final Map<String, String> _titles = {};
  ({String title, DateTime at})? _opened;

  /// The last screen counted, so the same screen twice in a row is one view.
  String? _last;
  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  bool _settling = false;
  AppLifecycleListener? _lifecycle;

  /// The name a turn carries: the app's own, else the route's. Null on a
  /// route with no name the app did not name either.
  String? get current => _named ?? _auto;

  void pushed(Route<dynamic> route) {
    if (route is! PageRoute) return;
    _pages.add(route);
    _look(arrived: true);
  }

  /// Popped or removed: the page under it is on top again if it was on top.
  void removed(Route<dynamic> route) {
    if (_pages.remove(route)) _look();
  }

  void replaced(Route<dynamic>? oldRoute, Route<dynamic>? newRoute) {
    final at = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (at >= 0) _pages.removeAt(at);
    if (newRoute is PageRoute) _pages.insert(at >= 0 ? at : _pages.length, newRoute);
    _look(arrived: true);
  }

  /// [arrived] when the page on top may be one that was just pushed or put
  /// in another's place, rather than uncovered.
  void _look({bool arrived = false}) {
    final route = _pages.isEmpty ? null : _pages.last;
    if (identical(route, _top)) return;
    _top = route;
    if (route == null) {
      _auto = _named = null;
      return;
    }
    final auto = screenName(route.settings.name);
    final opened = _opened;
    if (arrived && opened != null && DateTime.now().difference(opened.at) < _openedWithin) {
      _opened = null;
      _names[route] = opened.title;
      if (auto != null) _titles[auto] = opened.title;
    }
    _auto = auto == null ? null : _titles[auto] ?? auto;
    _named = _names[route];
    _settle();
  }

  /// `Rendel.setScreen`: the screen on top is called [name] until the app
  /// says otherwise; null hands it back to the route's name.
  void name(String? name) {
    _named = name;
    final top = _top;
    if (top != null) _names[top] = name;
    _settle();
  }

  /// Rendel is opening a registered screen: the route that arrives next is
  /// called by its [title], then and later.
  void opening(String title) => _opened = (title: title, at: DateTime.now());

  /// Counted at the end of the frame, so a push and the `setScreen` the new
  /// screen calls as it is first built are one view and not two.
  void _settle() {
    if (_settling) return;
    try {
      final binding = WidgetsBinding.instance;
      _settling = true;
      binding.addPostFrameCallback((_) {
        if (_settling) _record();
      });
      binding.ensureVisualUpdate();
    } catch (_) {
      // No binding yet: `setScreen` before `runApp`. Counted now.
      _settling = false;
      _record();
    }
  }

  void _record() {
    _settling = false;
    final screen = current;
    if (screen == null || screen == _last) return;
    _last = screen;
    _queue.add({'type': 'screen_view', 'screen': screen, 'at': DateTime.now().toUtc().toIso8601String()});
    if (_queue.length > _held) _queue.removeAt(0);
    _listen();
    _queued();
  }

  void _queued() {
    if (_queue.length >= _batch) {
      flush();
    } else if (timed && _send != null) {
      _timer ??= Timer(_flushEvery, flush);
    }
  }

  /// Sends what is waiting, if `init` has run.
  void flush() {
    _timer?.cancel();
    _timer = null;
    final send = _send;
    if (send == null || _queue.isEmpty) return;
    final views = List.of(_queue);
    _queue.clear();
    try {
      send(views);
    } catch (_) {
      // Only a count.
    }
  }

  /// Out of sight, where the app may never come back: what is waiting
  /// leaves now.
  void _listen() {
    if (_lifecycle != null) return;
    try {
      _lifecycle = AppLifecycleListener(onStateChange: (state) {
        if (state != AppLifecycleState.hidden && state != AppLifecycleState.paused) return;
        if (_settling) _record();
        flush();
      });
    } catch (_) {
      // No binding yet. The next view listens.
    }
  }

  /// For `Rendel.resetForTest`.
  void resetForTest() {
    _send = null;
    timed = !Platform.environment.containsKey('FLUTTER_TEST');
    _pages.clear();
    _top = null;
    _auto = null;
    _named = null;
    _titles.clear();
    _opened = null;
    _last = null;
    _queue.clear();
    _timer?.cancel();
    _timer = null;
    _settling = false;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}

/// `Rendel.navigatorObserver`: tells [RendelScreens] which pages come and go.
class RendelNavigatorObserver extends NavigatorObserver {
  RendelScreens get _screens => RendelScreens.instance;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _screens.pushed(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _screens.removed(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _screens.removed(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _screens.replaced(oldRoute, newRoute);
}
