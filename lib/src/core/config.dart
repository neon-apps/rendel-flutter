import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'log.dart';
import 'remote_config.dart';
import 'strings.dart';
import 'version.dart' as version;

/// The glyph on the composer's attachment control.
///
/// A closed set and never an image, here and on the wire alike. An icon a
/// device fetches from an address in a published payload is a tracking pixel
/// aimed at somebody else's users, and an icon a device renders from vector
/// data in a published payload is worse. A name maps to a glyph this package
/// already ships, or to nothing.
///
/// [off] is the honest answer for an app that will never take a picture: the
/// control is drawn disabled until the feature lands, and a bank that has no
/// intention of accepting a photograph should be able to say so rather than
/// show a paperclip that stays grey forever.
enum RendelAttachIcon {
  paperclip('paperclip'),
  image('image'),
  plus('plus'),
  off('off');

  const RendelAttachIcon(this.wireName);

  final String wireName;

  static RendelAttachIcon? fromName(String? name) {
    for (final value in RendelAttachIcon.values) {
      if (value.wireName == name) return value;
    }
    return null;
  }
}

/// The glyph on the composer's voice control. Same rule, same [off].
enum RendelVoiceIcon {
  microphone('microphone'),
  waveform('waveform'),
  off('off');

  const RendelVoiceIcon(this.wireName);

  final String wireName;

  static RendelVoiceIcon? fromName(String? name) {
    for (final value in RendelVoiceIcon.values) {
      if (value.wireName == name) return value;
    }
    return null;
  }
}

/// The glyph on the send button.
///
/// No `off`: it is the one thing the composer is for, and a message box with
/// no way to send a message is not a configuration anybody means.
enum RendelSendIcon {
  arrowUp('arrow-up'),
  paperPlane('paper-plane'),
  arrowRight('arrow-right');

  const RendelSendIcon(this.wireName);

  final String wireName;

  static RendelSendIcon? fromName(String? name) {
    for (final value in RendelSendIcon.values) {
      if (value.wireName == name) return value;
    }
    return null;
  }
}

/// Which of the copilot's two themes is drawn.
///
/// The SDK's own enum rather than Flutter's `ThemeMode`, because this file is
/// read without a widget in sight and the three answers are the same three.
/// A host whose `MaterialApp` already has a `themeMode` passes it across in
/// one line: `RendelThemeMode.values.byName(themeMode.name)`.
enum RendelThemeMode {
  /// The device's own setting, followed as it changes. The default.
  system,

  /// Always the light theme, whatever the device says.
  light,

  /// Always the dark theme.
  dark,
}

/// Everything about a copilot that is the host's choice rather than the
/// protocol's: where it points, what it is called, and how long it waits.
///
/// Several of these fields are also publishable from the console, where they
/// become the *default* and this object becomes the floor. See
/// [RendelRemoteConfig] for what may be overridden and what never can.
class RendelConfig {
  const RendelConfig({
    // Since 0.31.0. The old host, neon-copilot-api.vercel.app, is the same
    // deployment and keeps answering for builds that shipped with it.
    this.apiBaseUrl = 'https://api.rendel.ai',
    this.requestTimeout = const Duration(seconds: 30),
    this.sdkVersion = version.sdkVersion,
    this.locale,
    this.languages = const [],
    this.assistantName = 'Copilot',
    this.suggestions = const [],
    this.emptyStateTitle,
    this.emptyStateBody,
    this.onOpenUrl,
    this.bubbleOffset = 104,
    this.onPickAttachment,
    this.onDictate,
    this.onStopDictating,
    this.streamIdleTimeout = const Duration(seconds: 45),
    this.launcherLabel = 'Ask',
    this.composerHint,
    // The "+" the composer opens its menu of Photos, Camera and Files with.
    this.attachIcon = RendelAttachIcon.plus,
    this.voiceIcon = RendelVoiceIcon.microphone,
    this.sendIcon = RendelSendIcon.arrowUp,
    this.enabled = true,
    this.remoteConfig = true,
    this.strings,
    this.configStore,
    this.deviceIdStore,
    this.onLog,
    this.httpClient,
    this.userToken,
    this.themeMode = RendelThemeMode.system,
  });

  final String apiBaseUrl;

  /// Whether the copilot is drawn in its light theme, its dark one, or
  /// whichever the device is set to — the default, followed live, so the
  /// thread changes with the phone as the rest of a dark-aware app does.
  ///
  /// Set it to what your own app does. An app that is always light should
  /// say [RendelThemeMode.light], or a phone in dark mode opens a dark copilot
  /// over a light app. An app with an appearance switch of its own passes the
  /// choice it launches with here and calls `Rendel.setThemeMode` when the
  /// user changes it.
  ///
  /// The two themes are `Rendel.init`'s `theme` and `darkTheme`, with
  /// whatever the console publishes for each layered over them.
  final RendelThemeMode themeMode;

  /// The signed-in person's token, from your own sign-in — what lets the
  /// copilot reach your API as them, with no API key.
  ///
  /// Asked for before every question, so return the current one: your auth
  /// library already refreshes it (`await auth.currentUser?.getIdToken()`,
  /// `supabase.auth.currentSession?.accessToken`, your own refresh call).
  /// Return null when nobody is signed in.
  ///
  /// It goes with each question to Rendel and on to your endpoints as
  /// `Authorization: Bearer`, for the actions set to "the signed-in user's
  /// token" in the console. It is never stored there, and each person reaches
  /// only what their own token opens.
  final Future<String?> Function()? userToken;
  final Duration requestTimeout;

  /// The HTTP client every request goes through. Leave it null in production.
  ///
  /// This is the SDK's test seam, and it exists because there was not one. A
  /// host could not write a widget test proving their own `cancel_order`
  /// handler was reachable without either hitting the network or reaching into
  /// `package:rendel/src/...`, which the reference tells them never to
  /// do — and which the SDK's own suites were doing for exactly this reason.
  ///
  /// Pass a `MockClient` from `package:http/testing.dart` and the whole path
  /// runs offline: the manifest sync, the turn, the action dispatch and the
  /// blocks that come back.
  final http.Client? httpClient;
  final String sdkVersion;

  /// Where the SDK reports what it could not tell you any other way.
  ///
  /// Everything interesting used to go to `debugPrint` and stop there: a
  /// handler that threw, a context provider that missed its budget, a manifest
  /// the server rejected, a transport failure and its code. None of it reached
  /// the host's own logging, so the answer to "why did the copilot do that in
  /// production" lived on a device nobody had. Point this at your crash
  /// reporter and the SDK stops being a black box.
  final void Function(RendelLogRecord record)? onLog;

  /// The language the copilot answers in, as a BCP-47 tag: `'tr'`,
  /// `'pt-BR'`, `'de-DE'`.
  ///
  /// Null means the device's own locale, which is right for most apps and
  /// wrong for the ones that matter here: an app with its own language picker
  /// knows what its user chose, and a phone set to English showing a Turkish
  /// app should not make the copilot the one English thing on the screen. Pass
  /// what your app is rendering in.
  ///
  /// It is a default, not a rule. The server tells the model to answer in this
  /// language *unless the message it is answering is in another one* — someone
  /// typing English into a Turkish app gets English back, because the language
  /// in front of them beats a setting.
  ///
  /// It also picks the localized `RendelAction.confirmTemplates` sentence, which
  /// is what this field has always fed; answering in it is new.
  final String? locale;

  /// The languages this app is willing to have the copilot answer in, in
  /// preference order.
  ///
  /// Different from [locale], which is one setting: this is what the app
  /// ships. A clinic serving Türkiye and Russia has two languages its staff
  /// can read a transcript in, and an answer in a third — because somebody's
  /// phone is set to Thai — is a conversation nobody there can check, support
  /// or correct.
  ///
  /// ```dart
  /// RendelConfig(languages: ['tr', 'en', 'ru'])
  /// ```
  ///
  /// The device still decides which of them is used: a Russian phone gets
  /// Russian with nothing else configured. A device speaking none of them gets
  /// the **first** in the list, so the order is a decision.
  ///
  /// Empty hands the decision to the list published from the console, and
  /// absent that the copilot answers in whatever it is addressed in — which is
  /// what it has always done.
  final List<String> languages;

  /// What the copilot is called in the thread header. Set it to whatever your
  /// users already call the feature.
  final String assistantName;

  /// Opening prompts shown on an empty thread. Name things this app can
  /// actually do, in the user's words: "Where is my order?" beats "Ask me
  /// anything". Leave empty to keep the empty state text-only.
  final List<String> suggestions;

  /// The line under the empty thread's headline. The default names no verbs,
  /// because the SDK does not know whether this app tracks orders or transfers
  /// money; set it to your own and it will.
  /// The headline on an empty thread, in your own words.
  ///
  /// Null leaves the SDK's own, which is translated into the language the
  /// copilot answers in. Yours is not: it is one sentence, so an app serving
  /// several languages is usually better off leaving this alone or setting it
  /// through [strings].
  final String? emptyStateTitle;

  final String? emptyStateBody;

  /// Opens a URL an `open_url` action carries — a card's "Go to the product".
  ///
  /// Leave it null and the SDK opens it itself, in an in-app browser, so the
  /// user comes back to the conversation when they close it. Pass your own to
  /// route it instead: a deep link into your app's own product screen, or a
  /// browser of your choosing.
  final Future<void> Function(String url)? onOpenUrl;

  /// How far above the bottom edge, in logical pixels, the bubble sits while
  /// a screen the copilot opened is showing (`design/NAVIGATE.md`): clear of
  /// your own bottom bar. Never less than the safe area and a margin.
  final double bubbleOffset;

  /// Produces a file for the user to send.
  ///
  /// Null — the default — uses the SDK's own: Photos (the system photo
  /// picker), Camera (a photo taken there and then, attached as soon as it is
  /// taken) and Files (PDFs, text and pictures from the Files app), offered
  /// in the "+" menu and in the open message box. Supply one to use the
  /// picker your users already know; it then stands in for all three, and
  /// the "+" opens it directly:
  ///
  /// ```dart
  /// onPickAttachment: () async {
  ///   final file = await FilePicker.platform.pickFiles(withData: true);
  ///   final picked = file?.files.firstOrNull;
  ///   if (picked?.bytes == null) return null;
  ///   return RendelAttachment(
  ///     bytes: picked!.bytes!,
  ///     name: picked.name,
  ///     mediaType: 'application/pdf',
  ///   );
  /// }
  /// ```
  ///
  /// Return null when the user backs out. To remove the control altogether,
  /// set [attachIcon] to [RendelAttachIcon.off].
  ///
  /// Photos and Files need no permission on either platform: both are the
  /// system's own pickers, which hand over only what the user chose. Camera
  /// needs `NSCameraUsageDescription` in `ios/Runner/Info.plist`, and the
  /// system asks the user the first time; without the line the SDK leaves
  /// Camera out rather than let iOS close your app. A picker of your own may
  /// need more; that is between it and your Info.plist.
  final Future<RendelAttachment?> Function()? onPickAttachment;

  /// Turns speech into text.
  ///
  /// Null — the default — uses the SDK's own recogniser, `speech_to_text`
  /// on the device, listening in the language the copilot answers in when
  /// the device carries a model for it. The microphone opens voice mode:
  /// what it hears is written over the conversation as it is heard, and sent
  /// on its own when the speaker stops.
  ///
  /// Two lines in `Info.plist` are yours to add, because Apple shows them to
  /// your users: `NSMicrophoneUsageDescription` and
  /// `NSSpeechRecognitionUsageDescription`. Without them the built-in is not
  /// drawn — iOS would close the app the first time it was pressed — and
  /// `usage_description_missing` is logged. Android needs nothing: the SDK's
  /// manifest declares `RECORD_AUDIO`.
  ///
  /// Supply one to use a recogniser your app already has. Call `onPartial`
  /// with every partial; return the final text, null when nobody spoke, and
  /// throw when the recogniser failed — the thread words the last two
  /// differently. A recogniser ends a session four ways and most of them
  /// deliver no result; the built-in, in `batteries.dart`, is the reference
  /// for funnelling all four into one ending, for the session that has not
  /// released the audio hardware yet, for the locale the device does not
  /// carry, and for the iOS ending that arrives before its error. To remove
  /// the control altogether, set [voiceIcon] to [RendelVoiceIcon.off].
  final Future<String?> Function(void Function(String partial) onPartial)?
      onDictate;

  /// Ends a dictation the user started, when they press the microphone again.
  ///
  /// Only read when [onDictate] is yours; the built-in recogniser brings its
  /// own. Without it the microphone cannot be pressed while your recogniser
  /// is listening — there would be nothing for the press to do. Stop your
  /// recogniser here; the future from [onDictate] should then complete.
  final void Function()? onStopDictating;

  /// How long a turn may go without a single server event before the SDK
  /// gives up and offers a retry. A stream that connects and then stalls used
  /// to leave the composer disabled forever.
  final Duration streamIdleTimeout;

  /// The word on the launcher. Name what the user gets, in their words.
  final String launcherLabel;

  /// The words in the message box before anyone has typed.
  ///
  /// Null is the right default and not an empty one: [RendelStrings.composerHint]
  /// carries the SDK's own hint translated into every language it ships, so
  /// leaving this alone gets "Ne isterseniz sorun" in a Turkish app rather
  /// than an English sentence. Set it — in code or from the console — for an
  /// app that would rather prompt for something specific than for anything.
  final String? composerHint;

  /// The three glyphs in the composer.
  ///
  /// Publishable, like the launcher label beside them, so a customer can match
  /// the composer to the rest of their app without a release. The attachment
  /// and voice controls are drawn disabled until those features land; setting
  /// either to `off` removes it, which is the right answer for an app that is
  /// never going to have it.
  final RendelAttachIcon attachIcon;
  final RendelVoiceIcon voiceIcon;
  final RendelSendIcon sendIcon;

  /// The kill switch, in code. The console can flip the published one, which
  /// is how a customer pulls the copilot out of a shipped binary without an
  /// App Store review. Setting it false here disables it regardless.
  ///
  /// It is not a security control. The API enforces suspension server-side;
  /// this only decides whether the affordance is drawn.
  final bool enabled;

  /// Whether to fetch the published appearance and opening surface at init.
  /// False pins the copilot to exactly what this object says, which is the
  /// right choice for a host that wants its build reproducible.
  final bool remoteConfig;

  /// Every word the SDK puts on screen that did not come from your app or the
  /// model: the two buttons on a confirmation card, the status pill, the error
  /// bar.
  ///
  /// Null is not "English" — it is "use the language you are answering in".
  /// The SDK reads [locale] (or the device's) and takes the words from
  /// [RendelStrings.forLocale], which is why a Turkish app no longer offers
  /// "Confirm" under a Turkish sentence. A language the SDK does not carry
  /// falls back to English, as it always did.
  ///
  /// Set it and you own every word, including staying English on purpose in
  /// an app whose locale says otherwise. `RendelStrings.forLocale(tag).copyWith(…)`
  /// changes one of them without giving up the rest.
  final RendelStrings? strings;

  /// Where the published config is cached between launches, so the copilot
  /// paints in the app's colours before the network answers.
  ///
  /// Null — the default — keeps it in the app's preferences, through
  /// `shared_preferences`. Supply one to use your own storage.
  final RendelConfigStore? configStore;

  /// Where the install's anonymous device id is kept between launches.
  ///
  /// Null — the default — keeps it in the app's preferences, through
  /// `shared_preferences`, so the same phone is the same device on every
  /// launch: one row on the console's Users page, a per-device rate limit
  /// that does not reset when the user swipes the app away, and memory that
  /// finds its way back to the person. Supply one to use your own storage.
  /// It is an anonymous per-install identifier, carries no personal data, and
  /// the SDK never sends it anywhere but the copilot API; ordinary app
  /// storage, not the keychain, is the right place for it. Under
  /// `flutter test` the default is memory, so a widget test that calls `init`
  /// needs no plugin mocked.
  final RendelConfigStore? deviceIdStore;

  /// Everything the remote config may override, and nothing else. A null
  /// argument means "the published payload said nothing about this", which is
  /// not the same as "the published payload said empty".
  RendelConfig copyWith({
    String? assistantName,
    String? launcherLabel,
    String? emptyStateTitle,
    String? emptyStateBody,
    List<String>? suggestions,
    bool? enabled,
    String? composerHint,
    RendelAttachIcon? attachIcon,
    RendelVoiceIcon? voiceIcon,
    RendelSendIcon? sendIcon,
  }) {
    return RendelConfig(
      apiBaseUrl: apiBaseUrl,
      requestTimeout: requestTimeout,
      sdkVersion: sdkVersion,
      locale: locale,
      languages: languages,
      assistantName: assistantName ?? this.assistantName,
      suggestions: suggestions ?? this.suggestions,
      emptyStateTitle: emptyStateTitle ?? this.emptyStateTitle,
      emptyStateBody: emptyStateBody ?? this.emptyStateBody,
      onOpenUrl: onOpenUrl,
      bubbleOffset: bubbleOffset,
      onPickAttachment: onPickAttachment,
      onDictate: onDictate,
      onStopDictating: onStopDictating,
      streamIdleTimeout: streamIdleTimeout,
      launcherLabel: launcherLabel ?? this.launcherLabel,
      composerHint: composerHint ?? this.composerHint,
      attachIcon: attachIcon ?? this.attachIcon,
      voiceIcon: voiceIcon ?? this.voiceIcon,
      sendIcon: sendIcon ?? this.sendIcon,
      // A host that turned the copilot off in code stays off whatever the
      // console publishes: the local switch is the floor, not a default.
      enabled: enabled == null ? this.enabled : (this.enabled && enabled),
      remoteConfig: remoteConfig,
      strings: strings,
      configStore: configStore,
      deviceIdStore: deviceIdStore,
      onLog: onLog,
      userToken: userToken,
      // The host's, like the floor above: the console publishes a dark
      // theme, never which of the two this app shows.
      themeMode: themeMode,
    );
  }
}

/// Where a file in the composer comes from: the three entries of the "+"
/// menu, and the three tools in the open message box.
enum RendelAttachSource { photos, camera, files }

/// A file the host's own picker produced, on its way to the copilot.
///
/// Three things and no more: the SDK uploads the bytes, shows the name in the
/// composer while the message is being written, and tells the server what the
/// media type is so the model is handed an image as an image and a PDF as a
/// document.
class RendelAttachment {
  const RendelAttachment({
    required this.bytes,
    required this.name,
    required this.mediaType,
  });

  final Uint8List bytes;

  /// Shown on the chip in the composer, and sent as the message text when the
  /// user attaches something without typing anything.
  final String name;

  /// `image/png`, `image/jpeg`, `image/webp`, `image/gif`, `application/pdf`
  /// or `text/plain`. Anything else is refused by the upload, with a sentence
  /// saying so.
  final String mediaType;
}
