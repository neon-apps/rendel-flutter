// An identify that did not land is tried again, and a refusal is said once
// (P3-020, Tabak, 14 November): one failed call lost a person's name and
// email for good, and the console showed them by id.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';

const _key = 'nc_pk_test_example_000000000000000000000000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final defaults = Rendel.identifyRetry;
  final records = <RendelLogRecord>[];

  setUp(() {
    Rendel.identifyRetry = List.filled(defaults.length, const Duration(milliseconds: 10));
    records.clear();
  });

  tearDown(() {
    Rendel.resetForTest();
    Rendel.identifyRetry = defaults;
  });

  /// The identify calls the server got. [answers] are its statuses in order,
  /// 0 a network that dropped; past them it answers 200.
  Future<List<http.Request>> started(List<int> answers) async {
    final identifies = <http.Request>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/v1/identify')) {
        identifies.add(request);
        final status = answers.isEmpty ? 200 : answers.removeAt(0);
        if (status == 0) throw http.ClientException('Connection closed');
        return http.Response(
          status == 403
              ? '{"error":{"code":"invalid_request","message":"Identity verification required."}}'
              // 201 here: a 200 that bound nobody, as the server answers an unsigned id on a new install.
              : status == 201
                  ? '{"end_user_id":null,"verified":false,"code":"identify_unsigned","message":"\\"cust_1042\\" was not signed in on this device."}'
                  : '{}',
          status,
        );
      }
      return http.Response('{"ok":true}', 200);
    });
    await Rendel.init(appKey: _key, config: RendelConfig(httpClient: client, remoteConfig: false, onLog: records.add));
    return identifies;
  }

  test('tries again after a busy server and a dropped network', () async {
    final identifies = await started([503, 0]);
    await Rendel.identify(userId: 'zeynep', traits: {'name': 'Zeynep'});
    expect(identifies, hasLength(1), reason: 'the sign-in waits for the first try only');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(identifies, hasLength(3));
    expect(identifies.last.body, contains('Zeynep'));
  });

  test("says a refusal once, with the server's words, and does not ask again", () async {
    final identifies = await started([403]);
    await Rendel.identify(userId: 'zeynep', userHmac: 'wrong');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(identifies, hasLength(1));
    final refused = records.where((r) => r.code == 'identify_refused').toList();
    expect(refused, hasLength(1));
    expect(refused.single.message, contains('Identity verification required.'));
  });

  // Mira, F2348: on another key the same identify was a new install, and the customer silently anonymous.
  test('says an identify that bound nobody, with the server\'s words, and does not ask again', () async {
    final identifies = await started([201]);
    await Rendel.identify(userId: 'cust_1042');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(identifies, hasLength(1));
    final refused = records.where((r) => r.code == 'identify_refused').toList();
    expect(refused, hasLength(1));
    expect(refused.single.message, contains('identify_unsigned'));
    expect(refused.single.message, contains('"cust_1042" was not signed in on this device.'));
  });

  test('stops once the person signs out', () async {
    final identifies = await started([503, 503]);
    await Rendel.identify(userId: 'zeynep');
    Rendel.reset();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(identifies, hasLength(1));
  });

  test('gives up after five tries and says so', () async {
    final identifies = await started([503, 503, 503, 503, 503]);
    await Rendel.identify(userId: 'zeynep');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(identifies, hasLength(5));
    expect(records.any((r) => r.code == 'transport_failed' && r.message.contains('after 5 tries')), isTrue);
  });
}
