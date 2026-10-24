// The page's ground as the host paints its own screens (`theme.backdrop`),
// and the page steps' glyph in the family of its navigation
// (`theme.style.arrows`). Both are published from the console; a bad or
// illegible backdrop falls back to the plain ground and keeps the rest.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

const _palette = {
  'surface': '#FFFFFF',
  'onSurface': '#1D1D1B',
  'accent': '#392FFF',
  'onAccent': '#FFFFFF',
};

RendelRemoteConfig _parse(Map<String, dynamic> config) =>
    RendelRemoteConfig.tryParse(jsonEncode({'config': config}))!;

RendelTheme _light(Map<String, dynamic> theme) =>
    _parse({'theme': theme}).applyTo(RendelTheme.paper());

void main() {
  group('a backdrop', () {
    test('is drawn as the gradient the app paints its screens with', () {
      final theme = _light({
        ..._palette,
        'backdrop': {
          'colors': ['#E8E2D2', '#F2F4F2', '#F1F7EE'],
          'direction': 'to-bottom-right',
        },
      });
      final backdrop = theme.backdrop!;
      expect(backdrop.colors, const [Color(0xFFE8E2D2), Color(0xFFF2F4F2), Color(0xFFF1F7EE)]);
      expect(backdrop.begin, Alignment.topLeft);
      expect(backdrop.end, Alignment.bottomRight);
      expect(backdrop.stops, isNull);
      // The rest of the theme is the palette's, as without one.
      expect(theme.colors.accent, const Color(0xFF392FFF));
    });

    test('runs top to bottom when it names no direction, and keeps its stops', () {
      final backdrop = _light({
        ..._palette,
        'backdrop': {
          'colors': ['#FFFFFF', '#EEF1FD'],
          'stops': [0.2, 1],
        },
      }).backdrop!;
      expect(backdrop.begin, Alignment.topCenter);
      expect(backdrop.end, Alignment.bottomCenter);
      expect(backdrop.stops, const [0.2, 1.0]);
    });

    test('that the page cannot be read on is dropped, and nothing else is', () {
      final theme = _light({
        ..._palette,
        'radius': {'card': 8},
        'backdrop': {
          'colors': ['#FFFFFF', '#1D1D1B'],
        },
      });
      expect(theme.backdrop, isNull);
      expect(theme.radius.card, 8);
      expect(theme.colors.accent, const Color(0xFF392FFF));
    });

    test('that is malformed is no backdrop rather than half of one', () {
      for (final backdrop in [
        {'colors': ['#FFFFFF']},
        {'colors': ['#FFFFFF', 'blue']},
        {'colors': ['#FFFFFF', '#F2F4F2'], 'direction': 'sideways'},
        {'colors': ['#FFFFFF', '#F2F4F2'], 'stops': [0.6, 0.2]},
        {'colors': ['#FFFFFF', '#F2F4F2'], 'stops': [0]},
      ]) {
        expect(_light({..._palette, 'backdrop': backdrop}).backdrop, isNull, reason: '$backdrop');
      }
    });

    test('is not carried to the dark theme; the dark one is its own', () {
      final light = {
        ..._palette,
        'backdrop': {
          'colors': ['#E8E2D2', '#F1F7EE'],
        },
      };
      final codeLight = RendelTheme.paper();
      final codeDark = RendelTheme.deep();
      expect(_parse({'theme': light}).applyToDark(codeLight, codeDark).backdrop, isNull);

      final dark = _parse({
        'theme': light,
        'themeDark': {
          'backdrop': {
            'colors': ['#14121F', '#0C0F08'],
          },
        },
      }).applyToDark(codeLight, codeDark);
      expect(dark.backdrop!.colors, const [Color(0xFF14121F), Color(0xFF0C0F08)]);
    });
  });

  group('the page steps', () {
    test('are chevrons unless the app says otherwise', () {
      expect(_light({'radius': {'card': 8}}).style.arrows, RendelArrowStyle.chevron);
    });

    test('take the family the app names, and ignore one this build does not know', () {
      expect(_light({'style': {'arrows': 'ios'}}).style.arrows, RendelArrowStyle.ios);
      expect(_light({'style': {'arrows': 'arrow'}}).style.arrows, RendelArrowStyle.arrow);
      expect(_light({'style': {'arrows': 'triangle'}}).style.arrows, RendelArrowStyle.chevron);
    });
  });

  testWidgets('the page is drawn on the backdrop, with the arrows the app names', (tester) async {
    final theme = _light({
      ..._palette,
      'backdrop': {
        'colors': ['#E8E2D2', '#F2F4F2', '#F1F7EE'],
        'direction': 'to-bottom-right',
      },
      'style': {'arrows': 'ios'},
    });
    final api = RendelApiClient(appKey: 'rd_pk_test_x', deviceId: 'd', config: const RendelConfig());
    final controller = ConversationController(
      api: api,
      actions: const {},
      sdkVersion: 'flutter/test',
      onOpenUrl: (_) async => true,
    );
    addTearDown(controller.dispose);
    // Two pages: back and forward are drawn only once there is a second (QA 2026-10-24).
    for (final words in ['First answer.', 'Second answer.']) {
      controller.pages.add(RendelMessage.history('assistant', [
        WireBlock(id: words, type: 'text', fallbackText: words, props: {'markdown': words})..ready = true,
      ]));
    }
    controller.page = 1;
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: theme,
        child: Scaffold(body: ThreadScreen(controller: controller)),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    final grounds = tester
        .widgetList<Container>(find.byType(Container))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>()
        .where((gradient) => gradient.colors.first == const Color(0xFFE8E2D2));
    expect(grounds, isNotEmpty);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
  });
}
