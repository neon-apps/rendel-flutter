import 'dart:async';

/// One value a screen of the app is opened with (`design/NAVIGATE.md`).
///
/// The server checks every `navigate` against these before the block leaves:
/// a param that is not declared, has the wrong type, or is required and
/// missing never reaches [RendelRoute.open].
class RendelRouteParam {
  const RendelRouteParam.string({this.description, this.required = false, this.fromActions = false})
      : type = 'string';

  const RendelRouteParam.number({this.description, this.required = false, this.fromActions = false})
      : type = 'number';

  const RendelRouteParam.boolean({this.description, this.required = false, this.fromActions = false})
      : type = 'boolean';

  /// `string`, `number` or `boolean`, as the manifest spells it.
  final String type;

  /// For the model: what the value is, in a sentence.
  final String? description;
  final bool required;

  /// The value must be one an action returned in this conversation: an order
  /// id, an amount, an IBAN. One the model made up, read in the knowledge
  /// base or heard from the user does not open the screen.
  final bool fromActions;

  /// Only what was said: a false flag is left out rather than sent, so the
  /// manifest a host hashes is the smallest one that means the same.
  Map<String, dynamic> toJson() => {
        'type': type,
        if (description != null) 'description': description,
        if (required) 'required': true,
        if (fromActions) 'fromActions': true,
      };
}

/// What a route does when its card is tapped: the app's own navigation, run
/// on the app's own navigator.
typedef RendelRouteOpener = FutureOr<void> Function(Map<String, Object?> params);

/// A screen of the app the copilot may open, registered with
/// `Rendel.registerRoute`.
class RendelRoute {
  RendelRoute({
    required this.name,
    required this.title,
    required this.description,
    this.params = const {},
    required this.open,
  })  : assert(
          name.length <= 64 && _namePattern.hasMatch(name),
          'Route names must be snake_case, as action names are. The server '
          'rejects the whole manifest for one that is not, which takes every '
          'action down with it.',
        ),
        assert(
          title.isNotEmpty && title.length <= 60,
          'A route title is 1 to 60 characters: it is the line under a card.',
        ),
        assert(
          description.isNotEmpty && description.length <= 300,
          'A route description is 1 to 300 characters.',
        ),
        assert(
          params.length <= 8 && params.keys.every(_namePattern.hasMatch),
          'At most 8 params per route, each named in snake_case.',
        );

  static final RegExp _namePattern = RegExp(r'^[a-z][a-z0-9_]*$');

  final String name;

  /// The app's own words for the screen ("Orders › Order"), drawn under the
  /// model's title on the card, so where a tap goes is said by the app and
  /// not by the model.
  final String title;

  /// For the model: when this screen is the right one.
  final String description;
  final Map<String, RendelRouteParam> params;
  final RendelRouteOpener open;

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'description': description,
        if (params.isNotEmpty)
          'params': {for (final entry in params.entries) entry.key: entry.value.toJson()},
      };
}
