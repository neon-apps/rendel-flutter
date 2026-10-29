import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/action.dart';
import '../core/route.dart';

/// RDUI/1 protocol constants. Keep in lockstep with packages/protocol.
const int protocolVersion = 1;
const String catalogVersion = '2026-09.a';

/// Every type this SDK build can render — declared in the handshake so the
/// server only ever sends components we can draw.
const List<String> supportedComponents = [
  'text',
  'quick_replies',
  'info_card',
  'item_list',
  'product_cards',
  'confirm_card',
  'status_banner',
  'stat_group',
  'order_tracker',
  'receipt',
  'form',
  'datetime_slots',
  'booking_card',
  'chart',
  'table',
  'media_gallery',
  'progress',
  'key_value',
  'variant_picker',
  'article_card',
  'section',
  'key_points',
  'actions',
  'tags',
  'screens',
  'choice',
  'comparison',
  'contact',
  'rating',
  'disclosure',
  'checklist',
  'timeline',
  'place_card',
  'map',
  'pass',
  'code',
  'action_done',
];

/// Behaviours this build has beyond drawing [supportedComponents], declared in
/// the handshake as `client.capabilities`.
///
/// `form_update`: a `form` whose `form_id` matches one the user has not sent
/// replaces it, keeping what the user entered, and every message carries the
/// open forms' values. The server only lets the model reshape a form for a
/// build that says so; to any other build a re-drawn form is a second form.
///
/// `surface_update`: a block carrying a `surface_id` and a newer `revision`
/// takes the place of the one already drawn under that id, keeping the
/// user's choices it still offers; an older revision arriving late is
/// dropped. The server only offers the model `surface_id` for a build that
/// says so.
/// `answer_pages`: each answer gets a screen of its own, so the end of an
/// answer is the foot of a page. The server closes a substantial answer with
/// `quick_replies` carrying a heading, an icon each and whole questions only
/// for a build that says so; to any other build they are pills in a row,
/// where a sentence does not fit.
///
/// `detail_pages`: on a page, a product card or a list item opens over it and
/// asks for its detail, carrying `message.detail_of`.
///
/// `notices`: when the assistant will not answer on purpose (the person's
/// usage limit, the app's budget or credit paused), the server sends a
/// `notice`, drawn as a calm answer with the composer resting, instead of an
/// `error`.
///
/// `card_fill`: a `confirm_card` may leave out a value the person fills in
/// on the card, its `editable` control marked `required`; the card draws the
/// control empty and cannot be confirmed until a redraw carries the value.
/// The server only lets the model propose such a card to a build that says so.
const List<String> clientCapabilities = [
  'form_update',
  'surface_update',
  'answer_pages',
  'detail_pages',
  'notices',
  'card_fill',
];

/// The kinds of action this build carries out when a control is tapped,
/// declared in the handshake as `client.actions`. The server puts no other
/// kind on a block it sends this build and draws such a block as its fallback
/// text instead, so a kind added here is a promise the tap path keeps.
///
/// `navigate` opens one of the routes the app registered; the server offers
/// it, and `screens` with it, only to an app that registered one.
///
/// `call`, `copy` and `add_to_calendar` put something into the user's hands
/// on a tap (`design/CATALOG-B2.md`): the dialler with a number filled in,
/// a value on the clipboard, the device's own event editor filled in. The
/// server checks each value against the app's action results before the
/// block leaves, so the SDK carries them out as they are.
const List<String> clientActions = [
  'reply',
  'open_url',
  'navigate',
  'call',
  'copy',
  'add_to_calendar',
];

/// Keys the SDK writes into a block's own `props` to remember what the user
/// did with it.
///
/// They are client-local and never travel: the wire schema is a strict object
/// and would reject any of them on the way back. They are declared here rather
/// than left as string literals in four widget closures because the behaviour
/// they encode is load-bearing spec that the Swift and Kotlin SDKs have to
/// implement identically:
///
///  - a resolved confirm card is never confirmable again, and shows what was
///    agreed to when the thread is scrolled back;
///  - a chosen slot stays marked;
///  - an answered choice stays folded into its answer;
///  - a half-filled form survives being scrolled out of the list and back;
///  - a submitted form never becomes re-submittable;
///  - a form the copilot redraws keeps every value the user entered.
class RendelLocalKeys {
  const RendelLocalKeys._();

  /// `confirm_card`: 'confirmed', 'declined' or 'abandoned', absent while the
  /// card is still answerable. 'abandoned' is set when the user asks something
  /// else instead, which the server treats as an answer too.

  static const String resolved = '_resolved';

  /// `datetime_slots`: the id of the slot the user picked. `variant_picker`:
  /// the id of the option the user picked, which wins over the model's
  /// `selected_id`. `choice`: the ids lit so far, as a `List<String>`.
  /// `rating`: the score the server took, as an `int`. `checklist`: the ids
  /// ticked, as a `List<String>`, absent until the first tick changes the
  /// items' own `done`.
  static const String chosen = '_chosen';

  /// `choice`: what was sent, once it was — a map of `ids`, `other_text` when
  /// the user wrote the answer, and `shown`, the words it was asked in. The
  /// block folds into `shown` and is never answerable again. `rating`: true
  /// once it folded into its thanks, with or without a comment.
  static const String answered = '_answered';

  /// `form`: the working values, keyed by field name.
  static const String values = '_values';

  /// `form`: true once a submission has actually been sent.
  static const String submitted = '_submitted';

  /// `form`: the names of the fields the user changed themselves, as a
  /// `Set<String>`. A form the copilot redraws keeps these values whatever the
  /// new one proposes, and the server is told they are the user's.
  static const String edited = '_edited';

  /// `form`: the name of the text field that has focus right now, if any.
  static const String focused = '_focused';

  /// `form`: the field to focus once, when this form is drawn — set when it
  /// replaced a form whose same-named field had focus, so typing carries on.
  static const String refocus = '_refocus';

  /// `form`: the files of each `upload` field, picked and uploading, keyed by
  /// field name. Their upload ids are the field's value; the files are kept
  /// beside it for the thumbnails, so a form scrolled away and back still
  /// shows what was attached, and an upload still in flight still lands.
  static const String files = '_files';

  /// `confirm_card` with `type_to_confirm`: what the user typed, and true
  /// once the server found it did not match (cleared by typing again).
  static const String typed = '_typed';
  static const String mismatch = '_mismatch';

  /// `confirm_card` with `full_text`: true once the whole text was opened,
  /// and the text it replaces from `Rendel.setCardSource` (null when that
  /// could not be had, absent when the app gave none).
  static const String read = '_read';
  static const String current = '_current';
}

/// The keys a form field's value is kept and sent under: its name, or for a
/// `date_range` the two days it returns, `{name}_start` and `{name}_end`.
///
/// One reading for the form, the open forms the server is told about, and a
/// form the copilot redraws, so a range is carried and marked edited under the
/// same keys it is submitted under.
List<String> formFieldKeys(Map field) {
  final name = field['name'];
  if (name is! String) return const [];
  if (field['kind'] == 'date_range') return ['${name}_start', '${name}_end'];
  return [name];
}

/// What a form field's prefill puts under [formFieldKeys].
///
/// A `multi_select` arrives with a list of option values, copied so the
/// working value never aliases the wire's. A `date_range` has no prefill shape
/// of its own in the protocol; a list of two days is read as its start and
/// end, which is the one shape a model asked for "the stay" is likely to give.
Map<String, Object> formFieldSeeds(Map field) {
  final value = field['value'];
  final keys = formFieldKeys(field);
  if (value == null || keys.isEmpty) return const {};
  if (field['kind'] == 'date_range') {
    if (value is! List || value.length != 2) return const {};
    return {
      for (var i = 0; i < 2; i++)
        if (value[i] is String) keys[i]: value[i] as String,
    };
  }
  if (value is List) return {keys.single: value.whereType<String>().toList()};
  return {keys.single: value as Object};
}

/// The ids of a `choice` block's options, in order.
List<String> choiceOptionIds(Map<String, dynamic> props) {
  final options = props['options'];
  return [
    if (options is List)
      for (final option in options)
        if (option is Map && option['id'] is String) option['id'] as String,
  ];
}

/// How few and how many options a `choice` takes: one exactly, unless it is
/// `multi`, which takes `min_selected` (1 when absent) up to `max_selected`
/// (every option when absent). The same reading as `selectionOptions` in
/// packages/protocol, which the server checks the answer with, so the block
/// and the server cannot disagree on what may be sent.
(int, int) choiceBounds(Map<String, dynamic> props) {
  if (props['mode'] != 'multi') return (1, 1);
  final count = choiceOptionIds(props).length;
  final min = props['min_selected'];
  final max = props['max_selected'];
  return (
    min is int ? min : 1,
    max is int ? max : count,
  );
}

/// The scores a `rating` block's scale offers, in order: 1 to 5 for stars, 0
/// (down) and 1 (up) for thumbs, 0 to 10 for NPS. The table `/v1/ratings`
/// checks a score against, so the block never offers one the server would
/// refuse. Empty for a scale this build does not know.
List<int> ratingScores(Map<String, dynamic> props) => switch (props['scale']) {
      'stars_5' => const [1, 2, 3, 4, 5],
      'thumbs' => const [0, 1],
      'nps_11' => const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      _ => const [],
    };

// ————————————————————————— actions in props —————————————————————————

/// The closed union of everything an interactive prop may carry.
sealed class UIAction {
  const UIAction();

  static UIAction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    switch (map['kind']) {
      case 'reply':
        final text = map['text'];
        return text is String ? ReplyAction(text) : null;
      case 'app_action':
        final name = map['name'];
        if (name is! String) return null;
        return AppActionRef(
          invocationId: map['invocation_id'] as String?,
          name: name,
          params: (map['params'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      case 'confirm':
        final id = map['invocation_id'];
        return id is String ? ConfirmAction(id) : null;
      case 'cancel':
        final id = map['invocation_id'];
        return id is String ? CancelAction(id) : null;
      case 'open_url':
        final url = map['url'];
        if (url is! String || !url.startsWith('https://')) return null;
        return OpenUrlAction(url, external: map['external'] == true);
      case 'navigate':
        final route = map['route'];
        if (route is! String || route.isEmpty) return null;
        final params = map['params'];
        // Strings, numbers and booleans are all the wire allows; anything
        // else is dropped here rather than handed to the app's own code.
        return NavigateAction(route, {
          if (params is Map)
            for (final entry in params.entries)
              if (entry.value is String || entry.value is num || entry.value is bool)
                '${entry.key}': entry.value,
        });
      case 'call':
        final phone = map['phone'];
        if (phone is! String || phone.trim().isEmpty) return null;
        return CallAction(phone, label: _filled(map['label']));
      case 'copy':
        final text = map['text'];
        if (text is! String || text.isEmpty) return null;
        return CopyAction(text, label: _filled(map['label']));
      case 'add_to_calendar':
        final title = map['title'];
        final startsAt = _instant(map['starts_at']);
        if (title is! String || title.isEmpty || startsAt == null) return null;
        return AddToCalendarAction(
          title: title,
          startsAt: startsAt,
          endsAt: _instant(map['ends_at']),
          location: _filled(map['location']),
          notes: _filled(map['notes']),
        );
    }
    return null;
  }
}

String? _filled(Object? value) => value is String && value.isNotEmpty ? value : null;

/// An instant the wire gives with its offset, or null when it gives none
/// that parses: a calendar event at an unknown time is not one to add.
DateTime? _instant(Object? value) => value is String ? DateTime.tryParse(value) : null;

class ReplyAction extends UIAction {
  const ReplyAction(this.text);
  final String text;
}

class AppActionRef extends UIAction {
  const AppActionRef({this.invocationId, required this.name, required this.params});
  final String? invocationId;
  final String name;
  final Map<String, dynamic> params;
}

class ConfirmAction extends UIAction {
  const ConfirmAction(this.invocationId, {this.typed});
  final String invocationId;

  /// What the user typed on a card that asks for it (`type_to_confirm`).
  final String? typed;
}

class CancelAction extends UIAction {
  const CancelAction(this.invocationId);
  final String invocationId;
}

class OpenUrlAction extends UIAction {
  const OpenUrlAction(this.url, {this.external = false});
  final String url;

  /// Handed to the operating system rather than opened in an in-app browser,
  /// so a maps link opens the maps app (`design/CATALOG-B5.md`). The server
  /// allows it only for Apple's and Google's maps; the SDK also sets it on
  /// the directions and wallet links it builds itself.
  final bool external;
}

/// Opens [route], one of the screens the app registered, with [params]
/// (`design/NAVIGATE.md`). The server has checked both before the block left.
class NavigateAction extends UIAction {
  const NavigateAction(this.route, [this.params = const {}]);
  final String route;
  final Map<String, Object?> params;
}

/// Opens the dialler with [phone] filled in; the call is the user's to make.
/// The button shows [label], or the number itself.
class CallAction extends UIAction {
  const CallAction(this.phone, {this.label});
  final String phone;
  final String? label;
}

/// Opens the mail app with a message to [address]; the user writes and sends
/// it. Never on the wire: it is what a `contact` block's email channel builds
/// for itself, so its button goes through the same tap path as a call.
class EmailAction extends UIAction {
  const EmailAction(this.address);
  final String address;
}

/// Puts [text] on the clipboard: an account number, a reference, a code.
class CopyAction extends UIAction {
  const CopyAction(this.text, {this.label});
  final String text;
  final String? label;
}

/// Opens the device's own event editor with the event filled in; the user
/// saves it. [startsAt] and [endsAt] are the instants the wire gave.
class AddToCalendarAction extends UIAction {
  const AddToCalendarAction({
    required this.title,
    required this.startsAt,
    this.endsAt,
    this.location,
    this.notes,
  });
  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? location;
  final String? notes;
}

// ————————————————————————— blocks —————————————————————————

/// A block as it arrives on the wire. Props stay a raw map; renderers read
/// them leniently and unknown props are simply ignored (protocol rule).
class WireBlock {
  WireBlock({
    required this.id,
    required this.type,
    required this.fallbackText,
    required this.props,
    this.surfaceId,
    this.revision,
  });

  final String id;
  final String type;
  final String fallbackText;
  final Map<String, dynamic> props;

  /// The name of the thing on screen this block draws, when the model gave
  /// it one: a later block with the same id and a higher [revision] takes
  /// this one's place. Null for an id the protocol would not have sent.
  final String? surfaceId;

  /// Which drawing of [surfaceId] this is: 1 the first time in the
  /// conversation, one more each time after. Set by the server, never the
  /// model. Without it a block with a [surfaceId] is an ordinary block.
  final int? revision;

  static final RegExp _surfaceIdPattern = RegExp(r'^[a-z][a-z0-9_]{0,47}$');

  /// Mutable streaming buffer for `text` blocks while deltas arrive.
  String streamingText = '';
  bool ready = false;

  static WireBlock? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final id = map['id'];
    final type = map['type'];
    if (id is! String || type is! String) return null;
    final surfaceId = map['surface_id'];
    final revision = map['revision'];
    return WireBlock(
      id: id,
      type: type,
      fallbackText: map['fallback_text'] as String? ?? '',
      props: (map['props'] as Map?)?.cast<String, dynamic>() ?? const {},
      surfaceId: surfaceId is String && _surfaceIdPattern.hasMatch(surfaceId)
          ? surfaceId
          : null,
      revision: revision is int && revision >= 1 ? revision : null,
    )..ready = true;
  }
}

// ————————————————————————— SSE events —————————————————————————

/// Coercion, not casting. The renderers are forbidden from casting a wire
/// value and this file was teaching the opposite lesson about the same wire:
/// a hard cast here turns a schema change into an exception the transport
/// swallows, and the event is dropped with no signal at all.
String? _text(Object? value) => value is String ? value : null;

int? _int(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

sealed class RendelWireEvent {
  const RendelWireEvent();

  static RendelWireEvent? tryParse(String eventName, Map<String, dynamic> data) {
    switch (eventName) {
      case 'turn.start':
        final conversationId = _text(data['conversation_id']);
        final messageId = _text(data['message_id']);
        if (conversationId == null || messageId == null) return null;
        return TurnStart(
          conversationId: conversationId,
          messageId: messageId,
          model: _text(data['model']) ?? '',
          requestId: _text(data['request_id']),
          lang: _text(data['lang']),
        );
      case 'turn.status':
        final step = _text(data['step']);
        if (step == null) return null;
        return TurnStatus(step: step, action: _text(data['action']));
      case 'block.start':
        final index = _int(data['index']);
        final id = _text(data['id']);
        if (index == null || id == null) return null;
        return BlockStart(
          index: index,
          id: id,
          blockType: _text(data['block_type']) ?? 'text',
        );
      case 'block.delta':
        final index = _int(data['index']);
        if (index == null) return null;
        return BlockDelta(index: index, textDelta: _text(data['text_delta']) ?? '');
      case 'block.ready':
        final block = WireBlock.tryParse(data['block']);
        final index = _int(data['index']);
        if (block == null || index == null) return null;
        return BlockReady(index: index, block: block);
      case 'action.execute':
        final invocationId = _text(data['invocation_id']);
        final name = _text(data['name']);
        if (invocationId == null || name == null) return null;
        return ActionExecute(
          invocationId: invocationId,
          name: name,
          params: (data['params'] as Map?)?.cast<String, dynamic>() ?? const {},
          timeoutMs: _int(data['timeout_ms']) ?? 15000,
        );
      case 'turn.end':
        final remaining = data['remaining'];
        return TurnEnd(
          status: _text(data['status']) ?? 'completed',
          pending: (data['pending'] as List?)?.whereType<String>().toList() ?? const [],
          remainingHint: remaining is Map ? _text(remaining['hint']) : null,
          lang: _text(data['lang']),
          speech: _text(data['speech']),
        );
      case 'error':
        return RendelError(
          code: _text(data['code']) ?? 'internal',
          message: _text(data['message']) ?? '',
          retryable: data['retryable'] == true,
        );
      case 'notice':
        final message = _text(data['message']);
        final hint = _text(data['hint']);
        if (message == null || hint == null) return null;
        final action = data['action'];
        return RendelNotice(
          kind: _text(data['kind']) ?? 'paused',
          message: message,
          hint: hint,
          until: DateTime.tryParse(_text(data['until']) ?? ''),
          actionLabel: action is Map ? _text(action['label']) : null,
          actionUrl: action is Map ? _text(action['url']) : null,
        );
      case 'speech':
        final token = _text(data['token']);
        final text = _text(data['text']);
        if (token == null || text == null) return null;
        return TurnSpeech(
          token: token,
          text: text,
          lang: _text(data['lang']),
          parts: (data['parts'] as List?)?.whereType<String>().toList() ?? const [],
        );
      case 'memory':
        final op = MemoryOp.values.asNameMap()[_text(data['op'])];
        final key = _text(data['key']);
        if (op == null || key == null || key.isEmpty) return null;
        return MemoryChange(
          op: op,
          kind: MemoryKind.values.asNameMap()[_text(data['kind'])],
          id: _text(data['id']),
          key: key,
          label: _text(data['label']),
          value: _text(data['value']),
          category: _text(data['category']),
          expiresAt: DateTime.tryParse(_text(data['expires_at']) ?? ''),
        );
      case 'ping':
        return const Ping();
    }
    return null;
  }
}

class TurnStart extends RendelWireEvent {
  const TurnStart({
    required this.conversationId,
    required this.messageId,
    required this.model,
    this.requestId,
    this.lang,
  });
  final String conversationId;
  final String messageId;
  final String model;

  /// The server's id for this turn. Null against an older API. It is what
  /// makes a support message actionable: one string that appears in our logs,
  /// on the row in the database and on the user's screen.
  final String? requestId;

  /// The language this turn's answer is written in, as a BCP-47 tag (`tr`,
  /// `en-AU`). Null against an older API. The SDK's own words follow it, so
  /// a Turkish answer is not framed in English chrome.
  final String? lang;
}

/// What the turn is doing while the reader waits: `action` when the model
/// starts calling one of the app's actions (named in [action]), `composing`
/// when it starts drawing the answer. Kept as the wire's string, so a step
/// added later reaches the controller and is ignored there rather than lost
/// here.
class TurnStatus extends RendelWireEvent {
  const TurnStatus({required this.step, this.action});
  final String step;
  final String? action;
}

class BlockStart extends RendelWireEvent {
  const BlockStart({required this.index, required this.id, required this.blockType});
  final int index;
  final String id;
  final String blockType;
}

class BlockDelta extends RendelWireEvent {
  const BlockDelta({required this.index, required this.textDelta});
  final int index;
  final String textDelta;
}

class BlockReady extends RendelWireEvent {
  const BlockReady({required this.index, required this.block});
  final int index;
  final WireBlock block;
}

class ActionExecute extends RendelWireEvent {
  const ActionExecute({
    required this.invocationId,
    required this.name,
    required this.params,
    required this.timeoutMs,
  });
  final String invocationId;
  final String name;
  final Map<String, dynamic> params;
  final int timeoutMs;
}

class TurnEnd extends RendelWireEvent {
  const TurnEnd({required this.status, required this.pending, this.remainingHint, this.lang, this.speech});
  final String status;
  final List<String> pending;

  /// "1 question left today", once one is left under the app's usage limit.
  final String? remainingHint;

  /// The language the answer is written in (`tr`, `en`…), for the voice that
  /// reads it aloud. Null when its words did not say, and from an older server.
  final String? lang;

  /// The answer's opening, sealed for `GET /v1/speech/:token`, which returns
  /// it as MP3 in a natural voice. Null where the server has no voice.
  final String? speech;
}

class RendelError extends RendelWireEvent {
  const RendelError({required this.code, required this.message, required this.retryable});
  final String code;
  final String message;
  final bool retryable;
}

/// The assistant is not answering, on purpose (`notices`): the person's own
/// usage limit (`limit`), or the app's budget or credit paused (`paused`).
/// Drawn where the answer goes; the composer rests, saying [hint], until
/// [until].
class RendelNotice extends RendelWireEvent {
  const RendelNotice({
    required this.kind,
    required this.message,
    required this.hint,
    required this.until,
    this.actionLabel,
    this.actionUrl,
  });
  final String kind;
  final String message;
  final String hint;
  final DateTime? until;
  final String? actionLabel;
  final String? actionUrl;
}

/// The answer's opening, the moment it is written and ahead of the cards
/// under it: [token] for `GET /v1/speech/:token` (MP3 in a natural voice),
/// [text] and [lang] for reading it in the phone's own voice instead.
class TurnSpeech extends RendelWireEvent {
  const TurnSpeech({required this.token, required this.text, this.lang, this.parts = const []});
  final String token;
  final String text;
  final String? lang;

  /// The same words a sentence at a time, each its own `/v1/speech` token,
  /// played one after another so the first is heard soonest. Empty from a
  /// server before 2026-10-23's.
  final List<String> parts;
}

class Ping extends RendelWireEvent {
  const Ping();
}

/// What a turn did to the person's memory (`design/plans/preference-memory.md`).
enum MemoryOp { saved, updated, forgotten, used }

/// Who a note came from: the person said it (`stated`), Rendel noticed it
/// (`learned`), or the app wrote it (`set`).
enum MemoryKind { stated, learned, set }

/// One `memory` event: a note saved, changed or forgotten by this turn, or
/// one the answer relied on ([MemoryOp.used]). One event per note, before
/// `turn.end`, for the chips under the answer.
///
/// [id] is the note's, for Undo (`DELETE /v1/memory/:id`); null for a forget,
/// whose row is gone. [key] `*` is a forget of everything.
class MemoryChange extends RendelWireEvent {
  MemoryChange({
    required this.op,
    required this.key,
    this.kind,
    this.id,
    this.label,
    this.value,
    this.category,
    this.expiresAt,
  });
  final MemoryOp op;
  final MemoryKind? kind;
  final String? id;
  final String key;
  final String? label;
  final String? value;
  final String? category;

  /// The instant the note stops holding: the midnight after its last day.
  final DateTime? expiresAt;

  /// True once this save was taken back with Undo, on this device.
  bool undone = false;

  /// What the chip calls the note: its label, or its key.
  String get name => label ?? key;
}

// ————————————————————————— manifest —————————————————————————

/// Canonical JSON: sorted object keys at every level, no whitespace, nulls
/// dropped. Must produce byte-identical output to the server's canonicalize()
/// so SHA-256 hashes agree across languages.
String canonicalize(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return jsonEncode(value);
  }
  if (value is List) {
    return '[${value.map(canonicalize).join(',')}]';
  }
  if (value is Map) {
    final entries = value.entries
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key.toString(), e.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final body = entries
        .map((e) => '${jsonEncode(e.key)}:${canonicalize(e.value)}')
        .join(',');
    return '{$body}';
  }
  throw ArgumentError('unsupported manifest value: ${value.runtimeType}');
}

Map<String, dynamic> buildManifest(
  Iterable<RendelAction> actions, {
  Iterable<RendelRoute> routes = const [],
}) {
  final sorted = actions.toList()..sort((a, b) => a.name.compareTo(b.name));
  final screens = routes.toList()..sort((a, b) => a.name.compareTo(b.name));
  return {
    'version': 1,
    'actions': [
      for (final a in sorted)
        {
          'name': a.name,
          'description': a.description,
          'inputSchema': a.params.toJson(),
          'nc': {
            'risk': a.risk.name,
            if (a.confirmTemplate != null) 'confirmTemplate': a.confirmTemplate,
            // Omitted when empty, not sent as `{}`. The manifest is hashed and
            // the hash is compared byte for byte against the server's own
            // canonicalisation, so an empty map on one side and an absent key
            // on the other is a mismatch that reads as "the server has not
            // seen this manifest" on every turn.
            if (a.confirmTemplates != null && a.confirmTemplates!.isNotEmpty)
              'confirmTemplates': a.confirmTemplates,
            'timeoutMs': a.timeoutMs,
            // Only when set, for the same reason: every manifest from before
            // this flag keeps the hash it had.
            if (a.undoable) 'undoable': true,
            if (a.editable.isNotEmpty) 'editable': a.editable,
            if (a.typeToConfirm != null) 'typeToConfirm': a.typeToConfirm,
            if (a.fullText != null) 'fullText': a.fullText!.toJson(),
            if (a.confirmLabel != null) 'confirmLabel': a.confirmLabel,
            if (a.confirmLabels != null && a.confirmLabels!.isNotEmpty) 'confirmLabels': a.confirmLabels,
            if (a.undo != null) 'undo': a.undo!.toJson(),
            if (a.confirm != null) 'confirm': a.confirm!.name,
          },
        },
    ],
    // Left out, not sent empty, for an app that registers no routes: its hash
    // is then the one it had before routes existed, and the server does not
    // see a new manifest from every build that updates the SDK.
    if (screens.isNotEmpty) 'routes': [for (final route in screens) route.toJson()],
  };
}

String hashManifest(Map<String, dynamic> manifest) {
  return sha256.convert(utf8.encode(canonicalize(manifest))).toString();
}
