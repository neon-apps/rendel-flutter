import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show BlockEnter;

/// The invariant rule 8 of `blocks.dart` claims and nothing checked: props are
/// whatever the server put on the wire, and one wrong-typed field must degrade
/// rather than take the thread down with it.
///
/// Parameterised over `ComponentRegistry.registeredTypes`, so a nineteenth
/// block is covered the moment it is registered rather than when someone
/// remembers to add a case. This is the acceptance criterion the Swift and
/// Kotlin ports have to meet too.
void main() {
  final dispatch = RendelDispatcher(
    onAction: (_) async => true,
    onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
    canHandle: (_) => true,
  );

  Widget host(Widget child) => MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  /// Renders one block inside a real theme scope, on the narrowest screen
  /// still shipping. 320pt is where a fixed width or an unbounded Text shows
  /// up as an overflow rather than as slack.
  Future<void> pumpBlock(WidgetTester tester, WireBlock b) async {
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(Builder(builder: (context) => ComponentRegistry.build(context, b, dispatch))),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  WireBlock block(String type, Map<String, dynamic> props, {bool ready = true}) =>
      WireBlock(
        id: 'b_$type',
        type: type,
        fallbackText: 'A $type block.',
        props: props,
      )..ready = ready;

  group('every registered block survives hostile props', () {
    for (final type in ComponentRegistry.registeredTypes) {
      testWidgets('$type renders with no props at all', (tester) async {
        await pumpBlock(tester, block(type, {}));
        expect(tester.takeException(), isNull);
      });

      testWidgets('$type renders with wrong-typed props', (tester) async {
        // Every shape the wire could get wrong: a number where a string
        // belongs, a string where a list belongs, a map where a scalar
        // belongs, and nulls inside collections.
        final hostile = <String, dynamic>{
          'title': 42,
          'body': ['not', 'a', 'string'],
          'items': 'not a list',
          'fields': 7,
          'slots': {'not': 'a list'},
          'steps': 'nope',
          'lines': 1.5,
          'columns': true,
          'rows': 'oops',
          'series': 'one,two,three',
          'labels': 9,
          'images': [null, 3],
          'plans': {},
          'value': 'eight',
          'max': 'zero',
          'total': [],
          'kind': 11,
          'tone': [],
          'layout': 3,
          'summary': {'a': 1},
          'params_display': 'x',
          'action_name': 5,
        };
        await pumpBlock(tester, block(type, hostile));
        expect(tester.takeException(), isNull);
      });

      testWidgets('$type draws a skeleton before it is ready', (tester) async {
        await pumpBlock(tester, block(type, {}, ready: false));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an unknown type falls back to its text', (tester) async {
      await pumpBlock(tester, block('hologram_viewer', {}));
      expect(tester.takeException(), isNull);
      expect(find.text('A hologram_viewer block.'), findsOneWidget);
    });
  });

  group('BlockEnter', () {
    // It reads the theme for its duration, and reading an inherited widget
    // from a field initialiser touched in initState asserts — which put an
    // error widget in place of every block in the thread.
    testWidgets('mounts under a theme scope without asserting', (tester) async {
      final seen = <String>{};
      await tester.pumpWidget(
        host(BlockEnter(
          id: 'b1',
          seen: seen,
          child: const Text('arrived'),
        )),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('arrived'), findsOneWidget);
      expect(seen, contains('b1'));
    });

    // Under reduced motion build returns before touching the animation, so
    // dispose used to be the first thing to evaluate it — looking up an
    // ancestor that was already deactivated.
    testWidgets('disposes cleanly under reduced motion', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(BlockEnter(
            id: 'b2',
            seen: <String>{},
            child: const Text('still'),
          )),
        ),
      );
      expect(find.text('still'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('plays once per block id', (tester) async {
      final seen = <String>{'b3'};
      await tester.pumpWidget(
        host(BlockEnter(id: 'b3', seen: seen, child: const Text('again'))),
      );
      // Already seen, so the entrance is settled on its first frame rather
      // than replaying as an accidental scroll reveal.
      final opacity = tester.widget<FadeTransition>(
        find.byType(FadeTransition).first,
      );
      expect(opacity.opacity.value, 1.0);
    });
  });
}
