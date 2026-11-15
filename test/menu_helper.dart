import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/src/ui/renderer/blocks.dart' show RendelPressable;

/// The panel's look keeps start over and the page steps in the menu behind
/// the round button at the top left: opens it, unless it is open already.
Future<void> openMenu(WidgetTester tester, {String menu = 'Menu', String row = 'Start a new conversation'}) async {
  Finder pressable(String label) => find.byWidgetPredicate((Widget w) => w is RendelPressable && w.semanticLabel == label);
  if (pressable(row).evaluate().isNotEmpty) return;
  await tester.tap(pressable(menu));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
