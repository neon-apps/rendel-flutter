# rendel_push

Push notifications for [Rendel](https://rendel.ai) follow-ups. When something
a person asked your app for has news (a price that dropped, an answer that
arrived, a date coming up), Rendel can tell them while the app is closed; a
tap opens the conversation about it.

- **iOS: straight to Apple.** No Firebase: the package reads the device token
  itself, and Rendel sends with your app's Apple push key.
- **Android: Firebase Cloud Messaging, from Gradle.** No Dart-side Firebase
  package and no `google-services.json`: Rendel reads the project's options
  from your service account, and the package starts Firebase with them. An
  app that has Firebase keeps it.

This package asks for permission, hands the token and every refresh to
`Rendel.setPushToken`, and opens Rendel's own pushes with `Rendel.handlePush`.
A push that is not Rendel's is left to your app.

## Setup

1. In the Rendel console, Settings › Channels, drop in two files:
   - the Apple push key, `AuthKey_<Key ID>.p8` (developer.apple.com ›
     Certificates, IDs & Profiles › Keys › + › Apple Push Notifications
     service), and
   - the Firebase service account key (Firebase console › Project settings ›
     Service accounts › Generate new private key).
2. Add the package at the same tag as `rendel`:

```yaml
dependencies:
  rendel:
    git:
      url: https://github.com/neon-apps/rendel-flutter.git
      ref: v0.69.0
  rendel_push:
    git:
      url: https://github.com/neon-apps/rendel-flutter.git
      path: rendel_push
      ref: v0.69.0
```

3. After `Rendel.init(...)`:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

await RendelPush.init(navigatorKey: navigatorKey, askPermission: false);
runApp(MaterialApp(navigatorKey: navigatorKey, home: const Home()));

// When the person sees why (after sign-in, a first order):
await RendelPush.requestPermission();
```

4. iOS: give the Runner target the Push Notifications capability
   (`aps-environment` in `Runner.entitlements`) and `remote-notification` in
   `UIBackgroundModes`. Android needs nothing more.

If your app or a push provider's SDK handles notification taps itself, pass a
tapped notification's data on with `RendelPush.handleTap(context, data)`.
