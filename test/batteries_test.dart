import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/batteries.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The controls a host gets without writing them.
///
/// Until 0.12 a bare `RendelConfig` drew a composer with no paperclip and no
/// microphone, and the first real integration copied 150 lines to get them.
/// Now the two are the SDK's own; these pin that they are wired by default,
/// and that where the plugins are absent — here — they fail the way the
/// thread expects rather than hanging a lit control.
void main() {
  tearDown(Rendel.resetForTest);

  testWidgets('a bare config draws both controls', (tester) async {
    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(
        remoteConfig: false,
        httpClient: MockClient((_) async => http.Response(jsonEncode({'ok': true}), 200)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Rendel.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Attach a file'), findsOneWidget);
    expect(find.bySemanticsLabel('Speak instead of typing'), findsOneWidget);
  });

  test('the built-in recogniser reports a missing platform, not silence',
      () async {
    // No plugin behind the channel in a test. That is a failed recogniser,
    // which the thread words as unavailable and logs — never null, which it
    // would word as "nothing was heard".
    await expectLater(
      RendelSpeech(locale: 'tr-TR').dictate((_) {}),
      throwsA(isA<StateError>()),
    );
  });

  test('a press let go while the recogniser starts never opens the microphone', () async {
    // Tuna 2026-10-28, Grove: let go at once and the session opened anyway,
    // held the microphone and the thread for its 30-second pause, and the
    // microphone would not press again until then.
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final starting = Completer<bool>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'initialize' => starting.future,
        'has_permission' => true,
        'locales' => <dynamic>[],
        _ => true,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final speech = RendelSpeech();
    final heard = speech.dictate((_) {});
    speech.stop(); // let go before the recogniser is up
    starting.complete(true);

    expect(await heard.timeout(const Duration(seconds: 1)), isNull);
    expect(calls, isNot(contains('listen')));
  });

  test('the built-in picker reports a missing platform, not a cancel',
      () async {
    await expectLater(pickImage(), throwsA(isA<StateError>()));
  });

  test('the preferences store keeps what it is given', () async {
    SharedPreferences.setMockInitialValues({});
    const store = RendelPreferencesStore('nc_test_key');
    expect(await store.read(), isNull);
    await store.write('abc');
    expect(await store.read(), 'abc');
  });

  test('the device id survives a relaunch through the preferences store', () async {
    // The bug this fixes: every cold start was a new device, and the console
    // showed one "Not signed in" row per launch of the same phone. Under
    // `flutter test` the SDK defaults to memory, so the store is passed here
    // with the plugin mocked — the same store a device gets.
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((_) async => http.Response(jsonEncode({'ok': true}), 200));
    RendelConfig config() => RendelConfig(
          remoteConfig: false,
          httpClient: client,
          deviceIdStore: const RendelPreferencesStore('nc_device_id'),
        );
    await Rendel.init(appKey: 'nc_pk_test_example_000000000000000000000000', config: config());
    final first = Rendel.deviceId;
    Rendel.resetForTest();
    await Rendel.init(appKey: 'nc_pk_test_example_000000000000000000000000', config: config());
    expect(first, isNotNull);
    expect(Rendel.deviceId, first);
  });
}
