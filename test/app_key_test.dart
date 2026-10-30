import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';

/// A key that is not the app's says so, and says where the app's key is.
///
/// An example's `nc_pk_test_...` started like a key and passed the only check
/// there was, to fail later as a network error on the first question; a key
/// the server did not know failed the same way. A developer reading either
/// learned nothing about where to look.
void main() {
  tearDown(Rendel.resetForTest);

  test("an example's placeholder is refused, with where the real key is", () async {
    final logs = <RendelLogRecord>[];
    await expectLater(
      Rendel.init(appKey: 'nc_pk_test_...', config: RendelConfig(onLog: logs.add)),
      throwsA(isA<AssertionError>()),
    );
    expect(logs.single.code, 'invalid_key');
    expect(logs.single.message, contains('placeholder'));
    expect(logs.single.message, contains('Settings → Keys & environments'));
    expect(Rendel.isInitialized, isFalse);
  });

  test('a key the server does not know is named as the reason, with where the real key is', () async {
    final logs = <RendelLogRecord>[];
    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(
        onLog: logs.add,
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'error': {'code': 'invalid_key'}}), 401),
        ),
      ),
    );
    await pumpEventQueue();
    final refused = logs.where((record) => record.code == 'invalid_key').toList();
    expect(refused, isNotEmpty);
    expect(refused.first.message, contains('Settings → Keys & environments'));
  });

  // Keys made since the rename start rd_pk_; the ones made before, nc_pk_.
  // Both are the app's key, and neither may be refused before it is sent.
  for (final key in [
    'rd_pk_test_example_000000000000000000000000',
    'nc_pk_test_example_000000000000000000000000',
  ]) {
    test('${key.substring(0, 6)} is a key, and goes out as X-Rendel-Key', () async {
      final logs = <RendelLogRecord>[];
      final sent = <String?>[];
      await Rendel.init(
        appKey: key,
        config: RendelConfig(
          onLog: logs.add,
          httpClient: MockClient((request) async {
            sent.add(request.headers['X-Rendel-Key']);
            return http.Response(jsonEncode({}), 200);
          }),
        ),
      );
      await pumpEventQueue();
      expect(Rendel.isInitialized, isTrue);
      expect(logs.where((record) => record.code == 'invalid_key'), isEmpty);
      expect(sent, isNotEmpty);
      expect(sent, everyElement(key));
    });
  }

  test('a key with neither prefix is refused at init', () async {
    final logs = <RendelLogRecord>[];
    await expectLater(
      Rendel.init(appKey: 'xx_pk_test_example_0000', config: RendelConfig(onLog: logs.add)),
      throwsA(isA<AssertionError>()),
    );
    expect(logs.single.code, 'invalid_key');
  });
}
