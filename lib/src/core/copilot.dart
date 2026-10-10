import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../engine/conversation_controller.dart';
import '../protocol/protocol.dart';
import '../transport/api_client.dart';
import '../ui/presentation.dart';
import '../ui/theme.dart';
import '../ui/thread_screen.dart';
import 'action.dart';
import 'batteries.dart';
import 'config.dart';
import 'device_id.dart';
import 'events.dart';
import 'locale.dart';
import 'log.dart';
import 'pairing.dart';
import 'platform.dart';
import 'route.dart';
import 'strings.dart';
import 'remote_config.dart';

/// The SDK facade. One init per app run:
///
/// ```dart
/// await Rendel.init(
///   // Your app's key: Rendel console → Settings → API keys → Copy.
///   appKey: 'rd_pk_test_...',
///   theme: RendelTheme.paper(),
///   actions: [...],
/// );
/// ```
class Rendel {
  Rendel._();

  static RendelApiClient? _api;
  static ConversationController? _controller;
  static RendelTheme _theme = RendelTheme.paper();
  static RendelConfig _config = const RendelConfig();
  static final Map<String, RendelAction> _actions = {};
  static final Map<String, RendelRoute> _routes = {};
  static final Map<String, Future<Map<String, dynamic>> Function()> _providers = {};
  static final StreamController<RendelEvent> _events = StreamController.broadcast();
  static String? _appKey;
  static bool _manifestSynced = false;

  /// Who is signed in, as the last [identify] said, until [reset]. Sent on
  /// every turn: the server no longer keeps it for the phone, because two
  /// people can use one phone.
  static Map<String, String>? _user;

  /// Where [_user] is kept between launches. 0.13 held it in memory only, so
  /// every host had to write a second `identify` into its session-restore
  /// path or a relaunch talked as nobody; a copilot that needs code the docs
  /// do not show is not one that works when the dependency is in.
  static RendelConfigStore? _userStore;
  static RendelConfigStore get _users => _userStore ??= _defaultStore('nc_user');

  /// The last [identify] body, for an [identify] that arrived before [init]
  /// had a client to send it with.
  static Map<String, dynamic>? _identity;

  /// [pair] calls that ran before [init] had a client, waiting for one.
  static final List<Completer<RendelApiClient?>> _awaitingClient = [];

  /// The theme and config the host passed in, kept so a later remote config
  /// is always layered over the ORIGINAL rather than over the last applied
  /// one. Layering twice is how a radius drifts a point per launch.
  static RendelTheme _codeTheme = RendelTheme.paper();
  static RendelConfig _codeConfig = const RendelConfig();
  static RendelConfigStore _store = RendelMemoryConfigStore();
  static String? _configEtag;

  /// Fires when a published config lands and changes what is on screen, so a
  /// host embedding the thread itself can rebuild. The launcher listens to
  /// it; nothing else in the SDK needs to.
  static final ValueNotifier<int> configRevision = ValueNotifier<int>(0);

  static Stream<RendelEvent> get events => _events.stream;
  static RendelTheme get theme => _theme;
  static RendelConfig get config => _config;

  /// False when the host turned the copilot off in code, or when the customer
  /// published a kill switch. [RendelLauncher] draws nothing and [open]
  /// returns without presenting.
  static bool get isEnabled => _config.enabled;
  static bool get isInitialized => _api != null;

  static Future<void> init({
    required String appKey,
    RendelTheme? theme,
    List<RendelAction> actions = const [],
    RendelConfig config = const RendelConfig(),
  }) async {
    // Wired before anything can fail, so the first thing the host hears about
    // is reported through the channel they asked for.
    RendelLog.sink = config.onLog;

    // An example's placeholder — `rd_pk_test_...` — starts like a key, so
    // the prefix alone let it through to fail later as a network error.
    final placeholder = RegExp(r'\.\.\.|…|YOUR|<|>|XXXX').hasMatch(appKey);
    // nc_pk_ is how keys began before the rename; those keep working.
    final prefixed = appKey.startsWith('rd_pk_') || appKey.startsWith('nc_pk_');
    if (!prefixed || placeholder) {
      // Loud in debug, reported in release. This used to be a debugPrint and a
      // silent return: the launcher then drew nothing, `open()` did nothing,
      // and the developer had a copilot that was simply absent with no failure
      // anywhere to explain it. A key typo should cost a red screen in
      // development, not an afternoon.
      final why = placeholder
          ? 'appKey is still the example\'s placeholder ("$appKey"), not your app\'s key.'
          : 'appKey must start with rd_pk_ (got "$appKey").';
      RendelLog.error('invalid_key', '$why $rendelKeyHelp The copilot is disabled for this run.');
      assert(false, 'rendel: $why $rendelKeyHelp');
      _handOverClient(null);
      return;
    }
    _appKey = appKey;
    _codeConfig = config;
    _config = config;
    if (theme != null) _theme = theme;
    _codeTheme = _theme;
    // The SDK's own storage unless the host brought one — see `batteries.dart`.
    _store = config.configStore ?? _defaultStore('nc_config');
    auditContrast(_theme);
    for (final action in actions) {
      _actions[action.name] = action;
    }
    // Awaited, unlike the config fetch: the client cannot be built without an
    // id, and every caller of `init()` already awaits it. A store that hangs
    // is bounded below rather than allowed to stall launch.
    _api = RendelApiClient(
      appKey: appKey,
      deviceId: await _resolveDeviceId(
        config.deviceIdStore ?? _defaultStore('nc_device_id'),
      ),
      config: config,
      httpClient: config.httpClient,
    );
    _handOverClient(_api);
    unawaited(_syncManifest());
    // An app that restores its session before initialising the copilot calls
    // `identify` first. That call used to go nowhere, silently.
    final identity = _identity;
    if (identity != null) unawaited(_sendIdentity(identity));
    // Asked now so a missing usage string is in the log at launch, not only
    // the first time somebody opens the copilot.
    unawaited(RendelPlatform.microphoneReady());
    if (config.onPickAttachment == null) unawaited(RendelPlatform.cameraReady());
    // Otherwise, whoever was signed in when the app last closed. Read first
    // and assigned after, so an `identify` that lands during the read wins.
    final recalled = await _recallUser();
    _user ??= recalled;

    if (!config.remoteConfig) return;
    // The cached payload is applied BEFORE the fetch is even started, and
    // awaited, so launch two paints the customer's own look in the first
    // frame rather than flashing the code default and then correcting. The
    // network then runs unawaited: `init()` must not be slower than the
    // launcher it precedes, and an unreachable API must not delay it at all.
    await _applyCachedConfig();
    unawaited(_refreshConfig());
  }

  /// Re-reads the published config. Call it when your app returns to the
  /// foreground if you want a publish to land without a relaunch; the SDK
  /// does not hook the lifecycle itself, because an SDK that installs an app
  /// lifecycle observer in someone else's app is a surprise.
  static Future<void> refreshConfig() => _refreshConfig();

  static void registerAction(RendelAction action) {
    _actions[action.name] = action;
    _manifestSynced = false;
    unawaited(_syncManifest());
  }

  /// A screen of your app the copilot may open from an answer
  /// (`design/NAVIGATE.md`).
  ///
  /// ```dart
  /// Rendel.registerRoute(
  ///   'order_detail',
  ///   title: 'Orders › Order',
  ///   description: 'One order: its items, delivery and payment.',
  ///   params: {'order_id': RendelRouteParam.string(required: true, fromActions: true)},
  ///   open: (params) => navigatorKey.currentState!.push(
  ///     MaterialPageRoute(builder: (_) => OrderScreen(id: '${params['order_id']}')),
  ///   ),
  /// );
  /// ```
  ///
  /// [title] is drawn under the model's title on the card, so it is your
  /// app's own name for the screen; [description] tells the model when the
  /// screen is the right one. [open] runs your own navigation once the
  /// copilot's sheet is out of the way, so it pushes onto your navigator; the
  /// copilot waits in a bubble meanwhile, and a tap on it brings the answer
  /// back as it was. The server checks every param against [params] before a
  /// card is drawn. Like an action, a route goes into the manifest, which is
  /// synced again. Safe to call before [init].
  static void registerRoute(
    String name, {
    required String title,
    required String description,
    Map<String, RendelRouteParam> params = const {},
    required RendelRouteOpener open,
  }) {
    _routes[name] = RendelRoute(
      name: name,
      title: title,
      description: description,
      params: params,
      open: open,
    );
    _manifestSynced = false;
    unawaited(_syncManifest());
  }

  /// Call right after sign-in. Every turn from here until [reset] belongs to
  /// this user, whatever phone it is sent from — across relaunches too, so a
  /// restored session needs no second call. Safe to call before [init].
  static Future<void> identify({
    required String userId,
    Map<String, dynamic>? traits,
    String? userHmac,
  }) async {
    final previous = _user?['id'];
    final user = {'id': userId, if (userHmac != null) 'hmac': userHmac};
    _user = user;
    unawaited(_storeUser(jsonEncode(user)));
    // Somebody else's thread is not this person's to read, on a phone they
    // share. From anonymous to signed in it stays: it was theirs.
    if (previous != null && previous != userId) _controller?.reset();
    final identity = {
      'external_user_id': userId,
      if (traits != null) 'traits': traits,
      if (userHmac != null) 'user_hmac': userHmac,
    };
    _identity = identity;
    await _sendIdentity(identity);
  }

  /// The traits, and the anonymous history this phone had before the sign-in.
  /// The turns carry the user themselves, so a failure here costs neither.
  static Future<void> _sendIdentity(Map<String, dynamic> identity) async {
    try {
      await _api?.identify(identity);
    } catch (err) {
      RendelLog.warn('transport_failed', 'identify did not reach the server', error: err);
    }
  }

  /// Pairs this device with the console: pass the code the console shows
  /// (`K7Q2-M9XD`, dash and case optional). From then on the console watches
  /// this device's conversation for two hours, read only; the copilot behaves
  /// exactly as before. Test keys only; a code works once, for ten minutes.
  ///
  /// Never throws for anything the server says, or for a network that
  /// failed: the result carries a sentence a pairing screen can show as it
  /// is. Safe to call before [init]; it waits for it, briefly.
  static Future<RendelPairResult> pair(String code) async {
    final given = code.trim();
    final RendelPairResult result;
    if (given.isEmpty) {
      result = const RendelPairResult.failed(
        RendelPairFailure.failed,
        'Type the code the console shows, like K7Q2-M9XD.',
      );
    } else {
      final api = await _whenClient();
      result = api == null
          ? const RendelPairResult.failed(
              RendelPairFailure.failed,
              'The copilot has not started; call init with the app\'s test key first.',
            )
          : await api.pair(given);
    }
    final reason = result.reason;
    if (reason == null) {
      RendelLog.report(RendelLogLevel.debug, 'paired',
          'the console can watch this conversation until ${result.endsAt}');
    } else {
      RendelLog.warn(_pairCodes[reason]!, result.message!);
    }
    return result;
  }

  /// The web SDK's codes, so one log pipeline reads both.
  static const _pairCodes = {
    RendelPairFailure.testOnly: 'pair_test_only',
    RendelPairFailure.notFound: 'pair_not_found',
    RendelPairFailure.rateLimited: 'pair_rate_limited',
    RendelPairFailure.failed: 'pair_failed',
  };

  /// How long a [pair] made before [init] waits for it.
  static const _clientWait = Duration(seconds: 10);

  /// The client, now or once [init] builds it. Bounded, unlike [identify]'s
  /// hand-over, because a future the host awaits must complete: an app that
  /// never calls [init] gets an answer saying so rather than a spinner.
  static Future<RendelApiClient?> _whenClient() {
    final api = _api;
    if (api != null) return Future.value(api);
    final waiting = Completer<RendelApiClient?>();
    _awaitingClient.add(waiting);
    return waiting.future.timeout(_clientWait, onTimeout: () {
      _awaitingClient.remove(waiting);
      return null;
    });
  }

  static void _handOverClient(RendelApiClient? client) {
    for (final waiting in _awaitingClient) {
      if (!waiting.isCompleted) waiting.complete(client);
    }
    _awaitingClient.clear();
  }

  static void addContextProvider(
    String key,
    Future<Map<String, dynamic>> Function() provider,
  ) {
    _providers[key] = provider;
  }

  /// Presents the thread as a full-height modal sheet.
  ///
  /// Returns without presenting when the copilot is disabled, so a kill
  /// switch published mid-session closes the entry point even where a host
  /// calls `open()` from its own menu rather than from [RendelLauncher].
  static Future<void> open(BuildContext context) async {
    final api = _api;
    if (api == null || !_config.enabled) return;
    // Already presented: in the bubble while a screen it opened is in front,
    // the launcher does what the bubble does. Over the app, a second sheet of
    // the same thread is not drawn.
    final presented = _presentation;
    if (presented != null) {
      presented.restore();
      return presented.done;
    }
    // The SDK's own microphone only where iOS will not close the app for it.
    // A host that brought its own recogniser answers for its own Info.plist.
    final microphone = _config.onDictate != null || await RendelPlatform.microphoneReady();
    // And Camera only where iOS will not close the app for it either.
    final camera = _config.onPickAttachment == null && await RendelPlatform.cameraReady();
    if (!context.mounted) return;
    // The manifest sync at init() may have lost its network — an app launched
    // in airplane mode, a cold start on a flaky link. Without this, every turn
    // of the session fails `manifest_unknown` and the error's own advice
    // ("close and reopen it") could never work. Unawaited on purpose: the sync
    // usually wins the race against the user's first send, and losing it once
    // costs one retryable error, not the session.
    if (!_manifestSynced) unawaited(_syncManifest());
    _controller ??= ConversationController(
      api: api,
      actions: _actions,
      routes: _routes,
      sdkVersion: _config.sdkVersion,
      contextProviders: _providers,
      sandbox: RegExp(r'^(rd|nc)_pk_test_').hasMatch(_appKey ?? ''),
      onOpenUrl: _config.onOpenUrl ?? openLink,
      streamIdleTimeout: _config.streamIdleTimeout,
      locale: _config.locale,
      languages: _config.languages,
      onEvent: _events.add,
      user: () => _user,
    )..manifestHash = _currentManifestHash();
    _events.add(RendelEvent.opened);
    // One recogniser per presentation, for the built-in dictation; it listens
    // in the language the copilot answers in.
    final speech = RendelSpeech(
      locale: resolveSpokenLocale(_config.locale, _config.languages),
    );
    final controller = _controller!;
    late final RendelPresentation presentation;
    presentation = _presentation = RendelPresentation(
      context: context,
      theme: () => _theme,
      label: strings.backToAssistant,
      bubbleOffset: _config.bubbleOffset,
      openRoute: controller.tapAction,
      thread: () => RendelThemeScope(
        theme: _theme,
        child: ThreadScreen(
          strings: strings,
          controller: controller,
          title: _config.assistantName,
          logoUrl: logoUrl,
          logoHeaders: logoHeaders,
          headline: _config.emptyStateTitle,
          subtitle: _config.emptyStateBody,
          suggestions: _config.suggestions,
          composerHint: _config.composerHint,
          attachIcon: _config.attachIcon,
          voiceIcon: _config.voiceIcon,
          sendIcon: _config.sendIcon,
          // The host's own picker and recogniser when it has them, the SDK's
          // when it does not — see `batteries.dart`. The stop control belongs
          // to whichever recogniser is listening.
          onPickAttachment: switch (_config.onPickAttachment) {
            final pick? => (_) => pick(),
            null => pickFrom,
          },
          // A host's picker stands in for all three, so the "+" opens it.
          attachSources: _config.onPickAttachment != null
              ? const [RendelAttachSource.files]
              : [
                  RendelAttachSource.photos,
                  if (camera) RendelAttachSource.camera,
                  RendelAttachSource.files,
                ],
          onDictate: _config.onDictate ?? (microphone ? speech.dictate : null),
          onStopDictating: _config.onDictate == null
              ? (microphone ? speech.stop : null)
              : _config.onStopDictating,
          // The built-in reports how loud the speaker is; voice mode's glow
          // swells with it.
          dictationLevel: _config.onDictate == null ? speech.level : null,
          onNavigate: (action) => presentation.navigate(action),
        ),
      ),
    );
    _presenting++;
    try {
      // Until it is closed, not until it shrinks into the bubble: the thread
      // is still mounted then, in the overlay.
      await presentation.done;
    } finally {
      _presenting--;
      if (identical(_presentation, presentation)) _presentation = null;
      // In the finally, so a sheet that throws on present does not leak an
      // `opened` with no `closed` into whatever the host wired this stream to.
      _events.add(RendelEvent.closed);
    }
  }

  /// The thread on screen, in its sheet or in the bubble. Null when the
  /// copilot is closed.
  static RendelPresentation? _presentation;

  /// How many thread sheets are on screen right now. `reset()` needs to know:
  /// a controller disposed under a mounted [ThreadScreen] leaves the composer
  /// ticking a disposed notifier on the next send.
  ///
  /// A counter, not a flag: a second `open()` over an already-open thread — a
  /// double-tapped launcher, a deep link — used to clear the flag when the
  /// inner sheet closed, while the outer one was still up.
  static int _presenting = 0;

  static void close(BuildContext context) => Navigator.of(context).maybePop();

  /// Call on logout: clears the thread and the user. The next turn from this
  /// phone is anonymous until the next [identify].
  static void reset() => _endSession(forget: true);

  /// [forget] is the logout: the stored user goes too. Without it this is
  /// what a process ending does to the SDK, and the device keeps who it was.
  static void _endSession({required bool forget}) {
    _user = null;
    _identity = null;
    if (forget) unawaited(_storeUser(''));
    final controller = _controller;
    if (controller == null) return;
    controller.reset();
    // Dropping the reference without disposing leaked the controller's
    // notifier and every listener on it, one per logout. Disposing while the
    // sheet is still up would throw instead, so a reset that lands mid-session
    // clears the thread in place and the next `open()` reuses the same
    // controller — which is now empty, which is what reset promised.
    if (_presenting > 0) return;
    controller.dispose();
    _controller = null;
  }

  /// Puts the SDK back to the state a fresh process starts in.
  ///
  /// `reset()` is the logout call: it clears the thread and the user binding
  /// and deliberately leaves the client, the key and the registered actions
  /// alone, because the app is still the same app. A test suite needs the
  /// other thing — two `init()` calls in one process accumulated actions from
  /// the first into the second, so the second test saw a manifest the code
  /// under test never registered.
  ///
  /// [relaunch] keeps what the device stores — the signed-in user — so a test
  /// can check what a cold start restores.
  @visibleForTesting
  static void resetForTest({bool relaunch = false}) {
    _endSession(forget: !relaunch);
    // A test that ends with the sheet up never pops it, so the count stayed
    // above zero, `_endSession` kept the controller, and the next test's
    // thread talked through the previous test's client. Dropped rather than
    // disposed: the tree that listened to it may not be torn down yet.
    _controller = null;
    _presenting = 0;
    _presentation = null;
    RendelPlatform.resetForTest();
    _api = null;
    _handOverClient(null);
    _appKey = null;
    _actions.clear();
    _routes.clear();
    _providers.clear();
    _manifestSynced = false;
    _configEtag = null;
    _store = RendelMemoryConfigStore();
    _theme = RendelTheme.paper();
    _codeTheme = _theme;
    _config = const RendelConfig();
    _logoAssetId = null;
    _codeConfig = _config;
  }

  // ————————————————————————— remote config —————————————————————————

  /// Applies the last payload this device stored, if any. Never touches the
  /// network, so it is safe to await on the launch path.
  static Future<void> _applyCachedConfig() async {
    try {
      final cached = await _store.read();
      if (cached == null) return;
      final parsed = RendelRemoteConfig.tryParse(cached);
      if (parsed == null) return;
      _configEtag = parsed.etag;
      _apply(parsed);
    } catch (err) {
      // A corrupt cache is not a launch failure. The code config stands.
      RendelLog.warn('config_unreadable', 'cached config ignored', error: err);
    }
  }

  static Future<void> _refreshConfig() async {
    final api = _api;
    if (api == null || !_codeConfig.remoteConfig) return;
    final result = await api.fetchConfig(etag: _configEtag);
    // Null covers a 304, an error status and an unreachable network alike:
    // all three mean "no new config today", and what is on screen is already
    // correct.
    if (result == null) return;
    final parsed = RendelRemoteConfig.tryParse(result.$1, etag: result.$2);
    if (parsed == null) {
      RendelLog.warn('config_unreadable', 'published config was unreadable; ignoring it');
      return;
    }
    _configEtag = parsed.etag;
    _apply(parsed);
    try {
      await _store.write(parsed.toCache());
    } catch (err) {
      // A store that cannot write costs the next launch its head start and
      // nothing else.
      RendelLog.warn('config_cache_write_failed', 'config cache write failed', error: err);
    }
  }

  /// Layers a payload over the ORIGINAL code config, never over the last
  /// applied one, and audits the result the same way `init()` audits a
  /// hand-mapped theme.
  static void _apply(RendelRemoteConfig remote) {
    if (remote.isEmpty) return;
    // Compared by PAYLOAD, not by object identity. `copyWith` always
    // allocates, so an identity check never held and the launcher rebuilt on
    // every refresh whether or not anything about it had moved.
    final signature = remote.toCache();
    if (signature == _appliedSignature) return;
    _appliedSignature = signature;
    _theme = remote.applyTo(_codeTheme);
    _config = remote.applyToConfig(_codeConfig);
    _logoAssetId = remote.logoAssetId;
    auditContrast(_theme);
    configRevision.value++;
  }

  /// The payload currently on screen, so an unchanged republish is a no-op.
  static String? _appliedSignature;

  /// The published logo's id, if the customer set one.
  static String? _logoAssetId;

  /// Where the thread fetches the logo from.
  ///
  /// Built here rather than carried in the payload: the base is the host's own
  /// `apiBaseUrl` and the id is a uuid, so the only host a device is ever sent
  /// to is the one it was already configured to talk to. The id is in the
  /// query as well as in the path so that a new logo is a new URL and the old
  /// one falls out of the image cache on its own.
  static String? get logoUrl {
    final id = _logoAssetId;
    if (id == null) return null;
    return '${_config.apiBaseUrl}/v1/apps/logo?v=$id';
  }

  /// The words the thread is drawn with.
  ///
  /// The host's set wins whole. Null means it never said, and the SDK answers
  /// with the language it is already answering in — the same tag the handshake
  /// sends, so "Confirm" and the sentence above it cannot disagree.
  /// The SDK's own words, in the language the copilot is going to answer in.
  ///
  /// Through `languages` rather than straight off the device: the reply
  /// language already goes through that list on the server, and chrome that
  /// ignored it produced a thread prompting in Turkish and empty-stating in
  /// English on the same screen.
  /// The words the SDK is drawing in: the host's [RendelConfig.strings], or
  /// the shipped set for the language it answers in. The launcher sits in
  /// the host's tree, outside the thread's scope, and reads them here.
  static RendelStrings get strings =>
      _config.strings ??
      RendelStrings.forLocale(
        resolveSpokenLocale(_config.locale, _config.languages),
      );

  /// The key the logo request presents, the same one every other call sends.
  static Map<String, String> get logoHeaders {
    final key = _appKey;
    return key == null ? const {} : {'x-rendel-key': key};
  }

  // ————————————————————————— internals —————————————————————————

  static String? _cachedHash;

  static String? _currentManifestHash() {
    if (_actions.isEmpty && _routes.isEmpty) return null;
    return _cachedHash ??= hashManifest(_manifest());
  }

  static Map<String, dynamic> _manifest() =>
      buildManifest(_actions.values, routes: _routes.values);

  static Future<void> _syncManifest() async {
    final api = _api;
    if (api == null || (_actions.isEmpty && _routes.isEmpty) || _manifestSynced) return;
    _cachedHash = null;
    try {
      await api.syncManifest(_manifest(), _config.sdkVersion);
      _manifestSynced = true;
      _controller?.manifestHash = _currentManifestHash();
    } catch (err) {
      RendelLog.warn('manifest_sync_failed',
          'manifest sync failed; it is retried the next time open() runs',
          error: err);
    }
  }

  /// The anonymous per-install id this run is sending as `X-Rendel-Device`.
  ///
  /// Public because it is the one identifier that ties a user's report to the
  /// rows behind it: `/docs/resources/support` asks for it, and a host that
  /// runs its own support tooling should be able to attach it without
  /// guessing. Null before [init] completes.
  ///
  /// See [RendelConfig.deviceIdStore] for making it survive a relaunch.
  static String? get deviceId => _deviceId;
  static String? _deviceId;

  /// The preferences on a device; memory under `flutter test`.
  ///
  /// Under the test binding a platform channel nobody mocked never answers,
  /// and the two-second guard around the store is a timer the test clock
  /// does not advance — so a host's ordinary widget test that called `init`
  /// hung forever. `FLUTTER_TEST` is set by the test runner and by nothing
  /// else; a test that wants the real store mocks the plugin and passes one.
  static RendelConfigStore _defaultStore(String key) =>
      Platform.environment.containsKey('FLUTTER_TEST')
          ? RendelMemoryConfigStore()
          : RendelPreferencesStore(key);

  static Future<String> _resolveDeviceId(RendelConfigStore? store) async =>
      _deviceId ??= await RendelDeviceId.resolve(store);

  /// The user [identify] last stored, or null. A store that fails or hangs
  /// costs this launch its user, never its launch.
  static Future<Map<String, String>?> _recallUser() async {
    try {
      final stored = await _users.read().timeout(RendelDeviceId.storeTimeout);
      if (stored == null || stored.isEmpty) return null;
      final user = (jsonDecode(stored) as Map).cast<String, String>();
      return user['id'] == null ? null : user;
    } catch (err) {
      RendelLog.warn('user_store_failed', 'the signed-in user could not be read back', error: err);
      return null;
    }
  }

  /// Empty is signed out. The store has no delete, and an empty string is
  /// what [_recallUser] reads as nobody.
  static Future<void> _storeUser(String value) async {
    try {
      await _users.write(value).timeout(RendelDeviceId.storeTimeout);
    } catch (err) {
      RendelLog.warn('user_store_failed', 'the signed-in user could not be stored', error: err);
    }
  }
}
