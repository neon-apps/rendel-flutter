# Changelog

## 0.2.0

**Breaking**

- No more `firebase_messaging`. Remove `Firebase.initializeApp()` if you
  added it only for this package; an app that uses Firebase for itself keeps
  it, and Rendel sends through that project.
- iOS goes straight to Apple: upload the app's .p8 in Settings › Channels and
  give the Runner target the Push Notifications capability. No
  `GoogleService-Info.plist` and no APNs key in Firebase.
- `RendelPush.wire` (tests only) takes `RendelPushToken`s.

**Added**

- `RendelPush.requestPermission()`, to ask at a moment the person sees why
  (with `init(askPermission: false)`).
- `RendelPush.handleTap(context, data)`, for an app whose own code or push
  provider takes the taps.
- Android without `google-services.json`: the package starts Firebase with
  the options Rendel read from the service account. It declares
  `POST_NOTIFICATIONS` and a messaging service that steps aside for the app's
  own, and shows a Rendel push that arrives while the app is open.

## 0.1.0

- First version: permission, the token and its refreshes to
  `Rendel.setPushToken`, and taps on Rendel's pushes to `Rendel.handlePush`.
