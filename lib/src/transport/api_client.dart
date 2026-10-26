import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../core/locale.dart';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/followups.dart';
import '../core/log.dart';
import '../core/pairing.dart';
import '../protocol/protocol.dart';

/// What `GET /v1/apps/config` answered, as far as the SDK acts on it.
class RendelConfigAnswer {
  const RendelConfigAnswer.config(String this.body, this.etag)
      : refusal = null,
        unreachable = false;
  const RendelConfigAnswer.unchanged()
      : body = null,
        etag = null,
        refusal = null,
        unreachable = false;
  const RendelConfigAnswer.refused(String this.refusal)
      : body = null,
        etag = null,
        unreachable = false;

  /// The API could not be reached: no network, a timeout, or a server
  /// error. The launcher hides until it can be reached again, so nobody
  /// presses a button whose every press fails (resilience plan §1.2).
  const RendelConfigAnswer.unreachable()
      : body = null,
        etag = null,
        refusal = null,
        unreachable = true;

  /// The envelope, on a 200. Null on a 304 and on a refusal.
  final String? body;
  final String? etag;

  /// `app_not_live` — a live key before the app has gone live — or
  /// `app_suspended`. Either way the copilot is not this app's to show.
  final String? refusal;

  /// True when the request failed rather than being answered.
  final bool unreachable;
}

/// How long the config may take on launch before the launcher is hidden.
const Duration rendelConfigTimeout = Duration(seconds: 8);

/// What the config request names as the platform: `ios`, `android`,
/// `macos`, `windows`, `linux`, `fuchsia`, or `web`.
String rendelPlatformName() =>
    kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

/// Hand-rolled SSE over POST — deliberately no extra dependency. The server
/// closes the stream whenever it needs client input (continuation-POST model),
/// so a "connection" here is one turn, not a held socket.
class RendelApiClient {
  RendelApiClient({
    required this.appKey,
    required this.deviceId,
    required this.config,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String appKey;
  final String deviceId;
  final RendelConfig config;

  /// Injectable so the SSE parser can be driven from a test. It is the one
  /// piece of this SDK that turns bytes into protocol, and it had no coverage
  /// at all: the scripted client every other suite uses replaces `chat`
  /// wholesale and never reaches the parser.
  final http.Client _http;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Rendel-Key': appKey,
        'X-Rendel-Device': deviceId,
        // The language the chrome is drawn in, so a sentence the server puts
        // in the error bar arrives in it too. The turn body already carries
        // `client.locale`; an upload has no body of ours, only the file.
        'Accept-Language': resolveSpokenLocale(config.locale, config.languages),
      };

  /// The signed-in person's token from the host, asked for fresh each turn.
  ///
  /// A host whose token call throws still gets an answer — one that cannot
  /// reach their API as the person — rather than a failed turn.
  Future<String?> _userToken() async {
    final provider = config.userToken;
    if (provider == null) return null;
    try {
      final token = (await provider())?.trim();
      return token == null || token.isEmpty ? null : token;
    } catch (error) {
      RendelLog.warn('user_token_failed', 'userToken threw', error: error);
      return null;
    }
  }

  /// POST /v1/chat → parsed RDUI events until the server ends the turn.
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) async* {
    final token = await _userToken();
    final request = http.Request('POST', Uri.parse('${config.apiBaseUrl}/v1/chat'))
      ..headers.addAll({
        ..._headers,
        'Accept': 'text/event-stream',
        if (token != null) 'X-Rendel-User-Token': token,
      })
      ..body = jsonEncode(body);

    final response = await _http.send(request);
    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      String code = 'internal';
      String message = 'Request failed (${response.statusCode})';
      try {
        final parsed = jsonDecode(text) as Map<String, dynamic>;
        final error = parsed['error'] as Map<String, dynamic>?;
        code = error?['code'] as String? ?? code;
        message = error?['message'] as String? ?? message;
      } catch (_) {
        // The body was not the JSON error envelope. The status line already
        // carries enough to report, so fall through to the defaults above.
      }
      yield RendelError(code: code, message: message, retryable: response.statusCode >= 500);
      return;
    }

    String eventName = 'message';
    final dataLines = <String>[];
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty) {
          try {
            final data = jsonDecode(dataLines.join('\n')) as Map<String, dynamic>;
            final event = RendelWireEvent.tryParse(eventName, data);
            // Pings are yielded, not filtered. The idle timeout is applied to
            // this stream by the caller, so swallowing the server's 15s
            // keepalive here turned a connection-liveness check into a hard
            // cap on model latency: a turn that thinks for more than
            // `streamIdleTimeout` before its first block was killed with "the
            // assistant stopped responding" while the server was still
            // working. The controller drops them after the timer is reset.
            if (event != null) yield event;
          } catch (_) {
            // A frame the SDK cannot parse is skipped, never fatal: a server
            // that learns a new event type must not break an old build. Note
            // that nothing recovers the dropped frame — there is no gap
            // detection — so the turn's own settle pass at the end of `_run`
            // is what stops a half-arrived block pulsing forever.
          }
        }
        eventName = 'message';
        dataLines.clear();
      } else if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
  }

  /// `GET /v1/apps/config` → what the server said, or null when it said
  /// nothing the SDK acts on.
  ///
  /// Null on an error status other than the two refusals below, and on any
  /// transport failure: keep what you already have, because from the
  /// device's point of view that is no new config today.
  ///
  /// Sends which build this is and what it runs on (§9.7), so the console can
  /// say "Flutter 0.45.0 · iOS connected" and notice a build drifting behind.
  Future<RendelConfigAnswer?> fetchConfig({String? etag}) async {
    try {
      final response = await _http
          .get(
            Uri.parse('${config.apiBaseUrl}/v1/apps/config'),
            headers: {
              ..._headers,
              'X-Rendel-SDK': config.sdkVersion,
              'X-Rendel-Platform': rendelPlatformName(),
              if (etag != null) 'If-None-Match': etag,
            },
          )
          .timeout(config.requestTimeout < rendelConfigTimeout ? config.requestTimeout : rendelConfigTimeout);
      /* The first call every launch makes, so the one place to say a key the
         server does not know is the reason nothing works — rather than a
         network error on the first question. */
      if (response.statusCode == 401) {
        RendelLog.error('invalid_key', 'The Rendel server does not know this appKey. $rendelKeyHelp');
      }
      if (response.statusCode == 304) return const RendelConfigAnswer.unchanged();
      if (response.statusCode == 403) {
        final code = _errorCode(response.body);
        if (code == 'app_not_live' || code == 'app_suspended') {
          return RendelConfigAnswer.refused(code!);
        }
      }
      if (response.statusCode >= 500) return const RendelConfigAnswer.unreachable();
      if (response.statusCode != 200) return null;
      return RendelConfigAnswer.config(response.body, response.headers['etag']);
    } catch (_) {
      // No network, a timeout, or the API down.
      return const RendelConfigAnswer.unreachable();
    }
  }

  static String? _errorCode(String body) {
    try {
      final error = (jsonDecode(body) as Map<String, dynamic>)['error'];
      return error is Map && error['code'] is String ? error['code'] as String : null;
    } catch (_) {
      return null;
    }
  }

  /// POST /v1/uploads → the id a turn carries to put this file in front of
  /// the model.
  ///
  /// The bytes are the whole body and `Content-Type` says what they are. No
  /// multipart: there is one file and no fields to go with it, and a boundary
  /// parser would be a parser both ends would have to own.
  ///
  /// Uploaded before the turn rather than on it, because `/v1/chat` streams —
  /// a file on that request would mean buffering an upload before the first
  /// token could leave. It also makes a failed upload something the composer
  /// can say out loud and the user can retry, instead of a turn that failed
  /// for a reason nobody can see.
  Future<String> upload(Uint8List bytes, String mediaType, {String? fileName}) async {
    final name = fileNameHeader(fileName);
    final response = await _http
        .post(
          Uri.parse('${config.apiBaseUrl}/v1/uploads'),
          headers: {
            'Content-Type': mediaType,
            'X-Rendel-Key': appKey,
            'X-Rendel-Device': deviceId,
            if (name != null) 'X-Rendel-Filename': name,
          },
          body: bytes,
        )
        .timeout(config.requestTimeout);

    if (response.statusCode == 201) {
      return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
    }

    // The server's own words, not ours. It is the end that knows the ceiling
    // and the accepted types, and "that file is over 20 MB" is a sentence a
    // user can act on in a way that "upload failed" is not. Null when the
    // reply was not the server's envelope: the thread has a sentence for that
    // in the app's language, and this layer has none.
    String? message;
    try {
      final error = (jsonDecode(response.body) as Map<String, dynamic>)['error']
          as Map<String, dynamic>?;
      final given = error?['message'] as String?;
      if (given != null && given.isNotEmpty) message = given;
    } catch (_) {
      // Not the JSON envelope.
    }
    throw RendelUploadFailure(message);
  }

  Future<void> syncManifest(Map<String, dynamic> manifest, String sdkVersion) async {
    final response = await _http
        .post(
          Uri.parse('${config.apiBaseUrl}/v1/apps/manifest'),
          headers: _headers,
          body: jsonEncode({'manifest': manifest, 'sdk': sdkVersion}),
        )
        .timeout(config.requestTimeout);
    if (response.statusCode != 200) {
      // The server says WHICH action and WHICH field on a 400; this used to
      // throw the status code alone and drop the rest of the body, so the
      // developer got "manifest sync failed: 400" for a manifest with
      // fourteen actions in it. Everything the server was willing to explain
      // is carried into the message the host's logger receives.
      throw StateError(
        'manifest sync failed (${response.statusCode}): '
        '${_explain(response.body, response.statusCode)}',
      );
    }
  }

  /// The error envelope, flattened to one line. Falls back to the raw body,
  /// truncated, when the response was not the envelope at all — a proxy's
  /// HTML 502 is still more useful than nothing.
  static String _explain(String body, int status) {
    try {
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      final error = parsed['error'] as Map<String, dynamic>?;
      final message = error?['message'] as String?;
      final details = error?['details'];
      final buffer = StringBuffer(message ?? error?['code'] as String? ?? 'no message');
      if (details is List && details.isNotEmpty) {
        for (final entry in details.whereType<Map>()) {
          buffer.write('\n  - ${entry['path']}: ${entry['message']}');
        }
      }
      return buffer.toString();
    } catch (_) {
      final trimmed = body.trim();
      if (trimmed.isEmpty) return 'empty response body';
      return trimmed.length > 400 ? '${trimmed.substring(0, 400)}…' : trimmed;
    }
  }

  /// POST /v1/invocations/:id/confirm — the user's answer, recorded by the
  /// server rather than asserted by this device.
  ///
  /// Called the moment the button is pressed and BEFORE the handler runs, so
  /// the record exists independently of what the handler does or reports.
  /// Until this existed, a write action succeeded because the client posted
  /// `confirmed: true` next to its result, and a device is not a trust
  /// boundary.
  ///
  /// Returns the status the server recorded, or null when the call could not
  /// be made at all. Null is not the same as a refusal: a customer who has not
  /// turned server-mediated confirmation on is served exactly as before, so a
  /// network blip here must not cost the user their tap.
  Future<String?> recordDecision(String invocationId, {required bool confirm, String? typed}) async {
    try {
      final response = await _http
          .post(
            Uri.parse('${config.apiBaseUrl}/v1/invocations/$invocationId/confirm'),
            headers: _headers,
            body: jsonEncode({
              'decision': confirm ? 'confirm' : 'decline',
              if (confirm && typed != null) 'typed': typed,
            }),
          )
          .timeout(config.requestTimeout);
      // What the user typed did not match the stored value: the card stays open.
      if (response.statusCode == 422) {
        final refused = jsonDecode(response.body);
        final code = refused is Map ? (refused['error'] is Map ? refused['error']['code'] : refused['code']) : null;
        if (code == 'typed_mismatch') return 'typed_mismatch';
      }
      if (response.statusCode != 200) return null;
      final parsed = jsonDecode(response.body) as Map<String, dynamic>;
      return parsed['status'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// POST /v1/invocations/:id/edit — values the user changed on a
  /// confirmation card, checked by the server as it checks the model's call.
  ///
  /// `card`: the card redrawn with them, which is the one to confirm.
  /// `fields`: what was wrong, by parameter. Both null when the request could
  /// not be made, or the card is no longer open.
  Future<({Map<String, dynamic>? card, Map<String, String>? fields})> editInvocation(
    String invocationId,
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await _http
          .post(
            Uri.parse('${config.apiBaseUrl}/v1/invocations/$invocationId/edit'),
            headers: _headers,
            body: jsonEncode({'params': params}),
          )
          .timeout(config.requestTimeout);
      final parsed = jsonDecode(response.body);
      if (response.statusCode == 200 && parsed is Map && parsed['card'] is Map) {
        return (card: (parsed['card'] as Map).cast<String, dynamic>(), fields: null);
      }
      if (response.statusCode == 422 && parsed is Map && parsed['error'] is Map) {
        final fields = (parsed['error'] as Map)['fields'];
        if (fields is Map) {
          return (card: null, fields: fields.map((k, v) => MapEntry('$k', '$v')));
        }
      }
    } catch (_) {
      // Nothing to show but the generic line.
    }
    return (card: null, fields: null);
  }

  /// POST /v1/feedback. Best effort by design: a thumb is a nicety, and a
  /// failed one must never surface an error over the answer it was about.
  /// Returns whether the server accepted it, for the tests.
  Future<bool> sendFeedback(Map<String, dynamic> body) async {
    try {
      final response = await _http
          .post(
            Uri.parse('${config.apiBaseUrl}/v1/feedback'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(config.requestTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /v1/ratings: the answer to a `rating` block, which the server
  /// records with no model turn. Sent as [sendFeedback] is, with one
  /// difference in who reads the result: a rating the user tapped and the
  /// server never got is said under the block, so the user can tap again.
  Future<bool> sendRating(Map<String, dynamic> body) async {
    try {
      final response = await _http
          .post(
            Uri.parse('${config.apiBaseUrl}/v1/ratings'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(config.requestTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /v1/events with one event: a contact channel tapped, Rendel opened
  /// (analytics-roi T3, T4). Never a throw, and nothing the user sees waits
  /// on it; the server ignores an event it does not know.
  Future<void> sendEvent(Map<String, dynamic> event) => sendEvents([event]);

  /// POST /v1/events with several, as [sendEvent] sends one: the analytics
  /// queue goes in batches (product-analytics.md §2.1), at most 50 to a
  /// request, with who is signed in as a turn carries them.
  Future<void> sendEvents(List<Map<String, dynamic>> events, {Map<String, String>? user}) async {
    try {
      await _http
          .post(
            Uri.parse('${config.apiBaseUrl}/v1/events'),
            headers: _headers,
            body: jsonEncode({'events': events, if (user != null) 'user': user}),
          )
          .timeout(config.requestTimeout);
    } catch (_) {
      // A count that did not land is only a count.
    }
  }

  /// POST /v1/events: a screen of the app opened from a block in a reply
  /// (0073), for the app's Screens page to count against how often it was
  /// offered. Never a throw, and nothing the user sees waits on it.
  Future<void> sendScreenOpen(Map<String, String> open) async {
    try {
      await _http
          .post(
            Uri.parse('${config.apiBaseUrl}/v1/events'),
            headers: _headers,
            body: jsonEncode({
              'events': [
                {'type': 'screen_open', ...open},
              ],
            }),
          )
          .timeout(config.requestTimeout);
    } catch (_) {
      // A count that did not land is only a count.
    }
  }

  /// POST /v1/pairings/claim — this device answers the code the console
  /// shows, so the console can watch its conversation for the next two hours.
  ///
  /// Every answer is a result rather than a throw, a network that failed
  /// included: the caller is a developer's own pairing screen, and a sentence
  /// it can show is what they need from it. Read by error code, not status,
  /// so a 403 for a live key and a 403 for a suspended app are told apart.
  Future<RendelPairResult> pair(String code) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('${config.apiBaseUrl}/v1/pairings/claim'),
            headers: _headers,
            body: jsonEncode({'code': code}),
          )
          .timeout(config.requestTimeout);
    } catch (_) {
      return const RendelPairResult.failed(
        RendelPairFailure.failed,
        'The server could not be reached.',
      );
    }
    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Not JSON at all — a proxy's error page. The status is reported below.
    }
    final endsAt = parsed?['ends_at'];
    if (response.statusCode == 200 && parsed?['paired'] == true && endsAt is String) {
      return RendelPairResult.paired(endsAt);
    }
    final error = parsed?['error'];
    final errorCode = error is Map ? error['code'] : null;
    final given = error is Map ? error['message'] : null;
    final reason = switch (errorCode) {
      'pairing_test_only' => RendelPairFailure.testOnly,
      'pairing_not_found' => RendelPairFailure.notFound,
      'rate_limited' => RendelPairFailure.rateLimited,
      _ when response.statusCode == 429 => RendelPairFailure.rateLimited,
      _ => RendelPairFailure.failed,
    };
    final message = given is String && given.isNotEmpty
        ? given
        : switch (reason) {
            RendelPairFailure.testOnly =>
              "Pairing works with the app's test key. A live build cannot be paired.",
            RendelPairFailure.notFound =>
              'That code is not valid any more. Ask the console for a new one.',
            RendelPairFailure.rateLimited => 'Too many tries. Wait a minute and try again.',
            RendelPairFailure.failed => 'Pairing failed (${response.statusCode}'
                '${errorCode is String ? ', $errorCode' : ''}).',
          };
    return RendelPairResult.failed(reason, message);
  }

  /// `/v1/memory`, or `/v1/memory/:id` with [id]: what Rendel keeps about
  /// the person [user] names (`identify`'s `id`, and its `hmac` when the app
  /// verifies identities), or about this install when nobody is signed in.
  /// The status and the body, or null when the request could not be made.
  Future<({int status, String body})?> memory(
    String method, {
    String? id,
    Map<String, String>? user,
  }) async {
    try {
      final path = id == null ? '' : '/${Uri.encodeComponent(id)}';
      final request = http.Request(method, Uri.parse('${config.apiBaseUrl}/v1/memory$path'))
        ..headers.addAll({
          ..._headers,
          if (user?['id'] case final who?) 'X-Rendel-User': who,
          if (user?['hmac'] case final hmac?) 'X-Rendel-User-Hmac': hmac,
        });
      final response = await http.Response.fromStream(
        await _http.send(request).timeout(config.requestTimeout),
      );
      return (status: response.statusCode, body: response.body);
    } catch (_) {
      return null;
    }
  }

  Future<void> identify(Map<String, dynamic> body) async {
    await _http
        .post(
          Uri.parse('${config.apiBaseUrl}/v1/identify'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(config.requestTimeout);
  }

  /// The whole conversation, newest `limit` messages. Not convergence: the
  /// route takes no `after_seq` and this has no callers yet. Kept because the
  /// console and any host that wants to rehydrate a thread need it.
  Future<List<Map<String, dynamic>>> fetchMessages(String conversationId) async {
    final response = await _http
        .get(
          Uri.parse('${config.apiBaseUrl}/v1/conversations/$conversationId/messages'),
          headers: _headers,
        )
        .timeout(config.requestTimeout);
    if (response.statusCode != 200) return const [];
    final parsed = jsonDecode(response.body) as Map<String, dynamic>;
    return (parsed['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  /// GET /v1/followups/next: the follow-up this device should show now
  /// (design/plans/marketing-channels.md §3.10), written by the server at the
  /// moment it is asked. Null when there is none (204), which is most of the
  /// time, and on any failure: a follow-up is never worth an error.
  Future<RendelFollowup?> nextFollowup() async {
    try {
      final response = await _http
          .get(Uri.parse('${config.apiBaseUrl}/v1/followups/next'), headers: _headers)
          .timeout(config.requestTimeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      return body is Map ? RendelFollowup.tryParse(body['followup']) : null;
    } catch (_) {
      return null;
    }
  }

  /// GET /v1/followups/inbox: the messages waiting inside Rendel for this
  /// person, whatever channel they went on, newest first. Empty on any
  /// failure: a card is never worth an error.
  Future<List<RendelFollowup>> followupInbox() async {
    try {
      final response = await _http
          .get(Uri.parse('${config.apiBaseUrl}/v1/followups/inbox'), headers: _headers)
          .timeout(config.requestTimeout);
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body);
      final cards = body is Map ? body['cards'] : null;
      if (cards is! List) return const [];
      return cards.map(RendelFollowup.tryParse).whereType<RendelFollowup>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// POST /v1/followups/:id/open: the conversation the server wrote for a
  /// tapped follow-up, or null. The server counts the tap itself.
  Future<String?> openFollowup(String id) async {
    try {
      final response = await _http
          .post(Uri.parse('${config.apiBaseUrl}/v1/followups/${Uri.encodeComponent(id)}/open'), headers: _headers)
          .timeout(config.requestTimeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      final conversationId = body is Map ? body['conversation_id'] : null;
      return conversationId is String ? conversationId : null;
    } catch (_) {
      return null;
    }
  }

  /// POST /v1/push/token: the device's push token (null when the permission
  /// is gone), with its zone and language for quiet hours and the language a
  /// follow-up is written in. Never a throw.
  Future<bool> setPushToken({
    required String? token,
    required String platform,
    String? timezone,
    String? locale,
  }) async {
    try {
      final response = await _http
          .post(
            Uri.parse('${config.apiBaseUrl}/v1/push/token'),
            headers: _headers,
            body: jsonEncode({
              'token': token,
              'platform': platform,
              if (timezone != null) 'timezone': timezone,
              if (locale != null) 'locale': locale,
            }),
          )
          .timeout(config.requestTimeout);
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _http.close();
}

/// An upload the server refused, carrying the sentence it refused with.
///
/// An exception rather than a null, because every caller has to say something
/// to the user: a paperclip that opens a picker and then quietly does nothing
/// is the failure mode this whole feature exists to avoid.
class RendelUploadFailure implements Exception {
  const RendelUploadFailure(this.message);

  /// The server's sentence, or null when there was none to pass on.
  final String? message;

  @override
  String toString() => message ?? 'upload failed';
}

/// The file's own name for the card that shows it ("name · TYPE · size"):
/// URL-encoded, at most 200 characters, cut before the encoding would split
/// a character. Null when there is none.
String? fileNameHeader(String? name) {
  var cut = name?.trim() ?? '';
  while (cut.isNotEmpty && Uri.encodeComponent(cut).length > 200) {
    cut = String.fromCharCodes(cut.runes.toList()..removeLast());
  }
  return cut.isEmpty ? null : Uri.encodeComponent(cut);
}
