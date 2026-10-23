# rendel

Rendel is a Generative UI SDK for Flutter and web apps. It turns what users
say, type and tap into native screens in your app: it answers with your own
native widgets rather than a wall of text, and it runs the functions you
register rather than describing what it would do, while your team controls
every action.

It does not chat about your app. It operates it.

```yaml
dependencies:
  rendel:
    git:
      url: https://github.com/neon-apps/rendel-flutter.git
      ref: v0.58.5
```

## Three lines to a running assistant

```dart
await Rendel.init(
  // Your app's key: Rendel console → Settings → API keys → Copy.
  appKey: 'rd_pk_test_...',
  // The languages Rendel answers in: ['tr'] is Turkish only,
  // ['tr', 'en'] Turkish or English. Leave out config for any language.
  config: RendelConfig(languages: ['tr']),
);

Rendel.registerAction(RendelAction(
  name: 'get_order_status',
  description: 'Fetch the delivery status of an order',
  params: RendelSchema.object({'order_id': RendelSchema.string()}),
  risk: RendelRisk.read,
  handler: (params) async {
    final order = await api.fetchOrder(params['order_id']);
    return RendelResult.ok(order.toJson());
  },
));

// Anywhere you want the entry point:
const RendelLauncher();
```

Ask "where is my order 1042?" and Rendel calls your handler, then renders
the answer as an `order_tracker` component in your own colours and type.

## Reaching your API as the person asking

If people sign in to your app, give the SDK their current token. Rendel
then calls your own endpoints — "my routine", "my orders" — as that person,
with no API key for you to issue:

```dart
await Rendel.init(
  // Your app's key: Rendel console → Settings → API keys → Copy.
  appKey: 'rd_pk_test_...',
  config: RendelConfig(
    languages: ['tr'],
    userToken: () async => auth.accessToken, // your own sign-in
  ),
);
```

It is asked for before every question, so return the current one — your auth
code refreshes it when it runs out — and `null` when nobody is signed in. It is
sent on to your endpoints the way their document says, never stored, and each
person reaches only what their own token opens. In the console, add the
endpoints under Actions → Add source; the ones that want a signed-in person are
reached this way on their own.

## Platform permissions

The composer's microphone and its "+" — Photos, Camera and Files — are built
in (`image_picker`, `speech_to_text`, and the SDK's own document picker).
Photos and Files need no permission on either platform.

**iOS — required for the microphone and the camera.** Open
`ios/Runner/Info.plist` and add these inside the top-level `<dict>`, in your
own words; Apple shows them to your users in your app's name, so no package
can add them. Until they are there the SDK leaves the microphone or Camera
out instead of letting iOS close the app.

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Lets you speak to the assistant instead of typing.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Turns what you say into text for the assistant.</string>
<key>NSCameraUsageDescription</key>
<string>Lets you take a photo to show the assistant.</string>
```

**Android — already done by the SDK.** Its manifest declares these and the
build merges them into `android/app/src/main/AndroidManifest.xml`; adding them
there yourself, inside `<manifest>` above `<application>`, changes nothing.

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

**Maps.** The `map` component draws with
[`maplibre_gl`](https://pub.dev/packages/maplibre_gl) 0.27, over
OpenFreeMap's open map data (no key, no account). It asks for no permission
and no Info.plist or manifest line: Rendel never asks where the user is.
What it does need from your build:

- **iOS**: a deployment target of 13.0 or later, which the SDK already needs.
  CocoaPods or Swift Package Manager fetches MapLibre Native (6.28) on the
  next `pod install` or build.
- **Android**: `minSdk` 24, which the SDK already needs (MapLibre itself asks
  for 21). The plugin compiles against SDK 36 with Java 21, so build with
  JDK 21; JDK 17 fails with `invalid source release: 21`. It also names NDK
  28.2.13676358: if Flutter warns that your app's NDK differs, set
  `ndkVersion = "28.2.13676358"` in `android/app/build.gradle(.kts)`.
- **Web**: `maplibre_gl` loads MapLibre GL JS from unpkg.com unless
  `MapLibreMap.webLibrarySource` points at a copy you host.

Where the map cannot load (no network, a desktop build), the component lists
its places instead, each still opening in the maps app.

Create an app and a publishable key in the
[console](https://rendel.ai/console). Test keys
(`rd_pk_test_...`, or `nc_pk_test_...` from before the rename) are never billed.

## What it can do, and what it may do

An action carries a risk level, and the risk level decides what has to happen
before it runs:

| Risk | Behaviour |
| --- | --- |
| `read` | Runs when Rendel asks. Order status, balances, availability. |
| `write` | Proposed. Our servers build a confirmation card from your `confirmTemplate` and the parameters they validated, and your handler runs only after the user says yes. |
| `destructive` | The same, with an irreversible warning and nothing pre-selected. |

The confirmation card is never model output, and Rendel holds no
privileges of its own: your handler executes inside your app, on the user's
own session, against your own backend.

```dart
Rendel.registerAction(RendelAction(
  name: 'cancel_order',
  description: 'Cancel an order that has not shipped yet',
  params: RendelSchema.object({'order_id': RendelSchema.string()}),
  risk: RendelRisk.destructive,
  confirmTemplate: 'Cancel order {order_id}? This cannot be undone.',
  handler: (params) => api.cancelOrder(params['order_id']),
));
```

## Making it yours

```dart
await Rendel.init(
  appKey: 'rd_pk_live_...',
  theme: RendelTheme.fromTokens(
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF14110F),
    accent: const Color(0xFF2F6BFF),
    onAccent: const Color(0xFFFFFFFF),
  ),
  config: const RendelConfig(assistantName: 'Kicks'),
);
```

Every component in the catalog derives from those four colours, and the
derivation is checked for contrast: a palette the SDK cannot make legible is
refused rather than shipped to your users. Appearance and the opening surface
can also be published from the console without an app store release.

Live app state reaches the model only if you send it:

```dart
Rendel.addContextProvider('cart', () async => cart.toJson());
```

## Documentation

- [Quickstart](https://rendel.ai/docs)
- [Actions and risk levels](https://rendel.ai/docs/concepts/actions)
- [The component catalog](https://rendel.ai/docs/reference/components)
- [Theming](https://rendel.ai/docs/guides/theming)
- [Go-live checklist](https://rendel.ai/docs/guides/go-live)

Requires Dart 3.7 and Flutter 3.29 or newer.
