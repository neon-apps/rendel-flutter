// The point of this file is to use the old names.
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

/// Code written against 0.31, when the package was neon_copilot, has to
/// compile with only its import changed. These are the lines its quickstart
/// told people to write.
void main() {
  test('the old type names are the new types', () {
    expect(NCConfig, RendelConfig);
    expect(NCAction, RendelAction);
    expect(CopilotTheme, RendelTheme);
    expect(CopilotLauncher, RendelLauncher);
    expect(NeonCopilot, Rendel);
  });

  test('the old theme constructors give the new themes', () {
    expect(identical(CopilotTheme.neonDefault(), RendelTheme.paper()), isTrue);
    expect(identical(CopilotTheme.neonDeep(), RendelTheme.deep()), isTrue);
  });

  test('a static through the old name reaches the same SDK', () {
    expect(NeonCopilot.isInitialized, Rendel.isInitialized);
  });
}
