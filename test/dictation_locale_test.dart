// Tuna 2026-10-22: in a Turkish-only app (`languages: ['tr']`) the built-in
// microphone heard Russian as Turkish words. The recogniser listens in the
// phone's language now; `languages` only narrows what the copilot answers in
// when the words do not say.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';

void main() {
  // The phone's language. `TestPlatformDispatcher.localeTestValue` cannot
  // stand in: the SDK reads `PlatformDispatcher.instance`, the real one, as
  // locale_test.dart explains. Whatever this machine speaks, it is not Turkish.
  final phone = PlatformDispatcher.instance.locale;

  testWidgets("the phone's language, not the app's list", (tester) async {
    expect(phone.languageCode, isNot('tr'));
    final phoneId = phone.toLanguageTag().replaceAll('-', '_');
    addTearDown(Rendel.resetForTest);

    final listened = <Object?>[];
    const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'has_permission':
        case 'initialize':
          return true;
        case 'locales':
          return ['tr_TR:Türkçe', '$phoneId:Phone'];
        case 'listen':
          listened.add((call.arguments as Map)['localeId']);
          return true;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(
        languages: const ['tr'],
        httpClient: MockClient((_) async => http.Response('{"ok":true}', 200)),
        remoteConfig: false,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => Rendel.open(context), child: const Text('open'))),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump(const Duration(milliseconds: 100));

    expect(listened, [phoneId]);

    // The recogniser's own timers, run out so the test ends clean.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
