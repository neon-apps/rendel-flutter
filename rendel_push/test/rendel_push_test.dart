import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel_push/rendel_push.dart';

const _id = '0b8d3c1e-5f6a-4b7c-8d9e-0f1a2b3c4d5e';

/// What reaches the API: push tokens and opened follow-ups.
class _Server {
  final tokens = <Object?>[];
  final bodies = <Map<String, dynamic>>[];
  final opened = <String>[];

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/v1/push/token')) {
      final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
      tokens.add(body['token']);
      bodies.add(body);
      return http.Response('', 204);
    }
    if (path.endsWith('/open')) {
      opened.add(path.split('/')[3]);
      return http.Response(jsonEncode({'conversation_id': 'c'}), 200, headers: {'content-type': 'application/json'});
    }
    if (path.endsWith('/v1/followups/next')) return http.Response('', 204);
    return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
  });
}

void main() {
  tearDown(() async {
    await RendelPush.stop();
    Rendel.resetForTest();
  });

  Future<(_Server, GlobalKey<NavigatorState>)> start(WidgetTester tester) async {
    final server = _Server();
    final navigator = GlobalKey<NavigatorState>();
    await tester.runAsync(() => Rendel.init(
          appKey: 'nc_pk_test_example_000000000000000000000000',
          config: RendelConfig(remoteConfig: false, httpClient: server.client),
        ));
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const SizedBox()));
    return (server, navigator);
  }

  /// The push token is sent from a phone; the override is undone before the test ends, as the binding asks.
  Future<void> onAndroid(WidgetTester tester, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.runAsync(body);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  BuildContext? inside(GlobalKey<NavigatorState> navigator) => RendelPush.insideNavigator(navigator);

  testWidgets('hands the token and every refresh to Rendel', (tester) async {
    final (server, navigator) = await start(tester);
    final refreshes = StreamController<RendelPushToken>();
    await onAndroid(tester, () async {
      await RendelPush.wire(
        allowed: () async => true,
        token: () async => const RendelPushToken('token-1', androidPackage: 'co.neonapps.grove'),
        refreshes: refreshes.stream,
        taps: const Stream.empty(),
        launchTap: () async => null,
        context: () => inside(navigator),
      );
      refreshes.add(const RendelPushToken('token-2'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(server.tokens, ['token-1', 'token-2']);
    // A Firebase token is the default kind, and says which Android app it belongs to.
    expect(server.bodies.first.containsKey('provider'), isFalse);
    expect(server.bodies.first, containsPair('topic', 'co.neonapps.grove'));
  });

  testWidgets("says an iOS token is Apple's, with its build's environment, bundle id and team", (tester) async {
    final (server, navigator) = await start(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.runAsync(() => RendelPush.wire(
            allowed: () async => true,
            token: () async => const RendelPushToken(
              'ab12',
              apns: RendelApnsToken(environment: 'sandbox', bundleId: 'co.neonapps.grove', teamId: 'UH5437SQWZ'),
            ),
            refreshes: const Stream.empty(),
            taps: const Stream.empty(),
            launchTap: () async => null,
            context: () => inside(navigator),
          ));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    expect(server.bodies.single, containsPair('provider', 'apns'));
    expect(server.bodies.single, containsPair('environment', 'sandbox'));
    expect(server.bodies.single, containsPair('topic', 'co.neonapps.grove'));
    expect(server.bodies.single, containsPair('team_id', 'UH5437SQWZ'));
  });

  testWidgets('sends no token when notifications are off, and says so', (tester) async {
    final (server, navigator) = await start(tester);
    await onAndroid(tester, () => RendelPush.wire(
          allowed: () async => false,
          token: () async => fail('no token is asked for without permission'),
          refreshes: const Stream.empty(),
          taps: const Stream.empty(),
          launchTap: () async => null,
          context: () => inside(navigator),
        ));
    expect(server.tokens, [null]);
  });

  testWidgets("opens Rendel's pushes, the launching one included, and leaves the app's", (tester) async {
    final (server, navigator) = await start(tester);
    final taps = StreamController<Map<String, dynamic>>();
    await onAndroid(tester, () async {
      await RendelPush.wire(
        allowed: () async => true,
        token: () async => null,
        refreshes: const Stream.empty(),
        taps: taps.stream,
        launchTap: () async => {'rendel': '1', 'rendel_followup': _id},
        context: () => inside(navigator),
      );
      taps.add({'type': 'chat'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(server.opened, [_id]);
    navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
  });
}
