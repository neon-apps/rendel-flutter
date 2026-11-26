import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transport/api_client.dart';
import 'log.dart';
import 'strings.dart';

/// Who wrote a line of the thread with the app's team.
enum RendelSupportAuthorKind { user, agent, system }

/// Why an address will not do, by the rule the API holds it to (zod's
/// `email()` after a trim, at most 254 characters), or null when it is fine:
/// `empty` or `invalid`. Checked on the phone first, so the person reads it
/// under the field instead of after a round trip, as the web SDK does.
String? supportEmailProblem(String value) {
  final email = value.trim();
  if (email.isEmpty) return 'empty';
  return email.length <= 254 && _email.hasMatch(email) ? null : 'invalid';
}

final _email = RegExp(r"^(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9-]*\.)+[A-Za-z]{2,}$");

/// One durable line of the thread (`support.entry`): the person's, the team's,
/// or a marker the server wrote ("Your message is with the Grove team.").
class RendelSupportEntry {
  const RendelSupportEntry({
    required this.id,
    required this.seq,
    required this.marker,
    required this.author,
    required this.authorName,
    this.text,
    this.blocks = const [],
    this.files = const [],
    this.pictures = const [],
    this.clientMsgId,
    required this.createdAt,
    this.markerKind,
  });

  final String id;
  final int seq;

  /// A line the server wrote about the thread, drawn as a caption.
  final bool marker;

  /// What the marker says happened: handoff, joined, resolved, auto_resolved…
  final String? markerKind;
  final RendelSupportAuthorKind author;

  /// The name the app chose to show for the team's line: a first name, or the team's.
  final String? authorName;
  final String? text;

  /// Catalog blocks the team sent, checked by the server as the assistant's are.
  final List<Map<String, dynamic>> blocks;

  /// The names of the files sent with this line that are not shown as pictures.
  final List<String> files;

  /// The pictures sent with this line, by the address the server gave them.
  final List<String> pictures;
  final String? clientMsgId;
  final DateTime createdAt;

  static RendelSupportEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final seq = raw['seq'];
    final author = raw['author'];
    if (id is! String || seq is! int || author is! Map) return null;
    final kind = RendelSupportAuthorKind.values.asNameMap()[author['kind']];
    if (kind == null) return null;
    final text = raw['text'];
    final blocks = raw['blocks'];
    final client = raw['client_msg_id'];
    final name = author['name'];
    return RendelSupportEntry(
      id: id,
      seq: seq,
      marker: raw['kind'] == 'marker',
      author: kind,
      authorName: name is String ? name : null,
      text: text is String ? text : null,
      blocks: [
        if (blocks is List)
          for (final b in blocks)
            if (b is Map<String, dynamic>) b,
      ],
      files: [
        if (raw['attachments'] case final List<dynamic> files)
          for (final file in files)
            if (file is Map && !_picture(file)) '${file['name'] ?? file['media_type'] ?? ''}',
      ],
      pictures: [
        if (raw['attachments'] case final List<dynamic> files)
          for (final file in files)
            if (file is Map && _picture(file)) file['url'] as String,
      ],
      clientMsgId: client is String ? client : null,
      createdAt: DateTime.tryParse('${raw['created_at']}') ?? DateTime.now(),
      markerKind: raw['marker'] is String ? raw['marker'] as String : null,
    );
  }
}

/// An image the server can show: drawn as a picture rather than by its name.
bool _picture(Map<dynamic, dynamic> file) => '${file['media_type']}'.startsWith('image/') && file['url'] is String;

/// The words of the card that asks how it went, as the server wrote them.
class RendelSupportRating {
  const RendelSupportRating({
    required this.question,
    required this.up,
    required this.down,
    required this.commentHint,
    required this.send,
    required this.skip,
    required this.thanks,
  });

  final String question;
  final String up;
  final String down;
  final String commentHint;
  final String send;
  final String skip;
  final String thanks;

  static RendelSupportRating? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final words = [raw['question'], raw['up'], raw['down'], raw['comment_hint'], raw['send'], raw['skip'], raw['thanks']];
    if (words.any((w) => w is! String)) return null;
    return RendelSupportRating(
      question: words[0] as String,
      up: words[1] as String,
      down: words[2] as String,
      commentHint: words[3] as String,
      send: words[4] as String,
      skip: words[5] as String,
      thanks: words[6] as String,
    );
  }
}

/// The thread's state (`support.state`).
class RendelSupportState {
  const RendelSupportState({
    required this.threadId,
    required this.mode,
    required this.resolved,
    required this.teamHere,
    this.expectation,
    this.presence,
    this.waiting,
    this.agentName,
    this.teamReadSeq = 0,
    required this.userReadSeq,
    required this.lastSeq,
    required this.contactState,
    required this.contactRequired,
    this.contactOffered = false,
    this.contactBlocking,
    this.rating,
    this.backAt,
    this.closedReason,
    this.contactChannels = const [],
  });

  final String threadId;

  /// Whenever [presence] or [waiting] names when the team is back: that moment, ISO 8601 with the team's offset,
  /// for the page to say on the person's own clock (C4).
  final String? backAt;

  /// `support_off`: closed because the app switched Support off (K1). The page shows [contactChannels] and no box.
  final String? closedReason;

  /// With [closedReason]: the app's own ways to reach the team (`kind` call, email or url, `label`, `value`).
  final List<Map<String, dynamic>> contactChannels;

  /// Closed because the app switched Support off (K1).
  bool get closedOff => closedReason == 'support_off';

  /// K2: with [contactRequired], whether the next line waits for the email now. False while the team is live for
  /// the person: they keep writing, and the card is a request above the box. Null from a server that does not say.
  final bool? contactBlocking;

  /// The team closed this and has not heard how it went: the card's words, in the conversation's language.
  final RendelSupportRating? rating;

  /// ai, waiting, human or closed.
  final String mode;
  final bool resolved;
  final bool teamHere;

  /// A sentence the server wrote in the person's language: "Usually replies in about 10 minutes."
  final String? expectation;

  /// A short line under the team's name: "Dana is here · replies in about 10 minutes", "Back tomorrow at 09:00".
  final String? presence;

  /// While the team is away from an open thread, the row's line: "Waiting for the team · back tomorrow at 09:00".
  final String? waiting;
  final String? agentName;

  /// Lines up to this one were read by the team: "Read" goes under the person's newest run among them.
  final int teamReadSeq;
  final int userReadSeq;
  final int lastSeq;

  /// K14: none, stated, verified or not_needed.
  final String contactState;

  /// The next line waits for an email: nobody could reach the person otherwise.
  final bool contactRequired;

  /// The optional "Want the reply by email too?" may be offered: the app emails people who can't get a notification.
  /// Off, or from a server that does not say, an address given there would never be written to.
  final bool contactOffered;

  RendelSupportState read(int seq) => RendelSupportState(
        threadId: threadId,
        mode: mode,
        resolved: resolved,
        teamHere: teamHere,
        expectation: expectation,
        presence: presence,
        waiting: waiting,
        agentName: agentName,
        teamReadSeq: teamReadSeq,
        userReadSeq: seq,
        lastSeq: lastSeq,
        contactState: contactState,
        contactRequired: contactRequired,
        contactOffered: contactOffered,
        contactBlocking: contactBlocking,
        rating: rating,
        backAt: backAt,
        closedReason: closedReason,
        contactChannels: contactChannels,
      );

  static RendelSupportState? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final thread = raw['thread_id'];
    final mode = raw['mode'];
    if (thread is! String || mode is! String) return null;
    final contact = raw['contact'];
    final agent = raw['agent'];
    final expectation = raw['expectation'];
    final presence = raw['presence'];
    final waiting = raw['waiting'];
    return RendelSupportState(
      threadId: thread,
      mode: mode,
      resolved: raw['state'] == 'resolved',
      rating: RendelSupportRating.tryParse(raw['rating']),
      teamHere: raw['team_here'] == true,
      expectation: expectation is String ? expectation : null,
      presence: presence is String ? presence : null,
      waiting: waiting is String ? waiting : null,
      agentName: agent is Map && agent['name'] is String ? agent['name'] as String : null,
      teamReadSeq: raw['team_read_seq'] is int ? raw['team_read_seq'] as int : 0,
      userReadSeq: raw['user_read_seq'] is int ? raw['user_read_seq'] as int : 0,
      lastSeq: raw['last_seq'] is int ? raw['last_seq'] as int : 0,
      contactState: contact is Map && contact['state'] is String ? contact['state'] as String : 'not_needed',
      contactRequired: contact is Map && contact['required'] == true,
      contactOffered: contact is Map && contact['offer'] == true,
      contactBlocking: contact is Map && contact['blocking'] is bool ? contact['blocking'] as bool : null,
      backAt: raw['back_at'] is String ? raw['back_at'] as String : null,
      closedReason: raw['closed_reason'] is String ? raw['closed_reason'] as String : null,
      contactChannels: [
        if (raw['contact_channels'] case final List<dynamic> channels)
          for (final c in channels)
            if (c is Map<String, dynamic> && c['kind'] is String && c['label'] is String && c['value'] is String) c,
      ],
    );
  }
}

/// One of the person's conversations with the team, for Recent and the list
/// behind it (`GET /v1/support/threads`), newest first.
class RendelSupportThread {
  const RendelSupportThread({
    required this.threadId,
    required this.resolved,
    required this.title,
    this.agent,
    this.last,
    this.unread = 0,
    this.waiting,
    required this.lastMessageAt,
    this.resolvedAt,
    this.backAt,
    this.closedReason,
  });

  final String threadId;
  final bool resolved;

  /// As in the thread's state: when the team is back, whenever [waiting] names it (C4).
  final String? backAt;

  /// As in the thread's state: `support_off` once the app switched Support off (K1).
  final String? closedReason;

  /// Closed because the app switched Support off (K1): said so, never "Sorted".
  bool get closedOff => closedReason == 'support_off';

  /// The person's own first line in it.
  final String title;

  /// Who last wrote for the team; null until the team wrote.
  final String? agent;

  /// The newest line, the person's (`mine`) or the team's.
  final ({bool mine, String text})? last;
  final int unread;
  final String? waiting;
  final DateTime lastMessageAt;
  final DateTime? resolvedAt;

  static RendelSupportThread? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['thread_id'];
    final title = raw['title'];
    final at = DateTime.tryParse('${raw['last_message_at']}');
    if (id is! String || title is! String || at == null) return null;
    final last = raw['last'];
    return RendelSupportThread(
      threadId: id,
      resolved: raw['state'] == 'resolved',
      title: title,
      agent: raw['agent'] is String ? raw['agent'] as String : null,
      last: last is Map && last['text'] is String ? (mine: last['kind'] == 'user', text: last['text'] as String) : null,
      unread: raw['unread'] is int ? raw['unread'] as int : 0,
      waiting: raw['waiting'] is String ? raw['waiting'] as String : null,
      lastMessageAt: at.toLocal(),
      resolvedAt: DateTime.tryParse('${raw['resolved_at']}')?.toLocal(),
      backAt: raw['back_at'] is String ? raw['back_at'] as String : null,
      closedReason: raw['closed_reason'] is String ? raw['closed_reason'] as String : null,
    );
  }
}

/// The email card the page shows (K14, K2): `required` holds the box until the
/// person gives an address; `request` sits above the box while the team is live
/// for them, and they keep writing; null for neither. The first line always
/// goes. A sorted thread asks for nothing until the server held a line for an
/// address ([RendelSupportSnapshot.contactHeld]), so writing in it again never
/// ends on the card (sdk-03). A server that does not say `blocking` blocks.
String? rendelSupportContactNeed(RendelSupportSnapshot v) {
  final state = v.state;
  if (state == null || !state.contactRequired) return null;
  if (v.contactHeld) return 'required';
  if (state.resolved || !v.entries.any((e) => e.author == RendelSupportAuthorKind.user)) return null;
  return state.contactBlocking == false ? 'request' : 'required';
}

/// The app's channels on a page Support's switch closed, read as the assistant's own contact card reads them
/// (qa3-k1-02), as the web SDK's `reachChannels`: what kind of channel and where it goes ("Email support@grove.test",
/// "Call (02) 5550 0100"), never the app's label said again on each one. A link keeps its label.
List<Map<String, dynamic>> rendelSupportReachChannels(List<Map<String, dynamic>> channels, RendelStrings strings) => [
      for (final c in channels)
        switch (c['kind']) {
          'call' => {...c, 'label': strings.call},
          'email' => {...c, 'label': strings.email},
          _ => c,
        },
    ];

/// Someone from the team has started on it: they wrote, joined, or read the person's account. "By mistake? Back to
/// the assistant" is offered only before that, so a conversation the team acted in is never put away as a slip
/// (qa2-sdk-05), as the web SDK's `teamStarted`.
bool rendelSupportTeamStarted(List<RendelSupportEntry> entries) => entries.any(
    (e) => (!e.marker && e.author == RendelSupportAuthorKind.agent) || (e.marker && (e.markerKind == 'joined' || e.markerKind == 'lookup')));

/// The same read of their account said twice in a row: drawn once (check-08).
bool rendelSupportSameLookup(RendelSupportEntry? prev, RendelSupportEntry entry) =>
    entry.marker && entry.markerKind == 'lookup' && prev != null && prev.marker && prev.markerKind == 'lookup' && (prev.text ?? '') == (entry.text ?? '');

final _backAt = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?(Z|[+-]\d{2}:\d{2})$');

/// When the team is back, on the person's own clock and in their language
/// (C4, apps-06). Wherever the server's presence or waiting line names a
/// return ([backAt]), the line is said again with that moment as the phone
/// tells the time ([time] and [day] format it, as the page formats its other
/// dates): "Back tomorrow at 09:00" for a team in Istanbul reads "Back today at
/// 10:00 PM" in Los Angeles. The waiting sentence in the team's column says the
/// same, its team-clock time read again where it can be found. With no
/// [backAt], or one past, the server's lines stand.
({String? presence, String? waiting, String? expectation}) rendelSupportBack(
  RendelStrings strings, {
  String? presence,
  String? waiting,
  String? expectation,
  String? backAt,
  required String Function(DateTime local) time,
  required String Function(DateTime date) day,
  DateTime? now,
}) {
  final same = (presence: presence, waiting: waiting, expectation: expectation);
  final match = backAt == null ? null : _backAt.firstMatch(backAt);
  final instant = backAt == null ? null : DateTime.tryParse(backAt);
  final at = now ?? DateTime.now();
  if (match == null || instant == null || !instant.isAfter(at)) return same;
  String when(int inDays, String onDay, String clock) =>
      (inDays == 0 ? strings.supportWhenToday : inDays == 1 ? strings.supportWhenTomorrow : strings.supportWhenDay).replaceAll('{day}', onDay).replaceAll('{time}', clock);
  // The team's own phrase, as the server wrote it: their date against their today, their time.
  final zone = match.group(6)!;
  final offset = zone == 'Z' ? Duration.zero : Duration(hours: int.parse(zone.substring(1, 3)), minutes: int.parse(zone.substring(4, 6))) * (zone.startsWith('-') ? -1 : 1);
  final teamDate = DateTime.utc(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!));
  final teamNow = at.toUtc().add(offset);
  final theirs = when(teamDate.difference(DateTime.utc(teamNow.year, teamNow.month, teamNow.day)).inDays, day(teamDate), '${match.group(4)}:${match.group(5)}');
  // The person's: the same moment on this phone's calendar and clock.
  final local = instant.toLocal();
  final today = at.toLocal();
  final inDays = (DateTime(local.year, local.month, local.day).difference(DateTime(today.year, today.month, today.day)).inHours / 24).round();
  final mine = when(inDays, day(local), time(local));
  return (
    presence: presence == null ? null : strings.supportBackWhen.replaceAll('{when}', mine),
    waiting: waiting == null ? null : strings.supportWaitingWhen.replaceAll('{when}', mine),
    expectation: expectation != null && expectation.contains(theirs) ? expectation.replaceFirst(theirs, mine) : expectation,
  );
}

/// The team's newest unread line, for the banner while Rendel is closed. Its text is empty when the customer hides it.
typedef RendelSupportReply = ({int seq, String name, String text});

/// A line sent from here that the server has not confirmed yet.
class RendelSupportPending {
  const RendelSupportPending(this.clientMsgId, this.text, {this.failed = false, this.attachmentIds = const [], this.reason});

  final String clientMsgId;
  final String text;
  final bool failed;

  /// Files uploaded for this line: a retry sends them, not their name.
  final List<String> attachmentIds;

  /// `rate_limited`: a first line refused because too many conversations were started from here; the page says why (D1).
  /// `support_off`: refused because the app switched Support off; the line says why, with no retry (qa3-k1-01).
  final String? reason;
}

/// A read the team asked to make that waits for the person's yes, in the server's words: [failed] when the answer
/// did not go, [threadId] the thread it was asked in, and [expiresAt] when it goes off the page (check-11).
typedef RendelSupportAsk = ({String lookupId, String text, bool failed, String? threadId, DateTime? expiresAt});

/// Everything the support page draws, in one value so it never draws half a change.
class RendelSupportSnapshot {
  const RendelSupportSnapshot({
    this.threadId,
    this.entries = const [],
    this.state,
    this.typingUntil,
    this.pending = const [],
    this.unread = 0,
    this.asks = const [],
    this.otherOpen,
    this.contactHeld = false,
  });

  final String? threadId;

  /// The server held the person's line for an address: the email card is required until a state says otherwise (K2).
  final bool contactHeld;
  final List<RendelSupportEntry> entries;
  final RendelSupportState? state;

  /// Until when the team's typing line shows.
  final DateTime? typingUntil;
  final List<RendelSupportPending> pending;
  final int unread;

  /// Reads the team asked to make that wait for the person's yes, in the server's words.
  final List<RendelSupportAsk> asks;

  /// A sorted thread could not open again: this other one of the person's is open.
  final String? otherOpen;

  int get cursor => entries.isEmpty ? 0 : entries.last.seq;

  /// The team's questions the page shows: the ones asked in the thread it shows, or with no thread named.
  List<RendelSupportAsk> get asksHere => [for (final a in asks) if (a.threadId == null || a.threadId == threadId) a];

  RendelSupportSnapshot copyWith({
    String? threadId,
    List<RendelSupportEntry>? entries,
    RendelSupportState? state,
    DateTime? typingUntil,
    bool clearTyping = false,
    List<RendelSupportPending>? pending,
    int? unread,
    List<RendelSupportAsk>? asks,
    String? otherOpen,
    bool clearOtherOpen = false,
    bool? contactHeld,
  }) {
    final nextThread = threadId ?? this.threadId;
    final nextState = state ?? this.state;
    // A line held for an address holds the box until another thread, an address, or the team live again (K2).
    final held = contactHeld ??
        (this.contactHeld && nextThread == this.threadId && (nextState?.contactRequired ?? false) && nextState?.contactBlocking != false);
    return RendelSupportSnapshot(
      threadId: nextThread,
      entries: entries ?? this.entries,
      state: nextState,
      typingUntil: clearTyping ? null : (typingUntil ?? this.typingUntil),
      pending: pending ?? this.pending,
      unread: unread ?? this.unread,
      asks: asks ?? this.asks,
      otherOpen: clearOtherOpen ? null : (otherOpen ?? this.otherOpen),
      contactHeld: held,
    );
  }
}

/// The person's thread with the app's own team (design/plans/human-support.md
/// §3, §10), the Web SDK's `SupportSession` line for line.
///
/// Holds the lines by their thread `seq` and the thread's state, keeps one
/// stream open while the support page is on screen (the server holds it about
/// a minute; it reconnects from its cursor, backing off on errors), and closes
/// it when the page goes. Nothing this phone kept is trusted over the server:
/// every open reads `current` from the cursor.
class RendelSupport {
  /// The thread the person is looking at, or null: its push would only repeat the screen.
  final ValueNotifier<String?> onScreen = ValueNotifier<String?>(null);

  RendelSupport(this.api, {required this.user, required this.locale}) {
    unawaited(_loadSkipped());
    unawaited(_loadContact());
  }

  final RendelApiClient api;

  /// Who is signed in right now (`identify`'s `id` and `hmac`); null for nobody.
  final Map<String, String>? Function() user;
  final String Function() locale;

  /// This phone has a conversation with the team: told whenever one is read, so the SDK keeps the person's own
  /// conversations reachable once the app switches Support off (D4).
  VoidCallback? onKnown;

  /// The server says Support is off: a state closed by its switch (with its thread id), or a line, typing or a
  /// first line refused with `support_unavailable` (null). The SDK reads its config again, so a page opened while
  /// Support was on draws the app's channels and no box (qa3-k1-01). Told before that state is drawn.
  void Function(String? threadId)? onOff;

  /// How many times [reset] ran: a page or a list opened before it showed the last person's conversations.
  int get resets => _generation;

  /// Bumped by [reset]: an answer asked for before it is the last person's (qa3-sdk-02).
  int _generation = 0;

  /// Who the thread on hand was read as ('' for nobody signed in).
  String _readAs = '';

  String _who() => user()?['id'] ?? '';

  /// Drawn again as it is: what the SDK reads changed (Support switched off), not the thread.
  void redraw() => value.value = _now.copyWith();

  final ValueNotifier<RendelSupportSnapshot> value = ValueNotifier(const RendelSupportSnapshot());

  StreamSubscription<Map<String, dynamic>>? _stream;
  bool _watching = false;

  /// The stream's loop is running.
  bool _looping = false;
  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);

  /// How a thread that does not exist yet is opened by the person's first
  /// line (K3, Tuna 2026-11-17): the team's page opens at once, and nothing
  /// empty reaches the team's queue. "Contact us" unless the page was opened
  /// from an answer rated down, which carries its conversation.
  ({String trigger, String? conversationId})? _opening;

  RendelSupportSnapshot get _now => value.value;

  /// Whether a conversation with the team is open: the launcher goes back to it.
  bool get open => _open;
  bool _open = false;

  /// A thread the page shows by its id (one from Recent), not the phone's current one.
  String? _viewing;

  /// The team's newest unread line, as the last count read it: for the banner while Rendel is closed.
  RendelSupportReply? get lastReply => _reply;
  RendelSupportReply? _reply;

  /// A thread read whole: its lines and its state in one change. A sorted one
  /// shown by its id says nothing about whether another is open; the phone's
  /// current one does.
  void _apply(String threadId, List<RendelSupportEntry> entries, RendelSupportState state, {bool current = true}) {
    if (!state.resolved) {
      _open = true;
    } else if (current) {
      _open = false;
    }
    _opening = null;
    _applied++;
    _readAs = _who();
    if (_watching) onScreen.value = threadId;
    // Closed by Support's switch: the SDK learns Support is off before it is drawn (qa3-k1-01).
    if (state.closedOff) onOff?.call(threadId);
    final same = threadId == _now.threadId;
    // A first line written before there was a thread is still on its way in the one that now opened.
    final keepPending = same || _now.threadId == null;
    final bySeq = {for (final e in same ? _now.entries : const <RendelSupportEntry>[]) e.seq: e};
    for (final e in entries) {
      bySeq[e.seq] = e;
    }
    final confirmed = {for (final e in entries) if (e.clientMsgId != null) e.clientMsgId};
    value.value = _now.copyWith(
      threadId: threadId,
      entries: bySeq.values.toList()..sort((a, b) => a.seq.compareTo(b.seq)),
      pending: [for (final p in keepPending ? _now.pending : const <RendelSupportPending>[]) if (!confirmed.contains(p.clientMsgId)) p],
      state: state,
      clearOtherOpen: true,
    );
    onKnown?.call();
  }

  void _merge(List<RendelSupportEntry> entries) {
    if (entries.isEmpty) return;
    final bySeq = {for (final e in _now.entries) e.seq: e};
    for (final e in entries) {
      bySeq[e.seq] = e;
    }
    final confirmed = {for (final e in entries) if (e.clientMsgId != null) e.clientMsgId};
    value.value = _now.copyWith(
      entries: bySeq.values.toList()..sort((a, b) => a.seq.compareTo(b.seq)),
      pending: [for (final p in _now.pending) if (!confirmed.contains(p.clientMsgId)) p],
    );
  }

  bool _applyThread(Map<String, dynamic>? json, {bool current = true}) {
    final thread = json?['thread_id'];
    final state = RendelSupportState.tryParse(json?['state']);
    final entries = json?['entries'];
    if (thread is! String || state == null) return false;
    _apply(thread, [
      if (entries is List)
        for (final raw in entries)
          if (RendelSupportEntry.tryParse(raw) case final entry?) entry,
    ], state, current: current);
    return true;
  }

  int _applied = 0;

  /// How many times a thread was read whole from the server: a page that
  /// opens on what the session kept knows by this when the server's answer came.
  int get reads => _applied;

  /// The thread this phone has, if any, brought up to date: the one on the page when it was opened by its id.
  Future<bool> load() async {
    if (_viewing case final id?) return show(id);
    final known = _now.threadId;
    final generation = _generation;
    var answer = await api.support('GET', 'current?after=${known == null ? 0 : _now.cursor}', user: user());
    // Signed out while it was read: the answer was the last person's (qa3-sdk-02).
    if (generation != _generation) return false;
    if (answer.status == 204 && known != null && _readAs != _who()) {
      // Read as somebody else than who is here now: nothing of it is this person's to see (qa3-sdk-02).
      _open = false;
      value.value = RendelSupportSnapshot(unread: _now.unread);
      return false;
    }
    if (answer.status != 200) return known != null;
    // Another thread than the one this phone knows (a new one after a sorted one): its lines are
    // numbered from 1, so the old one's cursor would leave its first lines out (sdk-02).
    if (known != null && _now.cursor > 0 && answer.json?['thread_id'] is String && answer.json?['thread_id'] != known) {
      final whole = await api.support('GET', 'current?after=0', user: user());
      if (generation != _generation) return false;
      if (whole.status == 200) answer = whole;
    }
    // Opened from Contact us with Support on again: a conversation its switch closed is not the one they write in (K1, K3).
    if (_opening != null && known == null && (RendelSupportState.tryParse(answer.json?['state'])?.closedOff ?? false)) return false;
    return _applyThread(answer.json);
  }

  /// A turn handed the person to the team in [threadId]: a different thread
  /// from the one this session holds starts the page from nothing, so the
  /// last one's lines never show above it (sdk-02).
  void handedTo(String threadId) {
    if (threadId.isEmpty || threadId == _now.threadId) return;
    _viewing = null;
    value.value = RendelSupportSnapshot(unread: _now.unread);
  }

  /// Recent and the list behind it: the person's conversations with the team, newest first; null when it could not be read.
  Future<List<RendelSupportThread>?> threads() async {
    final generation = _generation;
    final answer = await api.support('GET', 'threads', user: user());
    final list = answer.json?['threads'];
    // Signed out while they were read: they were the last person's (qa3-sdk-02).
    if (answer.status != 200 || list is! List || generation != _generation) return null;
    final threads = [
      for (final raw in list)
        if (RendelSupportThread.tryParse(raw) case final thread?) thread,
    ];
    if (threads.isNotEmpty) onKnown?.call();
    return threads;
  }

  /// One of the person's threads, by its id: a sorted one comes back as it was, ready to be written in.
  Future<bool> show(String threadId) async {
    final same = _now.threadId == threadId;
    final generation = _generation;
    final answer = await api.support('GET', 'threads/${Uri.encodeComponent(threadId)}?after=${same ? _now.cursor : 0}', user: user());
    if (answer.status != 200 || generation != _generation) return false;
    _viewing = threadId;
    return _applyThread(answer.json, current: false);
  }

  /// The page of a thread shown by its id closed: the session holds the phone's current one again, or none.
  Future<void> restore() async {
    if (_viewing == null) return;
    _viewing = null;
    final generation = _generation;
    final answer = await api.support('GET', 'current?after=0', user: user());
    if (generation != _generation) return;
    if (answer.status == 200 && _applyThread(answer.json)) return;
    _open = false;
    value.value = RendelSupportSnapshot(unread: _now.unread);
  }

  /// The team's page opened with no thread to go back to: the person's first
  /// line opens one, by this [trigger] (`open_support` or `offer`, K3).
  /// Nothing is sent until they write; a thread the page then finds is the
  /// one they write in.
  void begin(String trigger, {String? conversationId}) {
    // One Support's switch closed is not where they write once it is on again: the page starts a new one (K1, K3).
    if (_now.threadId != null && _viewing == null && (_now.state?.closedOff ?? false)) value.value = RendelSupportSnapshot(unread: _now.unread, asks: _now.asks);
    if (_now.threadId != null) return;
    _opening = (trigger: trigger, conversationId: conversationId);
  }

  /// The first line of a thread that does not exist yet opens it, under the
  /// line's own client id, so a retry cannot open two. A thread that was
  /// already open takes the line as its next one. 'ok', 'failed', or
  /// 'rate_limited' when too many conversations were started from here (D1).
  Future<String> _first(String clientMsgId) async {
    final line = _now.pending.where((p) => p.clientMsgId == clientMsgId).firstOrNull;
    if (line == null) return 'failed';
    final how = _opening ?? (trigger: 'open_support', conversationId: null);
    final answer = await api.support('POST', 'handoff', user: user(), body: {
      'trigger': how.trigger,
      'client_msg_id': clientMsgId,
      'locale': locale(),
      if (line.attachmentIds.isEmpty) 'text': line.text,
      if (how.conversationId case final conversation?) 'conversation_id': conversation,
    });
    if (answer.status != 200 || !_applyThread(answer.json)) {
      // Too many conversations started from here (this phone, or its address): the line says why, not only "Not sent" (D1).
      final error = answer.json?['error'];
      final limited = answer.status == 429 && error is Map && error['code'] == 'rate_limited';
      // So does one refused because the app switched Support off meanwhile (qa3-k1-01).
      final off = _isOff(answer.status, answer.json);
      if (off) onOff?.call(null);
      _markFailed(clientMsgId, true, reason: limited ? 'rate_limited' : off ? 'support_off' : null);
      return limited ? 'rate_limited' : 'failed';
    }
    // The thread opened: its stream follows it while the page is on screen.
    if (_watching && !_looping) unawaited(_loop());
    if (!_now.pending.any((p) => p.clientMsgId == clientMsgId)) return 'ok';
    // Not taken with the thread (a file, or a thread already open): it goes as the thread's next line.
    await retry(clientMsgId);
    return _now.pending.any((p) => p.clientMsgId == clientMsgId && p.failed) ? 'failed' : 'ok';
  }

  String _path(String threadId, String rest) => 'threads/${Uri.encodeComponent(threadId)}/$rest';

  /// A line from the person: drawn at once as unsent and reconciled by its client id.
  /// 'ok', 'contact_required', 'another_open', 'too_long', 'rate_limited' or 'failed'. A line in a sorted
  /// thread opens it again, in place, with the server's "reopened" line first.
  /// With no thread yet, it opens one (K3).
  Future<String> send(String text, {List<String> attachmentIds = const [], String? fileName}) async {
    final threadId = _now.threadId;
    final body = text.trim();
    if (body.isEmpty && attachmentIds.isEmpty) return 'failed';
    final id = _uuid();
    value.value = _now.copyWith(pending: [..._now.pending, RendelSupportPending(id, body.isEmpty ? fileName ?? '' : body, attachmentIds: attachmentIds)]);
    if (threadId == null) return _first(id);
    final answer = await api.support('POST', _path(threadId, 'messages'), user: user(), body: {'client_msg_id': id, if (body.isNotEmpty) 'text': body, if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds});
    if (RendelSupportEntry.tryParse(answer.json?['entry']) case final entry? when answer.status == 200) {
      final reopened = RendelSupportEntry.tryParse(answer.json?['reopened']);
      _merge([if (reopened != null) reopened, entry]);
      // Written in a sorted thread: it is open again, with the team, and the state says so. One Support's switch
      // closed was not followed (qa2-k1-04): the stream follows it again now.
      if (reopened != null) {
        await load();
        if (_watching && !_looping) unawaited(_loop());
      }
      return 'ok';
    }
    final error = answer.json?['error'];
    if (answer.status == 409 && error is Map && error['code'] == 'contact_required') {
      value.value = _now.copyWith(pending: [for (final p in _now.pending) if (p.clientMsgId != id) p], contactHeld: true);
      return 'contact_required';
    }
    if (answer.status == 409 && error is Map && error['code'] == 'another_open' && error['thread_id'] is String) {
      value.value = _now.copyWith(pending: [for (final p in _now.pending) if (p.clientMsgId != id) p], otherOpen: error['thread_id'] as String);
      return 'another_open';
    }
    // Refused as it is (longer than the API takes): sending it again would only be refused again, so it goes back in the box.
    if (answer.status == 400 && body.isNotEmpty) {
      value.value = _now.copyWith(pending: [for (final p in _now.pending) if (p.clientMsgId != id) p]);
      return 'too_long';
    }
    if (_refusedOff(answer.status, answer.json, id)) return 'failed';
    _markFailed(id, true);
    return 'failed';
  }

  static bool _isOff(int status, Map<String, dynamic>? json) {
    final error = json?['error'];
    return status == 409 && error is Map && error['code'] == 'support_unavailable';
  }

  /// Refused because the app switched Support off (qa3-k1-01): the line says why instead of a bare "Not sent", the
  /// SDK reads its config again, and the thread is read again, closed, with the app's channels.
  bool _refusedOff(int status, Map<String, dynamic>? json, [String? clientMsgId]) {
    if (!_isOff(status, json)) return false;
    onOff?.call(null);
    if (clientMsgId != null) _markFailed(clientMsgId, true, reason: 'support_off');
    unawaited(load());
    return true;
  }

  void _markFailed(String id, bool failed, {String? reason}) {
    value.value = _now.copyWith(pending: [
      for (final p in _now.pending) p.clientMsgId == id ? RendelSupportPending(id, p.text, failed: failed, attachmentIds: p.attachmentIds, reason: reason) : p,
    ]);
  }

  /// Sends a failed line again, under the same client id, so it cannot arrive twice.
  Future<void> retry(String clientMsgId) async {
    final threadId = _now.threadId;
    final line = _now.pending.where((p) => p.clientMsgId == clientMsgId).firstOrNull;
    if (line == null) return;
    _markFailed(clientMsgId, false);
    // A first line that could not open the thread: it tries again, under the same id.
    if (threadId == null) {
      await _first(clientMsgId);
      return;
    }
    final answer = await api.support('POST', _path(threadId, 'messages'), user: user(), body: {'client_msg_id': clientMsgId, if (line.attachmentIds.isEmpty) 'text': line.text, if (line.attachmentIds.isNotEmpty) 'attachment_ids': line.attachmentIds});
    if (RendelSupportEntry.tryParse(answer.json?['entry']) case final entry? when answer.status == 200) {
      _merge([entry]);
    } else if (!_refusedOff(answer.status, answer.json, clientMsgId)) {
      _markFailed(clientMsgId, true);
    }
  }

  /// The person is typing: said at most every three seconds.
  void typing() {
    final threadId = _now.threadId;
    if (threadId == null || DateTime.now().difference(_lastTyping) < const Duration(seconds: 3)) return;
    _lastTyping = DateTime.now();
    unawaited(api.support('POST', _path(threadId, 'typing'), user: user(), body: const {}).then((answer) => _refusedOff(answer.status, answer.json)));
  }

  /// The read last said to the server.
  ({String threadId, int seq})? _readSent;

  /// Read up to the newest line: the badge clears. Said once per new line.
  void read() {
    final threadId = _now.threadId;
    final seq = _now.cursor;
    final state = _now.state;
    if (threadId == null || seq == 0 || state == null || state.userReadSeq >= seq) return;
    // A state read before the server had it (the stream's, a reload's) does not say it again (qa4-sdk-04).
    if (_readSent?.threadId == threadId && _readSent!.seq >= seq) return;
    _readSent = (threadId: threadId, seq: seq);
    unawaited(api.support('POST', _path(threadId, 'read'), user: user(), body: {'seq': seq}));
    value.value = _now.copyWith(unread: 0, state: state.read(seq));
  }

  /// The answer to how it went: `{'rating': 'up'}`, then perhaps `{'comment': …}`, or `{'dismissed': true}`.
  Future<void> rate(Map<String, Object> answer) async {
    final threadId = _now.threadId;
    if (threadId == null) return;
    await api.support('POST', _path(threadId, 'rating'), user: user(), body: answer);
  }

  /// "I'm sorted", or "By mistake? Back to the assistant".
  Future<bool> resolve({bool byMistake = false}) async {
    final threadId = _now.threadId;
    if (threadId == null) return false;
    final answer = await api.support('POST', _path(threadId, 'resolve'), user: user(), body: byMistake ? const {'by_mistake': true} : const {});
    if (answer.status != 204) return false;
    // A slip, put away before the team acted, is no history: nothing of it stays, so Contact us opens an empty page
    // and the next first line starts a new conversation (qa4-sdk-02). Its page closes, so nothing follows it either.
    if (byMistake) {
      watch(false);
      _open = false;
      _viewing = null;
      value.value = RendelSupportSnapshot(unread: _now.unread);
      return true;
    }
    await load();
    return true;
  }

  /// The address the reply goes to (K14): 'stated', 'verified', 'unsent', 'invalid', 'too_many' or 'failed'.
  /// 'unsent' is an address the server saved without emailing its code (a test key, or too many codes this hour);
  /// 'too_many' is one it would not take, the address having changed as often as a conversation allows.
  Future<String> contact(String email) async {
    final threadId = _now.threadId;
    if (threadId == null) return 'failed';
    final answer = await api.support('POST', _path(threadId, 'contact'), user: user(), body: {'email': email});
    if (answer.status == 400) return 'invalid';
    final error = answer.json?['error'];
    if (answer.status == 409 && error is Map && error['code'] == 'too_many_changes') return 'too_many';
    if (answer.status != 200) return 'failed';
    unawaited(_keepContact(email));
    await load();
    if (answer.json?['state'] == 'verified') return 'verified';
    return answer.json?['emailed'] == true ? 'stated' : 'unsent';
  }

  /// The address this person gave the team last on this phone: a later conversation's box comes filled with it, so
  /// one tap gives it again (QA 2026-11-20, B8). Kept here and never on the server, which holds an address for one
  /// conversation only (human-support §3.2b). Kept with who gave it, for them only; signing out forgets it.
  String? get lastContact => _lastContact != null && _lastContact!.who == _who() ? _lastContact!.email : null;
  ({String who, String email})? _lastContact;

  static const _contactKey = 'rendel_support_email';

  Future<void> _loadContact() async {
    try {
      // Who gave it, and the address.
      final saved = (await SharedPreferences.getInstance()).getStringList(_contactKey);
      if (_lastContact == null && saved != null && saved.length == 2) _lastContact = (who: saved[0], email: saved[1]);
    } catch (_) {
      // No storage: the address is kept for as long as the app runs.
    }
  }

  Future<void> _keepContact(String email) async {
    final kept = (who: _who(), email: email);
    _lastContact = kept;
    try {
      await (await SharedPreferences.getInstance()).setStringList(_contactKey, [kept.who, kept.email]);
    } catch (_) {}
  }

  Future<void> _forgetContact() async {
    _lastContact = null;
    try {
      await (await SharedPreferences.getInstance()).remove(_contactKey);
    } catch (_) {}
  }

  /// Where the card for the address given in [threadId] sits on its page: after the line that was newest when the
  /// address was first seen given, never under each line since, where it read as the team writing again
  /// (QA 2026-11-20, B8). Kept for the app's life, so the page opened again draws it there too; forgotten, and null,
  /// once no address waits in that conversation ([stated] false).
  int? contactAfter(String threadId, {required bool stated}) {
    if (!stated) {
      _contactAfter.remove(threadId);
      return null;
    }
    return _contactAfter.putIfAbsent(threadId, () => _now.cursor);
  }

  final Map<String, int> _contactAfter = {};

  /// Asks for the address's code again: 'sent', 'later' (too soon after the last one, or no email can go now) or 'failed'.
  Future<String> resendCode() async {
    final threadId = _now.threadId;
    if (threadId == null) return 'failed';
    final answer = await api.support('POST', _path(threadId, 'contact/resend'), user: user(), body: {});
    if (answer.status == 429) return 'later';
    if (answer.status != 200) return 'failed';
    return answer.json?['emailed'] == true ? 'sent' : 'later';
  }

  Future<bool> verify(String code) async {
    final threadId = _now.threadId;
    if (threadId == null) return false;
    final answer = await api.support('POST', _path(threadId, 'contact/verify'), user: user(), body: {'code': code});
    if (answer.status != 200) return false;
    await load();
    return true;
  }

  /// The team's cards the server would not open on this phone: drawn as not answered.
  final Set<String> refusedCards = {};

  /// The conversations whose optional email card the person put away, kept on this phone (Tuna, 2026-11-04).
  final ValueNotifier<Set<String>> contactSkipped = ValueNotifier(const {});

  static const _skippedKey = 'rendel_support_email_skipped';

  Future<void> _loadSkipped() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getStringList(_skippedKey);
      if (saved != null) contactSkipped.value = {...contactSkipped.value, ...saved};
    } catch (_) {
      // No storage: the card is put away for as long as the app runs.
    }
  }

  /// The person would rather not give an email in [threadId]: its optional card goes, and stays gone there.
  Future<void> skipContact(String threadId) async {
    contactSkipped.value = {...contactSkipped.value, threadId};
    try {
      // The newest fifty: a thread older than that has long had its answer.
      final kept = contactSkipped.value.toList();
      await (await SharedPreferences.getInstance()).setStringList(_skippedKey, kept.sublist(max(0, kept.length - 50)));
    } catch (_) {}
  }

  /// A confirm card the team sent, opened: its confirmation is minted on this
  /// phone now, and the line comes back with the card's `invocation_id`.
  Future<bool> openCard(String entryId) async {
    final threadId = _now.threadId;
    if (threadId == null) return false;
    final answer = await api.support('POST', _path(threadId, 'cards/${Uri.encodeComponent(entryId)}/open'), user: user(), body: const {});
    final block = answer.json?['block'];
    if (answer.status != 200 || block is! Map<String, dynamic>) {
      // Refused for good (the conversation was sorted, or the card is not this phone's): not answered, never left loading.
      if (answer.status == 404 || answer.status == 409) {
        refusedCards.add(entryId);
        value.value = _now.copyWith();
      }
      return false;
    }
    value.value = _now.copyWith(entries: [
      for (final e in _now.entries)
        e.id == entryId
            ? RendelSupportEntry(
                id: e.id,
                seq: e.seq,
                marker: e.marker,
                author: e.author,
                authorName: e.authorName,
                text: e.text,
                blocks: [for (final b in e.blocks) b['id'] == block['id'] ? block : b],
                files: e.files,
                pictures: e.pictures,
                clientMsgId: e.clientMsgId,
                createdAt: e.createdAt,
                markerKind: e.markerKind,
              )
            : e,
    ]);
    return true;
  }

  /// The person's answer to that card, on the assistant's own path; a yes
  /// runs the write once, as them: 'succeeded', 'failed', 'declined' or 'expired'.
  /// The card answered here says so at once, as the server spells it (`_resolved`): a reload reads only the
  /// lines after the cursor, so the card's own line would not come back with its answer (Tuna, 2026-11-04).
  void _answered(String invocationId, String resolved) {
    bool mine(Map<String, dynamic> b) => b['type'] == 'confirm_card' && b['props'] is Map && (b['props'] as Map)['invocation_id'] == invocationId;
    value.value = _now.copyWith(entries: [
      for (final e in _now.entries)
        e.blocks.any(mine)
            ? RendelSupportEntry(
                id: e.id,
                seq: e.seq,
                marker: e.marker,
                author: e.author,
                authorName: e.authorName,
                text: e.text,
                blocks: [
                  for (final b in e.blocks) mine(b) ? {...b, 'props': {...(b['props'] as Map<String, dynamic>), '_resolved': resolved}} : b,
                ],
                files: e.files,
                pictures: e.pictures,
                clientMsgId: e.clientMsgId,
                createdAt: e.createdAt,
                markerKind: e.markerKind,
              )
            : e,
    ]);
  }

  /// What the person typed did not match the value the card asks for: the card opens again, with why under the field.
  void _mismatched(String invocationId) {
    bool mine(Map<String, dynamic> b) => b['type'] == 'confirm_card' && b['props'] is Map && (b['props'] as Map)['invocation_id'] == invocationId;
    value.value = _now.copyWith(entries: [
      for (final e in _now.entries)
        e.blocks.any(mine)
            ? RendelSupportEntry(
                id: e.id,
                seq: e.seq,
                marker: e.marker,
                author: e.author,
                authorName: e.authorName,
                text: e.text,
                blocks: [
                  for (final b in e.blocks) mine(b) ? {...b, 'props': {...(b['props'] as Map<String, dynamic>), '_mismatch': true}} : b,
                ],
                files: e.files,
                pictures: e.pictures,
                clientMsgId: e.clientMsgId,
                createdAt: e.createdAt,
                markerKind: e.markerKind,
              )
            : e,
    ]);
  }

  /// The yes carries who the person is and their token, and what they typed on a card that asks for it (C8,
  /// sdk-10): a server that runs the card at the tap answers how it went, and there is nothing left to continue.
  /// 'succeeded', 'failed', 'unanswered', 'declined', 'expired' or 'typed_mismatch'. 'failed' is the server's answer
  /// that the write ran and failed: the card says so, and nothing is left to try again. 'unanswered' is no answer at
  /// all: the card stays open, and pressing it again can help (qa2-sdk-03).
  Future<String> decideCard(String invocationId, {required bool confirm, String? typed}) async {
    final threadId = _now.threadId;
    if (threadId == null) return 'unanswered';
    final status = await api.recordDecision(invocationId, confirm: confirm, typed: confirm ? typed : null, user: user());
    if (!confirm) {
      if (status == 'declined') _answered(invocationId, 'declined');
      return status == 'declined' ? 'declined' : 'unanswered';
    }
    if (status == 'typed_mismatch') {
      _mismatched(invocationId);
      return 'typed_mismatch';
    }
    if (status == 'expired') return 'expired';
    // Run at the tap, or pressed again after an answer that never came back: the server says how the write went.
    if (status == 'succeeded' || status == 'failed') {
      _answered(invocationId, status == 'succeeded' ? 'confirmed' : 'failed');
      await load();
      return status as String;
    }
    if (status != 'confirmed') return 'unanswered';
    final ran = await api.support('POST', _path(threadId, 'continue'), user: user(), body: {'invocation_id': invocationId}, asPerson: true);
    // The card says confirmed only once the write went through (sdk-21). One the server ran and that failed says so;
    // one that never got an answer stays open, so Confirm can be pressed again.
    final done = ran.status == 200 && ran.json?['status'] == 'succeeded';
    final failed = ran.status == 200 && ran.json?['status'] == 'failed';
    if (done) {
      _answered(invocationId, 'confirmed');
    } else if (failed) {
      _answered(invocationId, 'failed');
    }
    await load();
    return done ? 'succeeded' : (failed ? 'failed' : 'unanswered');
  }

  /// Reads the team asked for that this phone took up (running, run, answered or run out): never taken up twice.
  final Set<String> _lookupsTaken = {};

  /// When each question asking first goes off the page.
  final Map<String, Timer> _askTimers = {};

  /// A read the team asked for, from the stream or from the count (C6): the
  /// server offers it both ways until it is run, so it is taken up once,
  /// whichever comes first. One that does not ask first runs at once, as the
  /// person; one that asks is put to them until it runs out (check-11).
  void _offerLookup(Object? raw, String? threadId) {
    if (raw is! Map) return;
    final id = raw['lookup_id'];
    if (id is! String || _lookupsTaken.contains(id) || _now.asks.any((a) => a.lookupId == id)) return;
    final expiresAt = DateTime.tryParse('${raw['expires_at']}');
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) return;
    if (raw['ask'] != true) {
      _lookupsTaken.add(id);
      unawaited(answerLookup(id, allow: true, threadId: threadId));
      return;
    }
    value.value = _now.copyWith(asks: [..._now.asks, (lookupId: id, text: '${raw['action']}', failed: false, threadId: threadId, expiresAt: expiresAt)]);
    if (expiresAt != null) _askTimers[id] = Timer(expiresAt.difference(DateTime.now()), () => _dropAsk(id));
  }

  /// A question that can no longer be answered: off the page, and not asked again.
  void _dropAsk(String lookupId) {
    _askTimers.remove(lookupId)?.cancel();
    _lookupsTaken.add(lookupId);
    if (_now.asks.any((a) => a.lookupId == lookupId)) value.value = _now.copyWith(asks: [for (final a in _now.asks) if (a.lookupId != lookupId) a]);
  }

  /// A read the team asked for, answered from this phone: with the person's
  /// token for that one call, or their no. The server tells the thread. The
  /// question goes only once the answer reached the server; until then it
  /// stays, saying the answer did not go, to be pressed again (sdk-20). One
  /// that never asked and did not reach the server is taken up again the next
  /// time it is offered.
  Future<void> answerLookup(String lookupId, {required bool allow, String? threadId}) async {
    final ask = _now.asks.where((a) => a.lookupId == lookupId).firstOrNull;
    final thread = threadId ?? ask?.threadId ?? _now.threadId;
    if (thread == null) {
      if (ask == null) _lookupsTaken.remove(lookupId);
      return;
    }
    final answer = await api.support('POST', _path(thread, 'lookups/${Uri.encodeComponent(lookupId)}/run'), user: user(), body: {'allow': allow}, asPerson: true);
    // Answered, or nothing left to answer (it ran out, or was answered already): the question goes.
    final gone = (answer.status >= 200 && answer.status < 300) || answer.status == 404 || answer.status == 409;
    if (gone) return _dropAsk(lookupId);
    if (ask == null) {
      _lookupsTaken.remove(lookupId);
      return;
    }
    value.value = _now.copyWith(asks: [
      for (final a in _now.asks) a.lookupId == lookupId ? (lookupId: a.lookupId, text: a.text, failed: true, threadId: a.threadId, expiresAt: a.expiresAt) : a,
    ]);
  }

  /// The launcher's count: on init, on resume, on a push, and every half
  /// minute while the app has Support on and is in front of the person
  /// ([here]: the team's reply is then told in the app, not by a push).
  /// A read that failed changes nothing: the next one says how it stands.
  /// The reads the team asked for come with it, so they reach an app that is
  /// open even when the conversation is not on screen (C6, check-01); and it
  /// says whether the person is signed in, when the app gave a token (add-10).
  Future<int> refreshUnread({bool here = false}) async {
    final signedIn = await api.signedIn();
    final query = [if (here) 'here=1', if (signedIn != null) 'signed_in=${signedIn ? 1 : 0}'].join('&');
    final answer = await api.support('GET', query.isEmpty ? 'unread' : 'unread?$query', user: user());
    if (answer.status != 200 || answer.json == null) return _now.unread;
    final counted = answer.json?['thread_id'];
    if (answer.json?['lookups'] case final List<dynamic> lookups) {
      for (final lookup in lookups) {
        _offerLookup(lookup, counted is String ? counted : null);
      }
    }
    final unread = answer.json?['unread'] is int ? answer.json!['unread'] as int : 0;
    final open = answer.json?['open'] == true;
    if (open || counted is String) onKnown?.call();
    final last = answer.json?['last'];
    _reply = last is Map && last['seq'] is int && last['name'] is String ? (seq: last['seq'] as int, name: last['name'] as String, text: '${last['text'] ?? ''}') : null;
    if (unread != _now.unread || open != _open) {
      _open = open;
      value.value = _now.copyWith(unread: unread);
    }
    return unread;
  }

  /// Keeps the stream open while the support page is on screen.
  void watch(bool on) {
    if (on == _watching) return;
    _watching = on;
    onScreen.value = on ? _now.threadId : null;
    if (!on) {
      unawaited(_stream?.cancel());
      _stream = null;
      // A cancelled subscription never says it is done: the loop waiting on it is told here.
      if (_ended case final ended? when !ended.isCompleted) ended.complete(null);
      return;
    }
    // Back before the last loop noticed it was stopped: that one carries on.
    if (!_looping) unawaited(_loop());
  }

  /// The stream the loop is waiting on ended, or was put away.
  Completer<Object?>? _ended;

  Future<void> _loop() async {
    _looping = true;
    try {
      await _follow();
    } finally {
      _looping = false;
    }
  }

  Future<void> _follow() async {
    var backoff = 1000;
    final random = Random();
    // Closed by Support's switch, nobody on the team writes in it: nothing to follow, and the server refuses the
    // stream while Support is off, so it is not asked again and again (qa2-k1-04). Written in again, it is followed.
    while (_watching && _now.threadId != null && !(_now.state?.closedOff ?? false)) {
      final threadId = _now.threadId!;
      final started = DateTime.now();
      final done = Completer<Object?>();
      _ended = done;
      _stream = api.supportStream(threadId, _now.cursor, user: user()).listen(
        (event) {
          backoff = 1000;
          unawaited(_handle(event, threadId));
        },
        onError: (Object error) {
          if (!done.isCompleted) done.complete(error);
        },
        onDone: () {
          if (!done.isCompleted) done.complete(null);
        },
        cancelOnError: true,
      );
      // A stream the server held ends after about a minute; one that ends at
      // once (a proxy that answers and closes) is backed off like an error,
      // or the loop would spin.
      final error = await done.future ?? (DateTime.now().difference(started) < const Duration(seconds: 2) ? 'closed at once' : null);
      _stream = null;
      if (!_watching) return;
      if (error != null) {
        RendelLog.report(RendelLogLevel.debug, 'support_stream', 'the support stream ended', error: error);
        await Future<void>.delayed(Duration(milliseconds: backoff + random.nextInt(500)));
        backoff = min(backoff * 2, 30000);
        // A proxy that buffers the stream answers nothing: catch up with a plain read.
        await load();
      }
    }
  }

  Future<void> _handle(Map<String, dynamic> event, String threadId) async {
    switch (event['type']) {
      case 'support.entry':
        if (RendelSupportEntry.tryParse(event['entry']) case final entry?) _merge([entry]);
      case 'support.state':
        if (RendelSupportState.tryParse(event['state']) case final state?) {
          // Sorted or opened again while the page is up: the row and the launcher follow at once (sdk-14).
          // A sorted one shown by its id says nothing of whether another is open.
          if (!state.resolved) {
            _open = true;
          } else if (_viewing == null) {
            _open = false;
          }
          // Closed by Support's switch while the page is up: the SDK learns Support is off before it is drawn (qa3-k1-01).
          if (state.closedOff) onOff?.call(threadId);
          value.value = _now.copyWith(state: state);
        }
      case 'support.typing':
        value.value = _now.copyWith(typingUntil: DateTime.tryParse('${event['until']}'));
      case 'support.lookup':
        _offerLookup(event, threadId);
      case 'support.resync':
        await load();
    }
  }

  /// Signed out, or somebody else signed in: nothing of the last person's thread stays.
  void reset() {
    _generation++;
    _readAs = '';
    watch(false);
    _open = false;
    _viewing = null;
    _reply = null;
    _opening = null;
    for (final timer in _askTimers.values) {
      timer.cancel();
    }
    _askTimers.clear();
    _lookupsTaken.clear();
    _contactAfter.clear();
    // Nor the address they gave, on the phone either.
    if (_lastContact != null) unawaited(_forgetContact());
    value.value = const RendelSupportSnapshot();
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
