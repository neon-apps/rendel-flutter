import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// The last English in the product, and where it sat.
///
/// A copilot inside a Turkish app answered in Turkish, because the model
/// follows the user, and then offered "Confirm" and "Go back" underneath the
/// answer — on the two controls a person presses to authorise something they
/// may not be able to undo. These are the words the SDK supplies itself, and
/// until now there was no way to change them short of forking.
void main() {
  const turkish = RendelStrings(
    confirm: 'Onayla',
    goBack: 'Vazgeç',
    irreversible: 'Bu geri alınamaz',
    statusThinking: 'Düşünüyor…',
    ratedHelpful: 'Bu cevap işe yaradı',
    ratedUnhelpful: 'Bu cevap işe yaramadı',
  );

  ConversationController controller() => ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  Future<void> pump(
    WidgetTester tester,
    ConversationController c, {
    RendelStrings strings = const RendelStrings(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: ThreadScreen(
              controller: c,
              strings: strings,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  RendelMessage confirmCard() {
    final message = RendelMessage.assistant();
    message.serverId = 'm_1';
    message.blocks.add(
      WireBlock(
        id: 'b1',
        type: 'confirm_card',
        fallbackText: 'Cancel order 1042?',
        props: const {
          'invocation_id': 'inv_1',
          'action_name': 'cancel_order',
          'summary': '1042 numaralı siparişi iptal edelim mi?',
          'risk': 'destructive',
          'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
          'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
        },
      )..ready = true,
    );
    return message;
  }

  testWidgets('the confirmation card takes the host words', (tester) async {
    final c = controller();
    c.messages.add(confirmCard());
    await pump(tester, c, strings: turkish);

    expect(find.text('Onayla'), findsOneWidget);
    expect(find.text('Vazgeç'), findsOneWidget);
    expect(find.text('Bu geri alınamaz'), findsOneWidget);
    // And the English is gone, rather than sitting next to it.
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Go back'), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('English is still the default, so nobody has to do anything',
      (tester) async {
    final c = controller();
    c.messages.add(confirmCard());
    await pump(tester, c);

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
    addTearDown(c.dispose);
  });

  /* The one screen where the SDK speaks first.
  
     The empty state's two sentences were literals in the widget, so a copilot
     that answered in Turkish still opened in English — on the screen a user
     meets before anything else. */
  /* The pill, which is said by a method on the State.

     `State.context` sits above whatever `build` returns, so a
     `RendelStringsScope` created in `build` is invisible to every method on
     the State: the lookup found nothing, fell back to the English defaults,
     and a Turkish copilot said "Thinking" under its Turkish empty state. */
  testWidgets('the pill speaks the language the rest of the screen does',
      (tester) async {
    final c = controller();
    c.messages.add(RendelMessage.user('merhaba'));
    c.busy = true;
    c.phase = RendelPhase.thinking;
    await pump(tester, c, strings: turkish);

    expect(find.bySemanticsLabel('Düşünüyor…'), findsOneWidget);
    expect(find.bySemanticsLabel('Thinking…'), findsNothing);
    addTearDown(c.dispose);
  });

  test('the empty state is translated like everything else', () {
    expect(RendelStrings.forLocale('tr').emptyTitle, contains('sorun'));
    expect(RendelStrings.forLocale('de').emptyTitle, contains('App'));
    // Anything with no table falls to English, as the rest of the strings do.
    expect(
      RendelStrings.forLocale('ja').emptyTitle,
      'Ask anything about this app.',
    );
  });

  test('every field has an English default', () {
    const defaults = RendelStrings();
    expect(defaults.confirm, 'Confirm');
    expect(defaults.goBack, 'Go back');
    expect(defaults.yes, 'Yes');
    expect(defaults.no, 'No');
  });
}
