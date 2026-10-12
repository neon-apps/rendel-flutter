// analytics-roi T1 (answer thumbs) and T3 (contact taps): what the SDK
// sends, and never more.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Launcher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => true;

  @override
  Future<bool> canLaunch(String url) async => true;
}

class _Api extends RendelApiClient {
  _Api() : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final List<Map<String, dynamic>> sent = [];
  final List<Map<String, dynamic>> feedback = [];
  final List<Map<String, dynamic>> events = [];
  StreamController<RendelWireEvent>? _turn;

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) {
    sent.add(body);
    _turn = StreamController<RendelWireEvent>();
    return _turn!.stream;
  }

  @override
  Future<bool> sendFeedback(Map<String, dynamic> body) async {
    feedback.add(body);
    return true;
  }

  @override
  Future<void> sendEvent(Map<String, dynamic> event) async => events.add(event);

  Future<void> answer(WidgetTester tester, List<WireBlock> blocks) async {
    await tester.runAsync(() async {
      for (final event in [
        TurnStart(conversationId: 'c1', messageId: 'm${sent.length}', model: 'test'),
        for (var i = 0; i < blocks.length; i++) BlockReady(index: i, block: blocks[i]),
        const TurnEnd(status: 'completed', pending: []),
      ]) {
        _turn!.add(event);
      }
      await _turn!.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
  }
}

WireBlock _block(String type, Map<String, dynamic> props) => WireBlock.tryParse(jsonDecode(jsonEncode({
      'id': 'b_$type',
      'type': type,
      'fallback_text': 'A $type block.',
      'props': props,
    })))!;

void main() {
  setUp(() => UrlLauncherPlatform.instance = _Launcher());

  Future<_Api> answered(WidgetTester tester, WireBlock block, {bool feedback = false}) async {
    final api = _Api();
    final c = ConversationController(api: api, actions: const {}, sdkVersion: 'flutter/test', onOpenUrl: (_) async => true);
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(body: ThreadScreen(controller: c, feedback: feedback)),
      ),
    ));
    await tester.runAsync(() async {
      unawaited(c.send('Help'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await api.answer(tester, [block]);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    return api;
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsLabel(label));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump(const Duration(seconds: 1));
  }

  final sure = _block('text', {'markdown': 'Sure, it ships tomorrow.'});

  group('answer thumbs (T1)', () {
    testWidgets('are off unless the app turns them on', (tester) async {
      await answered(tester, sure);
      expect(find.text('Helpful?'), findsNothing);
    });

    testWidgets('send one rating for the answer, then say thanks', (tester) async {
      final api = await answered(tester, sure, feedback: true);
      expect(find.text('Helpful?'), findsOneWidget);
      await tap(tester, 'Good');
      await tap(tester, 'Not good');
      expect(api.feedback, [
        {'message_id': 'm1', 'rating': 1},
      ]);
      expect(find.text('Thanks for telling us'), findsOneWidget);
    });

    test('are read from the published config', () {
      final remote = RendelRemoteConfig.tryParse(
          '{"channel":"published","version":1,"config":{"copilot":{"feedback":true}}}')!;
      expect(remote.applyToConfig(const RendelConfig()).feedback, isTrue);
      expect(const RendelConfig().feedback, isFalse);
    });
  });

  group('contact taps (T3)', () {
    testWidgets('send the kind of channel, never its address', (tester) async {
      final api = await answered(
        tester,
        _block('contact', {
          'title': 'Talk to us',
          'channels': [
            {'kind': 'url', 'label': 'Open the help centre', 'value': 'https://example.com/help'},
          ],
        }),
      );
      await tap(tester, 'Open the help centre');
      expect(api.events, [
        {'type': 'contact_open', 'message_id': 'm1', 'block_id': 'b_contact', 'channel': 'url'},
      ]);
      expect(jsonEncode(api.events), isNot(contains('example.com')));
    });
  });
}
