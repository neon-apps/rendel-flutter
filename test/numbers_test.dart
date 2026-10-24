import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/numbers.dart';

/// Numbers in the panel's language (QA 2026-10-24): a Turkish lede said "4,6"
/// and "1.720" while the cards under it said "4.6 (1,720)" and the chart
/// "17.8". One helper, `rendelNumber`, writes them all, as the web SDK's
/// `numberIn` does.
void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  Future<void> draw(WidgetTester tester, String type, Map<String, dynamic> props, String locale) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: RendelStringsScope(
            strings: RendelStrings.forLocale(locale),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) => ComponentRegistry.build(
                    context,
                    WireBlock(id: 'b', type: type, fallbackText: '', props: props)..ready = true,
                    dispatch,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  test('rendelNumber writes each shipped language its own way, with Latin digits', () {
    expect(rendelNumber(4.6, 'tr', digits: 1), '4,6');
    expect(rendelNumber(1720, 'tr', digits: 0), '1.720');
    expect(rendelNumber(17.8, 'tr-TR'), '17,8');
    expect(rendelNumber(1720.5, 'en'), '1,720.5');
    expect(rendelNumber(1720.5, 'de'), '1.720,5');
    expect(rendelNumber(1720, 'fr'), '1 720');
    expect(rendelNumber(1720, 'es'), '1720');
    expect(rendelNumber(12345.5, 'es'), '12.345,5');
    expect(rendelNumber(4.6, 'ar', digits: 1), '4.6');
    expect(rendelNumber(-1234567.25, 'en', digits: 2), '-1,234,567.25');
    expect(rendelNumber(53.40, 'tr', digits: 2), '53,40');
  });

  testWidgets('a Turkish product card says 4,6 and 1.720, and reads them in Turkish', (tester) async {
    await draw(tester, 'product_cards', {
      'items': [
        {'title': 'Crew Socks', 'price': '\$12', 'rating': 4.6, 'rating_count': 1720},
      ],
    }, 'tr');
    expect(find.text('4,6 (1.720)'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('1\\.720 değerlendirmeye göre 5 üzerinden 4,6')), findsWidgets);
  });

  testWidgets('a Turkish chart writes 17,8, and English stays as it was', (tester) async {
    await draw(tester, 'chart', {
      'kind': 'bar',
      'labels': ['Oca', 'Şub', 'Mar'],
      'series': [
        {'name': 'GB', 'data': [53.4, 35.6, 17.8]},
      ],
    }, 'tr');
    expect(find.textContaining('17,8'), findsWidgets);
    expect(find.textContaining('17.8'), findsNothing);

    await draw(tester, 'product_cards', {
      'items': [
        {'title': 'Crew Socks', 'price': '\$12', 'rating': 4.6, 'rating_count': 1720},
      ],
    }, 'en');
    expect(find.text('4.6 (1,720)'), findsOneWidget);
  });
}
