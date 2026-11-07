import 'dart:convert';

import '../protocol/protocol.dart' show MemoryKind;
import '../transport/api_client.dart';

/// One note as `GET /v1/memory` lists it.
class RendelMemoryNote {
  const RendelMemoryNote({
    required this.id,
    required this.kind,
    required this.key,
    required this.value,
    this.label,
    this.category,
    this.expiresAt,
  });

  final String id;
  final MemoryKind kind;
  final String key;
  final String? label;
  final String value;
  final String? category;

  /// The instant the note stops holding: the midnight (UTC) after its last day.
  final DateTime? expiresAt;

  /// What the sheet calls the note: its label, or its key.
  String get name => label ?? key;

  /// The person may take it back; the app's own facts (`set`) they may not.
  bool get forgettable => kind != MemoryKind.set;

  static RendelMemoryNote? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final kind = MemoryKind.values.asNameMap()[raw['kind']];
    final key = raw['key'];
    final value = raw['value'];
    if (id is! String || kind == null || key is! String || value is! String) return null;
    final label = raw['label'];
    final category = raw['category'];
    final expires = raw['expires_at'];
    return RendelMemoryNote(
      id: id,
      kind: kind,
      key: key,
      value: value,
      label: label is String ? label : null,
      category: category is String ? category : null,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
    );
  }
}

/// One of the person's `identify` traits as `GET /v1/memory` lists it: the
/// key in words, and its value. The app's own, so it cannot be forgotten.
class RendelMemoryTrait {
  const RendelMemoryTrait({required this.key, required this.label, required this.value});

  final String key;
  final String label;
  final String value;

  static RendelMemoryTrait? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final label = raw['label'];
    final value = raw['value'];
    if (key is! String || label is! String || value is! String) return null;
    return RendelMemoryTrait(key: key, label: label, value: value);
  }
}

/// `GET /v1/memory`: whether the app keeps preferences at all, the notes,
/// what Rendel noticed without naming it ([other]) and the app's [traits].
/// The last two read empty from a server before them.
class RendelMemoryList {
  const RendelMemoryList({
    required this.enabled,
    required this.notes,
    this.other = const [],
    this.traits = const [],
  });
  final bool enabled;
  final List<RendelMemoryNote> notes;

  /// Notes Rendel noticed without naming them: read into answers too, so
  /// listed under "Other", by their sentence.
  final List<RendelMemoryNote> other;
  final List<RendelMemoryTrait> traits;
}

/// What Rendel remembers about the person on this device
/// (`design/plans/preference-memory.md` §3.7), through the SDK's own client
/// and headers: signed in, as the person [user] names; signed out, this
/// install's own anonymous record.
class RendelMemory {
  RendelMemory(this.api, {required this.user});

  final RendelApiClient api;

  /// Who is signed in right now (`identify`'s `id` and `hmac`), read on every
  /// call; null for nobody.
  final Map<String, String>? Function() user;

  /// The notes, or null when they could not be read.
  Future<RendelMemoryList?> list() async {
    final answer = await api.memory('GET', user: user());
    if (answer == null || answer.status != 200) return null;
    try {
      final parsed = jsonDecode(answer.body);
      if (parsed is! Map) return null;
      List<RendelMemoryNote> notesOf(Object? raw) => [
            if (raw is List)
              for (final item in raw)
                if (RendelMemoryNote.tryParse(item) case final note?) note,
          ];
      final traits = parsed['traits'];
      return RendelMemoryList(
        enabled: parsed['enabled'] != false,
        notes: notesOf(parsed['notes']),
        other: notesOf(parsed['other']),
        traits: [
          if (traits is List)
            for (final raw in traits)
              if (RendelMemoryTrait.tryParse(raw) case final trait?) trait,
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// Forgets the note [id]: a row's Forget, a chip's Undo. True once it is
  /// gone, which a 404 also says: there is no such note of theirs.
  Future<bool> forget(String id) async {
    final answer = await api.memory('DELETE', id: id, user: user());
    return answer != null && (answer.status == 204 || answer.status == 404);
  }

  /// Forgets every note the person told Rendel or it noticed; the app's own
  /// stay. True once the server did it.
  Future<bool> forgetAll() async {
    final answer = await api.memory('DELETE', user: user());
    return answer?.status == 204;
  }
}
