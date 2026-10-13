// Rendel in the console, P0.2 (BUILD.md's protocol contract), as the web SDK's
// confirm-p02.test.ts: a value typed back before a card confirms, a long text
// read whole with what changes, "suggested after", the new manifest fields,
// parameter titles, and the file name on an upload.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show fullTextPreview, lineDiff, showSuggestedAfter;

class _Api extends RendelApiClient {
  _Api() : super(appKey: 'nc_pk_test_x', deviceId: 'd', config: const RendelConfig());

  final decisions = <List<Object?>>[];
  @override
  Future<String?> recordDecision(String invocationId, {required bool confirm, String? typed}) async {
    decisions.add([invocationId, confirm, typed]);
    return 'typed_mismatch';
  }
}

void main() {
  final actions = <UIAction>[];

  Future<WireBlock> pump(
    WidgetTester tester,
    Map<String, dynamic> extra, {
    Future<String?>? Function(String action, Map<String, dynamic> params)? cardSource,
  }) async {
    actions.clear();
    final block = WireBlock(
      id: 'b_confirm',
      type: 'confirm_card',
      fallbackText: 'Delete Grove?',
      props: {
        'invocation_id': 'i1',
        'action_name': 'delete_app',
        'summary': 'Delete Grove?',
        'risk': 'destructive',
        'params_display': <Map<String, dynamic>>[],
        'params': <String, dynamic>{'app': 'grove'},
        'confirm': {'kind': 'confirm', 'invocation_id': 'i1'},
        'cancel': {'kind': 'cancel', 'invocation_id': 'i1'},
        ...extra,
      },
    )..ready = true;
    final dispatch = RendelDispatcher(
      onAction: (action) async {
        actions.add(action);
        return true;
      },
      onSubmitForm: (_, __) async => RendelSubmitOutcome.sent,
      canHandle: (_) => true,
      cardSource: cardSource,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return block;
  }

  RendelActionButton confirmButton(WidgetTester tester) =>
      tester.widget<RendelActionButton>(find.byWidgetPredicate((w) => w is RendelActionButton && w.danger));

  group('a value typed back', () {
    testWidgets('arms the button only on an exact match, and sends what was typed', (tester) async {
      await pump(tester, {
        'type_to_confirm': {'param': 'app', 'value': 'grove'},
      });
      expect(find.text('Type grove to confirm'), findsOneWidget);
      expect(confirmButton(tester).onTap, isNull);
      await tester.enterText(find.byType(TextField), 'grov');
      await tester.pump();
      expect(confirmButton(tester).onTap, isNull);
      await tester.enterText(find.byType(TextField), ' grove ');
      await tester.pump();
      confirmButton(tester).onTap!();
      await tester.pump();
      final sent = actions.single as ConfirmAction;
      expect(sent.invocationId, 'i1');
      expect(sent.typed, 'grove');
    });

    testWidgets('says so when the server found it did not match', (tester) async {
      await pump(tester, {
        'type_to_confirm': {'param': 'app', 'value': 'grove'},
        RendelLocalKeys.mismatch: true,
      });
      expect(find.text("That doesn't match. Type it exactly as shown."), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'g');
      await tester.pump();
      expect(find.text("That doesn't match. Type it exactly as shown."), findsNothing);
    });
  });

  group('a long text', () {
    final long = List.generate(40, (i) => 'Line ${i + 1} of the persona.').join('\n');

    testWidgets('shows the start, then all of it, and arms once read', (tester) async {
      expect(long.length, greaterThan(fullTextPreview));
      await pump(tester, {
        'risk': 'write',
        'full_text': {'param': 'instructions', 'value': long},
      });
      final button = find.byWidgetPredicate((w) => w is RendelActionButton && w.label == 'Confirm');
      expect(tester.widget<RendelActionButton>(button).onTap, isNull);
      expect(find.text('Read it all to confirm'), findsOneWidget);
      await tester.tap(find.text('Read all (${long.length} characters)'));
      await tester.pump();
      expect(find.text(long), findsOneWidget);
      expect(tester.widget<RendelActionButton>(button).onTap, isNotNull);
    });

    testWidgets('shows what changes, from the text the app hands over', (tester) async {
      Map<String, dynamic>? asked;
      await pump(
        tester,
        {
          'risk': 'write',
          'full_text': {'param': 'instructions', 'value': 'Be brief.\nAnswer in Turkish.'},
        },
        cardSource: (action, params) {
          asked = {'action': action, ...params};
          return Future.value('Be brief.\nAnswer in English.');
        },
      );
      await tester.pump();
      expect(asked, {'action': 'delete_app', 'app': 'grove'});
      expect(find.text('Changes'), findsOneWidget);
      expect(find.text('−  Answer in English.'.replaceFirst('  ', ' ')), findsOneWidget);
      expect(find.text('+ Answer in Turkish.'), findsOneWidget);
    });

    test('diffs by line', () {
      expect(lineDiff('a\nb\nc', 'a\nc\nd'), [('same', 'a'), ('del', 'b'), ('same', 'c'), ('add', 'd')]);
    });
  });

  testWidgets('a card drawn after reading what someone else wrote says so, from the release that switches it on',
      (tester) async {
    await pump(tester, {'suggested_after': 'a knowledge page'});
    expect(find.text('Suggested after reading a knowledge page'), showSuggestedAfter ? findsOneWidget : findsNothing);
  });

  test('the manifest carries the new fields only when set, and parameter titles', () {
    final base = RendelAction(
      name: 'delete_app',
      description: 'Delete an app',
      params: RendelSchema.object({
        'app': RendelSchema.string(title: 'App', titles: {'tr': 'Uygulama'}),
      }),
      risk: RendelRisk.destructive,
      handler: (_) async => RendelResult.ok({}),
    );
    final plain = buildManifest([base]);
    final nc = (plain['actions'] as List).single['nc'] as Map;
    expect(nc.keys.toSet(), {'risk', 'timeoutMs'});
    final props = ((plain['actions'] as List).single['inputSchema'] as Map)['properties'] as Map;
    expect(props['app'], {
      'type': 'string',
      'title': 'App',
      'titles': {'tr': 'Uygulama'},
    });

    final full = buildManifest([
      RendelAction(
        name: 'delete_app',
        description: 'Delete an app',
        params: RendelSchema.object({'app': RendelSchema.string()}),
        risk: RendelRisk.destructive,
        handler: (_) async => RendelResult.ok({}),
        typeToConfirm: 'app',
        fullText: const RendelFullText('app', current: true),
        confirmLabel: 'Delete app',
        confirmLabels: const {'tr': 'Uygulamayı sil'},
      ),
    ]);
    expect((full['actions'] as List).single['nc'], containsPair('typeToConfirm', 'app'));
    expect((full['actions'] as List).single['nc'], containsPair('fullText', {'param': 'app', 'current': true}));
    expect((full['actions'] as List).single['nc'], containsPair('confirmLabel', 'Delete app'));
    expect((full['actions'] as List).single['nc'], containsPair('confirmLabels', {'tr': 'Uygulamayı sil'}));
  });

  test("an upload's file name goes URL-encoded, at most 200 characters", () {
    expect(fileNameHeader('Fatura Ekim.pdf'), 'Fatura%20Ekim.pdf');
    expect(fileNameHeader(null), isNull);
    expect(fileNameHeader('   '), isNull);
    final long = fileNameHeader('${'ş' * 150}.pdf')!;
    expect(long.length, lessThanOrEqualTo(200));
    expect(() => Uri.decodeComponent(long), returnsNormally);
  });

  test('the controller reopens the card when the server refuses what was typed', () async {
    final api = _Api();
    final controller = ConversationController(api: api, actions: const {}, sdkVersion: 'flutter/test');
    addTearDown(controller.dispose);
    final card = WireBlock(
      id: 'b_card',
      type: 'confirm_card',
      fallbackText: 'Delete?',
      props: {
        'invocation_id': 'i1',
        'action_name': 'delete_app',
        'summary': 'Delete Grove?',
        'risk': 'destructive',
        'executes': 'server',
        'params': {'app': 'grove'},
        'params_display': <Map<String, dynamic>>[],
        'type_to_confirm': {'param': 'app', 'value': 'grove'},
        'confirm': {'kind': 'confirm', 'invocation_id': 'i1'},
        'cancel': {'kind': 'cancel', 'invocation_id': 'i1'},
      },
    )..ready = true;
    controller.messages.add(RendelMessage.assistant()..blocks.add(card));

    expect(await controller.confirmInvocation('i1', typed: 'grvoe'), isFalse);
    expect(api.decisions, [
      ['i1', true, 'grvoe'],
    ]);
    expect(card.props[RendelLocalKeys.resolved], isNull);
    expect(card.props[RendelLocalKeys.mismatch], isTrue);
    expect(controller.busy, isFalse);
  });
}
