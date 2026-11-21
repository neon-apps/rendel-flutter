// A page opened over the thread (the support page) is shown from where the
// thread was opened. After an answer opened a screen of the app, that page
// may be gone, and the team's page must still open (F1132).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/src/ui/presentation.dart';
import 'package:rendel/src/ui/theme.dart';

void main() {
  testWidgets('origin is still a mounted context once the page that opened the thread is replaced', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext opener;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Builder(builder: (context) {
        opener = context;
        return const Scaffold(body: Text('shop'));
      }),
    ));
    final presentation = RendelPresentation(
      context: opener,
      thread: () => const SizedBox(),
      openRoute: (_) async => true,
      theme: (_) => RendelTheme.paper(),
      label: 'Back to the assistant',
      bubbleOffset: 0,
    );
    expect(identical(presentation.origin, opener), isTrue);

    // An answer opened the app's order screen in place of the page Rendel was opened from.
    navigator.currentState!.pushReplacement(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('order'))));
    await tester.pumpAndSettle();
    expect(opener.mounted, isFalse);

    expect(presentation.origin.mounted, isTrue);
    // And a sheet shown from it lands on the app's navigator.
    showModalBottomSheet<void>(context: presentation.origin, builder: (_) => const Text('team'));
    await tester.pumpAndSettle();
    expect(find.text('team'), findsOneWidget);
    presentation.dispose();
  });
}
