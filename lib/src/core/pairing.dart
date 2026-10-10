/// Why a pairing code was not accepted.
enum RendelPairFailure {
  /// The app key is a live one. Pairing is for test builds.
  testOnly,

  /// The code is wrong, was already used, or is older than ten minutes. The
  /// server does not say which, so a guesser learns nothing.
  notFound,

  /// Too many tries from this device, or this app, in the last minute.
  rateLimited,

  /// Anything else: an unreachable network, a refused key, a suspended app.
  failed,
}

/// What `Rendel.pair` answers: the time the console stops watching, or
/// why it is not watching at all.
///
/// Mirrors the web SDK's `PairResult`: [ok] with [endsAt], or not [ok] with a
/// [reason] and a [message] a pairing screen can show as it is.
class RendelPairResult {
  const RendelPairResult.paired(String this.endsAt)
      : ok = true,
        reason = null,
        message = null;

  const RendelPairResult.failed(RendelPairFailure this.reason, String this.message)
      : ok = false,
        endsAt = null;

  final bool ok;

  /// When the console stops watching, ISO 8601 as the server sent it. Only
  /// when [ok].
  final String? endsAt;

  /// Only when not [ok].
  final RendelPairFailure? reason;

  /// The server's sentence, or the SDK's when it gave none. Only when not
  /// [ok].
  final String? message;

  @override
  String toString() => ok ? 'paired until $endsAt' : '${reason!.name}: $message';
}
