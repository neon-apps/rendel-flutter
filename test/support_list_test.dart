// The "With the team" list's search, Recent and rows, edge cases.
//
// The web panel lowers both sides with `toLocaleLowerCase(lang)`
// (sdk/web/src/ui/panel.ts), so a Turkish "İ" matches "i". These hold the
// Flutter list to the same.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/support.dart';
import 'package:rendel/src/ui/support_list.dart';

RendelSupportThread _thread(String id, String title, {bool resolved = false, DateTime? at, String? agent}) =>
    RendelSupportThread(
      threadId: id,
      resolved: resolved,
      title: title,
      agent: agent,
      lastMessageAt: at ?? DateTime.now(),
    );

void main() {
  Future<void> openList(WidgetTester tester, List<RendelSupportThread> threads) async {
    final theme = RendelTheme.paper();
    final strings = RendelStrings.forLocale('tr');
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: theme,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showRendelSupportList(
                    context,
                    threads: threads,
                    reload: () async => null,
                    team: 'Halden',
                    theme: theme,
                    strings: strings,
                    onOpen: (_) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a lowercase Turkish search finds a title that starts with İ', (tester) async {
    await openList(tester, [_thread('t1', 'İade talebim')]);
    await tester.enterText(find.byType(TextField), 'iade');
    await tester.pumpAndSettle();
    expect(find.text('İade talebim'), findsOneWidget);
  });

  testWidgets('a search typed with İ finds a lowercase title', (tester) async {
    await openList(tester, [_thread('t1', 'iade talebim')]);
    await tester.enterText(find.byType(TextField), 'İade');
    await tester.pumpAndSettle();
    expect(find.text('iade talebim'), findsOneWidget);
  });

  // Turkish casing: "I" lowers to "ı", not "i" (web: toLocaleLowerCase('tr')).
  testWidgets('a search typed with ı finds a title written with I', (tester) async {
    await openList(tester, [_thread('t1', 'KIRIK ÜRÜN GELDİ')]);
    await tester.enterText(find.byType(TextField), 'kırık');
    await tester.pumpAndSettle();
    expect(find.text('KIRIK ÜRÜN GELDİ'), findsOneWidget);
  });

  testWidgets('an ASCII search still finds an ASCII title', (tester) async {
    await openList(tester, [_thread('t1', 'Kargo nerede')]);
    await tester.enterText(find.byType(TextField), 'kargo');
    await tester.pumpAndSettle();
    expect(find.text('Kargo nerede'), findsOneWidget);
  });

  testWidgets('a very long title and an empty list draw without overflow', (tester) async {
    await openList(tester, [_thread('t1', 'Ş' * 2000, at: DateTime(2020))]);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('a thread with a missing or bad field is dropped, not thrown', () {
    expect(RendelSupportThread.tryParse({'thread_id': 't', 'title': 'x'}), isNull);
    expect(RendelSupportThread.tryParse({'thread_id': 't', 'title': 'x', 'last_message_at': 'nope'}), isNull);
    expect(RendelSupportThread.tryParse({'thread_id': 1, 'title': 'x', 'last_message_at': '2026-11-05T00:00:00Z'}), isNull);
    final ok = RendelSupportThread.tryParse({'thread_id': 't', 'title': 'x', 'last_message_at': '2026-11-05T00:00:00Z', 'unread': 2.0, 'last': {'text': 5}});
    expect(ok, isNotNull);
    expect(ok!.last, isNull);
  });
}
