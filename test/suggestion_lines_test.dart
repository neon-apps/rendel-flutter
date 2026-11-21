import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

// Helix, 2026-11-21: a suggestion's line could only be given in code; the console keeps it now (Persona › Opening).
void main() {
  test("the console's line under a suggestion is read, at most four, sixty characters each", () {
    final parsed = RendelRemoteConfig.tryParse(
      '{"config":{"copilot":{"suggestions":["My tasks"],"suggestionLines":{"My tasks":"What is due and overdue","Long":"${'x' * 61}"}}}}',
    )!;
    expect(parsed.suggestionLines, {'My tasks': 'What is due and overdue'});
  });

  test("a card is the app's own first, else the suggestion's words over the console's line", () {
    RendelLook.consoleLines = {'My tasks': 'What is due and overdue', 'Projects at risk': 'Late or quiet'};
    RendelLook.suggestionCards = const {'Projects at risk': RendelSuggestionCard(title: 'At risk', line: 'From code')};
    addTearDown(() {
      RendelLook.consoleLines = const {};
      RendelLook.suggestionCards = const {};
    });
    expect(RendelLook.cardFor('My tasks')?.title, 'My tasks');
    expect(RendelLook.cardFor('My tasks')?.line, 'What is due and overdue');
    expect(RendelLook.cardFor('Projects at risk')?.line, 'From code');
    expect(RendelLook.cardFor('Anything else'), isNull);
  });
}
