import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';

/// One turn, driven end to end through the controller.
///
/// Every other test in this suite pushes fixtures straight into `messages`,
/// which is why a `_notify()` that recursed into itself shipped: the streaming
/// path was never entered. This drives the real `_run` loop over a scripted
/// event stream.
class _ScriptedApi extends RendelApiClient {
  _ScriptedApi(this.script, {this.gapBetweenEvents = Duration.zero})
      : super(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
        );

  final List<RendelWireEvent> script;

  /// Real time between events, so a test can outlast an idle timeout.
  final Duration gapBetweenEvents;

  final List<Map<String, dynamic>> sent = [];

  /// Held open before the event at this index, so a test can act on a turn
  /// while it is genuinely mid-flight rather than after it.
  int? pauseBefore;
  final paused = Completer<void>();
  final resume = Completer<void>();

  @override
  Stream<RendelWireEvent> chat(Map<String, dynamic> body) async* {
    sent.add(body);
    for (var i = 0; i < script.length; i++) {
      if (gapBetweenEvents > Duration.zero) {
        await Future<void>.delayed(gapBetweenEvents);
      }
      if (i == pauseBefore) {
        paused.complete();
        await resume.future;
      }
      yield script[i];
    }
  }
}

void main() {
  ConversationController build(List<RendelWireEvent> script) => ConversationController(
        api: _ScriptedApi(script),
        actions: const {},
        sdkVersion: 'flutter/test',
      );

  WireBlock ready(String id, String type, Map<String, dynamic> props) =>
      WireBlock(id: id, type: type, fallbackText: 'A $type block.', props: props)
        ..ready = true;

  test('a streamed turn lands a message without recursing or hanging', () async {
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      const BlockDelta(index: 0, textDelta: 'Order 1042 '),
      const BlockDelta(index: 0, textDelta: 'is out for delivery.'),
      BlockReady(
        index: 0,
        block: ready('b0', 'text', {'markdown': 'Order 1042 is out for delivery.'}),
      ),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    await c.send('Where is order 1042?').timeout(const Duration(seconds: 5));

    expect(c.conversationId, 'c1');
    expect(c.messages.length, 2, reason: 'the user turn and the answer');
    expect(c.messages.last.blocks.single.props['markdown'],
        'Order 1042 is out for delivery.');
    expect(c.busy, isFalse);
    expect(c.phase, RendelPhase.idle);
    expect(c.errorText, isNull);
    c.dispose();
  });

  test('the controller notifies, and structure stays quiet for tokens', () async {
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      const BlockDelta(index: 0, textDelta: 'one '),
      const BlockDelta(index: 0, textDelta: 'two '),
      const BlockDelta(index: 0, textDelta: 'three'),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    var controllerTicks = 0;
    var structureTicks = 0;
    c.addListener(() => controllerTicks++);
    c.structure.addListener(() => structureTicks++);

    await c.send('hi').timeout(const Duration(seconds: 5));

    // The scroll-follow rides the controller, so it must hear every token.
    expect(controllerTicks, greaterThanOrEqualTo(3),
        reason: 'the live edge has to be trackable');
    // The list, the composer and the header ride `structure`, so three tokens
    // must not rebuild them three times.
    expect(structureTicks, lessThan(controllerTicks),
        reason: 'tokens must not tick the thread shape');
    c.dispose();
  });

  test('a form submission posts the form_submission shape', () async {
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      BlockReady(
        index: 0,
        block: ready('b0', 'text', {'markdown': 'Return started.'}),
      ),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    final outcome = await c
        .submitForm('return_request', {'order_id': '1042', 'pairs': 2, 'box': true})
        .timeout(const Duration(seconds: 5));

    expect(outcome, RendelSubmitOutcome.sent);
    final body = (c.api as _ScriptedApi).sent.single;
    expect(body['form_submission'], {
      'form_id': 'return_request',
      'values': {'order_id': '1042', 'pairs': 2, 'box': true},
    });
    // Exactly one of message | form_submission | tool_results.
    expect(body.containsKey('message'), isFalse);
    expect(body.containsKey('tool_results'), isFalse);
    c.dispose();
  });

  test('an error event surfaces as a retryable error', () async {
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const RendelError(code: 'model_busy', message: 'Busy.', retryable: true),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    await c.send('hi').timeout(const Duration(seconds: 5));

    expect(c.errorText, 'Busy.');
    expect(c.canRetry, isTrue, reason: 'the thread offers one tap to try again');
    expect(c.busy, isFalse);
    c.dispose();
  });

  test('a block announced but never completed is settled, not left pulsing',
      () async {
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'receipt'),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    await c.send('hi').timeout(const Duration(seconds: 5));

    final block = c.messages.last.blocks.single;
    expect(block.ready, isTrue,
        reason: 'an unfinished block must stop being a skeleton');
    c.dispose();
  });

  test('a turn that produces nothing is an error, not silence', () async {
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    await c.send('Where is order 1042?').timeout(const Duration(seconds: 5));

    // Without this the working row simply vanishes and the thread sits there,
    // identical to a turn still thinking, with nothing to retry.
    expect(c.errorText, isNotNull);
    expect(c.canRetry, isTrue);
    expect(c.busy, isFalse);
    // The empty assistant turn is still pruned: an error bar and an empty
    // bubble would both be saying the same thing.
    expect(c.messages.where((m) => m.role == 'assistant'), isEmpty);
    c.dispose();
  });

  test('a reset mid-turn does not leave the stream writing into nothing',
      () async {
    final api = _ScriptedApi([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      const BlockDelta(index: 0, textDelta: 'Order 1042 '),
      BlockReady(
        index: 0,
        block: ready('b0', 'text', {'markdown': 'Order 1042 is out.'}),
      ),
      const TurnEnd(status: 'completed', pending: []),
    ])
      ..pauseBefore = 2;
    final c = ConversationController(
      api: api,
      actions: const {},
      sdkVersion: 'flutter/test',
    );

    final turn = c.send('Where is order 1042?');
    await api.paused.future.timeout(const Duration(seconds: 5));

    // Logout, mid-answer. Every message the stream was writing into is gone.
    c.reset();
    api.resume.complete();
    await turn.timeout(const Duration(seconds: 5));

    // The turn abandons itself rather than dereferencing what reset cleared,
    // and it must not resurrect the thread it was told to drop.
    expect(c.messages, isEmpty);
    expect(c.errorText, isNull, reason: 'a reset is not a failure');
    c.dispose();
  });

  test('silence past the idle timeout still ends the turn', () async {
    final c = ConversationController(
      api: _ScriptedApi(const [
        TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
        BlockStart(index: 0, id: 'b0', blockType: 'text'),
      ], gapBetweenEvents: const Duration(milliseconds: 300)),
      actions: const {},
      sdkVersion: 'flutter/test',
      streamIdleTimeout: const Duration(milliseconds: 100),
    );

    await c.send('Something hard').timeout(const Duration(seconds: 5));

    expect(c.errorText, 'The assistant stopped responding.');
    expect(c.errorCode, 'copilot_stalled');
    c.dispose();
  });

  test('a retry carries the same turn_id, so the server can dedupe it',
      () async {
    // `model_busy` and a dropped stream are both raised after the server has
    // persisted the user's message, and the error bar offers exactly one
    // control. Without an idempotency key, that one tap wrote the user's own
    // words into their history a second time and billed the app for it.
    final api = _ScriptedApi([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const RendelError(
        code: 'model_busy',
        message: 'The assistant is busy.',
        retryable: true,
      ),
    ]);
    final c = ConversationController(
      api: api,
      actions: const {},
      sdkVersion: 'flutter/test',
      autoRetryDelay: Duration.zero,
    );

    await c.send('Where is order 1042?').timeout(const Duration(seconds: 5));
    expect(c.canRetry, isTrue);
    await c.retry().timeout(const Duration(seconds: 5));

    // A busy model is also tried once by itself on each attempt (busy_retry_test),
    // so there are four requests here: every one carries the same turn id.
    expect(api.sent, hasLength(4));
    final first = api.sent[0]['turn_id'];
    expect(first, isA<String>());
    for (final body in api.sent) {
      expect(body['turn_id'], first);
    }
    c.dispose();
  });

  test('a new turn mints a new turn_id', () async {
    final api = _ScriptedApi([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      BlockReady(index: 0, block: ready('b0', 'text', {'markdown': 'ok'})),
      const TurnEnd(status: 'completed', pending: []),
    ]);
    final c = ConversationController(
      api: api,
      actions: const {},
      sdkVersion: 'flutter/test',
    );

    await c.send('one').timeout(const Duration(seconds: 5));
    await c.send('two').timeout(const Duration(seconds: 5));

    expect(api.sent[0]['turn_id'], isNot(api.sent[1]['turn_id']));
    c.dispose();
  });

  test('a stream that stops mid-turn is reported, not presented as done',
      () async {
    // No exception, no timeout: the bytes simply end. Half an answer used to
    // land with no error bar and no retry, and the action the turn announced
    // was never run.
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      BlockReady(
        index: 0,
        block: ready('b0', 'text', {'markdown': 'Let me check that.'}),
      ),
    ]);

    await c.send('Where is order 1042?').timeout(const Duration(seconds: 5));

    expect(c.errorText, 'The connection dropped before the answer finished.');
    expect(c.errorCode, 'stream_dropped');
    expect(c.canRetry, isTrue);
    expect(c.busy, isFalse);
    c.dispose();
  });

  test('a turn that ends with status error says so', () async {
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      BlockReady(index: 0, block: ready('b0', 'text', {'markdown': 'Half.'})),
      const TurnEnd(status: 'error', pending: []),
    ]);

    await c.send('Where is order 1042?').timeout(const Duration(seconds: 5));

    expect(c.errorText, isNotNull);
    expect(c.canRetry, isTrue);
    c.dispose();
  });

  test('a repeated wire index adds to the turn, never deletes from it',
      () async {
    // A server-side correction round could re-issue an index whose block.ready
    // had already reached the client. Keying by index and replacing in place
    // then deleted content the user had already read.
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      BlockReady(index: 0, block: ready('b0', 'text', {'markdown': 'First.'})),
      BlockReady(index: 0, block: ready('b1', 'text', {'markdown': 'Second.'})),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    await c.send('hello').timeout(const Duration(seconds: 5));

    final turn = c.messages.firstWhere((m) => m.role == 'assistant');
    expect(
      turn.blocks.map((b) => b.id),
      ['b0', 'b1'],
      reason: 'the settled block was overwritten',
    );
    c.dispose();
  });

  test('asking something else abandons an open confirm card', () async {
    // The server closes the invocation when a new message arrives, so the card
    // is dead whatever the SDK draws. Leaving it live parked the phase for the
    // rest of the session and let a later tap run a destructive handler whose
    // result nothing would accept.
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'text'),
      BlockReady(index: 0, block: ready('b0', 'text', {'markdown': 'Sure.'})),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    final open = ready('b_card', 'confirm_card', {
      'invocation_id': 'inv_1',
      'summary': 'Cancel order 1042?',
      'risk': 'destructive',
      'params': {'order_id': '1042'},
      'params_display': <Map<String, dynamic>>[],
      'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
      'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
    });
    c.messages.add(RendelMessage.assistant()..blocks.add(open));

    await c.send('actually, where is order 1039?')
        .timeout(const Duration(seconds: 5));

    expect(open.props[RendelLocalKeys.resolved], 'abandoned');
    expect(c.phase, RendelPhase.idle);
    // And it cannot be confirmed after the fact.
    expect(await c.confirmInvocation('inv_1'), isFalse);
    c.dispose();
  });

  test('a lost terminator over a confirm card does not offer a retry',
      () async {
    // The turn succeeded; only `turn.end` was lost. Re-sending the message
    // hands the server an unanswered `tool_use` — a hard failure, or a second
    // invocation for the same action that no later turn can reach. The card is
    // the next move.
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b_card', blockType: 'confirm_card'),
      BlockReady(
        index: 0,
        block: ready('b_card', 'confirm_card', {
          'invocation_id': 'inv_1',
          'summary': 'Cancel order 1042?',
          'risk': 'destructive',
          'params': {'order_id': '1042'},
          'params_display': <Map<String, dynamic>>[],
          'confirm': {'kind': 'confirm', 'invocation_id': 'inv_1'},
          'cancel': {'kind': 'cancel', 'invocation_id': 'inv_1'},
        }),
      ),
    ]);

    await c.send('cancel order 1042').timeout(const Duration(seconds: 5));

    expect(c.errorText, isNotNull, reason: 'the drop is still reported');
    expect(c.phase, RendelPhase.awaitingConfirmation);
    expect(c.canRetry, isFalse, reason: 'the card is the next move');
    c.dispose();
  });

  test('a block announced and never hydrated settles as its own sentence',
      () async {
    // Marking it ready sent it past its skeleton into the real builder with
    // empty props, which drew a blank plate inside a turn that presented as a
    // clean success.
    final c = build([
      const TurnStart(conversationId: 'c1', messageId: 'm1', model: 'test'),
      const BlockStart(index: 0, id: 'b0', blockType: 'receipt'),
      const TurnEnd(status: 'completed', pending: []),
    ]);

    await c.send('what did I pay?').timeout(const Duration(seconds: 5));

    // `block.start` carries no fallback, so there is nothing to say in its
    // place: the block is dropped, the empty turn is pruned, and the user is
    // told the assistant did not answer rather than shown a blank plate.
    expect(c.messages.where((m) => m.role == 'assistant'), isEmpty);
    expect(c.errorText, isNotNull);
    c.dispose();
  });
}
