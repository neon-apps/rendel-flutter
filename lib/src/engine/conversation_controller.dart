import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/action.dart';
import '../core/batteries.dart' show dial, mail, openExternally;
import '../core/events.dart';
import '../core/locale.dart';
import '../core/log.dart';
import '../core/platform.dart';
import '../core/route.dart';
import '../protocol/protocol.dart';
import '../transport/api_client.dart';

/// What the copilot is actually doing right now.
///
/// Read off real transport state, never a timer: [thinking] means the request
/// is open and no block has arrived, [streaming] means blocks are landing,
/// [runningAction] means the device is executing a handler, and
/// [awaitingConfirmation] means the turn finished on an unresolved confirm
/// card and the next move belongs to the user. The UI renders these verbatim
/// so a spinner never outlives the work it stands for.
enum RendelPhase {
  idle,
  thinking,
  streaming,
  runningAction,
  awaitingConfirmation,
}

/// What became of a form submission.
enum RendelSubmitOutcome {
  /// Nothing was sent: the previous turn was still open.
  busy,

  /// The request went out and the turn failed afterwards. The form stays
  /// unlocked so the answers are not lost, and the thread carries the error.
  failed,

  /// The request went out and the turn completed.
  sent,
}

/// The former spelling, from when the package's types were `NC`: this one
/// shipped as `Nc`. Both resolve to the same enum.
typedef NcSubmitOutcome = RendelSubmitOutcome;

/// One turn in the thread, and its own notifier.
///
/// A streamed token changes exactly one message. Without a per-message
/// notifier the only signal is the controller's, and every listener rebuilds:
/// a thread showing a table, a receipt and a chip row rebuilt roughly a
/// thousand widgets per token, thirty times a second, to append one word to
/// the last paragraph. Finished turns now rebuild never.
class RendelMessage extends ChangeNotifier {
  RendelMessage.user(String text)
      : role = 'user',
        blocks = [
          WireBlock(id: 'local', type: 'text', fallbackText: text, props: {'markdown': text})
            ..ready = true,
        ];

  RendelMessage.assistant() : role = 'assistant', blocks = [];

  final String role;
  final List<WireBlock> blocks;

  /// The server's id for this turn, from `turn.start`. Null for a user
  /// message and for an assistant turn that never started one.
  ///
  /// It is the row this answer was written to, which is what makes a rating
  /// land on an answer rather than on a position in a list.
  String? serverId;

  /// The thumb this device has given this turn: 1, -1, or null for none.
  /// Local, and optimistic — the control has to answer the tap before the
  /// round-trip, and a rating that fails to reach the server is not worth
  /// interrupting anyone about.
  int? rating;

  /// The first picture the user sent with this question, kept on this device
  /// for the line its answer page opens with. Null for every other message.
  Uint8List? image;

  /// The card this turn was about, when it was asked by opening one over its
  /// page, or answered such a question. Null for every other turn: a detail
  /// is no page.
  RendelDetail? detail;

  /// Something inside this turn changed: a token arrived, a block hydrated, a
  /// confirm card resolved.
  void touch() => notifyListeners();
}

/// A card opened over its page (`design/DETAIL.md`): what the card itself
/// carried, which draws the head at once, and the turns that answered it.
class RendelDetail {
  RendelDetail({
    required this.title,
    this.subtitle,
    this.price,
    this.images = const [],
  });

  final String title;
  final String? subtitle;
  final String? price;

  /// The card's picture first, then any more of the same thing.
  final List<String> images;

  /// Every assistant turn the question led to, in order.
  final List<RendelMessage> answers = [];

  /// Which card this is, so opening it again finds what was fetched.
  String get key => '$title\n${subtitle ?? ''}\n${images.firstOrNull ?? ''}';

  /// Whether anything came back to show.
  bool get answered => answers.any((answer) => answer.blocks.isNotEmpty);

  /// `message.detail_of`.
  Map<String, dynamic> toWire() => {
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (images.isNotEmpty) 'image_url': images.first,
      };
}

/// A notifier the controller can tick without exposing `notifyListeners`.
class _Signal extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Owns one visible thread: sends messages, folds the SSE stream into block
/// state, runs read-action handlers, and issues continuation requests for
/// tool results and confirmations.
class ConversationController extends ChangeNotifier {
  ConversationController({
    required this.api,
    required this.actions,
    this.routes = const {},
    required this.sdkVersion,
    this.contextProviders = const {},
    this.sandbox = false,
    this.onOpenUrl,
    this.streamIdleTimeout = const Duration(seconds: 45),
    this.autoRetryDelay = const Duration(seconds: 3),
    this.locale,
    this.languages = const [],
    this.onEvent,
    this.onUnavailable,
    this.user = _nobody,
    this.cardSources = const {},
    this.parallelReads = _always,
  });

  static bool _always() => true;

  /// Whether context providers and device reads run side by side, up to four
  /// at once, rather than one after another. On unless the app config says
  /// `parallel_reads: false`: the server's switch, so a fault in the parallel
  /// path is turned off without waiting for a release.
  final bool Function() parallelReads;

  /// The text a full-text action replaces, per action (`Rendel.setCardSource`),
  /// for the card's "Changes".
  final Map<String, Future<String?> Function(Map<String, dynamic> params)> cardSources;

  /// The current text for [action]'s full-text card, or null when the app
  /// gave none (or the action did not ask for it with `fullText.current`).
  /// Resolves null when the app's source failed.
  Future<String?>? currentTextFor(String action, Map<String, dynamic> params) {
    if (actions[action]?.fullText?.current != true) return null;
    final source = cardSources[action];
    if (source == null) return null;
    return source(params).then<String?>((text) => text, onError: (Object _) => null);
  }

  static Map<String, String>? _nobody() => null;

  final RendelApiClient api;

  /// Who is signed in right now, read on every turn — `identify` and `reset`
  /// can change it while the thread is open. Null sends `user: null`, which
  /// tells the server nobody is.
  final Map<String, String>? Function() user;
  final Map<String, RendelAction> actions;

  /// The screens the app registered, by name. A `navigate` to one that is not
  /// here is not drawn as a control.
  final Map<String, RendelRoute> routes;
  final String sdkVersion;
  final Map<String, Future<Map<String, dynamic>> Function()> contextProviders;

  /// The host's `RendelConfig.locale`, or null to use the device's own.
  final String? locale;

  /// The host's `RendelConfig.languages`. Empty sends nothing and leaves the
  /// decision to the console's own list, or to no list at all.
  final List<String> languages;
  final bool sandbox;

  /// The host's URL opener. Null means this build cannot honour `open_url`,
  /// and controls carrying one are not drawn as buttons.
  final Future<void> Function(String url)? onOpenUrl;

  /// How long a turn may go without a server event before it is abandoned.
  final Duration streamIdleTimeout;

  /// How long to wait before trying a turn again by itself when the server
  /// said the model is busy, once (resilience plan §4.3). A random 0–2 s is
  /// added so devices do not retry in step; zero (tests) adds nothing.
  final Duration autoRetryDelay;

  /// True while a busy model's turn is being tried again by itself.
  bool _retryingByItself = false;

  /// Where lifecycle events go. `RendelEvent.messageSent` and
  /// `.actionExecuted` were declared on the public enum from the first
  /// release and emitted by nothing, so a host that wired analytics to them
  /// recorded silence and had no way to tell that from an unused copilot.
  final void Function(RendelEvent event)? onEvent;

  /// A new conversation was refused because the app is paused (credit spent,
  /// budget reached, a daily ceiling): the SDK hides its way in and says
  /// nothing to the user. The argument is for the developer's log.
  final void Function(String reason)? onUnavailable;

  /// An answer to read aloud: the message, its opening's words when the
  /// server sent them, the language they are in when it could tell, and the
  /// token they are spoken from (`/v1/speech`). Called once a question: the
  /// moment the server says the opening is written (`speech`), ahead of the
  /// cards under it, or at the turn's end from a server that does not. The
  /// thread on screen sets it; an answer with no thread open is read by nobody.
  void Function(RendelMessage answer, {String? text, String? lang, String? speech})? onAnswered;

  /// Whether this question's answer has been handed to [onAnswered] already.
  var _readThisQuestion = false;

  /// A quiet line over the composer after a turn: "1 question left today".
  String? hint;

  /// How long a context provider has to answer.
  ///
  /// Deliberately short: this runs on the send path, before the request is
  /// even built, so every millisecond here is a millisecond the user spends
  /// watching a composer that has already accepted their message.
  static const _contextProviderBudget = Duration(milliseconds: 300);

  /// At most this many providers or reads at once: one app's handlers share
  /// its network.
  static const _parallel = 4;

  /// The largest result the server accepts, as JSON characters
  /// (`packages/protocol/src/chat.ts`). It refuses the whole turn over one
  /// that is larger, so a handler that returns a big list ended the turn
  /// rather than reporting a failed action the model can talk about.
  static const _maxResultChars = 16384;

  final List<RendelMessage> messages = [];

  /// Fires when the *shape* of the thread changes: a message added or removed,
  /// the phase, the busy flag, the error. Deliberately silent for streamed
  /// tokens, which change one message and nothing else.
  ///
  /// The thread listens to this for its list and its composer, and to each
  /// message for that message's own contents. The controller itself still
  /// notifies on every event, which is what the scroll-follow tracks.
  Listenable get structure => _structure;
  final _Signal _structure = _Signal();

  bool _disposed = false;

  /// Notify listeners, and say whether the thread's shape changed with it.
  ///
  /// A device handler can outlive the controller — the user logs out while a
  /// destructive action is still running — and the turn that resumes
  /// afterwards used to tick a disposed signal.
  void _notify({bool structure = true}) {
    if (_disposed) return;
    if (structure) _structure.tick();
    notifyListeners();
  }

  /// Ids of blocks that have already arrived in this conversation. The thread
  /// plays a block's entrance once and never again, so scrolling back through
  /// a long answer re-reads it rather than re-animating it.
  final Set<String> enteredBlockIds = {};
  String? conversationId;

  /// The server's id for the most recent turn, shown with an error so a
  /// support message carries something an operator can search for.
  String? lastRequestId;
  String? manifestHash;
  bool busy = false;
  RendelPhase phase = RendelPhase.idle;

  /// The step the server last said this turn is on (`turn.status`): null
  /// until it says one, then `action` or `composing`. A step this build does
  /// not know is ignored and the one before it kept. Cleared when the turn
  /// ends.
  String? turnStatus;

  /// The answers a reader can step back and forward through when answers are
  /// pages, oldest first, and the one on screen: an index into [pages], or -1
  /// for the opening screen.
  ///
  /// Here rather than in the sheet, because they live as long as the
  /// conversation does: closing and reopening the sheet must not bring back
  /// the pages a question asked from an older one dropped. The thread screen
  /// keeps them; [reset] empties them with the rest of the conversation.
  final List<RendelMessage> pages = [];
  int page = -1;

  /// The cards opened over their pages in this conversation, by
  /// [RendelDetail.key]: opening one again shows what was fetched, without a
  /// request. Emptied by [reset], as the pages are.
  final Map<String, RendelDetail> details = {};

  /// The card the latest request asked about, whose turns go to it rather
  /// than to a page. Null for a question asked on a page.
  RendelDetail? get detail => _detail;
  RendelDetail? _detail;
  String? errorText;

  /// The assistant said, on purpose, that it will not answer for now (a
  /// usage limit, a paused budget): drawn as the answer, with the composer
  /// resting and saying its hint until it lapses.
  RendelNotice? notice;
  Timer? _noticeTimer;

  /// A notice is in force: nothing is sent until it lapses.
  bool get resting {
    final until = notice?.until;
    return notice != null && (until == null || DateTime.now().isBefore(until));
  }

  void _rest(RendelNotice next) {
    notice = next;
    _noticeTimer?.cancel();
    _noticeTimer = null;
    final until = next.until;
    if (until != null) {
      final wait = until.difference(DateTime.now()) + const Duration(milliseconds: 500);
      // The composer comes back on its own, on a screen left open.
      if (!wait.isNegative && wait < const Duration(days: 40)) {
        _noticeTimer = Timer(wait, () => _notify());
      }
    }
  }

  /// Which error [errorText] is, for the thread to say in its own language.
  ///
  /// The wire code for one the server sent, whose message already arrives in
  /// the app's language; one of the SDK's own names for the ones raised here,
  /// whose [errorText] is English and is there for logs and tests. The
  /// controller has no strings, on purpose, so the words live in the thread.
  String? errorCode;

  /// Last request payload, kept so a dropped connection is one tap from a
  /// retry instead of a retyped message.
  Map<String, dynamic>? _lastPayload;

  /// Whether the error on screen is one a resend can fix. The server says so
  /// on the wire (`retryable`); ignoring it gave a capped or rate-limited app
  /// an error bar with a Retry that could never work — the user taps it, the
  /// same refusal streams back, forever.
  bool _lastErrorRetryable = true;
  bool get canRetry =>
      errorText != null && _lastPayload != null && !busy && _lastErrorRetryable;

  /// Wire-index → block for the turn currently streaming.
  final Map<int, WireBlock> _turnBlocks = {};

  /// Bumped by [reset]. A turn in flight compares it against the value it
  /// started with: logging out mid-answer used to leave `_run` writing into an
  /// `_openAssistant` that reset had already set to null.
  int _generation = 0;
  RendelMessage? _openAssistant;
  final Map<String, ActionExecute> _pendingReads = {};

  /// The `form_id` of the form whose submission is in flight, from the
  /// request that sent it until the next message. Set in [_run].
  String? _submittingFormId;

  /// The revision on screen for each `surface_id` this conversation has
  /// drawn. The blocks themselves are found by walking the thread, so a
  /// block that left it some other way cannot linger here as a reference.
  final Map<String, int> _surfaceRevisions = {};

  /// Returns false when nothing was sent because the previous turn was still
  /// open. A block that renders its own "you picked this" state has to know:
  /// marking a slot chosen after a tap that was dropped is a lie the user acts
  /// on later.
  Future<bool> send(
    String text, {
    List<String> attachments = const [],
    RendelDetail? detail,
    Uint8List? image,
  }) async {
    if (busy || text.trim().isEmpty || resting) return false;
    errorText = null;
    errorCode = null;
    hint = null;
    _abandonOpenConfirmCards();
    _detail = detail;
    messages.add(RendelMessage.user(text.trim())
      ..detail = detail
      ..image = image);
    _notify();

    onEvent?.call(RendelEvent.messageSent);

    await _run({
      'message': {
        'text': text.trim(),
        if (detail != null) 'detail_of': detail.toWire(),
      },
      // Ids, uploaded before this turn was sent. Carried unchanged through
      // `retry` with the turn_id below, so the documented one-tap recovery
      // never uploads the same file twice.
      if (attachments.isNotEmpty) 'attachments': attachments,
      // Minted here and carried unchanged through `retry`, so the server can
      // tell a resend of this turn from a new one. Both `model_busy` and a
      // dropped stream are raised after the message has been persisted, so
      // without it the one-tap recovery wrote the user's words twice and
      // billed the app twice.
      'turn_id': _turnId(),
    });
    return true;
  }

  /// A v4-shaped uuid. Cryptographically random, and that is load-bearing:
  /// since the idempotency key became app-scoped (migration 0004), a replayed
  /// turn_id is also the server's resume oracle — it returns the conversation
  /// id and the last assistant turn's blocks to whoever presents it. A
  /// predictable generator would let one device holding the app's publishable
  /// key walk into another device's thread.
  String _turnId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  final Random _rng = Random.secure();


  /// Send a completed form back as a `form_submission` continuation request.
  ///
  /// Values are `String`, `num` or `bool` — the union `formSubmission` accepts
  /// on the wire. Like every other continuation this is a fresh POST rather
  /// than a write into an open stream, so a form that is submitted on a train
  /// resumes instead of failing.
  /// Reports what happened to the submission, which the form draws.
  ///
  /// This used to be a bool that returned `errorText == null`, so a POST that
  /// reached the server and then lost its stream came back the same as one
  /// that was never sent — and the form said "the assistant is still working"
  /// over an error bar reading "the connection dropped". Worse, it left the
  /// form unlocked, so the obvious next move resubmitted a return request the
  /// server had already accepted.
  Future<RendelSubmitOutcome> submitForm(
    String formId,
    Map<String, Object> values,
  ) async {
    if (busy) return RendelSubmitOutcome.busy;
    errorText = null;
    errorCode = null;
    _abandonOpenConfirmCards();
    // A form is answered on a page; the thread closes a detail before one
    // is sent from it.
    _detail = null;
    _notify();

    await _run({
      'form_submission': {'form_id': formId, 'values': values},
      'turn_id': _turnId(),
    });

    // Sent means the request left. Whether the turn then succeeded is the
    // thread's story to tell, in the error bar, with the retry beside it.
    return errorText == null ? RendelSubmitOutcome.sent : RendelSubmitOutcome.failed;
  }

  /// Send what the user picked on a block that offers a choice — a size on a
  /// `variant_picker`, a time on `datetime_slots` — as a `selection` turn.
  ///
  /// By id rather than as a sentence, so the model gets back the ids it wrote
  /// instead of reading them out of a label, and the server can check the
  /// pick against the block it drew. [shown] is what the question says on
  /// screen and in the thread: the words the user tapped, not the ids.
  ///
  /// The option is marked chosen before the request leaves. The tap is the
  /// answer, and a chip that waits for a round trip to light reads as a tap
  /// that missed. Returns false when nothing was sent: a turn is still open,
  /// or the block does not offer [id] for picking, as with a sold-out size.
  /// Values the user changed on [card], a `confirm_card`, before confirming:
  /// sent to the server, which checks them as it checks the model's call and
  /// redraws the card. On success the card's props become the redrawn ones,
  /// which is what a confirm then runs on, and null is returned. Otherwise
  /// what was wrong, by parameter, with `''` for a change that did not reach
  /// the server at all.
  Future<Map<String, String>?> editCard(WireBlock card, Map<String, dynamic> edits) async {
    final invocationId = card.props['invocation_id'];
    if (invocationId is! String || _isResolved(invocationId)) return {'': 'closed'};
    final answer = await api.editInvocation(invocationId, edits);
    final redrawn = answer.card;
    if (redrawn == null) return answer.fields ?? {'': 'unreachable'};
    // What this device keeps on the card itself survives the redraw.
    final local = {
      for (final entry in card.props.entries)
        if (entry.key.startsWith('_')) entry.key: entry.value,
    };
    card.props
      ..clear()
      ..addAll(redrawn)
      ..addAll(local);
    _notify();
    return null;
  }

  Future<bool> select(WireBlock block, String id, {required String shown}) async {
    if (busy || !_stillOffers(block, id)) return false;
    block.props[RendelLocalKeys.chosen] = id;
    await _sendSelection(block, {
      'block_id': block.id,
      'ids': [id],
    }, shown);
    return true;
  }

  /// Answer a `choice`: the options picked, by id; or what the user wrote in
  /// its `other` row, as [otherText] with no ids; or nothing at all, for its
  /// `skip`. Sent as a `selection` turn, as [select] sends a size, once the
  /// answer has been checked against the block the way the server will
  /// check it.
  ///
  /// [lit] is how long a single pick stays lit before it is sent, so the tap
  /// is seen to land before the page dissolves. It is waited out here rather
  /// than in the block because whether a tap counts is decided at the tap:
  /// one made during a turn must not light at all.
  ///
  /// Once sent, the block is answered for good and folds into [shown]. The
  /// server refuses a second answer, so a block that offered one would be a
  /// question that lies about being open. Returns false when nothing was
  /// sent: a turn is open, the block is already answered, or the answer is
  /// not one it takes.
  Future<bool> choose(
    WireBlock block,
    List<String> ids, {
    required String shown,
    String? otherText,
    Duration lit = Duration.zero,
  }) async {
    final written = otherText?.trim();
    if (busy || _choosing || !_takesAnswer(block, ids, written)) return false;
    if (lit > Duration.zero) {
      final generation = _generation;
      _choosing = true;
      block.props[RendelLocalKeys.chosen] = List<String>.of(ids);
      _touchBlock(block);
      await Future<void>.delayed(lit);
      _choosing = false;
      // Something else may have been asked while the pick was lit, typed or
      // tapped elsewhere, or the conversation may be gone. The pick goes dark
      // rather than staying lit over a question it never asked.
      if (busy || generation != _generation) {
        block.props.remove(RendelLocalKeys.chosen);
        _touchBlock(block);
        return false;
      }
    }
    block.props[RendelLocalKeys.answered] = {
      'ids': List<String>.of(ids),
      if (written != null) 'other_text': written,
      'shown': shown,
    };
    await _sendSelection(block, {
      'block_id': block.id,
      'ids': List<String>.of(ids),
      if (written != null) 'other_text': written,
    }, shown);
    return true;
  }

  /// A single pick on a `choice` is lit and not yet sent.
  ///
  /// Every other entry point is guarded by [busy], which is not set until the
  /// pick is sent; without this a second chip tapped inside the lit window
  /// would be a second answer to the same question.
  bool _choosing = false;

  /// The tail every pick shares: [shown] is asked over the screen, and
  /// [selection] goes up in its place.
  Future<void> _sendSelection(
    WireBlock block,
    Map<String, dynamic> selection,
    String shown,
  ) async {
    errorText = null;
    errorCode = null;
    _abandonOpenConfirmCards();
    // A choice is a question asked on a page; the thread closes a detail
    // before one is sent from it.
    _detail = null;
    _touchBlock(block);
    messages.add(RendelMessage.user(shown));
    _notify();

    onEvent?.call(RendelEvent.messageSent);

    await _run({'selection': selection, 'turn_id': _turnId()});
  }

  /// Redraws the turn that holds [block], whose props were just changed.
  void _touchBlock(WireBlock block) {
    for (final message in messages) {
      if (message.blocks.any((b) => identical(b, block))) message.touch();
    }
  }

  /// Re-issue the request that failed. Safe to call only while [canRetry].
  /// Rate one assistant turn.
  ///
  /// Optimistic and best effort. The control answers the tap immediately —
  /// a thumb that waits for a network round-trip before it moves feels
  /// broken — and a failure to reach the server is not worth interrupting
  /// someone's conversation about. Tapping the same thumb again clears it,
  /// which is the behaviour every thumb control in every product has.
  ///
  /// A turn with no `serverId` cannot be rated: it never got a `turn.start`,
  /// so there is no row on the other end to attach an opinion to.
  Future<void> rateTurn(RendelMessage message, int rating) async {
    final id = message.serverId;
    if (id == null || (rating != 1 && rating != -1)) return;

    final cleared = message.rating == rating;
    message.rating = cleared ? null : rating;
    message.touch();
    if (cleared) return;

    await api.sendFeedback({'message_id': id, 'rating': rating});
  }

  /// A channel of the `contact` block [block] was tapped (analytics-roi T3):
  /// its kind only, never the address. Fire and forget.
  void contactOpened(WireBlock block, String channel) {
    if (!const {'call', 'email', 'url'}.contains(channel)) return;
    final id = messages
        .where((message) => message.blocks.any((b) => identical(b, block)))
        .firstOrNull
        ?.serverId;
    if (id == null) return;
    unawaited(api.sendEvent({
      'type': 'contact_open',
      'message_id': id,
      'block_id': block.id,
      'channel': channel,
    }));
  }

  /// Answer [block], a `rating`, with [score], and with [comment] when the
  /// user wrote one: `POST /v1/ratings`, recorded as it is (A4).
  ///
  /// No turn, so nothing is asked over the screen, no page opens, and a turn
  /// in flight does not stop it: the copilot hears nothing of a rating. A
  /// comment goes up with the score again, which the server keeps beside the
  /// first. Returns whether the server took it; on false the block says so
  /// and the user taps again. A score its scale lacks, or a block on a turn
  /// with no `serverId`, has no row to land on and is not sent.
  Future<bool> rate(WireBlock block, int score, {String? comment}) async {
    if (block.type != 'rating' || !ratingScores(block.props).contains(score)) return false;
    final id = messages
        .where((message) => message.blocks.any((b) => identical(b, block)))
        .firstOrNull
        ?.serverId;
    if (id == null) return false;
    final written = comment?.trim();
    return api.sendRating({
      'message_id': id,
      'block_id': block.id,
      'score': score,
      if (written != null && written.isNotEmpty) 'comment': written,
    });
  }

  Future<void> retry() async {
    final payload = _lastPayload;
    if (payload == null || busy) return;
    errorText = null;
    errorCode = null;
    _notify();
    await _run(payload);
  }

  /// True when the card's `expires_at` has passed.
  ///
  /// The server enforces the same window when the result arrives, so this is
  /// not the only guard — but it is the one that runs before the handler does,
  /// and the handler is what actually charges the card. Do not weaken it on
  /// the assumption that the server will catch the case: by then the local
  /// side effect has already happened.
  bool _isExpired(String invocationId) {
    for (final message in messages) {
      for (final block in message.blocks) {
        if (block.type == 'confirm_card' &&
            block.props['invocation_id'] == invocationId) {
          final raw = block.props['expires_at'];
          if (raw is! String) return false;
          final at = DateTime.tryParse(raw);
          return at != null && DateTime.now().toUtc().isAfter(at.toUtc());
        }
      }
    }
    return false;
  }

  Future<bool> confirmInvocation(String invocationId, {String? typed}) async {
    // Every other entry point guards on `busy`; these two did not, and the
    // outgoing button row stays hit-testable for the length of the card's
    // resolution animation. A double tap on "Yes, do it" ran the destructive
    // handler twice.
    if (busy || _isResolved(invocationId) || _isExpired(invocationId)) {
      return false;
    }
    // What it leads to is drawn where the card is, page or detail.
    _detail = _detailOfCard(invocationId);
    // The handler below can run for seconds. If a logout lands inside it, this
    // turn belongs to nobody and must not post its result into whatever
    // conversation exists by then.
    final generation = _generation;
    // A console action the API runs itself, as the signed-in user: there is no
    // handler on this device to find, and none is needed. The tap is the whole
    // of this side's part.
    final card = _cardFor(invocationId);
    final runsOnServer = card?.props['executes'] == 'server';
    final action = runsOnServer ? null : _actionForInvocation(invocationId);
    if (!runsOnServer && action == null) {
      // Silently returning left the card unanswered, `busy` false and the
      // phase parked on awaitingConfirmation forever: the user taps Confirm
      // and nothing at all happens. The read path already reports this exact
      // condition, so report it the same way and let the turn finish.
      _markConfirmCard(invocationId, confirmed: false);
      await _run({
        'tool_results': [
          {
            'invocation_id': invocationId,
            'status': 'error',
            'error': 'action not registered on this device',
          }
        ],
      }, generation);
      // The tap was dispatched; it is the action that was missing, and the
      // card is now resolved either way.
      return true;
    }
    _markConfirmCard(invocationId, confirmed: true);
    // The handler for a write or destructive action runs before the
    // continuation request, so without this the page sits silent between
    // "Confirm" and the result: the pill says the app is being checked.
    busy = true;
    phase = RendelPhase.runningAction;
    _notify();

    // Tell the server the tap happened, BEFORE running anything.
    //
    // This is what lets the server stop trusting a boolean this device sends
    // about itself. The record is written from the user's press, not from the
    // handler's report, so a client that never taps cannot manufacture one.
    //
    // Awaited but not gated on: an app whose customer has not turned
    // server-mediated confirmation on is served exactly as before, and a
    // network blip on this call must not cost the user the action they just
    // authorised. The server is the one that decides whether the record was
    // required.
    final recorded = await api.recordDecision(invocationId, confirm: true, typed: typed);
    if (recorded == 'typed_mismatch') {
      // Not what the card asked for: open again, with the reason under the field.
      for (final message in messages) {
        for (final block in message.blocks) {
          if (block.type == 'confirm_card' && block.props['invocation_id'] == invocationId) {
            block.props.remove(RendelLocalKeys.resolved);
            block.props[RendelLocalKeys.mismatch] = true;
            message.touch();
          }
        }
      }
      busy = false;
      phase = RendelPhase.idle;
      _notify();
      return false;
    }
    if (recorded == 'expired') {
      // The card outlived its ten minutes while it sat on screen. Running the
      // handler now would perform an action the server is about to refuse to
      // record, which is the one ordering that can leave a real-world effect
      // with no row behind it.
      _markConfirmCard(invocationId, confirmed: false);
      busy = false;
      phase = RendelPhase.idle;
      errorText = 'That confirmation expired. Ask again and I will redo it.';
      errorCode = 'confirmation_expired';
      _notify();
      return true;
    }
    if (generation != _generation) return true;
    if (action == null) {
      // The server runs the action on this very request, after checking the
      // tap recorded above, and it needs the user's token to do it — which
      // every /v1/chat request carries. Success here means "confirmed", not
      // "done": what happened comes back as the answer.
      await _run({
        'tool_results': [
          {'invocation_id': invocationId, 'status': 'success', 'confirmed': true}
        ],
      }, generation);
      return true;
    }
    final result = await _execute(action.$1, action.$2, invocationId: invocationId);
    if (generation != _generation) return true;
    await _run({
      'tool_results': [
        {
          'invocation_id': invocationId,
          'status': result.ok ? 'success' : 'error',
          'confirmed': true,
          if (result.ok) 'data': result.data,
          if (!result.ok) 'error': result.error,
        }
      ],
    }, generation);
    return true;
  }

  Future<bool> declineInvocation(String invocationId) async {
    if (busy || _isResolved(invocationId)) return false;
    _detail = _detailOfCard(invocationId);
    _markConfirmCard(invocationId, confirmed: false);
    // Recorded server-side too, so a "no" is as much a fact on the record as
    // a "yes". Without this the decline path would be the one place the
    // device still spoke for the user unchallenged.
    await api.recordDecision(invocationId, confirm: false);
    await _run({
      'tool_results': [
        {'invocation_id': invocationId, 'status': 'declined'}
      ],
    });
    return true;
  }

  /// Whether this build can carry out [action] at all.
  ///
  /// Renderers ask before drawing a tap surface. `open_url` needs a host
  /// handler, and an `app_action` inside a block is only executable once the
  /// server has stamped it with an invocation id — until then it is a
  /// proposal, not an invocation, and a control that fires nothing must not
  /// look like a control.
  bool handles(UIAction action) => switch (action) {
        ReplyAction() || ConfirmAction() || CancelAction() => true,
        // An external link goes to the system, which needs nothing from the
        // host; any other opens through the host's handler.
        OpenUrlAction(:final external) => external || onOpenUrl != null,
        NavigateAction(:final route) => routes.containsKey(route),
        // The SDK's own: the dialler, the mail app, the clipboard and the
        // event editor need nothing from the host.
        CallAction() || EmailAction() || CopyAction() || AddToCalendarAction() => true,
        AppActionRef(:final invocationId) => invocationId != null,
      };

  /// The reply and block a navigate to [route] with [params] came from, newest
  /// reply first, or null for one no reply carries or a reply the server
  /// never named. A control parses its action from the block's raw props as
  /// it draws, so the block is found by the same navigate in those props.
  Map<String, String>? navigateOrigin(String route, Map<String, Object?> params) {
    bool same(Object? raw) {
      if (raw is! Map || raw['kind'] != 'navigate' || raw['route'] != route) return false;
      final parsed = UIAction.tryParse(raw);
      return parsed is NavigateAction && mapEquals(parsed.params, params);
    }

    bool holds(Object? value) {
      if (same(value)) return true;
      if (value is Map) return value.values.any(holds);
      if (value is List) return value.any(holds);
      return false;
    }

    for (final message in messages.reversed) {
      final id = message.serverId;
      if (message.role != 'assistant' || id == null) continue;
      for (final block in message.blocks) {
        if (holds(block.props)) return {'message_id': id, 'block_id': block.id};
      }
    }
    return null;
  }

  /// Runs [action], reporting whether it actually went anywhere.
  ///
  /// False means the tap was dropped — almost always because the previous turn
  /// is still open. The pill already says why; what the renderer
  /// needs from this is permission not to draw a result that did not happen.
  Future<bool> tapAction(UIAction action) async {
    switch (action) {
      case ReplyAction(:final text):
        return send(text);
      case ConfirmAction(:final invocationId, :final typed):
        return confirmInvocation(invocationId, typed: typed);
      case CancelAction(:final invocationId):
        return declineInvocation(invocationId);
      case OpenUrlAction(:final url, external: true):
        // A maps or wallet link, to the app that opens it. Like a call, it
        // waits on no turn.
        return openExternally(url);
      case OpenUrlAction(:final url):
        // The host opens it. The SDK takes no URL-launching dependency and
        // never navigates on its own.
        final open = onOpenUrl;
        if (open == null) return false;
        await open(url);
        return true;
      case NavigateAction(:final route, :final params):
        // The app's own navigation, with the params the server checked. The
        // thread does not wait on it to draw anything, so a screen that takes
        // a while to open costs nothing here.
        final screen = routes[route];
        if (screen == null) return false;
        final from = navigateOrigin(route, params);
        try {
          await screen.open(params);
        } catch (err) {
          RendelLog.warn('route_open_failed', 'the "$route" route threw while opening', error: err);
          return false;
        }
        // The open, reported for the app's Screens page (0073). Not awaited:
        // a count that does not land never holds up the screen.
        if (from != null) unawaited(api.sendScreenOpen({...from, 'route': route}));
        return true;
      // These three wait on no turn, as a link does not: they put something
      // into the user's hands and the copilot hears nothing of it.
      case CallAction(:final phone):
        return dial(phone);
      case EmailAction(:final address):
        return mail(address);
      case CopyAction(:final text):
        try {
          await Clipboard.setData(ClipboardData(text: text));
          return true;
        } on PlatformException catch (err) {
          RendelLog.warn('copy_failed', 'the clipboard refused the value', error: err);
          return false;
        }
      case AddToCalendarAction():
        return RendelPlatform.addToCalendar(
          title: action.title,
          startsAt: action.startsAt,
          endsAt: action.endsAt,
          location: action.location,
          notes: action.notes,
        );
      case AppActionRef():
        // Reserved. A block-borne app_action is not executable client-side
        // until the server stamps it; `handles` keeps it from being drawn as
        // a live control in the meantime.
        return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Anything still in flight is now someone else's turn to abandon.
    _generation++;
    _structure.dispose();
    // Messages are deliberately not disposed here. `reset()` clears the list
    // while the thread is still mounted, and a widget that then detaches from
    // an already-disposed notifier throws; a notifier with no listeners is
    // just an object, so letting them be collected is both safe and correct.
    super.dispose();
  }

  void reset() {
    _generation++;
    conversationId = null;
    messages.clear();
    enteredBlockIds.clear();
    _turnBlocks.clear();
    _openAssistant = null;
    _pendingReads.clear();
    _lastPayload = null;
    _submittingFormId = null;
    _surfaceRevisions.clear();
    pages.clear();
    page = -1;
    details.clear();
    _detail = null;
    busy = false;
    phase = RendelPhase.idle;
    turnStatus = null;
    errorText = null;
    errorCode = null;
    notice = null;
    _noticeTimer?.cancel();
    _noticeTimer = null;
    _notify();
  }

  // ————————————————————————— internals —————————————————————————

  /// [inherited] carries the generation of the turn that led here.
  ///
  /// Reading `_generation` fresh on every entry made the guard a no-op for the
  /// two paths that re-enter after awaiting a device handler — a continuation
  /// issued after a logout got a brand-new valid generation and stitched the
  /// previous user's action result into the next user's conversation.
  Future<void> _run(Map<String, dynamic> payload, [int? inherited]) async {
    final generation = inherited ?? _generation;
    if (generation != _generation) return;
    // A question of the person's, not the continuation of one: its answer is
    // read anew.
    if (inherited == null) _readThisQuestion = false;
    _lastPayload = payload;
    // `send`, `submitForm` and `retry` clear this; the confirm, decline and
    // pending-read continuations did not, so an error from an earlier turn
    // survived a turn that succeeded and left a failure bar and a live Retry
    // sitting under a correct answer.
    errorText = null;
    errorCode = null;
    busy = true;
    phase = RendelPhase.thinking;
    _notify();

    // A form whose answers are on their way is spoken for, through every
    // continuation the submission leads to, even though the form only marks
    // itself sent once the whole chain has finished. Only a new question ends
    // that, typed or picked: a failed submission leaves the form open again.
    final asks = payload.containsKey('message') || payload.containsKey('selection');
    final submission = payload['form_submission'];
    if (submission is Map) {
      final id = submission['form_id'];
      _submittingFormId = id is String ? id : null;
    } else if (asks) {
      _submittingFormId = null;
    }

    // Read on a question and nowhere else: a submission already carries its
    // form's values, and a tool result is the device answering, not the user.
    final openForms = asks ? _openForms() : const <Map<String, dynamic>>[];

    // Each provider keeps its own budget. Side by side, the turn waits for
    // the slowest of them rather than for all of them added up, and the keys
    // keep the providers' order whichever answers first.
    final providers = contextProviders.entries.toList();
    final answers = await _pooled<Map<String, dynamic>?>(providers.length, (i) async {
      final entry = providers[i];
      try {
        return await entry.value().timeout(_contextProviderBudget);
      } catch (err) {
        // A slow provider never blocks the turn — but it used to disappear
        // entirely. `context_provider_timeout` was named in `RendelLogRecord`'s
        // own list of stable codes and in the docs, and nothing ever emitted
        // it: a provider that threw on every turn cost the copilot the cart
        // it was supposed to know about, silently, forever. The whole point
        // of `onLog` is that the SDK stops being a black box, and this was
        // the one place still painted.
        RendelLog.warn(
          err is TimeoutException ? 'context_provider_timeout' : 'context_provider_failed',
          'context provider "${entry.key}" did not answer in time; '
              'this turn runs without it',
          error: err,
        );
        return null;
      }
    });
    final context = <String, dynamic>{
      for (var i = 0; i < providers.length; i++)
        if (answers[i] != null) providers[i].key: answers[i],
    };

    final body = {
      ...payload,
      if (conversationId != null) 'conversation_id': conversationId,
      'user': user(),
      'client': {
        'protocol': protocolVersion,
        'sdk': sdkVersion,
        'catalog_version': catalogVersion,
        'components': supportedComponents,
        'capabilities': clientCapabilities,
        'actions': clientActions,
        if (manifestHash != null) 'manifest_hash': manifestHash,
        // The language this turn should be answered in.
        //
        // `RendelAction.confirmTemplates` has been documented, implemented on the
        // server (`orchestrator.ts` reads `client.locale` and picks the
        // matching sentence) and covered by its own test suite for as long as
        // it has existed — and no SDK ever sent the field, so every localized
        // confirmation sentence a customer wrote was silently discarded and
        // every user saw the default one. The handshake schema has always
        // accepted it as optional; this is the line that fills it.
        //
        // The host's own first, because an app with a language picker knows
        // what its user chose and the phone does not: a device set to English
        // running a Turkish app should not make the copilot the one English
        // thing on the screen. The device's locale is the fallback, which is
        // right for every app that never thought about it.
        'locale': resolveLocale(locale),
        // The languages this build is willing to be answered in, as opposed to
        // the one language this device is set to. An app ships strings for
        // some set of languages and its support team reads some set of
        // languages; those are the same fact and neither is a phone setting.
        if (languages.isNotEmpty) 'languages': languages,
      },
      if (context.isNotEmpty || openForms.isNotEmpty)
        'context': {
          if (context.isNotEmpty) 'app_state': context,
          if (openForms.isNotEmpty) 'open_forms': openForms,
        },
    };

    // Context providers are awaited above, up to 300ms each, which is another
    // window a logout lands in. Checked here rather than only in the loop,
    // because the next three lines put a bubble on a thread that was cleared.
    if (generation != _generation) return;

    _turnBlocks.clear();
    _openAssistant = RendelMessage.assistant()..detail = _detail;
    _detail?.answers.add(_openAssistant!);
    messages.add(_openAssistant!);
    _pendingReads.clear();
    var awaitingReads = false;
    // A byte stream can simply stop — a proxy, a load balancer, a handoff
    // between networks. There is no exception and no timeout in that case, so
    // half an answer was presented as a whole one: no error bar, no retry, and
    // any action the turn had announced was never run.
    var settled = false;
    // The answer is a notice: not a failure, and not "no answer".
    var noticed = false;
    // A turn whose only blocks were older drawings of something already on
    // screen did answer; there is just nothing new to show for it.
    var droppedStale = false;
    // `turn.end` said the answer is complete, and in which language.
    var completed = false;
    String? answerLang;
    String? answerSpeech;

    try {
      // A stalled stream is indistinguishable from a slow one until it is
      // timed. Without this the composer sat disabled on "Working…" for as
      // long as the app was open, with no way back.
      await for (final event in api.chat(body).timeout(streamIdleTimeout)) {
        // A logout landed while this turn was open. Everything it was writing
        // into is gone, and the next line would dereference it.
        if (generation != _generation) return;
        // Not every event changes what is on screen, and the only listener is
        // the thread, which rebuilds every visible block when it hears one.
        var visible = true;
        var structural = true;
        switch (event) {
          case TurnStart(:final conversationId, :final messageId, :final requestId):
            this.conversationId = conversationId;
            lastRequestId = requestId;
            _openAssistant?.serverId = messageId;
            visible = false;
          case TurnStatus(:final step):
            if (step == 'action' || step == 'composing') {
              turnStatus = step;
            } else {
              visible = false;
            }
          case BlockStart(:final index, :final id, :final blockType):
            // Only the first block of a turn changes the thread's shape, by
            // ending the wait for one; the rest just extend a message.
            structural = phase != RendelPhase.streaming;
            phase = RendelPhase.streaming;
            final block = WireBlock(id: id, type: blockType, fallbackText: '', props: {});
            _turnBlocks[index] = block;
            _openAssistant!.blocks.add(block);
            _openAssistant!.touch();
          case BlockDelta(:final index, :final textDelta):
            _turnBlocks[index]?.streamingText += textDelta;
            _openAssistant?.touch();
            // A token changes one paragraph in one turn. Nothing about the
            // thread's shape moved, so nothing else needs to hear it.
            structural = false;
          case BlockReady(:final index, :final block):
            // A retry or a resumed stream can deliver an old drawing of a
            // surface after a newer one. Dropped before anything else, so it
            // cannot take a form's place or a surface's either.
            if (_isStaleSurface(block)) {
              droppedStale = true;
              _dropSkeleton(index);
              structural = false;
              break;
            }
            // Before the skeleton is looked up: the form or surface this one
            // replaces may sit earlier in this same turn, and removing it
            // moves the slot. The form goes first, so a form carrying both
            // ids is merged and removed once; the surface pass then finds
            // nothing left of it to remove.
            final emptiedByForm = block.type == 'form' && _adoptForm(block);
            final emptiedBySurface = _adoptSurface(block);
            final emptiedTurn = emptiedByForm || emptiedBySurface;
            final existing = _turnBlocks[index];
            // Only a skeleton is replaced. A settled block has already been
            // read; a repeated index — which a server-side correction round
            // could mint — must add to the turn, never delete from it.
            if (existing != null && !existing.ready) {

              final position = _openAssistant!.blocks.indexOf(existing);
              _openAssistant!.blocks[position] = block;
              // The skeleton already played the entrance for this slot, so
              // the id is carried forward and hydration cannot re-arm it.
              enteredBlockIds.add(block.id);
            } else {
              // No skeleton preceded it, so nothing has entered yet. Marking
              // it here — which is what used to happen for both branches —
              // meant BlockEnter's own `seen.add` returned false the first
              // time it mounted, and a block that arrived ready in one frame
              // appeared with no entrance at all.
              _openAssistant!.blocks.add(block);
            }
            _turnBlocks[index] = block;
            _openAssistant!.touch();
            // Hydration changes one block inside one message. The message has
            // just been told; nothing else needs to be — unless the form it
            // replaced took a whole earlier turn with it.
            structural = emptiedTurn;
          case ActionExecute():
            _pendingReads[event.invocationId] = event;
            structural = false;
          case TurnEnd(:final status, :final remainingHint, :final lang, :final speech):
            settled = true;
            completed = status == 'completed';
            answerLang = lang;
            answerSpeech = speech;
            if (remainingHint != null) hint = remainingHint;
            if (status == 'error' && errorText == null) {
              // The separate `error` frame usually carries the message; if it
              // was the frame that got lost, this is all we have.
              errorText = 'Something failed while finishing that. Try again.';
              errorCode = 'turn_failed';
              _lastErrorRetryable = true;
            }
            awaitingReads = status == 'awaiting_tool_results' && _pendingReads.isNotEmpty;
          case final RendelNotice told when told.kind == 'paused':
            // The app is paused: no conversation starts, and the user is told
            // nothing. The question goes with the sheet.
            settled = true;
            noticed = true;
            final asked = messages.lastIndexOf(_openAssistant!) - 1;
            if (asked >= 0 && messages[asked].role == 'user') messages.removeAt(asked);
            onUnavailable?.call(told.kind);
          case final RendelNotice told:
            settled = true;
            noticed = true;
            _openAssistant!.blocks.add(WireBlock(
              id: 'notice',
              type: 'notice',
              fallbackText: told.message,
              props: {
                'kind': told.kind,
                'message': told.message,
                if (told.actionLabel != null && told.actionUrl != null)
                  'action': {'label': told.actionLabel, 'url': told.actionUrl},
              },
            )..ready = true);
            _rest(told);
          case RendelError(:final code, :final message, :final retryable):
            settled = true;
            errorText = message;
            errorCode = code;
            _lastErrorRetryable = retryable;
            // The wire code and the request id, for whoever is debugging.
            // The bar above shows the message; this is the developer's copy.
            RendelLog.warn(
              code,
              '$message${lastRequestId == null ? '' : ' (request $lastRequestId)'}',
            );

          case TurnSpeech(:final token, :final text, :final lang):
            visible = false;
            if (!_readThisQuestion && _openAssistant != null) {
              _readThisQuestion = true;
              onAnswered?.call(_openAssistant!, text: text, lang: lang, speech: token);
            }
          case Ping():
            visible = false;
        }
        if (visible) _notify(structure: structural);
      }
    } on TimeoutException {
      errorText = 'The assistant stopped responding.';
      errorCode = 'copilot_stalled';
      _lastErrorRetryable = true;
    } catch (err) {
      errorText = 'The connection dropped before the answer finished.';
      errorCode = 'stream_dropped';
      _lastErrorRetryable = true;
      RendelLog.error(
        'transport_failed',
        // The id the errors reference tells developers to report. It is on
        // `turn.start`, so it exists for any turn that got that far.
        'the turn stream failed${lastRequestId == null ? '' : ' (request $lastRequestId)'}',
        error: err,
      );
    }

    // The stream can also end between the last event and here.
    if (generation != _generation) return;

    // Any block the server announced but never completed is settled here.
    // Left alone, a half-arrived turn leaves a skeleton pulsing forever or a
    // caret blinking under text that stopped coming.
    //
    // Walks the message, not `_turnBlocks`: a repeated `block.start` on one
    // index displaces the earlier skeleton out of that map, and a skeleton the
    // settle pass cannot reach is a skeleton that pulses forever, which is the
    // exact failure this exists to prevent.
    final open = _openAssistant;
    if (open != null) {
      for (var i = open.blocks.length - 1; i >= 0; i--) {
        final block = open.blocks[i];
        if (block.ready) continue;
        if (block.type == 'text') {
          block.props['markdown'] = block.streamingText;
          block.ready = true;
          continue;
        }
        // A non-text block that never hydrated has empty props, and marking it
        // ready sent it straight past its own skeleton into the real builder —
        // a blank plate inside a turn that presented as a clean success.
        //
        // `block.start` carries no fallback text (the server sends it with
        // `block.ready`), so there is usually nothing to say in its place and
        // the honest move is to drop it. If a fallback did arrive, it becomes
        // a sentence, which is what `fallback_text` is for. Either way
        // `_pruneEmptyAssistant` removes the turn if this was all of it, and
        // the empty-turn branch below reports it.
        _turnBlocks.removeWhere((_, value) => identical(value, block));
        if (block.fallbackText.isEmpty) {
          open.blocks.removeAt(i);
        } else {
          open.blocks[i] = WireBlock(
            id: block.id,
            type: 'text',
            fallbackText: block.fallbackText,
            props: {'markdown': block.fallbackText},
          )..ready = true;
        }
      }
    }




    // Neither `turn.end` nor an error arrived, so the stream was cut rather
    // than finished.
    if (!settled && errorText == null) {
      errorText = 'The connection dropped before the answer finished.';
      errorCode = 'stream_dropped';
      _lastErrorRetryable = true;
    }

    final produced = _turnBlocks.isNotEmpty || droppedStale || noticed;

    // Kept past the prune, which lets go of it, for whoever reads it aloud.
    final answer = open;
    _pruneEmptyAssistant();

    if (awaitingReads) {
      await _runPendingReads(generation);
      return; // _runPendingReads issues the continuation, which re-enters _run.
    }

    // A busy model, before anything was drawn: try the same turn again once,
    // by itself, after a short wait. It carries the same turn id, so the
    // server reuses the conversation and nothing is written twice. A second
    // `model_busy` is shown as usual, with its Retry.
    final busyPayload = _lastPayload;
    if (errorCode == 'model_busy' && !produced && !_retryingByItself && busyPayload != null) {
      _retryingByItself = true;
      errorText = null;
      errorCode = null;
      _notify();
      final jitter = autoRetryDelay == Duration.zero ? 0 : Random().nextInt(2000);
      await Future<void>.delayed(autoRetryDelay + Duration(milliseconds: jitter));
      try {
        if (generation == _generation) await _run(busyPayload, inherited);
      } finally {
        _retryingByItself = false;
      }
      return;
    }

    // A turn that ends having said nothing is indistinguishable, on screen,
    // from one that is still thinking: the pill disappears and the screen
    // simply sits there. Whatever went wrong upstream, the user is
    // owed a sentence and the retry that goes with it.
    if (!produced && errorText == null) {
      errorText = 'No answer came back. Try again.';
      errorCode = 'no_answer';
      _lastErrorRetryable = true;
    }

    busy = false;
    turnStatus = null;
    phase = _hasOpenConfirmCard()
        ? RendelPhase.awaitingConfirmation
        : RendelPhase.idle;

    // A turn that produced a confirm card is finished; only its terminator was
    // lost. Re-sending the message would hand the server a history whose
    // `tool_use` nothing has answered — a hard failure on the model call, and
    // if it does not fail, a second invocation for the same action that no
    // later turn can ever reach. The next move belongs to the card.
    if (phase == RendelPhase.awaitingConfirmation) _lastPayload = null;
    _notify();

    if (completed && errorText == null && answer != null && messages.contains(answer) && !_readThisQuestion) {
      _readThisQuestion = true;
      onAnswered?.call(answer, lang: answerLang, speech: answerSpeech);
    }
  }


  /// Mark every unanswered confirm card as abandoned.
  ///
  /// Asking something else is an answer of a kind, and the server treats it as
  /// one: `closeAbandonedInvocations` expires the invocation before the new
  /// message lands. Without the same move here the card stayed live, `phase`
  /// parked on `awaitingConfirmation` for the rest of the session, and tapping
  /// Confirm on the stale card still ran a destructive handler whose result
  /// the server then discarded — the action happened, and the model was never
  /// told.
  void _abandonOpenConfirmCards() {
    for (final message in messages) {
      var touched = false;
      for (final block in message.blocks) {
        if (block.type == 'confirm_card' &&
            block.props[RendelLocalKeys.resolved] == null) {
          block.props[RendelLocalKeys.resolved] = 'abandoned';
          touched = true;
        }
      }
      if (touched) message.touch();
    }
  }

  /// True when this card has already been confirmed or declined. A resolved

  /// card is never confirmable again, whatever manages to tap it.
  bool _isResolved(String invocationId) {
    for (final message in messages) {
      for (final block in message.blocks) {
        if (block.type == 'confirm_card' &&
            block.props['invocation_id'] == invocationId) {
          return block.props[RendelLocalKeys.resolved] != null;
        }
      }
    }
    return false;
  }

  /// True when the last turn ended on a confirm card the user has not yet
  /// answered, which is a wait on the user rather than on us.
  bool _hasOpenConfirmCard() {
    for (final message in messages.reversed) {
      for (final block in message.blocks) {
        if (block.type == 'confirm_card' && block.props[RendelLocalKeys.resolved] == null) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _runPendingReads(int generation) async {
    phase = RendelPhase.runningAction;
    _notify();
    // A snapshot: `reset()` clears `_pendingReads`, and clearing a map being
    // iterated across an await throws a ConcurrentModificationError out of
    // `_runPendingReads` — which is called outside `_run`'s try, so it escaped
    // `send()` entirely and landed as an unhandled zone error.
    //
    // Side by side, up to four at once. Each result names its invocation, and
    // the list keeps the order the server asked in.
    final pending = _pendingReads.values.toList();
    final results = await _pooled<Map<String, dynamic>?>(pending.length, (i) async {
      final read = pending[i];
      // Logged out while reads run: nothing more starts, and nothing is sent.
      if (generation != _generation) return null;
      final action = actions[read.name];
      if (action == null) {
        return {
          'invocation_id': read.invocationId,
          'status': 'error',
          'error': 'action not registered on this device',
        };
      }
      final result = await _execute(action, read.params, invocationId: read.invocationId);
      return {
        'invocation_id': read.invocationId,
        'status': result.ok ? 'success' : 'error',
        if (result.ok) 'data': result.data,
        if (!result.ok) 'error': result.error,
      };
    });
    if (generation != _generation) return;
    _pendingReads.clear();
    await _run({'tool_results': results}, generation);
  }

  /// `run(0)` to `run(count - 1)`, up to four at a time, or one at a time
  /// while the server has parallel reads off; each result stays at its index.
  Future<List<T>> _pooled<T>(int count, Future<T> Function(int i) run) async {
    final results = List<T?>.filled(count, null);
    final width = parallelReads() ? _parallel : 1;
    var next = 0;
    Future<void> worker() async {
      while (next < count) {
        final i = next++;
        results[i] = await run(i);
      }
    }

    await Future.wait([for (var w = 0; w < min(width, count); w++) worker()]);
    return results.cast<T>();
  }

  Future<RendelResult> _execute(
    RendelAction action,
    Map<String, dynamic> params, {
    required String invocationId,
  }) async {
    if (sandbox && action.sandboxResult != null) {
      return RendelResult.ok(action.sandboxResult);
    }
    try {
      final outcome = await action
          .run(RendelInvocation(
            id: invocationId,
            name: action.name,
            params: params,
            risk: action.risk,
          ))
          .timeout(action.timeout);
      onEvent?.call(RendelEvent.actionExecuted);
      return _capped(action, outcome);
    } on TimeoutException {
      // Logged as well as returned. A handler that quietly exceeds its budget
      // is one of the failures a developer cannot see from the device: the
      // model is told the action failed and the person debugging is told
      // nothing at all.
      RendelLog.warn('handler_timeout',
          '"${action.name}" exceeded its ${action.timeout.inSeconds}s budget');
      return RendelResult.fail(
        'handler timed out after ${action.timeout.inMilliseconds}ms',
      );
    } catch (err, stack) {
      RendelLog.error('handler_failed', '"${action.name}" threw',
          error: err, stackTrace: stack);
      return RendelResult.fail(err.toString());
    }
  }

  /// [outcome], or a failure in its place when its data is larger than the
  /// server accepts, worded as the web SDK words it. The result would also
  /// ride in the next thirty turns' history if it were let through.
  RendelResult _capped(RendelAction action, RendelResult outcome) {
    final data = outcome.data;
    if (!outcome.ok || data == null) return outcome;
    final int length;
    try {
      length = jsonEncode(data).length;
    } catch (_) {
      // Not JSON at all: left to fail where it always has.
      return outcome;
    }
    if (length <= _maxResultChars) return outcome;
    RendelLog.warn(
      'result_too_large',
      '"${action.name}" returned $length bytes; the limit is $_maxResultChars. '
          'Return only the fields Rendel needs.',
    );
    return RendelResult.fail('result was $length bytes, over the $_maxResultChars byte limit');
  }

  WireBlock? _cardFor(String invocationId) {
    for (final message in messages.reversed) {
      for (final block in message.blocks) {
        if (block.type == 'confirm_card' &&
            block.props['invocation_id'] == invocationId) {
          return block;
        }
      }
    }
    return null;
  }

  /// The detail the turn holding this card answered, if it did.
  RendelDetail? _detailOfCard(String invocationId) {
    for (final message in messages.reversed) {
      for (final block in message.blocks) {
        if (block.type == 'confirm_card' &&
            block.props['invocation_id'] == invocationId) {
          return message.detail;
        }
      }
    }
    return null;
  }

  (RendelAction, Map<String, dynamic>)? _actionForInvocation(String invocationId) {
    for (final message in messages.reversed) {
      for (final block in message.blocks) {
        if (block.type == 'confirm_card' &&
            block.props['invocation_id'] == invocationId) {
          final raw = block.props['action_name'];
          final name = raw is String ? raw : null;
          final action = name != null ? actions[name] : null;
          if (action == null) return null;
          // Machine-readable params ship on the card and are the only thing a
          // handler may run on. `params_display` is a stringly-typed rendering
          // for humans — every value passed through String() and truncated at
          // 200 characters — so rebuilding an invocation from it would execute
          // a destructive action with different arguments from the ones the
          // user was shown. A card without machine params is not confirmable.
          final params = block.props['params'];
          if (params is! Map) return null;
          return (action, params.cast<String, dynamic>());
        }
      }
    }
    return null;
  }

  void _markConfirmCard(String invocationId, {required bool confirmed}) {
    for (final message in messages) {
      for (final block in message.blocks) {
        if (block.type == 'confirm_card' &&
            block.props['invocation_id'] == invocationId) {
          block.props[RendelLocalKeys.resolved] = confirmed ? 'confirmed' : 'declined';
          message.touch();
        }
      }
    }
    _notify();
  }

  // ———————————————————— forms that update in place ————————————————————

  /// The id a form is submitted under: its `form_id`, or its block id when
  /// the wire left that out, as the form itself does.
  static String _formIdOf(WireBlock block) {
    final id = block.props['form_id'];
    return id is String && id.isNotEmpty ? id : block.id;
  }

  static List<Map> _namedFields(WireBlock block) {
    final fields = block.props['fields'];
    if (fields is! List) return const [];
    return [
      for (final field in fields)
        if (field is Map && field['name'] is String) field,
    ];
  }

  /// A form's working values, seeded with the model's own on first read.
  ///
  /// The form does the same when it is first drawn, and both read and write
  /// the one map on the block. Seeding here as well means a form nobody has
  /// scrolled to yet still has values to report and to carry over.
  static Map<String, dynamic> _valuesOf(WireBlock block) {
    final existing = block.props[RendelLocalKeys.values];
    if (existing is Map<String, dynamic>) return existing;
    final values =
        existing is Map ? existing.cast<String, dynamic>() : <String, dynamic>{};
    for (final field in _namedFields(block)) {
      for (final seed in formFieldSeeds(field).entries) {
        values.putIfAbsent(seed.key, () => seed.value);
      }
    }
    block.props[RendelLocalKeys.values] = values;
    return values;
  }

  /// Puts [incoming] in place of the open form it redraws, if there is one.
  ///
  /// The model reshapes a form by sending it again under the same `form_id`;
  /// drawn beside the first, the user would have two forms for one thing and
  /// half their answers in each. So the old one leaves the thread and the new
  /// one, arriving where the conversation now is, starts from what the user
  /// had. A form that was sent, or is being sent, is a record of what went,
  /// and is never replaced.
  ///
  /// Returns true when the old form was all its turn had, and that turn left
  /// the thread with it.
  bool _adoptForm(WireBlock incoming) {
    // A form with no fields draws as an empty plate and has nothing to carry;
    // one with no props at all has a read-only map that cannot be written.
    if (_namedFields(incoming).isEmpty) return false;
    _valuesOf(incoming);
    final id = _formIdOf(incoming);
    if (id == _submittingFormId) return false;
    for (final message in messages.reversed) {
      for (final old in message.blocks.reversed) {
        if (identical(old, incoming) || old.type != 'form' || !old.ready) continue;
        if (_formIdOf(old) != id || old.props[RendelLocalKeys.submitted] == true) {
          continue;
        }
        _carryForm(old, incoming);
        message.blocks.remove(old);
        _turnBlocks.removeWhere((_, block) => identical(block, old));
        // A turn with nothing left in it would draw as a gap with a rating
        // under it. The open turn stays: the new form is about to land in it.
        if (message.blocks.isNotEmpty || identical(message, _openAssistant)) {
          message.touch();
          return false;
        }
        messages.remove(message);
        return true;
      }
    }
    return false;
  }

  /// What [incoming] starts from, given the form it replaces.
  ///
  /// Per field of the new form: a value the user entered stays, whatever the
  /// model now proposes for it, because the server told the model not to
  /// touch it and a model can still get that wrong; otherwise the model's new
  /// value; otherwise what the field held before. A field the new form no
  /// longer has goes, with its value and its edited mark.
  static void _carryForm(WireBlock old, WireBlock incoming) {
    final before = _valuesOf(old);
    final rawEdited = old.props[RendelLocalKeys.edited];
    final editedBefore =
        rawEdited is Iterable ? rawEdited.toSet() : const <Object?>{};

    final values = <String, dynamic>{};
    final edited = <String>{};
    // By key rather than by name: a date range is two values, each of which
    // the user may have set and the model may propose on its own.
    for (final field in _namedFields(incoming)) {
      final proposed = formFieldSeeds(field);
      for (final key in formFieldKeys(field)) {
        if (editedBefore.contains(key)) {
          edited.add(key);
          if (before.containsKey(key)) {
            values[key] = before[key];
            continue;
          }
        }
        if (proposed.containsKey(key)) {
          values[key] = proposed[key];
        } else if (before.containsKey(key)) {
          values[key] = before[key];
        }
      }
    }
    incoming.props[RendelLocalKeys.values] = values;
    if (edited.isNotEmpty) incoming.props[RendelLocalKeys.edited] = edited;

    // The files behind an upload field's ids go with them, or the new form
    // would hold the ids with no thumbnail to show or remove them by.
    final files = old.props[RendelLocalKeys.files];
    if (files is Map) {
      incoming.props[RendelLocalKeys.files] = {
        for (final field in _namedFields(incoming))
          if (field['kind'] == 'upload' && files.containsKey(field['name']))
            field['name']: files[field['name']],
      };
    }

    // Someone typing into the form as it is redrawn carries on typing, in the
    // same field of the new one, rather than losing the keyboard mid-word.
    final focused = old.props[RendelLocalKeys.focused];
    if (focused is String &&
        _namedFields(incoming).any((field) => field['name'] == focused)) {
      incoming.props[RendelLocalKeys.refocus] = focused;
    }
  }

  // ———————————————————— blocks that replace themselves ————————————————————

  /// True when [incoming] is a drawing of a surface no newer than the one on
  /// screen, which is then logged and must not be shown.
  bool _isStaleSurface(WireBlock incoming) {
    final surface = incoming.surfaceId;
    final revision = incoming.revision;
    if (surface == null || revision == null) return false;
    final shown = _surfaceRevisions[surface];
    if (shown == null || revision > shown) return false;
    RendelLog.report(
      RendelLogLevel.debug,
      'surface_stale',
      'surface "$surface" revision $revision arrived with revision $shown '
          'on screen; dropped',
    );
    return true;
  }

  /// Takes back the skeleton [index] announced, for a block that will not
  /// arrive after all.
  void _dropSkeleton(int index) {
    final skeleton = _turnBlocks[index];
    if (skeleton == null || skeleton.ready) return;
    _turnBlocks.remove(index);
    _openAssistant?.blocks.remove(skeleton);
    _openAssistant?.touch();
  }

  /// Puts [incoming] in place of every earlier drawing of its surface.
  ///
  /// The model names a thing that will change — a cart, an order — and draws
  /// it again under the same `surface_id` as it changes. Shown beside the
  /// first, the thread would hold two carts that disagree. So the earlier one
  /// leaves, and the new one arrives where the conversation now is, keeping
  /// whatever the user picked in the old one that it still offers.
  ///
  /// Unlike a form, a surface is replaced even once it was acted on: the
  /// server numbered this drawing after that one, and it only does that for
  /// the same thing. A block with a `surface_id` and no `revision` is an
  /// ordinary block, neither replacing nor replaced.
  ///
  /// Returns true when an earlier turn was left with nothing and went too.
  bool _adoptSurface(WireBlock incoming) {
    final surface = incoming.surfaceId;
    final revision = incoming.revision;
    if (surface == null || revision == null) return false;
    _surfaceRevisions[surface] = revision;
    var emptied = false;
    for (final message in messages.toList()) {
      final earlier = [
        for (final old in message.blocks)
          if (!identical(old, incoming) &&
              old.surfaceId == surface &&
              old.revision != null)
            old,
      ];
      if (earlier.isEmpty) continue;
      for (final old in earlier) {
        _carrySurface(old, incoming);
        message.blocks.remove(old);
        _turnBlocks.removeWhere((_, block) => identical(block, old));
      }
      // As for a form: an emptied turn goes, the open one stays.
      if (message.blocks.isNotEmpty || identical(message, _openAssistant)) {
        message.touch();
        continue;
      }
      messages.remove(message);
      emptied = true;
    }
    return emptied;
  }

  /// What [incoming] keeps of the drawing it replaces: the slot or option the
  /// user picked, if the new one still offers it and, for a picker, names no
  /// selection of its own; and the keyboard, if the
  /// new one has the field that held it. A choice whose option is gone, or is
  /// now sold out, is dropped rather than left pointing at nothing. A form's
  /// values are not carried here; `_adoptForm` has already done that for the
  /// form it replaces.
  static void _carrySurface(WireBlock old, WireBlock incoming) {
    if (old.type != incoming.type) return;
    final chosen = old.props[RendelLocalKeys.chosen];
    // A picker redrawn with its own selection already heard the tap: it went
    // up as a selection, and "make it L" must not lose to the M picked before.
    final modelSelects = incoming.type == 'variant_picker' &&
        incoming.props['selected_id'] is String;
    if (chosen is String && !modelSelects && _stillOffers(incoming, chosen)) {
      incoming.props[RendelLocalKeys.chosen] = chosen;
    }
    final focused = old.props[RendelLocalKeys.focused];
    if (incoming.type == 'form' &&
        focused is String &&
        _namedFields(incoming).any((field) => field['name'] == focused)) {
      incoming.props[RendelLocalKeys.refocus] = focused;
    }
  }

  /// Whether [block] is a `choice` still open to the answer [ids] and
  /// [written]: options it offers, none twice, as many as its mode allows;
  /// or no ids, with [written] for its `other` row or nothing for its `skip`.
  /// The rules the server holds a selection to (`selectionOptions` in
  /// packages/protocol), so an answer it would refuse is never sent.
  static bool _takesAnswer(WireBlock block, List<String> ids, String? written) {
    final props = block.props;
    if (block.type != 'choice' || props[RendelLocalKeys.answered] != null) return false;
    if (ids.isEmpty) {
      if (written == null) return props['skip'] is Map;
      return props['other'] is Map && written.isNotEmpty && written.length <= 300;
    }
    if (written != null) return false;
    final offered = choiceOptionIds(props).toSet();
    if (ids.toSet().length != ids.length || !ids.every(offered.contains)) return false;
    final (min, max) = choiceBounds(props);
    return ids.length >= min && ids.length <= max;
  }

  /// Whether [block] still has a choice with id [id] the user could pick.
  static bool _stillOffers(WireBlock block, String id) {
    final (key, mustBeAvailable) = switch (block.type) {
      'datetime_slots' => ('slots', false),
      'variant_picker' => ('options', true),
      _ => (null, false),
    };
    if (key == null) return false;
    final choices = block.props[key];
    if (choices is! List) return false;
    return choices.any((choice) =>
        choice is Map &&
        choice['id'] == id &&
        (!mustBeAvailable || choice['available'] != false));
  }

  /// `context.open_forms`: the three most recent forms the user has not
  /// sent, with what is in them now.
  ///
  /// So "make it a refund to my card" is answered knowing which order and
  /// reason were already picked, and the model can redraw the form around
  /// them. Only a form with a `form_id` is listed, because that id is the
  /// only name the model has for it. Everything is cut to what the request
  /// schema accepts: one oversized value would cost the whole message.
  List<Map<String, dynamic>> _openForms() {
    final open = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final message in messages.reversed) {
      for (final block in message.blocks.reversed) {
        if (block.type != 'form' || !block.ready) continue;
        if (block.props[RendelLocalKeys.submitted] == true) continue;
        final id = block.props['form_id'];
        if (id is! String || id.isEmpty || id.length > 64 || !seen.add(id)) {
          continue;
        }
        final values = <String, Object>{};
        for (final entry in _valuesOf(block).entries) {
          final value = _wireValue(entry.value);
          if (entry.key.length <= 64 && value != null) values[entry.key] = value;
        }
        final edited = block.props[RendelLocalKeys.edited];
        open.add({
          'form_id': id,
          'values': values,
          'edited': [
            if (edited is Iterable)
              for (final name in edited)
                if (name is String && name.length <= 64) name,
          ].take(40).toList(),
        });
        if (open.length == 3) return open;
      }
    }
    return open;
  }

  /// A form value as the wire takes it: text up to 500 characters, a finite
  /// number, a bool, or up to 100 strings — a multi_select's picks, an
  /// upload's ids. Anything else — a cleared picker's null — is left out.
  static Object? _wireValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is List) {
      return [for (final item in value.whereType<String>().take(100)) _wireText(item)];
    }
    if (value is! String) return null;
    return _wireText(value);
  }

  static String _wireText(String value) {
    if (value.length <= 500) return value;
    // Never half a surrogate pair: the cut would leave a character that is
    // not one.
    final lead = value.codeUnitAt(499);
    return value.substring(0, lead >= 0xD800 && lead <= 0xDBFF ? 499 : 500);
  }

  void _pruneEmptyAssistant() {
    final open = _openAssistant;
    if (open != null && open.blocks.isEmpty) messages.remove(open);
    _openAssistant = null;
  }
}
