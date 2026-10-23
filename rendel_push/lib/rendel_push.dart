/// Push notifications for Rendel follow-ups, on Firebase Cloud Messaging.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:rendel/rendel.dart';

/// Wires Firebase Cloud Messaging to Rendel: asks for permission, hands the
/// token and every refresh to `Rendel.setPushToken`, and opens Rendel's own
/// pushes when they are tapped, the one that launched the app included. A
/// push that is not Rendel's is left to the app.
///
/// After `Firebase.initializeApp()` and `Rendel.init(...)`:
///
/// ```dart
/// final navigatorKey = GlobalKey<NavigatorState>();
/// await RendelPush.init(navigatorKey: navigatorKey);
/// runApp(MaterialApp(navigatorKey: navigatorKey, home: const Home()));
/// ```
class RendelPush {
  RendelPush._();

  static final List<StreamSubscription<Object?>> _subscriptions = [];

  /// [askPermission] false leaves the prompt to the app: the token is sent
  /// only once the app has been allowed to notify.
  static Future<void> init({required GlobalKey<NavigatorState> navigatorKey, bool askPermission = true}) {
    final messaging = FirebaseMessaging.instance;
    return wire(
      allowed: () async {
        final settings = askPermission ? await messaging.requestPermission() : await messaging.getNotificationSettings();
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      },
      // The registration token and its refreshes, which Rendel's server sends
      // to (FCM HTTP v1 `message.token`). 17.0 deprecates them for
      // `register()` / `onRegistered`, whose installation id is a different
      // send target; they move together with the server.
      // ignore: deprecated_member_use
      token: messaging.getToken,
      // ignore: deprecated_member_use
      refreshes: messaging.onTokenRefresh,
      taps: FirebaseMessaging.onMessageOpenedApp.map((message) => message.data),
      launchTap: () async => (await messaging.getInitialMessage())?.data,
      context: () => insideNavigator(navigatorKey),
    );
  }

  /// [init]'s wiring, with each source passed in.
  @visibleForTesting
  static Future<void> wire({
    required Future<bool> Function() allowed,
    required Future<String?> Function() token,
    required Stream<String> refreshes,
    required Stream<Map<String, dynamic>> taps,
    required Future<Map<String, dynamic>?> Function() launchTap,
    required BuildContext? Function() context,
  }) async {
    await stop();
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
    final current = await token();
    if (current != null) await Rendel.setPushToken(current);
    _subscriptions.add(refreshes.listen((next) => unawaited(Rendel.setPushToken(next))));
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

  static void _open(BuildContext? Function() context, Map<String, dynamic> data) {
    final at = context();
    if (at != null) unawaited(Rendel.handlePush(at, data));
  }
}
