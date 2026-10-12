import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';

/// While the API cannot be reached, the launcher is hidden.
///
/// A failed config request used to leave `Rendel.available` true, so during
/// an outage the host app kept a button whose every press failed
/// (design/plans/resilience.md §1.2). It hides now, and comes back once the
/// API answers again.
void main() {
  // Hiding the launcher listens for the app's return to the foreground.
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Rendel.resetForTest);

  const key = 'rd_pk_test_example_000000000000000000000000';
  final envelope = jsonEncode({'channel': 'published', 'version': null, 'updated_at': null, 'config': {}});

  Future<void> start(int Function() status) => Rendel.init(
        appKey: key,
        config: RendelConfig(
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/v1/apps/config')) {
              final code = status();
              if (code < 0) throw http.ClientException('network down');
              return http.Response(code == 200 ? envelope : '{}', code);
            }
            return http.Response('{}', 200);
          }),
        ),
      );

  test('a server error hides the launcher, and an answer brings it back', () async {
    var status = 503;
    await start(() => status);
    await pumpEventQueue();
    expect(Rendel.available.value, isFalse);

    status = 200;
    await Rendel.refreshConfig();
    expect(Rendel.available.value, isTrue);
  });

  test('no network at all hides it too', () async {
    await start(() => -1);
    await pumpEventQueue();
    expect(Rendel.available.value, isFalse);
  });

  test('a 304 after an outage brings it back', () async {
    var status = 503;
    await start(() => status);
    await pumpEventQueue();
    expect(Rendel.available.value, isFalse);
    status = 304;
    await Rendel.refreshConfig();
    expect(Rendel.available.value, isTrue);
  });

  test('a refusal that is not an outage leaves it as it was', () async {
    await start(() => 401);
    await pumpEventQueue();
    expect(Rendel.available.value, isTrue);
  });
}
