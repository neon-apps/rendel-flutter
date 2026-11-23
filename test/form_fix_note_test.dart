// A Turkish form in an app that loaded no Turkish Material words: the hotel
// search from 2026-11-23. Send looked like it did nothing, the note over it
// was English, and its dates read "Dec 15".
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

void main() {
  final year = DateTime.now().year;

  Map<String, dynamic> hotelSearch() => {
        'id': 'b_hotels',
        'type': 'form',
        'fallback_text': 'Otel arama formu.',
        'props': {
          'form_id': 'hotels',
          'title': 'İspanya otel arama',
          'submit_label': 'Otelleri ara',
          'fields': [
            {'kind': 'text', 'name': 'city', 'label': 'Şehir', 'placeholder': 'Madrid, Barselona...', 'required': true},
            {'kind': 'date_range', 'name': 'dates', 'label': 'Tarihler', 'value': ['$year-12-15', '$year-12-19']},
            {'kind': 'number', 'name': 'guests', 'label': 'Kişi sayısı', 'stepper': true, 'min': 1, 'value': 2},
          ],
        },
      };

  final submitted = <Map<String, Object>>[];
  setUp(submitted.clear);

  Future<void> pump(WidgetTester tester, RendelStrings strings) async {
    final block = WireBlock.tryParse(jsonDecode(jsonEncode(hotelSearch())) as Map<String, dynamic>)!;
    final dispatch = RendelDispatcher(
      onAction: (_) async => true,
      canHandle: (_) => true,
      onSubmitForm: (formId, values) async {
        submitted.add(values);
        return RendelSubmitOutcome.sent;
      },
    );
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // An English-only MaterialApp, as most host apps are.
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: RendelStringsScope(
            strings: strings,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> send(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool cityHasFocus(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText).first).focusNode.hasFocus;

  testWidgets('Send on an empty required field says so in Turkish and takes the reader to it', (tester) async {
    await pump(tester, RendelStrings.forLocale('tr'));
    expect(cityHasFocus(tester), isFalse);

    await send(tester, 'Otelleri ara');

    expect(submitted, isEmpty);
    expect(find.text('Yukarıda düzeltilmesi gereken 1 alan var.'), findsOneWidget);
    expect(find.text('Devam etmek için bunu doldurun.'), findsOneWidget);
    expect(find.textContaining('needs fixing'), findsNothing);
    expect(cityHasFocus(tester), isTrue);

    await tester.enterText(find.byType(EditableText).first, 'Madrid');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Yukarıda düzeltilmesi gereken 1 alan var.'), findsNothing);
    await send(tester, 'Otelleri ara');
    expect(submitted.single, {'city': 'Madrid', 'dates_start': '$year-12-15', 'dates_end': '$year-12-19', 'guests': 2});
  });

  testWidgets('a Turkish form in an English app says its days in Turkish', (tester) async {
    await pump(tester, RendelStrings.forLocale('tr'));

    expect(find.text('15 Ara'), findsOneWidget);
    expect(find.text('19 Ara'), findsOneWidget);
    expect(find.text('Dec 15'), findsNothing);
  });

  testWidgets('an English form in an English app keeps the host\'s Material words', (tester) async {
    await pump(tester, const RendelStrings());

    expect(find.text('Dec 15'), findsOneWidget);
    await send(tester, 'Otelleri ara');
    expect(find.text('1 field above needs fixing.'), findsOneWidget);
  });
}
