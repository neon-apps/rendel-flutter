// The night of 20 November's P2 sweep of the SDKs: what its people found,
// each held. The web SDK's `night-p2.test.ts` holds the web's side.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show RendelPage;
import 'package:rendel/src/ui/thread_screen.dart';

void main() {
  Future<void> open(WidgetTester tester, RendelStrings strings) async {
    final c = ConversationController(
      api: RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
        httpClient: MockClient((request) async => http.Response('{}', 200)),
      ),
      actions: const {},
      sdkVersion: 'flutter/test',
    );
    addTearDown(c.dispose);
    // An English phone.
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: ThreadScreen(
            controller: c,
            strings: strings,
            onPickAttachment: (_) async => null,
            onDictate: (_) async => null,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a first line past 200 characters is no lede and no centred summary (F1809, F0729, F1688)', (tester) async {
    final dispatch = RendelDispatcher(
      onAction: (_) async => true,
      onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
      canHandle: (_) => true,
    );
    Future<TextStyle?> styleOf(String words, {bool detail = false}) async {
      final block = WireBlock(id: 'b-${words.length}-$detail', type: 'text', fallbackText: words, props: {'markdown': words})..ready = true;
      await tester.pumpWidget(MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: RendelPage(
                flat: true,
                inset: 16,
                lede: true,
                detail: detail,
                child: Builder(builder: (c) => ComponentRegistry.build(c, block, dispatch)),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      return tester.widget<RichText>(find.byType(RichText).first).text.style;
    }

    expect((await styleOf('The return is open.'))?.fontSize, 21);
    final wall = 'Sipariş detayını kontrol ettim ve iki kavanozun iade edildiğini görüyorum. ' * 3;
    expect((await styleOf(wall))?.fontSize, 15);
    // On a card's detail, the long summary is read from the start, not centred.
    final summary = await styleOf(wall, detail: true);
    expect(summary?.fontSize, 15);
    expect(tester.widget<RichText>(find.byType(RichText).first).textAlign, isNot(TextAlign.center));
  });

  testWidgets("the opening's day is in the words' language, not the phone's (F1334)", (tester) async {
    final now = DateTime.now();
    final turkish = RendelStrings.forLocale('tr');
    await open(tester, turkish);
    expect(find.text(turkish.dayHeadingFor(now)), findsOneWidget);
    expect(find.text(const DefaultMaterialLocalizations().formatMediumDate(now)), findsNothing);

    // English words keep the phone's own date, as before.
    await open(tester, const RendelStrings());
    expect(find.text(const DefaultMaterialLocalizations().formatMediumDate(now)), findsOneWidget);
  });
}
