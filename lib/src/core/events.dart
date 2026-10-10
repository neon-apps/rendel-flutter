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
