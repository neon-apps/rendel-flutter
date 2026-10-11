import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/protocol/protocol.dart';

/// Cross-language golden: the expected values were produced by the server's
/// TypeScript `canonicalize`/`hashManifest` (packages/protocol). If this test
/// fails, SDK and server hashes have drifted and manifest sync will loop.
void main() {
  RendelAction action({
    required String name,
    required String description,
    required RendelSchema params,
    required RendelRisk risk,
    String? confirmTemplate,
  }) =>
      RendelAction(
        name: name,
        description: description,
        params: params,
        risk: risk,
        confirmTemplate: confirmTemplate,
        handler: (_) async => RendelResult.ok(),
      );

  test('manifest hash matches the TypeScript implementation', () {
    final actions = [
      action(
        name: 'search_products',
        description: 'Search the sneaker catalog by name and optional maximum price.',
        params: RendelSchema.object({
          'query': RendelSchema.string(description: 'Free text, e.g. "running"').orAbsent,
          'max_price': RendelSchema.number(description: 'Upper price bound in USD').orAbsent,
        }),
        risk: RendelRisk.read,
      ),
      action(
        name: 'cancel_order',
        description: 'Cancel an order that has not shipped yet.',
        params: RendelSchema.object({'order_id': RendelSchema.string()}),
        risk: RendelRisk.destructive,
        confirmTemplate: 'Cancel order {order_id}? This cannot be undone.',
      ),
    ];

    final manifest = buildManifest(actions);
    expect(
      canonicalize(manifest).startsWith(
        '{"actions":[{"description":"Cancel an order that has not shipped yet.","inputSch',
      ),
      isTrue,
    );
    expect(
      hashManifest(manifest),
      '0e3f799aa6dfdf8034d57deb371672a550e33905064b85703780394fc7e8ea30',
    );
  });

  test('undoable rides in the manifest only when it is set', () {
    RendelAction place({bool undoable = false}) => RendelAction(
          name: 'place_cart_order',
          description: 'Order the cart.',
          params: RendelSchema.object({}),
          risk: RendelRisk.destructive,
          undoable: undoable,
          handler: (_) async => RendelResult.ok(),
        );
    Map nc(Map<String, dynamic> m) => ((m['actions'] as List).single as Map)['nc'] as Map;
    expect(nc(buildManifest([place(undoable: true)]))['undoable'], isTrue);
    // Absent, not false: a build that never sets it keeps the hash it had.
    expect(nc(buildManifest([place()])).containsKey('undoable'), isFalse);
  });

  test('editable rides in the manifest only when it names something', () {
    RendelAction add({List<String> editable = const []}) => RendelAction(
          name: 'add_to_cart',
          description: 'Put a product in the cart.',
          params: RendelSchema.object({}),
          risk: RendelRisk.write,
          editable: editable,
          handler: (_) async => RendelResult.ok(),
        );
    Map nc(Map<String, dynamic> m) => ((m['actions'] as List).single as Map)['nc'] as Map;
    expect(nc(buildManifest([add(editable: ['quantity'])]))['editable'], ['quantity']);
    expect(nc(buildManifest([add()])).containsKey('editable'), isFalse);
  });

  test('canonicalize sorts keys and drops nulls', () {
    expect(
      canonicalize({'b': 1, 'a': {'d': null, 'c': [2, 1]}}),
      '{"a":{"c":[2,1]},"b":1}',
    );
  });
}
