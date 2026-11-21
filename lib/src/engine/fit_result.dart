import 'dart:convert';

/// The most of a handler's result the server takes, as `MAX_RESULT_BYTES`
/// in `@rendel/protocol` (32 KB since 2026-11-21).
const maxResultChars = 32768;

/// What the model is told a trimmed result left out, as `RESULT_CUT_NOTE`.
const resultCutNote =
    'Only the start of this result fit. Say what it shows, and that there is more; ask the person to narrow it (a date, a name, a status) to see the rest.';

/// [data] made to fit [limit] characters of JSON, as `fitResult` in
/// `@rendel/protocol` does it (Helix, 2026-11-21: a 39,685-character calendar
/// was refused whole, and the assistant said it could not read it). Its
/// fields are kept with its longest list cut to its first items; failing
/// that, the start of its JSON. `_cut` tells the model there is more.
/// Null when it fits as it is.
Map<String, dynamic>? fitResult(Map<String, dynamic> data, [int limit = maxResultChars]) {
  if (jsonEncode(data).length <= limit) return null;
  bool fits(Object value) => jsonEncode(value).length <= limit;
  String note(int kept, int of) => '$resultCutNote Kept $kept of $of.';
  MapEntry<String, dynamic>? longest;
  for (final entry in data.entries) {
    if (entry.value is! List) continue;
    if (longest == null || jsonEncode(entry.value).length > jsonEncode(longest.value).length) longest = entry;
  }
  if (longest != null) {
    final list = longest.value as List;
    Map<String, dynamic> build(int kept) => {...data, longest!.key: list.sublist(0, kept), '_cut': note(kept, list.length)};
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (fits(build(mid))) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final out = build(lo);
    if (fits(out)) return out;
  }
  final text = jsonEncode(data);
  final keep = limit - resultCutNote.length - 80;
  return {'text': text.substring(0, keep < 0 ? 0 : (keep < text.length ? keep : text.length)), '_cut': resultCutNote};
}
