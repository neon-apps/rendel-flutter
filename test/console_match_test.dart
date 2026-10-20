// The phone draws what the console's Appearance phone shows (Tuna,
// 2026-10-20, Protein Ocean): the page on the app's Background (`surface`),
// with cards raised on it, and the assistant's name in the heading style.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

void main() {
  testWidgets('the page is the Background colour and the name a heading', (tester) async {
    final theme = RendelRemoteConfig.tryParse(jsonEncode({
      'config': {
        'theme': {
          'surface': '#F7F9FC',
          'onSurface': '#19191A',
          'accent': '#28398E',
          'onAccent': '#FFFFFF',
          'surfaceRaised': '#FFFFFF',
        },
      },
    }))!
        .applyTo(RendelTheme.paper());
    final api = RendelApiClient(appKey: 'rd_pk_test_x', deviceId: 'd', config: const RendelConfig());
    final controller = ConversationController(
      api: api,
      actions: const {},
      sdkVersion: 'flutter/test',
      onOpenUrl: (_) async => true,
    )..messages.add(RendelMessage.user('Do you have this in a larger size?'));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: theme,
        child: Scaffold(body: ThreadScreen(controller: controller, title: 'Asistan')),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    final sheet = tester
        .widgetList<Container>(find.byType(Container))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.borderRadius != null && decoration.color != null);
    expect(sheet.color, const Color(0xFFF7F9FC));

    final name = tester.widget<Text>(find.text('Asistan'));
    expect(name.style?.fontSize, theme.text.heading.fontSize);
    expect(name.style?.fontWeight, theme.text.heading.fontWeight);
  });
}
