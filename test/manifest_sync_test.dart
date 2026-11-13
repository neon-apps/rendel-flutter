// The manifest is sent one request at a time, and the last one sent is the
// newest. Registrations right after `init` used to race: each fired its own
// request with the routes registered so far, the server kept whichever
// arrived last, and a build could land with a screen missing (AI setup eval,
// 0.45.0).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';

void _register(String name) =>
    Rendel.registerRoute(name, title: name, description: 'The $name screen.', open: (_) {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Rendel.resetForTest);

  test('registrations after init end in one manifest with all of them, never two at once', () async {
    final sent = <List<String>>[];
    var inFlight = 0;
    var overlapped = false;
    await Rendel.init(
      appKey: 'nc_pk_test_race_0000000000000000000000000',
      config: RendelConfig(
        remoteConfig: false,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/v1/apps/manifest')) {
            inFlight++;
            if (inFlight > 1) overlapped = true;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final routes = ((body['manifest'] as Map)['routes'] as List?) ?? const [];
            sent.add([for (final r in routes) (r as Map)['name'] as String]);
            // Slow enough that the next registration lands mid-flight.
            await Future<void>.delayed(const Duration(milliseconds: 30));
            inFlight--;
          }
          return http.Response('{}', 200);
        }),
      ),
    );
    _register('home');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _register('orders');
    _register('help');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(overlapped, isFalse);
    expect(sent.last, unorderedEquals(['home', 'orders', 'help']));
  });

  // Night 13 November (PERF B): every launch posted the same manifest again.
  test('an unchanged manifest is not posted again on the next launch, a changed one is', () async {
    var posts = 0;
    Future<void> launch(String description) async {
      await Rendel.init(
        appKey: 'nc_pk_test_sent_0000000000000000000000000',
        config: RendelConfig(
          remoteConfig: false,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/v1/apps/manifest')) posts++;
            return http.Response('{}', 200);
          }),
        ),
      );
      Rendel.registerRoute('home', title: 'Home', description: description, open: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // The empty manifest at init, then the whole one.
    await launch('The home screen.');
    expect(posts, 2);
    Rendel.resetForTest(relaunch: true);
    await launch('The home screen.');
    expect(posts, 2);
    Rendel.resetForTest(relaunch: true);
    await launch('The home screen, with offers.');
    expect(posts, 3);
  });
}
