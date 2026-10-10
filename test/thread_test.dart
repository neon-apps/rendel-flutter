import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

/// The copilot's shell, which the catalog's own gallery never exercises.
///
/// The gallery calls `ComponentRegistry.build` directly, so a defect that only
/// bites through `ThreadScreen` — an inherited-widget lookup in the wrong
/// lifecycle callback, say — renders every gallery fixture perfectly and every
/// real answer as an error widget. That is exactly what happened once.
void main() {
  ConversationController controller() => ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  Future<void> pumpThread(WidgetTester tester, ConversationController c) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(body: ThreadScreen(controller: c)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders every block type on a real page, not an error widget',
      (tester) async {
    final c = controller();
    final message = RendelMessage.assistant();
    for (final type in ComponentRegistry.registeredTypes) {
      message.blocks.add(
        WireBlock(
          id: 'b_$type',
          type: type,
          fallbackText: 'A $type block.',
          props: const {},
        )..ready = true,
      );
    }
    c.messages.add(message);

    await pumpThread(tester, c);
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('a skeleton hydrates without throwing', (tester) async {
    final c = controller();
    final message = RendelMessage.assistant();
    final block = WireBlock(
      id: 'b1',
      type: 'receipt',
      fallbackText: 'A receipt.',
      props: const {},
    );
    message.blocks.add(block);
    c.messages.add(message);

    await pumpThread(tester, c);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ErrorWidget), findsNothing);

    block.ready = true;
    message.touch();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('a streamed token rebuilds its own turn and no other',
      (tester) async {
    final c = controller();
    final finished = RendelMessage.assistant()
      ..blocks.add(
        WireBlock(
          id: 'old',
          type: 'text',
          fallbackText: 'Done.',
          props: const {'markdown': 'Done.'},
        )..ready = true,
      );
    final live = RendelMessage.assistant()
      ..blocks.add(
        WireBlock(id: 'live', type: 'text', fallbackText: '', props: const {}),
      );
    c.messages..add(finished)..add(live);

    await pumpThread(tester, c);

    // Count how often each turn's subtree is built.
    var finishedBuilds = 0;
    var liveBuilds = 0;
    finished.addListener(() => finishedBuilds++);
    live.addListener(() => liveBuilds++);

    for (var i = 0; i < 5; i++) {
      live.blocks.first.streamingText += 'word ';
      live.touch();
      await tester.pump();
    }

    expect(liveBuilds, 5, reason: 'the streaming turn hears every token');
    expect(
      finishedBuilds,
      0,
      reason: 'a finished turn must not rebuild while a later one streams',
    );
    addTearDown(c.dispose);
  });

  testWidgets('the whole shell survives reduced motion', (tester) async {
    final c = controller();
    final message = RendelMessage.assistant();
    for (final type in ['text', 'receipt', 'quick_replies', 'form']) {
      message.blocks.add(
        WireBlock(
          id: 'r_$type',
          type: type,
          fallbackText: 'A $type block.',
          props: const {},
        )..ready = true,
      );
    }
    c.messages.add(message);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          // The setting that made three dispose paths evaluate a `late final`
          // for the first time, from inside dispose.
          data: const MediaQueryData(disableAnimations: true),
          child: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(body: ThreadScreen(controller: c)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ErrorWidget), findsNothing);

    // Tear the tree down: the dispose paths run here.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
    addTearDown(c.dispose);
  });

  testWidgets('every swap in the catalog survives reduced motion',
      (tester) async {
    // The suite already had a reduced-motion test. It pumped once and tore the
    // tree down, so no `stateKey` ever changed and no `RendelSwap` ever swapped —
    // it could not reach the one thing reduced motion broke, and did not, for
    // eight review rounds.
    //
    // `AnimatedSize` with `Duration.zero` completes its controller inside
    // `performLayout` and the listener re-dirties the object being laid out.
    // Every confirm-card resolution and every skeleton hydration threw, twice.
    final c = controller();
    final message = RendelMessage.assistant();
    final card = WireBlock(
      id: 'r_confirm',
      type: 'confirm_card',
      fallbackText: 'Confirm this?',
      props: {
        'summary': 'Cancel order 1042?',
        'risk': 'destructive',
        'params': const {'order_id': '1042'},
        'params_display': const <Map<String, dynamic>>[],
        'confirm': const {'kind': 'confirm', 'invocation_id': 'inv_1'},
        'cancel': const {'kind': 'cancel', 'invocation_id': 'inv_1'},
      },
    )..ready = true;
    final hydrating = WireBlock(
      id: 'r_receipt',
      type: 'receipt',
      fallbackText: 'A receipt.',
      props: {},
    );
    message.blocks.addAll([card, hydrating]);
    c.messages.add(message);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(body: ThreadScreen(controller: c)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'the first paint');

    // Now actually swap both: a card resolving and a skeleton hydrating.
    for (final resolution in ['confirmed', 'declined', 'abandoned']) {
      card.props[RendelLocalKeys.resolved] = resolution;
      message.touch();
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'the card swapping to $resolution',
      );
    }

    hydrating.props['title'] = 'Order 1042';
    hydrating.props['lines'] = [
      {'label': 'Aero Glide 2', 'amount': '£129.00'},
    ];
    hydrating.props['total'] = '£129.00';
    hydrating.ready = true;
    message.touch();
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'the skeleton hydrating');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
    addTearDown(c.dispose);
  });

  /// The composer's three glyphs.
  ///
  /// Easy to get wrong quietly: nothing visible changes when a control is
  /// drawn with the wrong icon, or drawn at all for an app that will never
  /// accept a photograph. So the test asks the pixels.
  ///
  /// All three now do something — the "+" opens Photos, Camera and Files,
  /// the microphone records — but which glyph and whether it appears is still
  /// the customer's choice, and `off` still has to remove it.
  group('the composer glyphs', () {
    Future<void> pump(
      WidgetTester tester, {
      RendelAttachIcon attach = RendelAttachIcon.plus,
      RendelVoiceIcon voice = RendelVoiceIcon.microphone,
      RendelSendIcon send = RendelSendIcon.arrowUp,
      bool wired = true,
    }) async {
      final c = controller();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                attachIcon: attach,
                voiceIcon: voice,
                sendIcon: send,
                // A host that wired both. The icon a customer chose is only a
                // question once there is something behind it.
                onPickAttachment: wired ? (_) async => null : null,
                onDictate: wired ? (_) async => null : null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('draws the defaults', (tester) async {
      await pump(tester);
      // At rest: the "+", the microphone and the keyboard.
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);

      // The keyboard opens the box: the three sources and send.
      await tester.tap(find.bySemanticsLabel('Type a message'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.bySemanticsLabel('Photos'), findsOneWidget);
      expect(find.bySemanticsLabel('Camera'), findsOneWidget);
      expect(find.bySemanticsLabel('Files'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('the "+" opens Photos, Camera and Files', (tester) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Attach a file'));
      await tester.pumpAndSettle();
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);

      // And closes at a tap anywhere else.
      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();
      expect(find.text('Photos'), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('an empty box settles back to rest', (tester) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Type a message'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
    });

    testWidgets('a box with words in it stays open', (tester) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Type a message'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'merhaba');
      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();
      expect(find.text('merhaba'), findsOneWidget);
    });

    testWidgets('draws the glyphs the customer chose', (tester) async {
      await pump(
        tester,
        attach: RendelAttachIcon.paperclip,
        voice: RendelVoiceIcon.waveform,
        send: RendelSendIcon.paperPlane,
      );
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      await tester.tap(find.bySemanticsLabel('Type a message'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('removes the ones an app says it will never have',
        (tester) async {
      await pump(tester, attach: RendelAttachIcon.off, voice: RendelVoiceIcon.off);
      // No microphone leaves nothing for the middle: the box is all there is.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.bySemanticsLabel('Photos'), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      // Send survives: it is the one thing the composer is for.
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('and the ones nothing is wired to', (tester) async {
      // A control that opens nothing is the thing this whole arrangement
      // exists to avoid.
      await pump(tester, wired: false);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.bySemanticsLabel('Photos'), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets("a host's own picker is the one tool, behind the \"+\"",
        (tester) async {
      final c = controller();
      addTearDown(c.dispose);
      final asked = <RendelAttachSource>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                onPickAttachment: (source) async {
                  asked.add(source);
                  return null;
                },
                attachSources: const [RendelAttachSource.files],
                onDictate: (_) async => null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Attach a file'));
      await tester.pumpAndSettle();
      // No menu: the "+" opened the picker.
      expect(find.text('Photos'), findsNothing);
      expect(asked, [RendelAttachSource.files]);
    });
  });

  /// The microphone, once it is listening.
  ///
  /// A control that is recording has to be stoppable and has to look live —
  /// the version before this dimmed it and refused the press, which told the
  /// user to wait while the recogniser waited for them.
  group('the microphone mid-session', () {
    Future<void> listen(
      WidgetTester tester, {
      required bool stoppable,
      required List<String> stops,
    }) async {
      final c = controller();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                // Never completes: the session stays open so the listening
                // state can be looked at.
                onDictate: (_) => Completer<String?>().future,
                onStopDictating: stoppable ? () => stops.add('stopped') : null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Speak instead of typing'));
      await tester.pump();
    }

    testWidgets('turns into a stop control when the host can stop it',
        (tester) async {
      final stops = <String>[];
      await listen(tester, stoppable: true, stops: stops);

      expect(find.bySemanticsLabel('Stop listening'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Stop listening'));
      await tester.pump();
      expect(stops, ['stopped']);
    });

    testWidgets('writes what it hears as it hears it', (tester) async {
      final c = controller();
      addTearDown(c.dispose);
      late void Function(String) say;
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                onDictate: (onPartial) {
                  say = onPartial;
                  return Completer<String?>().future;
                },
                onStopDictating: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Voice mode opens over the page, waiting for the first word.
      await tester.tap(find.bySemanticsLabel('Speak instead of typing'));
      await tester.pump();
      expect(find.text('Listening…'), findsOneWidget);

      say('merhaba');
      await tester.pump();
      expect(find.text('merhaba'), findsOneWidget);

      say('merhaba nasılsın');
      await tester.pump();
      expect(find.text('merhaba nasılsın'), findsOneWidget);
      expect(find.text('merhaba'), findsNothing);
    });

    Future<Completer<String?>> speak(
      WidgetTester tester,
      ConversationController c,
      void Function(void Function(String)) onSay,
    ) async {
      final done = Completer<String?>();
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                onDictate: (onPartial) {
                  onSay(onPartial);
                  return done.future;
                },
                onStopDictating: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Speak instead of typing'));
      await tester.pump();
      return done;
    }

    // Said with the pill in the microphone's place.
    testWidgets('sends what was heard on its own, and says what it is doing',
        (tester) async {
      // A request that never answers: the turn stays at "thinking".
      final c = ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          httpClient: MockClient((_) => Completer<http.Response>().future),
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );
      addTearDown(c.dispose);
      late void Function(String) say;
      final done = await speak(tester, c, (onPartial) => say = onPartial);

      say('merhaba');
      await tester.pump();
      done.complete('merhaba');
      await tester.pump();

      // No box to read it back from: it went, and the pill says why it waits.
      expect(c.messages.where((m) => m.role == 'user'), hasLength(1));
      expect(find.bySemanticsLabel('Thinking…'), findsOneWidget);

      // Past the copilot's own time limit, which ends the turn it is holding.
      await tester.pump(const Duration(minutes: 2));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('clears when the turn ends', (tester) async {
      // Refused at once, which ends the turn the moment it starts.
      final c = controller();
      addTearDown(c.dispose);
      late void Function(String) say;
      final done = await speak(tester, c, (onPartial) => say = onPartial);

      say('merhaba');
      done.complete('merhaba');
      await tester.pump();
      expect(find.bySemanticsLabel('Thinking…'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel('Thinking…'), findsNothing);
      expect(find.bySemanticsLabel('Speak instead of typing'), findsOneWidget);
    });

    testWidgets('a tap away lets the question go unsent', (tester) async {
      final c = controller();
      addTearDown(c.dispose);
      late void Function(String) say;
      final done = await speak(tester, c, (onPartial) => say = onPartial);

      say('merhaba');
      await tester.pump();
      await tester.tapAt(const Offset(200, 150));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('merhaba'), findsNothing);

      // The recogniser finishing afterwards does not send it either.
      done.complete('merhaba');
      await tester.pump();
      expect(c.messages, isEmpty);
    });

    testWidgets("says the recogniser failed, in the host's language",
        (tester) async {
      // The other way a dictation ends with nothing. Null is silence and the
      // SDK says so; a throw is a recogniser that failed, and blaming the
      // microphone for that sent people to check one that was fine.
      final c = controller();
      addTearDown(c.dispose);
      final logged = <RendelLogRecord>[];
      RendelLog.sink = logged.add;
      addTearDown(() => RendelLog.sink = null);
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                strings: RendelStrings.forLocale('tr'),
                onDictate: (_) async => throw StateError('error_unknown (300)'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // The control is named in the host's language too.
      await tester.tap(find.bySemanticsLabel('Yazmak yerine konuşun'));
      await tester.pump();

      expect(find.text('Konuşma tanıma şu anda kullanılamıyor.'), findsOneWidget);
      expect(find.text('That could not be heard. Try again.'), findsNothing);
      expect(logged.single.code, 'dictation_failed');
      expect('${logged.single.error}', contains('error_unknown (300)'));
    });

    testWidgets('stays un-pressable when there is nothing to stop it with',
        (tester) async {
      final stops = <String>[];
      await listen(tester, stoppable: false, stops: stops);

      // Still named for what it is doing, so a screen reader is not lied to —
      // it just does nothing on tap, because there is nothing to do.
      await tester.tap(find.bySemanticsLabel('Stop listening'));
      await tester.pump();
      expect(stops, isEmpty);
    });
  });

  /// The corner control on a file waiting in the composer.
  ///
  /// `RendelPressable` floors every target at 44pt and a decorated box handed the
  /// floor paints to it, so the 20pt circle 0.10.1 announced rendered as a
  /// 44pt one — half the width of the card. The target keeps the floor; the
  /// circle does not.
  /// The keyboard, which the sheet does not make room for on its own.
  ///
  /// Before 0.23 nothing did, and the box sat under the keyboard on a real
  /// phone; a simulator with a hardware keyboard never showed it.
  testWidgets('the open box sits above the keyboard', (tester) async {
    final c = controller();
    addTearDown(c.dispose);
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          // No Scaffold: the copilot is a sheet, and a Scaffold would make
          // the room itself.
          child: Material(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ThreadScreen(
                controller: c,
                onDictate: (_) async => null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Type a message'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize.height / 3;
    expect(
      tester.getBottomLeft(find.byType(TextField)).dy,
      lessThan(screen - 336),
    );
  });

  group('the attachment remove control', () {
    testWidgets('is a small circle on a full-size target', (tester) async {
      final c = ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          // The upload lands, so the card gets its id and its control.
          httpClient: MockClient((_) async => http.Response('{"id":"f1"}', 201)),
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                onPickAttachment: (_) async => RendelAttachment(
                  bytes: Uint8List.fromList([1, 2, 3]),
                  name: 'notes.pdf',
                  mediaType: 'application/pdf',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // No microphone here, so the box is open and Files is in it.
      await tester.tap(find.bySemanticsLabel('Files'));
      await tester.pumpAndSettle();

      final control = find.bySemanticsLabel('Remove notes.pdf');
      expect(control, findsOneWidget);
      expect(tester.getSize(control), const Size(44, 44),
          reason: 'the tap target keeps its floor');

      final circle = find.descendant(
        of: control,
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle),
      );
      expect(tester.getSize(circle), const Size(22, 22),
          reason: 'what is drawn is not the target');
    });
  });

  /// The error bar, in the host's language.
  ///
  /// `RendelStrings` carried `streamDropped`, `noAnswer`, `confirmationExpired`
  /// and `retry` since the strings existed, and the bar drew the controller's
  /// English and a literal 'Try again' instead — under a Turkish answer, next
  /// to a Turkish composer.
  group('the error bar', () {
    testWidgets('says what failed in the host\'s language', (tester) async {
      final c = controller()
        ..messages.add(RendelMessage.user('Siparişim nerede?'))
        ..errorText = 'The connection dropped before the answer finished.'
        ..errorCode = 'stream_dropped';
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                strings: RendelStrings.forLocale('tr'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Bağlantı, yanıt tamamlanmadan koptu.'), findsOneWidget);
      expect(
        find.text('The connection dropped before the answer finished.'),
        findsNothing,
      );
    });

    testWidgets('keeps the server\'s sentence, which arrives translated',
        (tester) async {
      final c = controller()
        ..messages.add(RendelMessage.user('Siparişim nerede?'))
        ..errorText = 'Asistan kısa süreliğine kapasitesini aştı. Tekrar deneyin.'
        ..errorCode = 'model_busy';
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                strings: RendelStrings.forLocale('tr'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Asistan kısa süreliğine kapasitesini aştı. Tekrar deneyin.'),
        findsOneWidget,
      );
    });
  });

  /// The prompt in the message box.
  ///
  /// `RendelStrings.composerHint` has carried a translated one since the strings
  /// existed — and the composer drew the literal 'Ask anything' instead, so a
  /// Turkish app prompted its users in English while every other word on the
  /// screen was Turkish. Nothing failed; it just read as somebody else's app.
  group('the composer prompt', () {
    Future<void> pump(
      WidgetTester tester, {
      RendelStrings strings = const RendelStrings(),
      String? hint,
    }) async {
      final c = controller();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RendelThemeScope(
            theme: RendelTheme.paper(),
            child: Scaffold(
              body: ThreadScreen(
                controller: c,
                strings: strings,
                composerHint: hint,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('speaks the language the rest of the screen speaks',
        (tester) async {
      await pump(tester, strings: RendelStrings.forLocale('tr'));
      expect(find.text('Ne isterseniz sorun'), findsOneWidget);
      expect(find.text('Ask anything'), findsNothing);
    });

    testWidgets('takes the customer\'s own prompt over the SDK\'s',
        (tester) async {
      await pump(
        tester,
        strings: RendelStrings.forLocale('tr'),
        hint: 'Siparişini sor',
      );
      expect(find.text('Siparişini sor'), findsOneWidget);
      expect(find.text('Ne isterseniz sorun'), findsNothing);
    });
  });
}
