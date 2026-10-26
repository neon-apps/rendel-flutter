// Tap autocapture (design/plans/product-analytics.md §2.4): real Material
// controls, the markers, the privacy rules, what is not a tap, rage, the
// capture config, the switch, and what the global route costs.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/analytics.dart';
import 'package:rendel/src/core/screens.dart';
import 'package:rendel/src/core/taps.dart';

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Shop'),
            actions: [IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () {})],
            bottom: const TabBar(tabs: [Tab(text: 'Coffee'), Tab(text: 'Tea')]),
          ),
          body: ListView(
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Buy now')),
              FilledButton(key: const ValueKey('checkout'), onPressed: () {}, child: const Text('Checkout')),
              TextButton(onPressed: () {}, child: const Text('Mail ada@example.com')),
              IconButton(icon: const Icon(Icons.favorite, semanticLabel: 'Favourite'), onPressed: () {}),
              ListTile(title: const Text('Ada Lovelace'), subtitle: const Text('Last seen today'), onTap: () {}),
              const TextField(decoration: InputDecoration(labelText: 'Email', hintText: 'you@example.com')),
              Switch(value: true, onChanged: (_) {}),
              Checkbox(value: false, onChanged: (_) {}),
              InkWell(onTap: () {}, child: const Text('Plain ink')),
              InkWell(onTap: () {}, child: const Column(children: [Text('Order from Ada'), Text('2 items')])),
              RendelName('promo_banner', child: GestureDetector(onTap: () {}, child: const Text('Promo'))),
              RendelMask(child: TextButton(onPressed: () {}, child: const Text('Your balance'))),
              RendelIgnore(child: TextButton(onPressed: () {}, child: const Text('Ignored'))),
              OutlinedButton(onPressed: () => Navigator.of(context).pushNamed('/detail'), child: const Text('Open detail')),
            ],
          ),
        ),
      );
}

Widget _app() => MaterialApp(
      navigatorObservers: [Rendel.navigatorObserver],
      home: const ShopPage(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('Detail'))),
      ),
    );

RendelTaps get _taps => RendelTaps.instance;
RendelScreens get _screens => RendelScreens.instance;

void main() {
  late List<Map<String, dynamic>> sent;

  setUp(() {
    sent = [];
    _screens.send = sent.addAll;
    _taps
      ..attachable = true
      ..attach();
  });
  tearDown(Rendel.resetForTest);

  /// The pointers' clock: the test's own gestures all say zero, which is
  /// every tap in the same second.
  var clock = Duration.zero;
  var pointer = 1;

  /// A tap [after] the one before, held for [hold].
  Future<void> press(WidgetTester tester, Offset at,
      {Duration after = const Duration(seconds: 2), Duration hold = const Duration(milliseconds: 80)}) async {
    clock += after;
    final gesture = await tester.createGesture(pointer: pointer++);
    await gesture.down(at, timeStamp: clock);
    await gesture.up(timeStamp: clock + hold);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      // Further down the list than it has built yet.
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await press(tester, tester.getCenter(finder));
    await tester.pumpAndSettle();
    // The scheduler task the tap left, run.
    await tester.pump();
  }

  /// The taps counted, without their times and sessions.
  List<Map<String, dynamic>> taps() {
    _screens.flush();
    return [
      for (final item in sent)
        if (item['type'] == 'tap') {...item}..remove('at')..remove('session'),
    ];
  }

  Map<String, dynamic> tapOn(String screen, String role, String locator, {String? label, bool rage = false}) => {
        'type': 'tap',
        'screen': screen,
        'role': role,
        if (label != null) 'label': label,
        'locator': locator,
        'platform': 'android',
        if (rage) 'rage': true,
      };

  group('Material controls', () {
    testWidgets('buttons, links and tabs by their caption; rows and switches without text', (tester) async {
      await tester.pumpWidget(_app());
      for (final finder in [
        find.byTooltip('Search'),
        find.text('Tea'),
        find.text('Buy now'),
        find.text('Checkout'),
        find.text('Mail ada@example.com'),
        find.byIcon(Icons.favorite),
        find.text('Ada Lovelace'),
        find.byType(Switch),
        find.byType(Checkbox),
        find.text('Plain ink'),
        find.text('2 items'),
      ]) {
        await tap(tester, finder);
      }
      const page = 'ShopPage > Scaffold';
      expect(taps(), [
        tapOn('/', 'button', '$page > AppBar > IconButton', label: 'Search'),
        tapOn('/', 'tab', '$page > AppBar > TabBar > Tab', label: 'Tea'),
        tapOn('/', 'button', '$page > ListView > ElevatedButton', label: 'Buy now'),
        // A Key wins over the chain.
        tapOn('/', 'button', 'checkout', label: 'Checkout'),
        tapOn('/', 'button', '$page > ListView > TextButton', label: 'Mail [masked]'),
        // An icon-only button by its icon's semantic label.
        tapOn('/', 'button', '$page > ListView > IconButton', label: 'Favourite'),
        tapOn('/', 'row', '$page > ListView > ListTile'),
        tapOn('/', 'switch', '$page > ListView > Switch'),
        tapOn('/', 'checkbox', '$page > ListView > Checkbox'),
        tapOn('/', 'button', '$page > ListView', label: 'Plain ink'),
        // A tappable card in a list holding two texts is a row: its text is content.
        tapOn('/', 'row', '$page > ListView'),
      ]);
    });

    testWidgets('a field by its label, never by what was typed in it', (tester) async {
      await tester.pumpWidget(_app());
      await tap(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'secret words');
      await tester.pump();
      await tap(tester, find.byType(TextField));
      final counted = taps();
      expect(counted.first, tapOn('/', 'field', 'ShopPage > Scaffold > ListView > TextField', label: 'Email'));
      expect(counted, hasLength(2));
      expect(counted.toString(), isNot(contains('secret')));
    });

    testWidgets('the back button, on the screen it was tapped on, though the tap pops it', (tester) async {
      await tester.pumpWidget(_app());
      await tap(tester, find.text('Open detail'));
      await tap(tester, find.byType(BackButton));
      expect(taps(), [
        tapOn('/', 'button', 'ShopPage > Scaffold > ListView > OutlinedButton', label: 'Open detail'),
        tapOn('/detail', 'button', 'Scaffold > AppBar > BackButton > IconButton', label: 'Back'),
      ]);
    });
  });

  group('markers', () {
    testWidgets('RendelName names, RendelMask keeps no text, RendelIgnore counts nothing', (tester) async {
      await tester.pumpWidget(_app());
      await tap(tester, find.text('Promo'));
      await tap(tester, find.text('Your balance'));
      await tap(tester, find.text('Ignored'));
      expect(taps(), [
        tapOn('/', 'button', 'promo_banner', label: 'promo_banner'),
        tapOn('/', 'button', 'ShopPage > Scaffold > ListView > TextButton'),
      ]);
    });
  });

  group('not a tap', () {
    testWidgets('a long press, or a drag past the slop', (tester) async {
      await tester.pumpWidget(_app());
      final at = tester.getCenter(find.text('Buy now'));
      await press(tester, at, hold: const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(at);
      await gesture.moveBy(const Offset(0, 40));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump();
      expect(taps(), isEmpty);
    });
  });

  group('rage', () {
    testWidgets('the third tap within a second and 30 px is rage', (tester) async {
      await tester.pumpWidget(_app());
      final at = tester.getCenter(find.text('Buy now'));
      for (var i = 0; i < 4; i++) {
        await press(tester, at + Offset(i * 5.0, 0), after: const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Seconds later, a tap on its own.
      await press(tester, at);
      await tester.pumpAndSettle();
      await tester.pump();
      expect(taps().map((t) => t['rage'] == true), [false, false, true, true, false]);
    });
  });

  group('capture config', () {
    testWidgets('off counts no taps', (tester) async {
      RendelAnalytics.instance.capture = const RendelCapture(taps: 'off');
      await tester.pumpWidget(_app());
      await tap(tester, find.text('Buy now'));
      expect(taps(), isEmpty);
    });

    testWidgets('no_text keeps taps without labels; a masked screen keeps no labels', (tester) async {
      await tester.pumpWidget(_app());
      RendelAnalytics.instance.capture = const RendelCapture(taps: 'no_text');
      await tap(tester, find.text('Buy now'));
      RendelAnalytics.instance.capture = const RendelCapture(mask: ['/']);
      await tap(tester, find.text('Buy now'));
      expect(taps(), [
        for (var i = 0; i < 2; i++) tapOn('/', 'button', 'ShopPage > Scaffold > ListView > ElevatedButton'),
      ]);
    });

    testWidgets('a sample is by device', (tester) async {
      await tester.pumpWidget(_app());
      const id = '0123456789abcdef0123456789abcdef';
      _taps.deviceId = () => id;
      final share = sampleOf(id);
      RendelAnalytics.instance.capture = RendelCapture(sample: share * 0.99);
      await tap(tester, find.text('Buy now'));
      expect(taps(), isEmpty);
      RendelAnalytics.instance.capture = RendelCapture(sample: share + 0.0001);
      await tap(tester, find.text('Buy now'));
      expect(taps(), hasLength(1));
    });
  });

  testWidgets('analytics off counts no taps', (tester) async {
    await tester.pumpWidget(_app());
    Rendel.setAnalyticsEnabled(false);
    await tap(tester, find.text('Buy now'));
    expect(taps(), isEmpty);
  });

  testWidgets('the platform is named as the protocol names it', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(RendelTaps.platform, 'ios');
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(RendelTaps.platform, 'macos');
    debugDefaultTargetPlatformOverride = null;
    expect(RendelTaps.platform, 'android');
  });

  testWidgets('the global route takes under 0.2 ms for a tap', (tester) async {
    await tester.pumpWidget(_app());
    final at = tester.getCenter(find.text('Buy now'));
    final down = <int>[], up = <int>[];
    final watch = Stopwatch();
    for (var i = 0; i < 300; i++) {
      watch
        ..reset()
        ..start();
      _taps.route(PointerDownEvent(pointer: 100 + i, position: at, timeStamp: Duration(seconds: i)));
      watch.stop();
      down.add(watch.elapsedMicroseconds);
      watch
        ..reset()
        ..start();
      _taps.route(PointerUpEvent(pointer: 100 + i, position: at, timeStamp: Duration(seconds: i, milliseconds: 80)));
      watch.stop();
      up.add(watch.elapsedMicroseconds);
    }
    // The first calls compile the code; what a running app pays is the rest.
    int median(List<int> times) => (times.skip(50).toList()..sort())[125];
    debugPrint('route: down ${median(down)} µs, up ${median(up)} µs (median, debug mode)');
    expect(median(down), lessThan(200));
    expect(median(up), lessThan(200));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}
