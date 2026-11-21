// A live key before Go live (QA 2026-11-20 B4): the server serves it as the test key (f6ac3e5c3), so the
// team's page says what a test key's does, that the address is saved and no email goes, instead of asking
// for a code that never comes.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/support_sheet.dart';

const _liveKey = 'nc_pk_live_example_000000000000000000000000';
const _thread = '00000000-0000-4000-8000-000000000001';

MockClient _client(String channel) => MockClient.streaming((request, body) async {
      final path = request.url.path;
      await body.drain<void>();
      http.StreamedResponse json(Object value) =>
          http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), 200, headers: {'content-type': 'application/json'});
      if (path == '/v1/apps/config') {
        return json({'channel': channel, 'version': null, 'updated_at': null, 'config': <String, Object>{}, 'support': {'enabled': true, 'team': 'Grove'}});
      }
      if (path == '/v1/support/unread') return json({'unread': 0});
      if (path == '/v1/support/current') {
        return json({
          'thread_id': _thread,
          'conversation_id': 'c1',
          'state': {'thread_id': _thread, 'mode': 'waiting', 'state': 'open', 'team_here': false, 'team_read_seq': 0, 'user_read_seq': 1, 'last_seq': 1, 'contact': {'state': 'not_needed', 'required': false}},
          'entries': <Object>[],
        });
      }
      if (path == '/v1/support/threads') return json({'threads': <Object>[]});
      if (path.endsWith('/stream')) return http.StreamedResponse(StreamController<List<int>>().stream, 200);
      return json({'ok': true});
    });

Future<bool> _sheetSandbox(WidgetTester tester, String channel) async {
  await tester.runAsync(() async {
    await Rendel.init(appKey: _liveKey, config: RendelConfig(httpClient: _client(channel)));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
    context = c;
    return const Scaffold(body: Text('the app'));
  })));
  unawaited(Rendel.openSupport(context));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return tester.widget<RendelSupportSheet>(find.byType(RendelSupportSheet)).sandbox;
}

void main() {
  tearDown(Rendel.resetForTest);

  testWidgets("a live key the server serves as the test key opens the team's page as a test key's", (tester) async {
    expect(await _sheetSandbox(tester, 'draft'), isTrue);
  });

  testWidgets("a live key after Go live opens it as a live one's", (tester) async {
    expect(await _sheetSandbox(tester, 'published'), isFalse);
  });
}
