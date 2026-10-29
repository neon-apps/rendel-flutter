// The launcher's style, icon, own icon and drag (Tuna, 2026-10-28): what the
// console publishes, how each is drawn, and where a dragged launcher goes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/followups.dart';
import 'package:rendel/src/ui/followup_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'nc_pk_test_launcher_00000000000000000000000';
const _asset = '3f6b0b8e-6b0e-4a5f-9a1a-2c8f0d5e7a11';
const _place = 'rendel_launcher_place_$_key';

/// A 1 × 1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

RendelRemoteConfig _parse(Map<String, Object?> copilot) =>
    RendelRemoteConfig.tryParse(jsonEncode({
      'config': {'copilot': copilot},
    }))!;

Future<void> _start(WidgetTester tester, [RendelConfig config = const RendelConfig()]) =>
    tester.runAsync(() => Rendel.init(
          appKey: _key,
          config: RendelConfig(
            remoteConfig: false,
            httpClient: MockClient((request) async => http.Response('{}', 200)),
            launcherStyle: config.launcherStyle,
            launcherIcon: config.launcherIcon,
            launcherDraggable: config.launcherDraggable,
          ),
        ));

Widget _fab() => const MaterialApp(home: Scaffold(floatingActionButton: RendelLauncher()));

/// The painted icon inside the launcher.
Finder get _glyph => find.descendant(
      of: find.byType(RendelPressable),
      matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null),
    );

Finder get _button => find.byType(RendelPressable);

/// Lets the store and an image arrive, which need the real event loop.
Future<void> _arrive(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}

void main() {
  group('the published launcher fields', () {
    const code = RendelConfig();

    test('are read onto the config', () {
      final applied = _parse({
        'launcherStyle': 'icon',
        'launcherIcon': 'headset',
        'launcherDraggable': true,
      }).applyToConfig(code);
      expect(applied.launcherStyle, RendelLauncherStyle.icon);
      expect(applied.launcherIcon, 'headset');
      expect(applied.launcherDraggable, isTrue);
    });

    test('default to the label, the sparkle and staying put', () {
      expect(code.launcherStyle, RendelLauncherStyle.label);
      expect(code.launcherIcon, 'sparkle');
      expect(code.launcherDraggable, isFalse);
      final applied = _parse({'launcherLabel': 'Help'}).applyToConfig(code);
      expect(applied.launcherStyle, RendelLauncherStyle.label);
      expect(applied.launcherIcon, 'sparkle');
      expect(applied.launcherDraggable, isFalse);
    });

    test('an icon or a style this build does not know is said nothing', () {
      const host = RendelConfig(launcherIcon: 'heart', launcherStyle: RendelLauncherStyle.icon);
      final applied = _parse({'launcherIcon': 'unicorn', 'launcherStyle': 'pill'}).applyToConfig(host);
      expect(applied.launcherIcon, 'heart');
      expect(applied.launcherStyle, RendelLauncherStyle.icon);
      expect(_parse({'launcherIcon': 'custom'}).applyToConfig(code).launcherIcon, 'custom');
      expect(_parse({'launcherDraggable': 'yes'}).applyToConfig(code).launcherDraggable, isFalse);
    });

    test('the own icon is an id or nothing', () {
      expect(_parse({'launcherIconAssetId': ' $_asset '}).launcherIconAssetId, _asset);
      expect(_parse({'launcherIconAssetId': 'https://evil.example/x.png'}).launcherIconAssetId, isNull);
      expect(_parse({'launcherIconAssetId': 7}).launcherIconAssetId, isNull);
      expect(_parse({}).launcherIconAssetId, isNull);
    });
  });

  group('drawn', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(Rendel.resetForTest);

    testWidgets('label: the icon, 20 square in the ink, then the word', (tester) async {
      await _start(tester);
      await tester.pumpWidget(_fab());
      expect(find.text('Ask'), findsOneWidget);
      expect(tester.getSize(_glyph), const Size(20, 20));
      expect(tester.renderObject(_glyph), paints..path(color: Rendel.theme.colors.onAccent));
      // The icon leads, 8 before the word.
      expect(tester.getTopLeft(find.text('Ask')).dx - tester.getTopRight(_glyph).dx, 8);
      expect(find.bySemanticsLabel(Rendel.strings.openCopilot), findsOneWidget);
    });

    testWidgets('icon: round, as tall as the label, and says the word', (tester) async {
      await _start(tester);
      await tester.pumpWidget(_fab());
      final labelHeight = tester.getSize(_button).height;
      await tester.pumpWidget(const SizedBox());
      Rendel.resetForTest();

      await _start(tester, const RendelConfig(launcherStyle: RendelLauncherStyle.icon));
      await tester.pumpWidget(_fab());
      expect(find.text('Ask'), findsNothing);
      expect(tester.getSize(_button), Size(labelHeight, labelHeight));
      expect(tester.getSize(_glyph), const Size(20, 20));
      final box = tester.widget<Container>(find.descendant(of: _button, matching: find.byType(Container)));
      expect((box.decoration! as BoxDecoration).shape, BoxShape.circle);
      expect(find.bySemanticsLabel('Ask'), findsOneWidget);
    });

    testWidgets('each icon is drawn, and one this build lacks is the sparkle', (tester) async {
      for (final id in ['heart', 'unicorn']) {
        await _start(tester, RendelConfig(launcherIcon: id));
        await tester.pumpWidget(_fab());
        expect(tester.renderObject(_glyph), paints..path(color: Rendel.theme.colors.onAccent));
        await tester.pumpWidget(const SizedBox());
        Rendel.resetForTest();
      }
    });
  });

  group('the own icon', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(() {
      imageCache.clear();
      Rendel.resetForTest();
    });

    Future<_FakeHttp> publish(WidgetTester tester, {required int status}) async {
      final server = _FakeHttp(status, _png);
      debugNetworkImageHttpClientProvider = () => server;
      await tester.runAsync(() => Rendel.init(
            appKey: _key,
            config: RendelConfig(
              httpClient: MockClient((request) async => request.url.path.endsWith('/v1/apps/config')
                  ? _json({
                      'config': {
                        'copilot': {'launcherIcon': 'custom', 'launcherIconAssetId': _asset},
                      },
                    })
                  : _json({})),
            ),
          ));
      await tester.runAsync(Rendel.refreshConfig);
      return server;
    }

    testWidgets('is fetched like the logo and drawn in the ink', (tester) async {
      final server = await publish(tester, status: 200);
      await tester.pumpWidget(_fab());
      await _arrive(tester);
      expect(server.urls, [Uri.parse('https://api.rendel.ai/v1/apps/launcher-icon?v=$_asset')]);
      expect(server.headers['x-rendel-key'], _key);
      final image = tester.widget<RawImage>(find.descendant(of: _button, matching: find.byType(RawImage)));
      expect(image.image, isNotNull);
      expect(image.color, Rendel.theme.colors.onAccent);
      expect(image.colorBlendMode, BlendMode.srcIn);
      expect(_glyph, findsNothing);
      // Unset inside the test: the binding checks it before any tear-down.
      debugNetworkImageHttpClientProvider = null;
    });

    testWidgets('is the sparkle when it cannot be had', (tester) async {
      await publish(tester, status: 404);
      await tester.pumpWidget(_fab());
      await _arrive(tester);
      expect(tester.renderObject(_glyph), paints..path(color: Rendel.theme.colors.onAccent));
      debugNetworkImageHttpClientProvider = null;
    });
  });

  group('dragged', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(Rendel.resetForTest);

    const draggable = RendelConfig(launcherDraggable: true);

    Future<void> mount(WidgetTester tester, Widget app, {Map<String, Object> saved = const {}}) async {
      SharedPreferences.setMockInitialValues(saved);
      await _start(tester, draggable);
      await tester.pumpWidget(app);
      await _arrive(tester);
    }

    Future<Map<String, dynamic>?> stored(WidgetTester tester) async {
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      final value = prefs!.getString(_place);
      return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
    }

    testWidgets('first shows where its slot was, which stays empty', (tester) async {
      await mount(tester, _fab());
      expect(tester.getSize(find.byType(RendelLauncher)), Size.zero);
      expect(find.text('Ask'), findsOneWidget);
      // The floatingActionButton's corner, 16 from the right and the bottom,
      // taken in at the launcher's own 20.
      final rect = tester.getRect(_button);
      expect(rect.right, 800 - 20);
      expect(rect.bottom, 600 - 20);
    });

    testWidgets('let go past the threshold, it settles on the nearer side and is kept', (tester) async {
      await mount(tester, _fab());
      final opened = <RendelEvent>[];
      final sub = Rendel.events.listen(opened.add);
      addTearDown(sub.cancel);
      final before = tester.getRect(_button);

      await tester.drag(find.text('Ask'), const Offset(-500, -200));
      await tester.pumpAndSettle();
      final after = tester.getRect(_button);
      expect(after.left, 20);
      expect(after.top, closeTo(before.top - 200, 0.01));
      expect(Rendel.isOpen, isFalse);
      expect(opened, isEmpty);

      final place = await stored(tester);
      expect(place!['side'], 'left');
      expect(place['y'], closeTo(after.top / 600, 0.0001));
    });

    testWidgets("let go low, it stays above the app's tab bar, where its slot was", (tester) async {
      await mount(
        tester,
        MaterialApp(
          home: Scaffold(
            floatingActionButton: const RendelLauncher(),
            bottomNavigationBar: NavigationBar(
              key: const ValueKey('tabs'),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Shop'),
                NavigationDestination(icon: Icon(Icons.person), label: 'Account'),
              ],
            ),
          ),
        ),
      );
      final tabs = tester.getRect(find.byKey(const ValueKey('tabs')));
      // Dragged to the bottom right corner, over the Account tab (QA R2-14).
      await tester.drag(find.text('Ask'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(tester.getRect(_button).bottom, lessThanOrEqualTo(tabs.top));
    });

    testWidgets('a short move is a tap, and a longer one is not', (tester) async {
      await mount(tester, _fab());
      final at = tester.getRect(_button);

      // Past 6 but inside the tap's own slop: a drag, which opens nothing.
      var gesture = await tester.startGesture(at.center);
      await gesture.moveBy(const Offset(-10, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      await _arrive(tester);
      expect(Rendel.isOpen, isFalse);
      expect(tester.getRect(_button), at);

      gesture = await tester.startGesture(at.center);
      await gesture.moveBy(const Offset(-3, 0));
      await gesture.up();
      await _arrive(tester);
      expect(Rendel.isOpen, isTrue);
      // Hidden while the thread is up, as the placed one is under the sheet.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Ask'), findsNothing);
    });

    testWidgets('steps aside for the bubble', (tester) async {
      await mount(tester, _fab());
      Rendel.minimised.value = true;
      addTearDown(() => Rendel.minimised.value = false);
      await tester.pump();
      expect(find.text('Ask'), findsNothing);
      Rendel.minimised.value = false;
      await tester.pump();
      expect(find.text('Ask'), findsOneWidget);
    });

    testWidgets('the waiting message opens over it, once, from the side it is on', (tester) async {
      await mount(
        tester,
        // Two placements low on the left.
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: Column(mainAxisSize: MainAxisSize.min, children: [RendelLauncher(), RendelLauncher()]),
            ),
          ),
        ),
      );
      RendelFollowups.instance.current.value = const RendelFollowup(
        id: 'f1',
        type: 'watch',
        title: 'Pegasus 41 is on sale',
        body: 'Down to 449.90.',
        button: 'Show',
      );
      // The launcher places the popup after a frame; nothing else asks for one.
      tester.binding.scheduleFrame();
      await tester.pump();
      await tester.pump();
      expect(find.text('Pegasus 41 is on sale'), findsOneWidget);
      var card = tester.getRect(find.byType(RendelFollowupCard));
      Rect at() => tester.getRect(find.ancestor(of: find.text('Ask'), matching: _button));
      var launcher = at();
      expect(launcher.left, 20);
      expect(card.left, launcher.left);
      expect(card.bottom, launcher.top - 12);

      await tester.drag(find.text('Ask'), const Offset(500, -100));
      await tester.pumpAndSettle();
      card = tester.getRect(find.byType(RendelFollowupCard));
      launcher = at();
      expect(launcher.right, 800 - 20);
      expect(card.right, launcher.right);
      expect(card.bottom, launcher.top - 12);
    });

    testWidgets('starts where this device left it', (tester) async {
      await mount(tester, _fab(), saved: {_place: '{"side":"left","y":0.25}'});
      final rect = tester.getRect(_button);
      expect(rect.left, 20);
      expect(rect.top, 150);
    });

    testWidgets('one over the app, however many screens place one', (tester) async {
      await mount(
        tester,
        MaterialApp(
          home: const Scaffold(floatingActionButton: RendelLauncher()),
          routes: {
            '/second': (_) => const Scaffold(floatingActionButton: RendelLauncher()),
          },
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.pushNamed('/second'));
      await tester.pumpAndSettle();
      expect(find.byType(RendelLauncher, skipOffstage: false), findsNWidgets(2));
      expect(find.text('Ask'), findsOneWidget);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Ask'), findsOneWidget);

      // None placed, none drawn.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(find.text('Ask'), findsNothing);
    });
  });
}

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// What `NetworkImage` asks of `dart:io`, and no more.
class _FakeHttp implements HttpClient {
  _FakeHttp(this.status, this.body);

  final int status;
  final List<int> body;
  final urls = <Uri>[];
  final headers = <String, String>{};

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    return _FakeRequest(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.client);

  final _FakeHttp client;

  @override
  late final HttpHeaders headers = _FakeHeaders(client.headers);

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(client.status, client.body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this.into);

  final Map<String, String> into;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) => into[name] = '$value';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, this.body);

  @override
  final int statusCode;
  final List<int> body;

  @override
  int get contentLength => body.length;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(body).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
