import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// A note the app's team left for this person (0345, `GET /v1/standing`),
/// asked as the assistant opens: a block rests the composer under the team's
/// words before anyone types; a warning is shown over the composer until it
/// is closed, and the assistant answers under it as usual.
void main() {
  final requests = <http.Request>[];
  RendelApiClient api(http.Response Function(http.Request) answer) => RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
        httpClient: MockClient((request) async {
          requests.add(request);
          return answer(request);
        }),
      );

  ConversationController controller() => ConversationController(
        api: api((_) => http.Response('{}', 200)),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  Future<void> show(WidgetTester tester, ConversationController c) async {
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(theme: RendelTheme.paper(), child: Scaffold(body: ThreadScreen(controller: c))),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  test('reads a standing, and 204 or a failure as nothing, asking as the signed-in person', () async {
    requests.clear();
    final answers = [
      http.Response.bytes(utf8.encode('{"standing":{"kind":"blocked","message":"Kapalı.","hint":"Kullanılamıyor","until":null}}'), 200,
          headers: {'content-type': 'application/json'}),
      http.Response('', 204),
    ];
    final client = api((_) => answers.isEmpty ? throw Exception('offline') : answers.removeAt(0));
    final blocked = await client.standing(user: {'id': 'u-1', 'hmac': 'abc'}, locale: 'tr-TR');
    expect(blocked?.kind, 'blocked');
    expect(blocked?.message, 'Kapalı.');
    expect(requests.single.url.path, '/v1/standing');
    expect(requests.single.url.queryParameters['locale'], 'tr-TR');
    expect(requests.single.headers['X-Rendel-User'], 'u-1');
    expect(requests.single.headers['X-Rendel-User-Hmac'], 'abc');
    expect(await client.standing(locale: 'tr'), isNull);
    expect(await client.standing(locale: 'tr'), isNull);
  });

  testWidgets('a block rests the composer under the team words, and lifts on the next open', (tester) async {
    final c = controller();
    c.applyStanding(const RendelStanding(kind: 'blocked', message: 'Asistan hesabın için kapatıldı.', hint: 'Kullanılamıyor'));
    expect(c.resting, isTrue);
    expect(await c.send('Swift kodumu düzelt'), isFalse);
    await show(tester, c);
    expect(find.text('Asistan hesabın için kapatıldı.'), findsOneWidget);
    expect(find.text('Kullanılamıyor'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Close this note'), findsNothing);
    c.applyStanding(null);
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.resting, isFalse);
    expect(find.text('Asistan hesabın için kapatıldı.'), findsNothing);
  });

  testWidgets('a warning shows over a working composer until it is closed', (tester) async {
    final c = controller();
    c.applyStanding(const RendelStanding(kind: 'warning', message: 'Lütfen asistanı alışveriş için kullan.'));
    expect(c.resting, isFalse);
    await show(tester, c);
    expect(find.text('Lütfen asistanı alışveriş için kullan.'), findsOneWidget);
    // Told once: an open that finds nothing keeps it until it is closed.
    c.applyStanding(null);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Lütfen asistanı alışveriş için kullan.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close this note'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Lütfen asistanı alışveriş için kullan.'), findsNothing);
    expect(c.standing, isNull);
  });
}
