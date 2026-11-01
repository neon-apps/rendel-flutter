import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';

/// While the API cannot be reached, `Rendel.available` is false, and true
/// again once the API answers. The launcher stays on screen throughout
/// (Tuna, 2026-11-01: "kendini gizlememeli hiç").
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

  test('a server error turns available off, and an answer back on', () async {
    var status = 503;
    await start(() => status);
    await pumpEventQueue();
    expect(Rendel.available.value, isFalse);

    status = 200;
    await Rendel.refreshConfig();
    expect(Rendel.available.value, isTrue);
  });

  test('no network at all turns it off too, and the launcher stays enabled', () async {
    await start(() => -1);
    await pumpEventQueue();
    expect(Rendel.available.value, isFalse);
    expect(Rendel.isEnabled, isTrue);
  });

  test('a 304 after an outage turns it back on', () async {
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

  for (final (name, status, body) in [
    ('an outage', -1, envelope),
    ('a paused organization', 200, jsonEncode({'config': {}, 'available': false, 'unavailable_reason': 'credits'})),
  ]) {
    testWidgets('the launcher stays on screen through $name', (tester) async {
      await tester.runAsync(() => Rendel.init(
            appKey: key,
            config: RendelConfig(
              httpClient: MockClient((request) async {
                if (!request.url.path.endsWith('/v1/apps/config')) return http.Response('{}', 200);
                if (status < 0) throw http.ClientException('network down');
                return http.Response(body, status);
              }),
            ),
          ));
      await tester.runAsync(Rendel.refreshConfig);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(floatingActionButton: RendelLauncher())));
      await tester.pump();
      expect(Rendel.available.value, isFalse);
      expect(find.text(Rendel.config.launcherLabel), findsOneWidget);
    });
  }
}
