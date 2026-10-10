import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:neon_kicks/gallery.dart';

// The SDK's own check against packages/protocol's wire schema.
import '../../test/wire_schema.dart';

/// The gallery is the only place a developer can see the whole catalog without
/// talking the model into emitting it, so a type with no fixture is a type
/// nobody reviews. This is the check that keeps the two in step.
void main() {
  test('every registered block type has a gallery fixture', () {
    final shown = {for (final entry in galleryFixtures()) entry.$2.type};
    final registered = ComponentRegistry.registeredTypes.toSet();

    expect(
      registered.difference(shown),
      isEmpty,
      reason: 'Renderable but absent from the gallery, so unreviewable.',
    );
  });

  test('fixtures carry a fallback_text and an id', () {
    for (final (label, block) in galleryFixtures()) {
      expect(block.fallbackText, isNotEmpty, reason: '$label has no fallback');
      expect(block.id, isNotEmpty, reason: '$label has no id');
    }
  });

  test('every fixture is one the server could send', () {
    for (final (label, block) in galleryFixtures()) {
      // The one fixture that exists to be a type the protocol lacks.
      if (!ComponentRegistry.registeredTypes.contains(block.type)) continue;
      expect(
        wireBlockErrors({
          'id': block.id,
          'type': block.type,
          'fallback_text': block.fallbackText,
          'props': block.props,
        }),
        isEmpty,
        reason: label,
      );
    }
  });

  test('fixture ids are unique, so BlockEnter keys cannot collide', () {
    final ids = [for (final entry in galleryFixtures()) entry.$2.id];
    expect(ids.toSet().length, ids.length);
  });
}
