/// Push notifications for Rendel follow-ups: straight to Apple on iOS, Firebase
/// Cloud Messaging on Android.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rendel/rendel.dart';

/// A device's push token, and on iOS what Apple needs to know about it.
@immutable
class RendelPushToken {
  const RendelPushToken(this.token, {this.apns, this.androidPackage});

  final String token;

  /// Set for an iOS device token, which Rendel sends straight to Apple.
  final RendelApnsToken? apns;

  /// The Android app a Firebase token belongs to.
  final String? androidPackage;
}

/// Wires the device's push to Rendel: asks for permission, hands the token and
/// every refresh to `Rendel.setPushToken`, and opens Rendel's own pushes when
/// they are tapped, the one that launched the app included. A push that is not
/// Rendel's is left to the app.
///
/// - **iOS**: the device token from Apple, no Firebase. The app needs the Push
///   Notifications capability; Rendel sends with the .p8 key uploaded in
///   Settings › Channels.
/// - **Android**: Firebase Cloud Messaging, from Gradle. An app with no Firebase
///   of its own needs no `google-services.json`: Rendel reads the project's
///   options from the service account uploaded in Settings › Channels, and
///   this package starts Firebase with them. An app that has Firebase already
///   keeps its own, and the token is that project's.
///
/// After `Rendel.init(...)`:
///
/// ```dart
/// final navigatorKey = GlobalKey<NavigatorState>();
/// await RendelPush.init(navigatorKey: navigatorKey);
/// runApp(MaterialApp(navigatorKey: navigatorKey, home: const Home()));
/// ```
class RendelPush {
  RendelPush._();

  static const MethodChannel _channel = MethodChannel('rendel/push');
  static final List<StreamSubscription<Object?>> _subscriptions = [];
  static final StreamController<RendelPushToken> _tokens = StreamController.broadcast();
  static final StreamController<Map<String, dynamic>> _taps = StreamController.broadcast();
  static bool _listening = false;
  static Future<RendelPushToken?> Function()? _token;

  /// [askPermission] false leaves the prompt to the app or to a better moment
  /// ([requestPermission]): the token is sent only once the app may notify.
  static Future<void> init({required GlobalKey<NavigatorState> navigatorKey, bool askPermission = true}) {
    _listen();
    return wire(
      allowed: () => _allowed(ask: askPermission),
      token: _nativeToken,
      refreshes: _tokens.stream,
      taps: _taps.stream,
      launchTap: () async => _strings(await _channel.invokeMethod<Object?>('launchTap')),
      context: () => insideNavigator(navigatorKey),
    );
  }

  /// Asks for notification permission now, at a moment the person sees why
  /// (after Rendel was first useful to them, say), and hands the token to
  /// Rendel once it is granted. True when the app may notify. Call [init] first.
  static Future<bool> requestPermission() async {
    final allowed = await _allowed(ask: true);
    if (!allowed) {
      await Rendel.setPushToken(null);
      return false;
    }
    await _send(await (_token ?? _nativeToken)());
    return true;
  }

  /// For an app whose own push code receives the notifications (another
  /// provider's SDK that takes the taps): hand Rendel's tapped push over.
  /// True when it was Rendel's and opened.
  static Future<bool> handleTap(BuildContext context, Map<String, dynamic> data) => Rendel.handlePush(context, data);

  /// [init]'s wiring, with each source passed in.
  @visibleForTesting
  static Future<void> wire({
    required Future<bool> Function() allowed,
    required Future<RendelPushToken?> Function() token,
    required Stream<RendelPushToken> refreshes,
    required Stream<Map<String, dynamic>> taps,
    required Future<Map<String, dynamic>?> Function() launchTap,
    required BuildContext? Function() context,
  }) async {
    await stop();
    _token = token;
    // Taps before the token: a push that launched the app opens even when no
    // token can be had.
    _subscriptions.add(taps.listen((data) => _open(context, data)));
    final launched = await launchTap();
    if (launched != null) {
      // Before the first frame there is no navigator to open it in.
      if (context() != null) {
        _open(context, launched);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _open(context, launched));
      }
    }
    if (!await allowed()) {
      // Notifications off: Rendel sends none until a token comes back.
      await Rendel.setPushToken(null);
      return;
    }
    await _send(await token());
    _subscriptions.add(refreshes.listen((next) => unawaited(_send(next))));
  }

  /// Stops listening for taps and token refreshes.
  static Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  /// A context inside one of the navigator's routes, where the thread can be
  /// presented: the key's own context, and its overlay's, are both above the
  /// overlay the thread goes into.
  @visibleForTesting
  static BuildContext? insideNavigator(GlobalKey<NavigatorState> navigatorKey) {
    Element? inside;
    void visit(Element element) {
      if (inside != null) return;
      if (Overlay.maybeOf(element) != null) {
        inside = element;
      } else {
        element.visitChildElements(visit);
      }
    }

    navigatorKey.currentState?.overlay?.context.visitChildElements(visit);
    return inside;
  }

  /// What the native side says without being asked: a tap, and a new token.
  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'tap':
          final data = _strings(call.arguments);
          if (data != null) _taps.add(data);
        case 'token':
          final token = _tokenOf(call.arguments);
          if (token != null) _tokens.add(token);
      }
      return null;
    });
  }

  static Future<bool> _allowed({required bool ask}) async =>
      await _channel.invokeMethod<bool>('permission', {'ask': ask}) ?? false;

  /// The device's token from the native side. On Android with no Firebase of
  /// its own, Rendel's options for this package first.
  static Future<RendelPushToken?> _nativeToken() async {
    Map<String, String>? options;
    if (defaultTargetPlatform == TargetPlatform.android && await _channel.invokeMethod<bool>('hasFirebase') != true) {
      final package = await _channel.invokeMethod<String>('package');
      options = package == null ? null : await Rendel.pushFirebaseOptions(package);
      if (options == null) {
        RendelLog.warn('push_not_set_up', 'Push is not set up for this app in Settings › Channels yet; no token was sent');
        return null;
      }
    }
    try {
      return _tokenOf(await _channel.invokeMethod<Object?>('token', {'firebase': options}));
    } on PlatformException catch (e) {
      RendelLog.warn('push_token', e.message ?? e.code);
      return null;
    }
  }

  static Future<void> _send(RendelPushToken? token) async {
    if (token != null) await Rendel.setPushToken(token.token, apns: token.apns, androidPackage: token.androidPackage);
  }

  static RendelPushToken? _tokenOf(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['token'];
    if (token is! String || token.isEmpty) return null;
    final apns = raw['provider'] == 'apns'
        ? RendelApnsToken(
            environment: raw['environment'] == 'sandbox' ? 'sandbox' : 'production',
            bundleId: raw['bundleId'] as String?,
            teamId: raw['teamId'] as String?,
          )
        : null;
    return RendelPushToken(token, apns: apns, androidPackage: apns == null ? raw['bundleId'] as String? : null);
  }

  static Map<String, dynamic>? _strings(Object? raw) =>
      raw is Map ? {for (final e in raw.entries) '${e.key}': e.value} : null;

  static void _open(BuildContext? Function() context, Map<String, dynamic> data) {
    final at = context();
    if (at != null) unawaited(Rendel.handlePush(at, data));
  }
}
