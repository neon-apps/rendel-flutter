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
  });

  final String id;

  /// What kind it is: `watch`, `date`, `answer_arrived`, … — for an app that
  /// draws its own.
  final String type;
  final String title;
  final String body;
  final String button;

  /// One from `GET /v1/followups/next`, or null when it is not whole.
  static RendelFollowup? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'], body = raw['body'], button = raw['button'];
    if (id is! String || title is! String || body is! String || button is! String) return null;
    final type = raw['type'];
    return RendelFollowup(id: id, type: type is String ? type : '', title: title, body: body, button: button);
  }
}

/// The SDK's own follow-up state, shared by [Rendel], the launcher's popup and
/// the card at the top of the thread. Not exported: an app reads
/// `Rendel.followup` and acts through `Rendel.openFollowup` /
/// `Rendel.dismissFollowup`.
class RendelFollowups {
  RendelFollowups._();

  static final RendelFollowups instance = RendelFollowups._();

  /// The follow-up waiting to be seen, or null.
  final ValueNotifier<RendelFollowup?> current = ValueNotifier<RendelFollowup?>(null);

  /// Where `followup_shown` and `followup_dismiss` go; set by `Rendel.init`.
  void Function(Map<String, dynamic> event)? send;

  String? _counted;

  /// It is on screen, as the popup or the card: counted once a follow-up,
  /// however often it is drawn.
  void shown() {
    final followup = current.value;
    if (followup == null || _counted == followup.id) return;
    _counted = followup.id;
    send?.call({'type': 'followup_shown', 'followup_id': followup.id});
  }

  /// Put away for good with the cross.
  void dismiss() {
    final followup = current.value;
    if (followup == null) return;
    current.value = null;
    send?.call({'type': 'followup_dismiss', 'followup_id': followup.id});
  }

  void clear() {
    current.value = null;
    _counted = null;
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
