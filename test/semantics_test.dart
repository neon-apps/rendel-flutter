// The semantics tree as the product actually builds it: inside the thread.
//
// Every earlier accessibility check rendered one block into a plain box, and
// in that context the tree is correct for all 21 types. It is wrong in a
// sliver item, which is the only way a block is ever drawn: the delegate wraps
// each item in an `IndexedSemantics` with `container: false`, every
// `Semantics` in the catalog is `container: false` too, and a whole turn
// therefore collapsed into one node. A per-block assertion cannot see that, so
// this suite goes through `ThreadScreen`.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/transport/api_client.dart';
import 'package:rendel/src/ui/thread_screen.dart';

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

  WireBlock block(String type, Map<String, dynamic> props) => WireBlock(
        id: 'b_$type',
        type: type,
        fallbackText: 'A $type block.',
        props: props,
      )..ready = true;

  Future<void> pumpThread(
    WidgetTester tester,
    ConversationController c,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(body: ThreadScreen(controller: c)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// The root of the merged tree.
  ///
  /// `rootPipelineOwner.semanticsOwner` is null in a widget test, so this
  /// still goes through the deprecated accessor; the replacement does not
  /// expose a root here.
  SemanticsNode root(WidgetTester tester) =>
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;

  /// Every label in the merged tree, flattened.
  List<String> labels(SemanticsNode from) {
    final out = <String>[];
    void walk(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.label.isNotEmpty) out.add(data.label);
      node.visitChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(from);
    return out;
  }

  testWidgets('a multi-block turn is many nodes, not one', (tester) async {
    final handle = tester.ensureSemantics();
    final c = controller();
    final turn = RendelMessage.assistant()
      ..blocks.addAll([
        block('text', {'markdown': 'Here is where your order stands.'}),
        block('progress', {
          'items': [
            {'label': 'Photos', 'value': 3, 'max': 10},
          ],
        }),
        block('text', {'markdown': 'Anything else?'}),
      ]);
    c.messages
      ..add(RendelMessage.user('Where is my order?'))
      ..add(turn);

    await pumpThread(tester, c);
    final found = labels(root(tester));

    // Each block names itself. Collapsed, the whole turn came back as one
    // label carrying every sentence in it, with the progress bar's own
    // percentage attached to the lot.
    expect(
      found,
      contains('Here is where your order stands.'),
      reason: 'labels were: $found',
    );
    expect(found, contains('Anything else?'));
    expect(
      found.any((l) =>
          l.contains('Here is where your order stands.') &&
          l.contains('Anything else?')),
      isFalse,
      reason: 'two blocks merged into one label: $found',
    );
    handle.dispose();
    c.dispose();
  });

  testWidgets('prose beside a control does not become the control',
      (tester) async {
    final handle = tester.ensureSemantics();
    final c = controller();
    c.messages.add(RendelMessage.assistant()
      ..blocks.addAll([
        block('text', {'markdown': 'Your order is on the way.'}),
        block('quick_replies', {
          'items': [
            {
              'label': 'Track it',
              'action': {'kind': 'reply', 'text': 'track'},
            },
          ],
        }),
      ]));

    await pumpThread(tester, c);
    final tree = root(tester);

    // The button's label must be the button's label. Merged, the answer's
    // prose became part of it and the button's rect covered the paragraph.
    final buttons = <String>[];
    void walk(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.flagsCollection.isButton) buttons.add(data.label);
      node.visitChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(tree);
    expect(buttons, contains('Track it'), reason: 'buttons were: $buttons');
    expect(
      buttons.any((b) => b.contains('Your order is on the way.')),
      isFalse,
      reason: 'the prose ended up inside a button: $buttons',
    );
    handle.dispose();
    c.dispose();
  });

  testWidgets('a live region announces its own block, not the turn',
      (tester) async {
    final handle = tester.ensureSemantics();
    final c = controller();
    c.messages.add(RendelMessage.assistant()
      ..blocks.addAll([
        block('text', {'markdown': 'I can cancel that for you.'}),
        block('confirm_card', {
          'summary': 'Cancel order 4821?',
          'risk': 'write',
          'params': {'order_id': '4821'},
          'params_display': <Map<String, dynamic>>[],
          'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
          'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
        })
          ..props[RendelLocalKeys.resolved] = 'confirmed',
      ]));

    await pumpThread(tester, c);
    final tree = root(tester);

    String? live;
    void walk(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.flagsCollection.isLiveRegion) live ??= data.label;
      node.visitChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(tree);
    // Hoisted to the turn, VoiceOver re-read the whole answer instead of the
    // one word that changed.
    expect(live, isNotNull);
    expect(
      live,
      isNot(contains('I can cancel that for you.')),
      reason: 'the live region swallowed the prose: $live',
    );
    handle.dispose();
    c.dispose();
  });

  testWidgets('a control never encloses its siblings', (tester) async {
    // `container: true` alone only moved the collapse down a level: an
    // annotation node absorbs every compatible descendant, so `item_list`'s
    // first row came back as a button whose semantics rect covered rows two
    // and three. Touch exploration over row two landed on row one.
    final handle = tester.ensureSemantics();
    final c = controller();
    c.messages.add(RendelMessage.assistant()
      ..blocks.add(block('item_list', {
        'items': [
          for (final name in ['Merino crew', 'Wool socks', 'Cotton tee'])
            {
              'title': name,
              'trailing': '£18.00',
              'action': {'kind': 'reply', 'text': name},
            },
        ],
      })));

    await pumpThread(tester, c);

    final buttons = <SemanticsNode>[];
    void collect(SemanticsNode node) {
      if (node.getSemanticsData().flagsCollection.isButton) buttons.add(node);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(root(tester));
    final rows = buttons
        .where((b) => b.getSemanticsData().label.contains('Merino') ||
            b.getSemanticsData().label.contains('Wool') ||
            b.getSemanticsData().label.contains('Cotton'))
        .toList();
    expect(rows, hasLength(3), reason: 'three rows, three buttons');

    // A row is about 61pt tall; the block is about 185. Collapsed, row one's
    // node was the height of all three, so a tap anywhere in the list fired
    // the first row's action.
    for (final row in rows) {
      expect(
        row.rect.height,
        lessThan(100),
        reason: '"${row.getSemanticsData().label}" is ${row.rect.height}pt '
            'tall, so it covers its siblings',
      );
    }

    handle.dispose();
    c.dispose();
  });

  testWidgets('a live region announces only what changed', (tester) async {
    // The earlier version of this test only checked that the live label did
    // not contain a *different block's* prose, which passed while the label
    // carried the whole card. One word changed; the reader heard everything.
    final handle = tester.ensureSemantics();
    final c = controller();
    c.messages.add(RendelMessage.assistant()
      ..blocks.add(block('confirm_card', {
        'summary': 'Cancel order 4821?',
        'risk': 'write',
        'params': {'order_id': '4821'},
        'params_display': <Map<String, dynamic>>[],
        'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
        'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
      })
        ..props[RendelLocalKeys.resolved] = 'confirmed'));

    await pumpThread(tester, c);

    final live = <String>[];
    void collect(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.flagsCollection.isLiveRegion) live.add(data.label);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(root(tester));
    expect(live, contains('Confirmed'), reason: 'live regions were: $live');
    expect(
      live.any((l) => l.contains('Cancel order 4821?')),
      isFalse,
      reason: 'the live region carried the whole card: $live',
    );
    handle.dispose();
    c.dispose();
  });

  testWidgets('a card\'s button is named for the button, not the card',
      (tester) async {
    // The clearest shape of the collapse: `info_card` came back as one
    // 334x160 BUTTON whose name was the title, the body and the CTA run
    // together, so the reader had no way to reach the control on its own.
    final handle = tester.ensureSemantics();
    final c = controller();
    c.messages.add(RendelMessage.assistant()
      ..blocks.add(block('info_card', {
        'icon': 'truck',
        'title': 'Out for delivery',
        'body': 'Arriving before 6pm today.',
        'cta': {
          'label': 'Track parcel',
          'action': {'kind': 'reply', 'text': 'track'},
        },
      })));

    await pumpThread(tester, c);

    final buttons = <String>[];
    void collect(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.flagsCollection.isButton) buttons.add(data.label);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(root(tester));
    expect(
      buttons,
      contains('Track parcel'),
      reason: 'buttons were: $buttons',
    );
    expect(
      buttons.any((b) => b.contains('Out for delivery')),
      isFalse,
      reason: 'the card swallowed its own button: $buttons',
    );
    handle.dispose();
    c.dispose();
  });
}
