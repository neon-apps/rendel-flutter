import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'log.dart';
import 'remote_config.dart' show RendelConfigStore;

/// Product analytics on the device (design/plans/product-analytics.md §2):
/// the session every counted item belongs to, the super properties sent on
/// it, the switch that stops all of it, and the rules a value or a label
/// passes before it leaves. The wire contract and the masking patterns are
/// `packages/protocol/src/analytics.ts`; the web SDK's twin is
/// `sdk/web/src/analytics.ts`.

/// An event or property name: `add_to_cart`, `plan`.
final RegExp analyticsName = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// At most this many properties on one event or session.
const int maxProps = 20;

/// A string property's longest value; longer is cut.
const int maxPropChars = 255;

/// A tap's label, at most: a control's caption, never content.
const int maxLabelChars = 50;

const String masked = '[masked]';

/// Values that look personal: emails, IBANs, phone numbers, and any run of
/// four or more digits (card numbers and national ids included). The same
/// list, in the same order, as the protocol's `MASK_PATTERNS`.
final List<RegExp> maskPatterns = [
  RegExp(r'[^\s@]+@[^\s@]+\.[^\s@]+'),
  RegExp(r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,4})?\b', caseSensitive: false),
  RegExp(r'\+?\d[\d\s().-]{6,}\d'),
  RegExp(r'\d{4,}'),
];

/// [text] with anything personal-looking replaced by `[masked]`.
String maskText(String text) => maskPatterns.fold(text, (out, pattern) => out.replaceAll(pattern, masked));

/// Flat properties as the server takes them: valid names, scalar values,
/// strings masked and cut, at most [room] keys. The keys left out are added
/// to [dropped], for the caller to say so.
Map<String, Object?> cleanProps(Map<String, dynamic> given, {int room = maxProps, List<String>? dropped}) {
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in given.entries) {
    final scalar = value == null || value is bool || (value is num && value.isFinite) || value is String;
    if (!analyticsName.hasMatch(key) || !scalar || out.length >= room) {
      dropped?.add(key);
      continue;
    }
    out[key] = value is String ? _cut(maskText(value), maxPropChars) : value;
  }
  return out;
}

String _cut(String text, int max) => text.length > max ? text.substring(0, max) : text;

/// What the server says about tap capture (`capture` in the app config),
/// each field its default when it is missing or wrong.
@immutable
class RendelCapture {
  const RendelCapture({this.taps = 'on', this.sample = 1, this.mask = const []});

  /// `on`, `no_text` (taps without labels) or `off`.
  final String taps;

  /// The share of devices whose taps are kept, by a hash of the device id.
  final double sample;

  /// Screen names whose taps keep no label.
  final List<String> mask;

  static const RendelCapture defaults = RendelCapture();

  bool get isDefault => taps == 'on' && sample == 1 && mask.isEmpty;

  static RendelCapture parse(Object? raw) {
    if (raw is! Map) return defaults;
    final taps = raw['taps'];
    final sample = raw['sample'];
    final mask = raw['mask'];
    return RendelCapture(
      taps: taps == 'off' || taps == 'no_text' ? taps as String : 'on',
      sample: sample is num && sample >= 0 && sample <= 1 ? sample.toDouble() : 1,
      mask: mask is List ? [for (final m in mask.take(50)) if (m is String && m.length <= 200) m] : const [],
    );
  }

  Map<String, Object?> toJson() => {'taps': taps, 'sample': sample, 'mask': mask};

  @override
  bool operator ==(Object other) =>
      other is RendelCapture && other.taps == taps && other.sample == sample && listEquals(other.mask, mask);

  @override
  int get hashCode => Object.hash(taps, sample, Object.hashAll(mask));
}

/// 0 up to 1 from the device id, the same on every launch: whether this
/// device is in a tap sample. FNV-1a, as the web SDK's `sampleOf`.
double sampleOf(String deviceId) {
  var hash = 0x811c9dc5;
  for (final unit in deviceId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash / 0x100000000;
}

/// A v4 uuid, made on the device.
String uuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// The session, the super properties and the switch, kept on the device.
class RendelAnalytics {
  RendelAnalytics._();

  static final RendelAnalytics instance = RendelAnalytics._();

  /// A session ends after this long with nothing counted, or this long in
  /// the background.
  static const Duration idle = Duration(minutes: 30);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// Whether screen views, taps, events and sessions are counted on this
  /// device. Chat does not depend on it.
  bool get enabled => _enabled;
  bool _enabled = true;

  /// The super properties, sent on the session rather than on every row.
  Map<String, Object?> get superProps => Map.unmodifiable(_super);
  final Map<String, Object?> _super = {};

  /// What the server last said about taps.
  RendelCapture capture = RendelCapture.defaults;

  String? _session;
  DateTime? _started;
  DateTime? _last;
  DateTime? _hidden;

  /// The session the next item belongs to, once one has started.
  String? get session => _session;

  /// Where the three are kept; null until `init` hands it over, and what was
  /// changed before then is written once it has read what was kept.
  RendelConfigStore? _store;
  bool _loaded = false;
  bool? _enabledBefore;
  final Set<String> _removedBefore = {};
  final Set<String> _setBefore = {};

  /// Called with a session item to queue: a session starting, or its super
  /// properties changing. Wired by [RendelScreens].
  void Function(Map<String, dynamic> item)? onSession;

  /// Called when the switch goes off: what waits is dropped.
  VoidCallback? onDisabled;

  /// Reads what this device kept, once, with what changed before winning.
  Future<void> load(RendelConfigStore store) async {
    if (_loaded) return;
    _store = store;
    Map<String, dynamic> kept = const {};
    try {
      final raw = await store.read().timeout(const Duration(seconds: 2));
      if (raw != null && raw.isNotEmpty) kept = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (err) {
      RendelLog.warn('analytics_store_failed', 'the analytics settings could not be read back', error: err);
    }
    _loaded = true;
    final keptEnabled = kept['enabled'] != false;
    final keptSuper = kept['super'] is Map ? cleanProps((kept['super'] as Map).cast<String, dynamic>()) : <String, Object?>{};
    final changed = _enabledBefore != null || _setBefore.isNotEmpty || _removedBefore.isNotEmpty;
    final merged = <String, Object?>{
      for (final e in keptSuper.entries)
        if (!_removedBefore.contains(e.key) && !_setBefore.contains(e.key)) e.key: e.value,
      for (final key in _setBefore)
        if (_super.containsKey(key)) key: _super[key],
    };
    final before = jsonEncode(_super);
    _super
      ..clear()
      ..addAll(Map.fromEntries(merged.entries.take(maxProps)));
    final enabled = _enabledBefore ?? keptEnabled;
    // A session that started while the switch was not read yet is resumed
    // when it was kept, and told its properties when they arrived.
    final session = kept['session'];
    if (_session == null && session is Map && session['id'] is String && session['started'] is String && session['last'] is String) {
      final last = DateTime.tryParse(session['last'] as String);
      final started = DateTime.tryParse(session['started'] as String);
      if (last != null && started != null && clock().difference(last) < idle) {
        _session = session['id'] as String;
        _started = started;
        _last = last;
      }
    }
    _enabledBefore = null;
    _setBefore.clear();
    _removedBefore.clear();
    _setEnabled(enabled, write: false);
    if (enabled && _session != null && jsonEncode(_super) != before) _emitSession();
    if (changed) _write();
  }

  /// `Rendel.setAnalyticsEnabled`.
  void setEnabled(bool enabled) {
    if (!_loaded) _enabledBefore = enabled;
    _setEnabled(enabled, write: true);
  }

  void _setEnabled(bool enabled, {required bool write}) {
    final was = _enabled;
    _enabled = enabled;
    if (!enabled && was) {
      _session = _started = _last = null;
      onDisabled?.call();
    }
    if (write) _write();
  }

  /// `Rendel.register`: set or replace, at most 20 in all.
  void register(Map<String, dynamic> given) {
    final dropped = <String>[];
    final fresh = cleanProps(given, dropped: dropped);
    var changed = false;
    for (final MapEntry(:key, :value) in fresh.entries) {
      if (!_super.containsKey(key) && _super.length >= maxProps) {
        dropped.add(key);
        continue;
      }
      if (_super.containsKey(key) && _super[key] == value) continue;
      _super[key] = value;
      changed = true;
      if (!_loaded) {
        _setBefore.add(key);
        _removedBefore.remove(key);
      }
    }
    if (dropped.isNotEmpty) {
      RendelLog.warn(
        'invalid_prop',
        'register kept no ${dropped.map((k) => '"$k"').join(', ')}: a name is lowercase letters, digits and _, '
            'a value a string, number, boolean or null, and 20 at most',
      );
    }
    if (changed) _changed();
  }

  /// `Rendel.unregister`.
  void unregister(String key) {
    if (!_loaded) {
      _removedBefore.add(key);
      _setBefore.remove(key);
    }
    if (!_super.containsKey(key)) return;
    _super.remove(key);
    _changed();
  }

  void _changed() {
    _write();
    // Sent again on the session it changed in, for the whole of it.
    if (_enabled && _session != null) _emitSession();
  }

  /// The session for an item counted now: a new one after [idle] with
  /// nothing counted, or after [idle] in the background, and its session item
  /// queued first.
  String touch() {
    final now = clock();
    final last = _last;
    final hidden = _hidden;
    if (_session == null ||
        last == null ||
        now.difference(last) >= idle ||
        (hidden != null && now.difference(hidden) >= idle)) {
      _session = uuid();
      _started = now;
      _last = now;
      _hidden = null;
      _emitSession();
      _write();
    }
    _last = now;
    return _session!;
  }

  /// Somebody else from here on (`identify` of another person, `reset`): the
  /// next item starts a new session.
  void rotate() {
    _session = _started = _last = null;
  }

  /// The app went to the background: kept, so a relaunch soon after is the
  /// same session.
  void hidden() {
    _hidden ??= clock();
    if (_session != null) _write();
  }

  void resumed() {
    final hidden = _hidden;
    if (hidden != null && clock().difference(hidden) >= idle) rotate();
    _hidden = null;
  }

  void _emitSession() {
    final session = _session;
    final started = _started;
    if (session == null || started == null) return;
    onSession?.call({
      'type': 'session',
      'session': session,
      'started_at': started.toUtc().toIso8601String(),
      if (_super.isNotEmpty) 'super_props': Map<String, Object?>.of(_super),
    });
  }

  void _write() {
    final store = _store;
    if (store == null || !_loaded) return;
    final session = _session;
    final value = jsonEncode({
      'enabled': _enabled,
      if (_super.isNotEmpty) 'super': _super,
      if (session != null && _started != null && _last != null)
        'session': {
          'id': session,
          'started': _started!.toUtc().toIso8601String(),
          'last': _last!.toUtc().toIso8601String(),
        },
    });
    unawaited(Future.sync(() => store.write(value)).timeout(const Duration(seconds: 2)).catchError((Object err) {
      RendelLog.warn('analytics_store_failed', 'the analytics settings could not be kept', error: err);
    }));
  }

  /// For `Rendel.resetForTest`.
  void resetForTest() {
    clock = DateTime.now;
    _enabled = true;
    _super.clear();
    capture = RendelCapture.defaults;
    _session = _started = _last = _hidden = null;
    _store = null;
    _loaded = false;
    _enabledBefore = null;
    _setBefore.clear();
    _removedBefore.clear();
  }
}
