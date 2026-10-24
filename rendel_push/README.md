# rendel_push

Push notifications for [Rendel](https://rendel.ai) follow-ups, on Firebase
Cloud Messaging. When something a person asked your app for has news (a
price that dropped, an answer that arrived, a date coming up), Rendel can tell
them while the app is closed; a tap opens the conversation about it.

This package asks for permission, hands the token and every refresh to
`Rendel.setPushToken`, and opens Rendel's own pushes with `Rendel.handlePush`.
A push that is not Rendel's is left to your app.

## Setup

1. Add Firebase to your app and `firebase_messaging` as its docs say. On iOS,
   upload your APNs key to Firebase.
2. In the Rendel console, upload the Firebase service account key in
   Settings › Channels.
3. Add the package at the same tag as `rendel`:

```yaml
dependencies:
  rendel:
    git:
      url: https://github.com/neon-apps/rendel-flutter.git
      ref: v0.59.7
  rendel_push:
    git:
      url: https://github.com/neon-apps/rendel-flutter.git
      path: rendel_push
      ref: v0.59.7
```

4. After `Firebase.initializeApp()` and `Rendel.init(...)`:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

await RendelPush.init(navigatorKey: navigatorKey);
runApp(MaterialApp(navigatorKey: navigatorKey, home: const Home()));
```

Pass `askPermission: false` if your app asks for notification permission
itself; the token is then sent once it has been granted.
