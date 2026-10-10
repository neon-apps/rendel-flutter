// Dark mode, and the three things the AI-setup release asks of the SDK
// (design/AI-SETUP.md §9.5, §9.7, §2.6).
//
// The derivation is pinned to exact hex because it is written three times:
// `deriveDarkTokens` in `packages/protocol` (whose test holds these same
// inputs to these same values), the web SDK, and `rendelDarkRoles` here. A
// change to one that is not made to the others fails here or there.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/version.dart';
import 'package:rendel/src/ui/theme.dart' show rendelDarkRoles;

String _hex(Color color) {
  final value = (color.r * 255).round() << 16 |
      (color.g * 255).round() << 8 |
      (color.b * 255).round();
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color _c(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

List<String> _roles(String surface, String onSurface, String accent,
    String onAccent,
    {String? darkAccent}) {
  final roles = rendelDarkRoles(
    surface: _c(surface),
    onSurface: _c(onSurface),
    accent: _c(accent),
    onAccent: _c(onAccent),
    darkAccent: darkAccent == null ? null : _c(darkAccent),
  );
  return [roles.surface, roles.onSurface, roles.accent, roles.onAccent]
      .map(_hex)
      .toList();
}

void main() {
  group('the dark roles, as the protocol derives them', () {
    test('the brand palette derives to exactly deep()', () {
      expect(_roles('#F4F2EE', '#171615', '#0A0A0A', '#FFFFFF'),
          ['#12110F', '#F4F2EE', '#FEF7AF', '#0A0A0A']);
    });

    test('an accent that reads on the dark ground is kept', () {
      expect(_roles('#ECE9E8', '#2E2A29', '#F55733', '#1F1A19'),
          ['#12110F', '#F4F2EE', '#F55733', '#1F1A19']);
    });

    test('one that does not is lightened along its hue', () {
      expect(_roles('#FFFFFF', '#111111', '#2E40EA', '#FFFFFF'),
          ['#12110F', '#F4F2EE', '#3B4CEB', '#FFFFFF']);
      expect(_roles('#FFFFFF', '#111111', '#1A237E', '#FFFFFF')[2], '#555C9F');
    });

    test('a black action becomes the dark ink, not the brand yellow', () {
      expect(_roles('#FFFFFF', '#111111', '#000000', '#FFFFFF'),
          ['#12110F', '#F4F2EE', '#F4F2EE', '#0A0A0A']);
    });

    test('the label is picked to read on the dark accent', () {
      expect(_roles('#FFF6F0', '#2A1B12', '#FF9A3D', '#FFFFFF')[3], '#0A0A0A');
    });

    test('a palette that is already dark is left alone', () {
      expect(_roles('#101014', '#F2F2F7', '#7C5BFF', '#0A0A0A'),
          ['#101014', '#F2F2F7', '#7C5BFF', '#0A0A0A']);
    });

    test('what the dark palette states is kept, and only the rest derived', () {
      expect(
          _roles('#FFFFFF', '#111111', '#2E40EA', '#FFFFFF',
              darkAccent: '#8899FF'),
          ['#12110F', '#F4F2EE', '#8899FF', '#0A0A0A']);
    });
  });

  group('RendelTheme.darkFrom', () {
    test('paper is deep, the published pair', () {
      expect(identical(RendelTheme.darkFrom(RendelTheme.paper()),
          RendelTheme.deep()), isTrue);
    });

    test('a dark theme is its own dark theme', () {
      final deep = RendelTheme.deep();
      expect(identical(RendelTheme.darkFrom(deep), deep), isTrue);
    });

    test('keeps the shapes and drops the colours chosen for a light plate',
        () {
      final light = RendelTheme.fromTokens(
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF111111),
        accent: const Color(0xFF2E40EA),
        onAccent: const Color(0xFFFFFFFF),
        radius: const RendelRadiusScale(card: 20),
        fontFamily: 'Inter',
        cards: const {
          'product_cards': RendelCardLook(
            surfaceRaised: Color(0xFFFAFAFA),
            radius: 6,
            parts: {'price': RendelPartLook(color: Color(0xFF111111), size: 16)},
          ),
        },
      );
      final dark = RendelTheme.darkFrom(light);
      expect(_hex(dark.colors.surface), '#12110F');
      expect(_hex(dark.colors.accent), '#3B4CEB');
      expect(dark.radius.card, 20);
      expect(dark.fontFamily, 'Inter');
      final card = dark.cards['product_cards']!;
      expect(card.surfaceRaised, isNull);
      expect(card.radius, 6);
      expect(card.parts['price']!.color, isNull);
      expect(card.parts['price']!.size, 16);
    });
  });

  group('the published dark theme', () {
    final codeLight = RendelTheme.paper();
    final codeDark = RendelTheme.deep();
    RendelRemoteConfig parse(Map<String, Object?> config) =>
        RendelRemoteConfig.tryParse(jsonEncode({'config': config}))!;

    test('a partial dark palette is completed from the published light one',
        () {
      final dark = parse({
        'theme': {
          'surface': '#FFFFFF',
          'onSurface': '#111111',
          'accent': '#2E40EA',
          'onAccent': '#FFFFFF',
        },
        'themeDark': {'accent': '#8899FF'},
      }).applyToDark(codeLight, codeDark);
      expect(_hex(dark.colors.surface), '#12110F');
      expect(_hex(dark.colors.accent), '#8899FF');
      expect(_hex(dark.colors.onAccent), '#0A0A0A');
    });

    test('a light palette alone gives a derived dark theme, not the host one',
        () {
      final dark = parse({
        'theme': {
          'surface': '#FFFFFF',
          'onSurface': '#111111',
          'accent': '#2E40EA',
          'onAccent': '#FFFFFF',
          'surfaceRaised': '#F0F0F0',
        },
      }).applyToDark(codeLight, codeDark);
      expect(_hex(dark.colors.accent), '#3B4CEB');
      // The light theme's raised plate is no plate on a dark ground.
      expect(dark.colors.surfaceRaised.computeLuminance(), lessThan(0.05));
    });

    test('sizes travel without a palette, and the dark colours stay the host\'s',
        () {
      final dark = parse({
        'theme': {
          'radius': {'card': 20}
        },
        'themeDark': {
          'radius': {'card': 12}
        },
      }).applyToDark(codeLight, codeDark);
      expect(dark.colors.surface, codeDark.colors.surface);
      expect(dark.accentText, codeDark.accentText);
      expect(dark.radius.card, 12);
    });

    test('a dark colour this build cannot read keeps the compiled dark theme',
        () {
      final dark = parse({
        'theme': {
          'surface': '#FFFFFF',
          'onSurface': '#111111',
          'accent': '#2E40EA',
          'onAccent': '#FFFFFF',
        },
        'themeDark': {'surface': '#00000000'},
      }).applyToDark(codeLight, codeDark);
      expect(identical(dark, codeDark), isTrue);
    });

    test('an empty payload leaves the compiled dark theme alone', () {
      expect(identical(parse({}).applyToDark(codeLight, codeDark), codeDark),
          isTrue);
    });

    test('is cached with the rest of the payload', () {
      final remote = parse({
        'themeDark': {
          'radius': {'card': 12}
        }
      });
      final again = RendelRemoteConfig.tryParse(remote.toCache())!;
      expect(again.themeDark, {
        'radius': {'card': 12}
      });
    });
  });

  group('following the device', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(Rendel.resetForTest);

    MockClient offline() =>
        MockClient((request) async => http.Response('{}', 200));

    Future<void> start({RendelThemeMode mode = RendelThemeMode.system}) =>
        Rendel.init(
          appKey: 'nc_pk_test_dark_000000000000000000000000',
          config: RendelConfig(
            httpClient: offline(),
            remoteConfig: false,
            themeMode: mode,
          ),
        );

    Color launcherFill(WidgetTester tester) {
      final box = tester.widget<Container>(find.descendant(
        of: find.byType(RendelLauncher),
        matching: find.byType(Container),
      ));
      return (box.decoration! as BoxDecoration).color!;
    }

    testWidgets('the launcher repaints when the phone switches', (tester) async {
      await start();
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(floatingActionButton: RendelLauncher()),
      ));
      expect(launcherFill(tester), RendelTheme.paper().colors.accent);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(launcherFill(tester), RendelTheme.deep().colors.accent);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pump();
      expect(launcherFill(tester), RendelTheme.paper().colors.accent);
    });

    testWidgets('a host that is always light stays light', (tester) async {
      await start(mode: RendelThemeMode.light);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(floatingActionButton: RendelLauncher()),
      ));
      expect(launcherFill(tester), RendelTheme.paper().colors.accent);

      // An app with its own switch changes it while running.
      Rendel.setThemeMode(RendelThemeMode.dark);
      await tester.pump();
      expect(launcherFill(tester), RendelTheme.deep().colors.accent);
    });

    test('a host theme brings its own derived dark theme', () async {
      final brand = RendelTheme.fromTokens(
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF111111),
        accent: const Color(0xFF2E40EA),
        onAccent: const Color(0xFFFFFFFF),
      );
      await Rendel.init(
        appKey: 'nc_pk_test_dark_000000000000000000000000',
        theme: brand,
        config: RendelConfig(httpClient: offline(), remoteConfig: false),
      );
      expect(identical(Rendel.themeFor(Brightness.light), brand), isTrue);
      expect(_hex(Rendel.themeFor(Brightness.dark).colors.accent), '#3B4CEB');
    });

    test('a dark theme the host passes is the one drawn', () async {
      final mine = RendelTheme.fromTokens(
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFFFFFFF),
        accent: const Color(0xFFFF5500),
        onAccent: const Color(0xFF000000),
      );
      await Rendel.init(
        appKey: 'nc_pk_test_dark_000000000000000000000000',
        darkTheme: mine,
        config: RendelConfig(httpClient: offline(), remoteConfig: false),
      );
      expect(identical(Rendel.themeFor(Brightness.dark), mine), isTrue);
    });
  });

  group('the config request', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(Rendel.resetForTest);

    test('says which build is calling and from what', () async {
      final sent = <http.Request>[];
      await Rendel.init(
        appKey: 'nc_pk_test_dark_000000000000000000000000',
        config: RendelConfig(
          httpClient: MockClient((request) async {
            sent.add(request);
            return http.Response('{"config":{}}', 200);
          }),
        ),
      );
      await Rendel.refreshConfig();
      final config =
          sent.firstWhere((r) => r.url.path.endsWith('/v1/apps/config'));
      expect(config.headers['X-Rendel-SDK'], sdkVersion);
      // `flutter test` runs as Android unless a test says otherwise.
      expect(config.headers['X-Rendel-Platform'], 'android');
    });
  });

  group('a manifest with nothing in it', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(Rendel.resetForTest);

    test('still goes out, so the console knows the SDK is in', () async {
      Map<String, dynamic>? body;
      await Rendel.init(
        appKey: 'nc_pk_test_dark_000000000000000000000000',
        config: RendelConfig(
          remoteConfig: false,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/v1/apps/manifest')) {
              body = jsonDecode(request.body) as Map<String, dynamic>;
            }
            return http.Response('{}', 200);
          }),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(body?['manifest'], {'version': 1, 'actions': []});
      expect(body?['sdk'], sdkVersion);
    });
  });

  group('an app the server refuses', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(Rendel.resetForTest);

    for (final code in ['app_not_live', 'app_suspended']) {
      testWidgets('$code hides the launcher, says so once, and shows no error',
          (tester) async {
        final logs = <RendelLogRecord>[];
        var answer = http.Response(
            jsonEncode({
              'error': {'code': code}
            }),
            403);
        await tester.runAsync(() => Rendel.init(
              appKey: 'rd_pk_live_dark_000000000000000000000000',
              config: RendelConfig(
                onLog: logs.add,
                httpClient: MockClient((request) async =>
                    request.url.path.endsWith('/v1/apps/config')
                        ? answer
                        : http.Response('{}', 200)),
              ),
            ));
        await tester.runAsync(Rendel.refreshConfig);
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(floatingActionButton: RendelLauncher()),
        ));

        expect(Rendel.isEnabled, isFalse);
        expect(find.text('Ask'), findsNothing);
        final said = logs.where((r) => r.code == code).toList();
        expect(said, hasLength(1));
        expect(
          said.single.level,
          code == 'app_not_live'
              ? RendelLogLevel.warning
              : RendelLogLevel.debug,
        );
        expect(said.single.message, isNot(contains('\n')));
        if (code == 'app_not_live') {
          expect(said.single.message, contains('test key'));
          expect(said.single.message, contains('Go live'));
        }
        // Nothing the user would read as a failure.
        expect(logs.where((r) => r.level == RendelLogLevel.error), isEmpty);

        // Once the app is live, the next answer brings the launcher back.
        answer = http.Response('{"config":{}}', 200);
        await tester.runAsync(Rendel.refreshConfig);
        await tester.pump();
        expect(Rendel.isEnabled, isTrue);
        expect(find.text('Ask'), findsOneWidget);
      });
    }
  });
}
