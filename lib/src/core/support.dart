import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transport/api_client.dart';
import 'log.dart';

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
    this.rating,
  });

  final String threadId;

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
        rating: rating,
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
  });

  final String threadId;
  final bool resolved;

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
    );
  }
}

/// The team's newest unread line, for the banner while Rendel is closed. Its text is empty when the customer hides it.
typedef RendelSupportReply = ({int seq, String name, String text});

/// A line sent from here that the server has not confirmed yet.
class RendelSupportPending {
  const RendelSupportPending(this.clientMsgId, this.text, {this.failed = false, this.attachmentIds = const []});

  final String clientMsgId;
  final String text;
  final bool failed;

  /// Files uploaded for this line: a retry sends them, not their name.
  final List<String> attachmentIds;
}

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
  });

  final String? threadId;
  final List<RendelSupportEntry> entries;
  final RendelSupportState? state;

  /// Until when the team's typing line shows.
  final DateTime? typingUntil;
  final List<RendelSupportPending> pending;
  final int unread;

  /// Reads the team asked to make that wait for the person's yes, in the server's words.
  final List<({String lookupId, String text})> asks;

  /// A sorted thread could not open again: this other one of the person's is open.
  final String? otherOpen;

  int get cursor => entries.isEmpty ? 0 : entries.last.seq;

  RendelSupportSnapshot copyWith({
    String? threadId,
    List<RendelSupportEntry>? entries,
    RendelSupportState? state,
    DateTime? typingUntil,
    bool clearTyping = false,
    List<RendelSupportPending>? pending,
    int? unread,
    List<({String lookupId, String text})>? asks,
    String? otherOpen,
    bool clearOtherOpen = false,
  }) =>
      RendelSupportSnapshot(
        threadId: threadId ?? this.threadId,
        entries: entries ?? this.entries,
        state: state ?? this.state,
        typingUntil: clearTyping ? null : (typingUntil ?? this.typingUntil),
        pending: pending ?? this.pending,
        unread: unread ?? this.unread,
        asks: asks ?? this.asks,
        otherOpen: clearOtherOpen ? null : (otherOpen ?? this.otherOpen),
      );
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
  }

  final RendelApiClient api;

  /// Who is signed in right now (`identify`'s `id` and `hmac`); null for nobody.
  final Map<String, String>? Function() user;
  final String Function() locale;

  final ValueNotifier<RendelSupportSnapshot> value = ValueNotifier(const RendelSupportSnapshot());

  StreamSubscription<Map<String, dynamic>>? _stream;
  bool _watching = false;
  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);

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
    if (_watching) onScreen.value = threadId;
    final same = threadId == _now.threadId;
    final bySeq = {for (final e in same ? _now.entries : const <RendelSupportEntry>[]) e.seq: e};
    for (final e in entries) {
      bySeq[e.seq] = e;
    }
    final confirmed = {for (final e in entries) if (e.clientMsgId != null) e.clientMsgId};
    value.value = _now.copyWith(
      threadId: threadId,
      entries: bySeq.values.toList()..sort((a, b) => a.seq.compareTo(b.seq)),
      pending: [for (final p in same ? _now.pending : const <RendelSupportPending>[]) if (!confirmed.contains(p.clientMsgId)) p],
      state: state,
      clearOtherOpen: true,
    );
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

  /// The thread this phone has, if any, brought up to date: the one on the page when it was opened by its id.
  Future<bool> load() async {
    if (_viewing case final id?) return show(id);
    final known = _now.threadId;
    final answer = await api.support('GET', 'current?after=${known == null ? 0 : _now.cursor}', user: user());
    if (answer.status != 200) return known != null;
    return _applyThread(answer.json);
  }

  /// Recent and the list behind it: the person's conversations with the team, newest first; null when it could not be read.
  Future<List<RendelSupportThread>?> threads() async {
    final answer = await api.support('GET', 'threads', user: user());
    final list = answer.json?['threads'];
    if (answer.status != 200 || list is! List) return null;
    return [
      for (final raw in list)
        if (RendelSupportThread.tryParse(raw) case final thread?) thread,
    ];
  }

  /// One of the person's threads, by its id: a sorted one comes back as it was, ready to be written in.
  Future<bool> show(String threadId) async {
    final same = _now.threadId == threadId;
    final answer = await api.support('GET', 'threads/${Uri.encodeComponent(threadId)}?after=${same ? _now.cursor : 0}', user: user());
    if (answer.status != 200) return false;
    _viewing = threadId;
    return _applyThread(answer.json, current: false);
  }

  /// The page of a thread shown by its id closed: the session holds the phone's current one again, or none.
  Future<void> restore() async {
    if (_viewing == null) return;
    _viewing = null;
    final answer = await api.support('GET', 'current?after=0', user: user());
    if (answer.status == 200 && _applyThread(answer.json)) return;
    _open = false;
    value.value = RendelSupportSnapshot(unread: _now.unread);
  }

  /// Opens the thread (or the one already open), with the person's first words when they wrote some.
  /// 'ok', or the server's refusal code.
  Future<String> handoff(String trigger, {String? text, String? conversationId}) async {
    final answer = await api.support('POST', 'handoff', user: user(), body: {
      'trigger': trigger,
      'client_msg_id': _uuid(),
      'locale': locale(),
      if (text != null && text.isNotEmpty) 'text': text,
      if (conversationId != null) 'conversation_id': conversationId,
    });
    if (answer.status != 200) {
      final error = answer.json?['error'];
      return error is Map && error['code'] is String ? error['code'] as String : (answer.status == 0 ? 'unreachable' : 'failed');
    }
    return _applyThread(answer.json) ? 'ok' : 'failed';
  }

  String _path(String threadId, String rest) => 'threads/${Uri.encodeComponent(threadId)}/$rest';

  /// A line from the person: drawn at once as unsent and reconciled by its client id.
  /// 'ok', 'contact_required', 'another_open' or 'failed'. A line in a sorted
  /// thread opens it again, in place, with the server's "reopened" line first.
  Future<String> send(String text, {List<String> attachmentIds = const [], String? fileName}) async {
    final threadId = _now.threadId;
    final body = text.trim();
    if (threadId == null || (body.isEmpty && attachmentIds.isEmpty)) return 'failed';
    final id = _uuid();
    value.value = _now.copyWith(pending: [..._now.pending, RendelSupportPending(id, body.isEmpty ? fileName ?? '' : body, attachmentIds: attachmentIds)]);
    final answer = await api.support('POST', _path(threadId, 'messages'), user: user(), body: {'client_msg_id': id, if (body.isNotEmpty) 'text': body, if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds});
    if (RendelSupportEntry.tryParse(answer.json?['entry']) case final entry? when answer.status == 200) {
      final reopened = RendelSupportEntry.tryParse(answer.json?['reopened']);
      _merge([if (reopened != null) reopened, entry]);
      // Written in a sorted thread: it is open again, with the team, and the state says so.
      if (reopened != null) await load();
      return 'ok';
    }
    final error = answer.json?['error'];
    if (answer.status == 409 && error is Map && error['code'] == 'contact_required') {
      value.value = _now.copyWith(pending: [for (final p in _now.pending) if (p.clientMsgId != id) p]);
      return 'contact_required';
    }
    if (answer.status == 409 && error is Map && error['code'] == 'another_open' && error['thread_id'] is String) {
      value.value = _now.copyWith(pending: [for (final p in _now.pending) if (p.clientMsgId != id) p], otherOpen: error['thread_id'] as String);
      return 'another_open';
    }
    _markFailed(id, true);
    return 'failed';
  }

  void _markFailed(String id, bool failed) {
    value.value = _now.copyWith(pending: [
      for (final p in _now.pending) p.clientMsgId == id ? RendelSupportPending(id, p.text, failed: failed, attachmentIds: p.attachmentIds) : p,
    ]);
  }

  /// Sends a failed line again, under the same client id, so it cannot arrive twice.
  Future<void> retry(String clientMsgId) async {
    final threadId = _now.threadId;
    final line = _now.pending.where((p) => p.clientMsgId == clientMsgId).firstOrNull;
    if (threadId == null || line == null) return;
    _markFailed(clientMsgId, false);
    final answer = await api.support('POST', _path(threadId, 'messages'), user: user(), body: {'client_msg_id': clientMsgId, if (line.attachmentIds.isEmpty) 'text': line.text, if (line.attachmentIds.isNotEmpty) 'attachment_ids': line.attachmentIds});
    if (RendelSupportEntry.tryParse(answer.json?['entry']) case final entry? when answer.status == 200) {
      _merge([entry]);
    } else {
      _markFailed(clientMsgId, true);
    }
  }

  /// The person is typing: said at most every three seconds.
  void typing() {
    final threadId = _now.threadId;
    if (threadId == null || DateTime.now().difference(_lastTyping) < const Duration(seconds: 3)) return;
    _lastTyping = DateTime.now();
    unawaited(api.support('POST', _path(threadId, 'typing'), user: user(), body: const {}));
  }

  /// Read up to the newest line: the badge clears. Said once per new line.
  void read() {
    final threadId = _now.threadId;
    final seq = _now.cursor;
    final state = _now.state;
    if (threadId == null || seq == 0 || state == null || state.userReadSeq >= seq) return;
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
  Future<bool> resolve() async {
    final threadId = _now.threadId;
    if (threadId == null) return false;
    final answer = await api.support('POST', _path(threadId, 'resolve'), user: user(), body: const {});
    if (answer.status != 204) return false;
    await load();
    return true;
  }

  /// The address the reply goes to (K14): 'stated', 'verified', 'invalid' or 'failed'.
  Future<String> contact(String email) async {
    final threadId = _now.threadId;
    if (threadId == null) return 'failed';
    final answer = await api.support('POST', _path(threadId, 'contact'), user: user(), body: {'email': email});
    if (answer.status == 400) return 'invalid';
    if (answer.status != 200) return 'failed';
    await load();
    return answer.json?['state'] == 'verified' ? 'verified' : 'stated';
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

  Future<String> decideCard(String invocationId, {required bool confirm}) async {
    final threadId = _now.threadId;
    if (threadId == null) return 'failed';
    final status = await api.recordDecision(invocationId, confirm: confirm);
    if (!confirm) {
      if (status == 'declined') _answered(invocationId, 'declined');
      return status == 'declined' ? 'declined' : 'failed';
    }
    if (status == 'expired') return 'expired';
    if (status != 'confirmed') return 'failed';
    _answered(invocationId, 'confirmed');
    final ran = await api.support('POST', _path(threadId, 'continue'), user: user(), body: {'invocation_id': invocationId}, asPerson: true);
    await load();
    return ran.status == 200 && ran.json?['status'] == 'succeeded' ? 'succeeded' : 'failed';
  }

  /// A read the team asked for, answered from this phone: with the person's
  /// token for that one call, or their no. The server tells the thread.
  Future<void> answerLookup(String lookupId, {required bool allow}) async {
    final threadId = _now.threadId;
    value.value = _now.copyWith(asks: [for (final a in _now.asks) if (a.lookupId != lookupId) a]);
    if (threadId == null) return;
    await api.support('POST', _path(threadId, 'lookups/${Uri.encodeComponent(lookupId)}/run'), user: user(), body: {'allow': allow}, asPerson: true);
  }

  /// The launcher's count: on init, on resume, on a push, and every half
  /// minute while a thread is open and the app is in front of the person
  /// ([here]: the team's reply is then told in the app, not by a push).
  Future<int> refreshUnread({bool here = false}) async {
    final answer = await api.support('GET', here ? 'unread?here=1' : 'unread', user: user());
    final unread = answer.status == 200 && answer.json?['unread'] is int ? answer.json!['unread'] as int : 0;
    var open = _open;
    if (answer.status == 200) open = answer.json?['open'] == true;
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
      return;
    }
    unawaited(_loop());
  }

  Future<void> _loop() async {
    var backoff = 1000;
    final random = Random();
    while (_watching && _now.threadId != null) {
      final threadId = _now.threadId!;
      final started = DateTime.now();
      final done = Completer<Object?>();
      _stream = api.supportStream(threadId, _now.cursor, user: user()).listen(
        (event) {
          backoff = 1000;
          unawaited(_handle(event));
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

  Future<void> _handle(Map<String, dynamic> event) async {
    switch (event['type']) {
      case 'support.entry':
        if (RendelSupportEntry.tryParse(event['entry']) case final entry?) _merge([entry]);
      case 'support.state':
        if (RendelSupportState.tryParse(event['state']) case final state?) value.value = _now.copyWith(state: state);
      case 'support.typing':
        value.value = _now.copyWith(typingUntil: DateTime.tryParse('${event['until']}'));
      case 'support.lookup':
        final id = event['lookup_id'];
        if (id is! String) return;
        if (event['ask'] == true) {
          if (!_now.asks.any((a) => a.lookupId == id)) {
            value.value = _now.copyWith(asks: [..._now.asks, (lookupId: id, text: '${event['action']}')]);
          }
        } else {
          await answerLookup(id, allow: true);
        }
      case 'support.resync':
        await load();
    }
  }

  /// Signed out, or somebody else signed in: nothing of the last person's thread stays.
  void reset() {
    watch(false);
    _open = false;
    _viewing = null;
    _reply = null;
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
