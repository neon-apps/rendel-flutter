import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// The SDK's last English.
///
/// The confirm buttons left first, then the empty state, then the composer's
/// prompt, then the error bar. What remained was everything the renderer said
/// on its own: "Required" beside a form field, "Sending…" under the answers,
/// "Total" on a receipt, "Expired" on a card, "Test mode" in the header, and
/// every name a screen reader gives a control. These pin the catalog to the
/// screen, in Turkish, so the next literal cannot slip back in unnoticed.
void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );
  final tr = RendelStrings.forLocale('tr');

  Future<void> pumpBlock(
    WidgetTester tester,
    String type,
    Map<String, dynamic> props,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: RendelStringsScope(
            strings: tr,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) => ComponentRegistry.build(
                    context,
                    WireBlock(
                      id: 'b_$type',
                      type: type,
                      fallbackText: 'A $type block.',
                      props: props,
                    )..ready = true,
                    dispatch,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a form flags and submits in the host\'s language',
      (tester) async {
    await pumpBlock(tester, 'form', {
      'form_id': 'clinic',
      'title': '24 Saat Açık Pet Kliniği Ara',
      'fields': [
        {'kind': 'text', 'name': 'city', 'label': 'Şehir', 'required': true},
        {'kind': 'text', 'name': 'note', 'label': 'Not'},
      ],
    });
    // Blocks v6 ("F3") flags the field that may stay empty, not the ones
    // that must be filled, so the word to find is "Optional" in Turkish.
    expect(find.text('İsteğe bağlı'), findsOneWidget);
    expect(find.text('Gönder'), findsOneWidget);
    expect(find.text('Optional'), findsNothing);
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('a receipt sums in the host\'s language', (tester) async {
    await pumpBlock(tester, 'receipt', {
      'title': 'Sipariş',
      'lines': [
        {'label': 'Mama', 'amount': '₺100'},
      ],
      'subtotal': '₺100',
      'tax': '₺18',
      'total': '₺118',
    });
    expect(find.text('Ara toplam'), findsOneWidget);
    expect(find.text('Vergi'), findsOneWidget);
    expect(find.text('Toplam'), findsOneWidget);
    expect(find.text('Total'), findsNothing);
  });

  testWidgets('the header badge and the spoken labels follow too',
      (tester) async {
    final c = ConversationController(
      api: RendelApiClient(
        appKey: 'nc_pk_test_x',
        deviceId: 'd',
        config: const RendelConfig(),
      ),
      actions: const {},
      sdkVersion: 'flutter/test',
      // A test key: the header wears the badge.
      sandbox: true,
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: ThreadScreen(
              controller: c,
              strings: tr,
              onDictate: (_) async => null,
              onPickAttachment: (_) async => null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Test modu'), findsOneWidget);
    expect(find.text('Test mode'), findsNothing);
    expect(find.bySemanticsLabel('Copilotu kapat'), findsOneWidget);
    expect(find.bySemanticsLabel('Dosya ekle'), findsOneWidget);
    expect(find.bySemanticsLabel('Yazmak yerine konuşun'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Mesaj yaz'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Mesajı gönder'), findsOneWidget);
    expect(find.bySemanticsLabel('Fotoğraflar'), findsOneWidget);
    expect(find.bySemanticsLabel('Kamera'), findsOneWidget);
    expect(find.bySemanticsLabel('Dosyalar'), findsOneWidget);
  });

  test('the day heading is ordered the way the language orders it', () {
    final thursday = DateTime(2026, 9, 24, 10);
    expect(const RendelStrings().dayHeadingFor(thursday), 'Thu 24 Sep');
    expect(tr.dayHeadingFor(thursday), '24 Eyl Per');
  });
}
