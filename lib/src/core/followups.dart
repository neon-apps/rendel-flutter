import 'package:flutter/foundation.dart';

/// A follow-up for the person using the app (design/plans/marketing-channels.md
/// §3.10): something they asked for has news. The words are the server's,
/// written for them in their language at the moment it was asked; nothing
/// here is a string of the SDK's.
@immutable
class RendelFollowup {
  const RendelFollowup({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.button,
    this.channel = 'in_app',
    this.style = 'popup',
  });

  final String id;

  /// What kind it is: `watch`, `date`, `answer_arrived`, … — for an app that
  /// draws its own.
  final String type;
  final String title;
  final String body;
  final String button;

  /// The channel it went on: `in_app`, `push` or `email`. Whatever it was, it
  /// also waits inside Rendel as a card.
  final String channel;

  /// How an "In the app" message shows on the app's screens while Rendel is
  /// closed: `popup` by the launcher, or `banner` across the top.
  final String style;

  bool get isBanner => style == 'banner';

  /// One from `GET /v1/followups/next` or `/inbox`, or null when it is not whole.
  static RendelFollowup? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'], body = raw['body'], button = raw['button'];
    if (id is! String || title is! String || body is! String || button is! String) return null;
    final type = raw['type'], channel = raw['channel'], style = raw['style'];
    return RendelFollowup(
      id: id,
      type: type is String ? type : '',
      title: title,
      body: body,
      button: button,
      channel: channel is String ? channel : 'in_app',
      style: style == 'banner' ? 'banner' : 'popup',
    );
  }
}

/// The SDK's own follow-up state (Tuna, 2026-10-24), in two places:
///
/// - [current]: the one "In the app" message, shown on the app's screens
///   while Rendel is closed, by the launcher or as a banner.
/// - [cards]: every message waiting inside Rendel for this person, whatever
///   channel it went on, at the top of its first page: [current] while it
///   waits, then what `/v1/followups/inbox` read when Rendel opened.
///
/// Not exported: an app reads `Rendel.followup` / `Rendel.followupCards` and
/// acts through `Rendel.openFollowup` / `Rendel.dismissFollowup`.
class RendelFollowups {
  RendelFollowups._() {
    current.addListener(_recompute);
  }

  static final RendelFollowups instance = RendelFollowups._();

  /// How many cards wait inside Rendel at once, as the server keeps them.
  static const inboxSize = 3;

  /// The "In the app" message waiting to be seen, or null.
  final ValueNotifier<RendelFollowup?> current = ValueNotifier<RendelFollowup?>(null);

  /// The cards inside Rendel, newest first, none put away.
  final ValueNotifier<List<RendelFollowup>> cards = ValueNotifier<List<RendelFollowup>>(const []);

  List<RendelFollowup> _inbox = const [];
  final Set<String> _gone = {};
  final Set<String> _counted = {};

  /// Where `followup_shown` and `followup_dismiss` go; set by `Rendel.init`.
  void Function(Map<String, dynamic> event)? send;

  /// What `/v1/followups/inbox` read when Rendel opened.
  void setInbox(List<RendelFollowup> inbox) {
    _inbox = inbox;
    _recompute();
  }

  void _recompute() {
    final seen = <String>{};
    cards.value = [if (current.value case final waiting?) waiting, ..._inbox]
        .where((card) => !_gone.contains(card.id) && seen.add(card.id))
        .take(inboxSize)
        .toList(growable: false);
  }

  /// On screen, as the popup, the banner or a card: counted once a message,
  /// however often it is drawn. [id] is [current]'s when not given.
  void shown([String? id]) {
    final shownId = id ?? current.value?.id;
    if (shownId == null || !_counted.add(shownId)) return;
    send?.call({'type': 'followup_shown', 'followup_id': shownId});
  }

  /// Gone from wherever it was: the app's screen and Rendel alike.
  void forget(String id) {
    _gone.add(id);
    _inbox = _inbox.where((card) => card.id != id).toList(growable: false);
    if (current.value?.id == id) {
      current.value = null;
    } else {
      _recompute();
    }
  }

  /// Put away for good with the cross. [id] is [current]'s when not given.
  void dismiss([String? id]) {
    final dismissed = id ?? current.value?.id;
    if (dismissed == null) return;
    forget(dismissed);
    send?.call({'type': 'followup_dismiss', 'followup_id': dismissed});
  }

  void clear() {
    _inbox = const [];
    _gone.clear();
    _counted.clear();
    current.value = null;
    _recompute();
  }
}

/// The device's zone where it has no name for it: IANA's `Etc/GMT` zones,
/// whose sign is the reverse of the offset (UTC+3 is `Etc/GMT-3`). Null for an
/// offset that is not whole hours, which keeps the app's default zone. A host
/// that knows the real zone (`rendel_push` does) passes it instead.
String? offsetZone(Duration offset) {
  if (offset.inMinutes % 60 != 0) return null;
  final hours = offset.inHours;
  if (hours == 0) return 'Etc/GMT';
  return hours > 0 ? 'Etc/GMT-$hours' : 'Etc/GMT+${-hours}';
}
