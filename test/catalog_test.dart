import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/protocol/protocol.dart';

/// The catalog is declared in three places and has to be identical in all of
/// them: `CATALOG_BLOCK_TYPES` in packages/protocol, `supportedComponents` in
/// this SDK's handshake, and the builder map in the component registry.
///
/// Drift between the first two is not a rendering bug, it is a hard failure:
/// `clientHandshake.components` is a strict enum, so one unknown string fails
/// validation of the entire request. Drift between the last two is worse in a
/// quieter way — the server offers the model a component this build then draws
/// as fallback text.
///
/// The generated artifact is the source of truth here rather than a list typed
/// out again, because a list typed out again is a fourth place to drift.
void main() {
  final artifact = File('../../../packages/protocol/schemas/catalog.json');

  test('catalog.json is present', () {
    expect(
      artifact.existsSync(),
      isTrue,
      reason:
          'Expected ${artifact.absolute.path}. Run `pnpm gen:schemas` from the '
          'repository root; these tests run from inside the monorepo.',
    );
  });

  test('the protocol version is the same integer on both sides', () {
    final catalog = jsonDecode(artifact.readAsStringSync()) as Map<String, dynamic>;
    expect(
      protocolVersion,
      catalog['protocol'],
      reason: 'The handshake sends `protocol` and the server matches it with '
          'z.literal. Drifting apart fails every request at runtime with a '
          'validation error that names neither file.',
    );
  });

  test('supportedComponents matches the protocol catalog exactly', () {
    final catalog = jsonDecode(artifact.readAsStringSync()) as Map<String, dynamic>;
    final declared = (catalog['all_types'] as List).cast<String>().toSet();
    final supported = supportedComponents.toSet();

    expect(
      supported.difference(declared),
      isEmpty,
      reason: 'Declared in the handshake but absent from the protocol catalog. '
          'The server rejects the whole request on one unknown component.',
    );
    expect(
      declared.difference(supported),
      isEmpty,
      reason: 'In the protocol catalog but not declared by this SDK. Add it to '
          'supportedComponents once it has a renderer.',
    );
  });

  test('every declared component has a renderer, and vice versa', () {
    final supported = supportedComponents.toSet();
    final registered = ComponentRegistry.registeredTypes.toSet();

    expect(
      supported.difference(registered),
      isEmpty,
      reason: 'Declared in the handshake with no builder: the model would be '
          'offered a component this build draws as fallback text.',
    );
    expect(
      registered.difference(supported),
      isEmpty,
      reason: 'Has a builder but is not declared, so the model is never '
          'offered it and the renderer is dead code.',
    );
  });

  test('the Dart catalog version matches the protocol', () {
    final catalog = jsonDecode(artifact.readAsStringSync()) as Map<String, dynamic>;
    expect(catalogVersion, catalog['catalog_version']);
  });

  test('supportedComponents has no duplicates', () {
    expect(supportedComponents.toSet().length, supportedComponents.length);
  });

  test('the icon list in the docs and the catalog matches the map', () {
    // `infoCardIconNames` says it exists so these cannot drift, which was only
    // true once something read it. A substring check is not that something: a
    // panel lens deleted both lists and 5 of 28 names still "passed", because
    // `info`, `order`, `truck`, `card` and `lock` are ordinary words on that
    // page. This parses the two lists and compares the sets.
    final docs = File(
      '../../../apps/web/content/docs/reference/components/info-card.mdx',
    );
    final catalog = File('../../../packages/protocol/src/catalog.ts');
    expect(
      docs.existsSync() && catalog.existsSync(),
      isTrue,
      reason: 'these tests run from inside the monorepo',
    );

    final expected = infoCardIconNames.toSet();

    // The fenced block on the docs page: names separated by middots. Some
    // names have an underscore (`map_pin`).
    final fence = RegExp(r'```\n([a-z_ \u00b7\n]+)\n```')
        .firstMatch(docs.readAsStringSync());
    expect(fence, isNotNull, reason: 'no icon fence on info-card.mdx');
    final fromDocs = fence!
        .group(1)!
        .split(RegExp(r'[\u00b7\n]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toSet();
    expect(fromDocs, expected, reason: 'info-card.mdx has drifted');

    // The model-facing sentence: "must be one of: a, b, c. Omit it".
    final sentence = RegExp(r'must be one of: ([^.]+)\. Omit')
        .firstMatch(catalog.readAsStringSync().replaceAll(RegExp(r'"\s*\+\s*\n\s*"'), ''));
    expect(sentence, isNotNull, reason: 'no icon sentence in catalog.ts');
    final fromCatalog = sentence!
        .group(1)!
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toSet();
    expect(fromCatalog, expected, reason: 'catalog.ts has drifted');
  });
}
