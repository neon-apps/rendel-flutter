import 'package:flutter/foundation.dart';

/// How bad the thing that happened was.
enum RendelLogLevel { debug, warning, error }

/// One thing the SDK wants the host to know.
///
/// [code] is stable and safe to switch on; [message] is for humans and may be
/// reworded. Where the platform supplied its own error code, it is [code].
/// Where a developer gets the key, said wherever one is refused. An
/// example's `rd_pk_test_...` used to pass the first check and fail later as
/// a network error nobody could read. Not exported.
const String rendelKeyHelp = "Copy your app's key from the Rendel console: "
    'your app → Settings → Keys & environments → Copy beside Test.';

class RendelLogRecord {
  const RendelLogRecord({
    required this.level,
    required this.code,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final RendelLogLevel level;

  /// Stable identifiers, and this list is the whole set:
  ///
  /// * `invalid_key` — `appKey` does not start with `rd_pk_` (or `nc_pk_`), is still an
  ///   example's placeholder, or the server does not know it
  /// * `handler_failed` — an action handler threw
  /// * `handler_timeout` — a handler passed its `timeout`
  /// * `result_too_large` — a handler returned more than 16,384 characters
  ///   of JSON, so the action is reported as failed (the web SDK logs the
  ///   same code)
  /// * `context_provider_timeout` — a provider missed its 300 ms budget
  /// * `context_provider_failed` — a provider threw
  /// * `manifest_sync_failed` — the server rejected the manifest; the message
  ///   carries the field and the reason
  /// * `transport_failed` — a network call failed
  /// * `config_unreadable` — a published config could not be parsed, or was
  ///   not legible on this device
  /// * `config_cache_write_failed` — the config store threw on write
  /// * `app_not_live` — warning: the server refuses a live key until the app
  ///   goes live in the console, so the launcher is hidden; use the test key
  ///   or press Go live
  /// * `app_suspended` — debug: the app is suspended, so the launcher is
  ///   hidden
  /// * `device_id_ephemeral` — no `deviceIdStore`, so the id is per launch
  /// * `device_id_store_failed` — the device id store threw or hung
  /// * `usage_description_missing` — Info.plist lacks the microphone's or the
  ///   camera's usage strings, so that control is not drawn
  /// * `user_store_failed` — the signed-in user could not be stored or read
  ///   back, so a relaunch starts signed out
  /// * `paired` — `pair` was accepted; the console watches until the time in
  ///   the message
  /// * `pair_test_only` — `pair` with a live key
  /// * `pair_not_found` — `pair` with a code that is wrong, used or expired
  /// * `pair_rate_limited` — `pair` tried too often in a minute
  /// * `pair_failed` — `pair` failed any other way, the network included
  /// * `surface_stale` — debug: a block arrived for a `surface_id` with a
  ///   revision no newer than the one on screen, and was dropped
  /// * `user_token_failed` — `userToken` threw; the call went without a token
  /// * `dictation_failed` — the host's `onDictate` threw
  /// * `route_open_failed` — a registered route's `open` threw (the web SDK
  ///   logs the same code)
  /// * `open_url_failed` — a link could not be opened in the in-app browser
  /// * `open_external_failed` — a link could not be handed to the system
  /// * `call_failed` — the dialler could not be opened for a `call` tap
  /// * `mail_failed` — the mail app could not be opened for an `email` tap
  /// * `copy_failed` — the clipboard refused a `copy` tap's value
  /// * `calendar_failed` — the event editor could not be opened for an
  ///   `add_to_calendar` tap
  /// * `invalid_goal` — `track` was given a goal name that is not one, or a
  ///   value without a three-letter currency; nothing was sent
  /// * `invalid_screen` — `setScreen` was given an empty name
  /// * the server's own code when a turn ends in an `error` frame:
  ///   `invalid_key`, `quota_exceeded`, `rate_limited`, `model_busy`,
  ///   `upgrade_required`, `manifest_unknown`, `invalid_request` or `internal`
  ///
  /// This list used to name a code nothing emitted. Keep it honest: a code
  /// documented and never sent is worse than one sent and never documented.
  final String code;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() => '[$code] $message${error == null ? '' : ': $error'}';
}

/// The SDK's single reporting point.
///
/// Always prints in debug, so nothing that used `debugPrint` gets quieter, and
/// additionally hands the record to the host's sink when one is configured. A
/// throwing sink is swallowed: the host's logger failing must not take down
/// the turn it was reporting on.
class RendelLog {
  RendelLog._();

  static void Function(RendelLogRecord record)? sink;

  static void report(
    RendelLogLevel level,
    String code,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final record = RendelLogRecord(
      level: level,
      code: code,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
    if (kDebugMode) debugPrint('[rendel] $record');
    try {
      sink?.call(record);
    } catch (err) {
      if (kDebugMode) debugPrint('[rendel] log sink threw: $err');
    }
  }

  static void warn(String code, String message, {Object? error}) =>
      report(RendelLogLevel.warning, code, message, error: error);

  static void error(
    String code,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      report(RendelLogLevel.error, code, message, error: error, stackTrace: stackTrace);
}
