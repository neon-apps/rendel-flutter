// Security assessment 2026-11-20, decision 9 (Tuna: "Uyarıyla", the way
// ChatGPT asks before an unverified link): a link in an answer to a site that
// is not one of the app's own asks before it opens; the app's own open at once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/protocol/protocol.dart' show clientCapabilities;
import 'package:rendel/src/ui/leave_sheet.dart';

void main() {
  group('a link off the app\'s own sites', () {
    const own = ['grove.app', '*.help.grove.app'];

    test('is named by its site, without www', () {
      expect(leavesOwnSites('https://www.kotu-site.com/login?x=1', own), 'kotu-site.com');
      expect(leavesOwnSites('https://grove.app.kotu-site.com/a', own), 'grove.app.kotu-site.com');
    });

    test('is not one of the app\'s own, their www twin or a wildcard\'s subdomains', () {
      expect(leavesOwnSites('https://www.grove.app/returns', own), isNull);
      expect(leavesOwnSites('https://eu.help.grove.app/a', own), isNull);
      expect(leavesOwnSites('https://help.grove.app/a', own), isNull);
      expect(leavesOwnSites('mailto:help@grove.app', own), isNull);
    });

    test('is a check the thread tells the server it makes', () {
      expect(clientCapabilities, contains('leave_check'));
    });
  });

  group('the question', () {
    Future<bool?> ask(WidgetTester tester, String tap) async {
      bool? answer;
      await tester.pumpWidget(MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => answer = await askToLeave(context, 'kotu-site.com', strings: const RendelStrings()),
                child: const Text('tap the link'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('tap the link'));
      await tester.pumpAndSettle();
      expect(find.text('Open another site?'), findsOneWidget);
      expect(find.textContaining('kotu-site.com', findRichText: true), findsOneWidget);
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
      expect(find.text('Open another site?'), findsNothing);
      return answer;
    }

    testWidgets('opens the site only on Open site', (tester) async {
      expect(await ask(tester, 'Open site'), isTrue);
    });

    testWidgets('opens nothing on Go back', (tester) async {
      expect(await ask(tester, 'Go back'), isFalse);
    });
  });
}
