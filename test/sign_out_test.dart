// A sign-out reaches the server, and another person's sign-in leaves nothing
// of the last one's (security audit NV-27). The device id outlives a logout,
// so a phone still bound to who signed out served the next person their
// follow-ups, inbox and push.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/followups.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';

const _card = RendelFollowup(id: 'f-1', type: 'watch', title: 'For Ayşe', body: 'B', button: 'Open');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Rendel.resetForTest);

  Future<List<http.Request>> started() async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{"ok":true}', 200);
    });
    await Rendel.init(appKey: _key, config: RendelConfig(httpClient: client, remoteConfig: false));
    return requests;
  }

  test('reset tells the server this device is nobody now, as the device', () async {
    final requests = await started();
    await Rendel.identify(userId: 'ayse');
    Rendel.reset();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final signOut = requests.where((r) => r.url.path.endsWith('/v1/identify/reset')).toList();
    expect(signOut, hasLength(1));
    expect(signOut.single.method, 'POST');
    expect(signOut.single.headers['X-Rendel-Device'], isNotEmpty,
        reason: 'the server unbinds the device it is told about, and no other');
  });

  test("another person's sign-in drops the last one's follow-ups", () async {
    await started();
    await Rendel.identify(userId: 'ayse');
    RendelFollowups.instance.setInbox(const [_card]);
    expect(RendelFollowups.instance.cards.value, hasLength(1));

    // The same person again keeps them.
    await Rendel.identify(userId: 'ayse');
    expect(RendelFollowups.instance.cards.value, hasLength(1));

    await Rendel.identify(userId: 'mehmet');
    expect(RendelFollowups.instance.cards.value, isEmpty);
  });
}
