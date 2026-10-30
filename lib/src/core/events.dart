/// Host-observable lifecycle events, for the app's own analytics.
///
/// Its own file because the controller raises two of these and the facade
/// raises the other two, and the facade already imports the controller.
enum RendelEvent {
  /// The thread sheet was presented.
  opened,

  /// The thread sheet was dismissed.
  closed,

  /// The user sent a message, or submitted a form as one.
  messageSent,

  /// A registered action's handler finished running on this device, whatever
  /// it returned. Fires once per invocation, reads and confirmed writes alike.
  actionExecuted,
}

/// Something Rendel changed in the app's own data, so the app can refresh
/// what it holds of it: a list its favourites screen read at launch, a cart
/// kept in memory, a profile field.
///
/// Raised once for every write the server carried out for the person (a
/// confirmed card, or a card-less write with an Undo), and once more, with
/// [undone] true, when the person takes one back. An action the app runs
/// itself is the app's own doing and raises [RendelEvent.actionExecuted]
/// instead; a read raises nothing.
final class RendelChange {
  const RendelChange({
    required this.action,
    required this.risk,
    this.params = const {},
    this.undone = false,
  });

  /// The action's name, as the console lists it: `add_to_list`.
  final String action;

  /// `write` or `destructive`.
  final String risk;

  /// The values the call was made with, as the confirmation card showed them.
  final Map<String, dynamic> params;

  /// True when this is the Undo of [action], not the action itself.
  final bool undone;

  @override
  String toString() => 'RendelChange($action${undone ? ', undone' : ''})';
}
