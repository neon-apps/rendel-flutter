// `Rendel.changes`: a write the server carried out for the person is said to
// the app, so it can refresh what it holds of its own data. The server's
// `action.done` frame says it; an Undo the server ran says it again with
// `undone`. A frame this build does not know is dropped, as before.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rendel/rendel.dart';
import 'package:rendel/src/engine/conversation_controller.dart';
import 'package:rendel/src/protocol/protocol.dart';
import 'package:rendel/src/transport/api_client.dart';

void main() {
  ConversationController controller(http.BaseClient server, void Function(RendelChange) onChange) => ConversationController(
        api: RendelApiClient(
          appKey: 'nc_pk_test_x',
          deviceId: 'd',
          config: const RendelConfig(),
          httpClient: server,
        ),
        actions: const {},
        sdkVersion: 'flutter/test',
        onChange: onChange,
      );

  test('the frame is parsed with its name, risk and the values the card showed', () {
    final event = RendelWireEvent.tryParse('action.done', {
      'invocation_id': 'i1',
      'name': 'add_to_list',
      'risk': 'write',
      'params': {'list_id': '91', 'product_id': 'p1'},
    });
    expect(event, isA<ActionDone>());
    final done = event! as ActionDone;
    expect(done.name, 'add_to_list');
    expect(done.risk, 'write');
    expect(done.params, {'list_id': '91', 'product_id': 'p1'});
    expect(RendelWireEvent.tryParse('action.done', {'name': 'x'}), isNull);
    expect(RendelWireEvent.tryParse('action.wished', {'name': 'x'}), isNull);
  });

  test('a write the server made is handed to the app, and the answer still draws', () async {
    final changes = <RendelChange>[];
    final server = _Server([
      {'type': 'action.done', 'invocation_id': 'i1', 'name': 'add_to_list', 'risk': 'write', 'params': {'list_id': '91'}},
      {
        'type': 'block.ready',
        'index': 0,
        'block': {'id': 'b0', 'type': 'text', 'fallback_text': 'Saved.', 'props': {'markdown': 'Saved.'}},
      },
    ]);
    final c = controller(server, changes.add);

    await c.send('save it');

    expect(changes.map((change) => change.action), ['add_to_list']);
    expect(changes.single.params, {'list_id': '91'});
    expect(changes.single.undone, isFalse);
    expect(c.messages.last.blocks.single.type, 'text');
    c.dispose();
  });

  test('an undo the server ran is said again, undone', () async {
    final changes = <RendelChange>[];
    final server = _Server([], undo: {'state': 'undone'});
    final c = controller(server, changes.add);
    await c.send('add it');
    final block = WireBlock(
      id: 'b0',
      type: 'action_done',
      fallbackText: 'Added',
      props: {
        'invocation_id': 'inv-1',
        'action_name': 'add_to_cart',
        'text': 'Added',
        'undo_until': DateTime.now().add(const Duration(minutes: 1)).toIso8601String(),
      },
    );

    expect(await c.undoAction(block), 'undone');

    expect(changes.single.action, 'add_to_cart');
    expect(changes.single.undone, isTrue);
    c.dispose();
  });
}

class _Server extends http.BaseClient {
  _Server(this.frames, {this.undo});

  final List<Map<String, dynamic>> frames;
  final Map<String, dynamic>? undo;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/undo')) {
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(undo ?? {'state': 'failed'}))), 200);
    }
    var seq = 0;
    String frame(Map<String, dynamic> data) =>
        'event: ${data['type']}\ndata: ${jsonEncode({'v': 1, 'seq': seq++, ...data})}\n\n';
    final sse = StringBuffer(frame({'type': 'turn.start', 'conversation_id': 'c1', 'message_id': 'm1', 'model': 'test'}));
    frames.forEach((data) => sse.write(frame(data)));
    sse.write(frame({'type': 'turn.end', 'status': 'completed', 'pending': <String>[]}));
    return http.StreamedResponse(Stream.value(utf8.encode(sse.toString())), 200);
  }
}
