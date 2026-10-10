import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

/// The public surface frozen by publication. Each of these was a real gap the
/// readiness review named, so each gets an assertion rather than a comment.
void main() {
  group('RendelAction names', () {
    test('accepts snake_case', () {
      expect(
        () => RendelAction(
          name: 'get_order_status',
          description: 'x',
          params: RendelSchema.object({}),
          risk: RendelRisk.read,
          handler: (_) async => RendelResult.ok(),
        ),
        returnsNormally,
      );
    });

    test('rejects camelCase at the line that wrote it', () {
      // Without this the server rejects the whole manifest, the SDK logs it
      // and carries on, and every later turn fails with `manifest_unknown`
      // telling the developer to retry, which can never work.
      expect(
        () => RendelAction(
          name: 'getOrderStatus',
          description: 'x',
          params: RendelSchema.object({}),
          risk: RendelRisk.read,
          handler: (_) async => RendelResult.ok(),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a name starting with a digit or carrying a dash', () {
      for (final bad in ['1st_action', 'get-order', 'Get_order', '_hidden']) {
        expect(
          () => RendelAction(
            name: bad,
            description: 'x',
            params: RendelSchema.object({}),
            risk: RendelRisk.read,
            handler: (_) async => RendelResult.ok(),
          ),
          throwsA(isA<AssertionError>()),
          reason: '"$bad" should be refused',
        );
      }
    });

    test('needs one of the two handlers', () {
      expect(
        () => RendelAction(
          name: 'orphan',
          description: 'x',
          params: RendelSchema.object({}),
          risk: RendelRisk.read,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('timeout', () {
    test('is a Duration, and still serializes as milliseconds', () {
      final action = RendelAction(
        name: 'slow_one',
        description: 'x',
        params: RendelSchema.object({}),
        risk: RendelRisk.read,
        timeout: const Duration(seconds: 30),
        handler: (_) async => RendelResult.ok(),
      );
      expect(action.timeout, const Duration(seconds: 30));
      expect(action.timeoutMs, 30000);
    });

    test('defaults to fifteen seconds', () {
      final action = RendelAction(
        name: 'default_one',
        description: 'x',
        params: RendelSchema.object({}),
        risk: RendelRisk.read,
        handler: (_) async => RendelResult.ok(),
      );
      expect(action.timeoutMs, 15000);
    });
  });

  group('run', () {
    test('a plain handler receives the parameters', () async {
      Map<String, dynamic>? seen;
      final action = RendelAction(
        name: 'plain',
        description: 'x',
        params: RendelSchema.object({}),
        risk: RendelRisk.read,
        handler: (params) async {
          seen = params;
          return RendelResult.ok();
        },
      );
      await action.run(const RendelInvocation(
        id: 'inv_1',
        name: 'plain',
        params: {'order_id': '1042'},
        risk: RendelRisk.read,
      ));
      expect(seen, {'order_id': '1042'});
    });

    test('onInvoke receives the id, which is the idempotency key', () async {
      String? seenId;
      final action = RendelAction(
        name: 'idempotent',
        description: 'x',
        params: RendelSchema.object({}),
        risk: RendelRisk.destructive,
        onInvoke: (invocation) async {
          seenId = invocation.id;
          return RendelResult.ok();
        },
      );
      await action.run(const RendelInvocation(
        id: 'inv_7',
        name: 'idempotent',
        params: {},
        risk: RendelRisk.destructive,
      ));
      expect(seenId, 'inv_7');
    });
  });

  group('RendelSchema', () {
    test('list declares an array of its item type', () {
      final schema = RendelSchema.list(RendelSchema.string(), minItems: 1).toJson();
      expect(schema['type'], 'array');
      expect((schema['items'] as Map)['type'], 'string');
      expect(schema['minItems'], 1);
    });

    test('raw passes a hand-written schema through untouched', () {
      final schema = RendelSchema.raw({'oneOf': [], 'title': 'custom'}).toJson();
      expect(schema['title'], 'custom');
    });

    test('optional and orAbsent mean the same thing', () {
      final viaNew = RendelSchema.object({
        'required_one': RendelSchema.string(),
        'other': RendelSchema.string().optional,
      }).toJson();
      final viaOld = RendelSchema.object({
        'required_one': RendelSchema.string(),
        'other': RendelSchema.string().orAbsent,
      }).toJson();
      expect(viaNew['required'], ['required_one']);
      expect(viaOld['required'], ['required_one']);
    });

    test('a list can be a parameter', () {
      final schema = RendelSchema.object({
        'ids': RendelSchema.list(RendelSchema.string()),
      }).toJson();
      final properties = schema['properties'] as Map;
      expect((properties['ids'] as Map)['type'], 'array');
    });
  });
}
