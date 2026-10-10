import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/src/core/device_id.dart';
import 'package:rendel/rendel.dart';

/// A store that records what it was asked to do, so a test can tell "read the
/// stored id" apart from "minted a new one and happened to write it".
class _RecordingStore implements RendelConfigStore {
  _RecordingStore([this._value]);

  String? _value;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read() async {
    reads++;
    return _value;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    _value = value;
  }
}

class _ThrowingStore implements RendelConfigStore {
  @override
  Future<String?> read() async => throw StateError('no disk today');

  @override
  Future<void> write(String value) async {}
}

class _HangingStore implements RendelConfigStore {
  @override
  Future<String?> read() => Completer<String?>().future;

  @override
  Future<void> write(String value) async {}
}

void main() {
  tearDown(() => RendelLog.sink = null);

  group('the id itself', () {
    test('is 32 lowercase hex characters', () {
      expect(RendelDeviceId.looksValid(RendelDeviceId.mint()), isTrue);
    });

    test('is not the same twice', () {
      final ids = List.generate(64, (_) => RendelDeviceId.mint()).toSet();
      expect(ids.length, 64);
    });

    test('rejects anything that is not the shape it mints', () {
      // The realistic failure is a key collision with the config store: both
      // sides read and write a single string, so a host that reuses one key
      // hands a JSON envelope to the device header.
      expect(RendelDeviceId.looksValid('{"config":{}}'), isFalse);
      expect(RendelDeviceId.looksValid(''), isFalse);
      expect(RendelDeviceId.looksValid('ABCDEF01234567890123456789012345'), isFalse);
      expect(RendelDeviceId.looksValid('0123456789abcdef'), isFalse);
      expect(RendelDeviceId.looksValid('${RendelDeviceId.mint()} '), isFalse);
    });
  });

  group('resolving against a store', () {
    test('a stored id comes back unchanged and is not rewritten', () async {
      final id = RendelDeviceId.mint();
      final store = _RecordingStore(id);
      expect(await RendelDeviceId.resolve(store), id);
      expect(store.reads, 1);
      expect(store.writes, 0);
    });

    test('two launches of one install are one device', () async {
      final store = _RecordingStore();
      final first = await RendelDeviceId.resolve(store);
      final second = await RendelDeviceId.resolve(store);
      expect(second, first, reason: 'this is the whole point of the store');
      expect(store.writes, 1);
    });

    test('an empty store is minted into and written through', () async {
      final store = _RecordingStore();
      final id = await RendelDeviceId.resolve(store);
      expect(RendelDeviceId.looksValid(id), isTrue);
      expect(store.writes, 1);
      expect(await store.read(), id);
    });

    test('a value that is not an id is replaced rather than sent', () async {
      final store = _RecordingStore('{"channel":"published"}');
      final id = await RendelDeviceId.resolve(store);
      expect(RendelDeviceId.looksValid(id), isTrue);
      expect(store.writes, 1);
    });

    test('a store that throws costs durability, not the launch', () async {
      final records = <RendelLogRecord>[];
      RendelLog.sink = records.add;
      final id = await RendelDeviceId.resolve(_ThrowingStore());
      expect(RendelDeviceId.looksValid(id), isTrue);
      expect(records.map((r) => r.code), contains('device_id_store_failed'));
    });

    test('a store that never answers does not hold init open', () async {
      final records = <RendelLogRecord>[];
      RendelLog.sink = records.add;
      final id = await RendelDeviceId.resolve(_HangingStore());
      expect(RendelDeviceId.looksValid(id), isTrue);
      expect(records.map((r) => r.code), contains('device_id_store_failed'));
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  test('no store says so once, at debug level', () async {
    final records = <RendelLogRecord>[];
    RendelLog.sink = records.add;
    final id = await RendelDeviceId.resolve(null);
    expect(RendelDeviceId.looksValid(id), isTrue);
    final warned = records.where((r) => r.code == 'device_id_ephemeral');
    expect(warned, hasLength(1));
    expect(warned.single.level, RendelLogLevel.debug);
  });
}
