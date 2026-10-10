import 'dart:math';

import 'log.dart';
import 'remote_config.dart';

/// The anonymous per-install identifier the SDK sends as `X-Rendel-Device`.
///
/// It is what the server buckets rate limits by, what `identify` binds a user
/// to, and what makes two launches of one install a returning device rather
/// than two new ones.
///
/// It used to be minted fresh on every cold start. Nothing was broken by that
/// — the server accepts any opaque id — but two things were quietly wrong:
/// the console's device and conversation counts were counting app launches,
/// and a per-device rate limit was reset by swiping the app away. Both are the
/// kind of wrong that stays invisible until someone reads a number and
/// believes it.
///
/// The SDK still takes no storage dependency (see [RendelConfigStore] for why), so
/// durability is a seam the host wires in three lines. A host that does not
/// wire it gets exactly the old behaviour and is told once, at debug level,
/// which number it is inflating.
class RendelDeviceId {
  RendelDeviceId._();

  /// The shape this SDK mints, and the only shape it will trust back out of a
  /// store. Deliberately not "any non-empty string": accepting whatever the
  /// key happened to hold is how a cached config payload ends up being sent
  /// as a device id after a key collision.
  static final RegExp _shape = RegExp(r'^[0-9a-f]{32}$');

  static bool looksValid(String value) => _shape.hasMatch(value);

  /// 128 bits from a secure source. Secure rather than `Random()` because the
  /// id is an identity the server buckets by: a guessable anon id lets a
  /// stranger holding the app's public key exhaust a specific device's rate
  /// bucket.
  static String mint() {
    final rng = Random.secure();
    return List.generate(32, (_) => '0123456789abcdef'[rng.nextInt(16)]).join();
  }

  /// How long a single key read or write may take before the launch gives up
  /// on durability. Generous for a plugin round-trip, short enough that a
  /// wedged store costs this install its stable id rather than its copilot.
  static const storeTimeout = Duration(seconds: 2);

  /// Reads the stored id, or mints and stores one. Never throws: a store that
  /// fails costs durability, never the launch.
  static Future<String> resolve(RendelConfigStore? store) async {
    if (store == null) {
      RendelLog.report(
        RendelLogLevel.debug,
        'device_id_ephemeral',
        'no RendelConfig.deviceIdStore is set, so this install gets a new device '
            'id on every cold start. Per-device rate limits reset each launch '
            "and the console's device counts will read high.",
      );
      return mint();
    }

    try {
      final stored = await store.read().timeout(storeTimeout);
      if (stored != null && looksValid(stored)) return stored;

      // Absent, or present but unusable — a truncated write, a key collision
      // with the config store, a hand-edited value. Replacing it is right:
      // the whole point of the id is that the server can bucket by it, and a
      // value the server may reject is worse than a fresh one.
      final minted = mint();
      await store.write(minted).timeout(storeTimeout);
      return minted;
    } catch (err) {
      RendelLog.warn(
        'device_id_store_failed',
        'the device id store failed; using an id that lasts for this run only',
        error: err,
      );
      return mint();
    }
  }
}
