import 'schema.dart';

/// Risk decides the ceremony: read runs instantly, write renders a
/// confirmation card first, destructive demands an explicit yes.
enum RendelRisk { read, write, destructive }

/// A handler's outcome. [data] flows back to the model as the tool result.
class RendelResult {
  RendelResult.ok([Map<String, dynamic>? data])
      : ok = true,
        data = data ?? const {'ok': true},
        error = null;

  RendelResult.fail(String this.error)
      : ok = false,
        data = null;

  final bool ok;
  final Map<String, dynamic>? data;
  final String? error;
}

typedef RendelHandler = Future<RendelResult> Function(Map<String, dynamic> params);

/// Everything the platform knows about one proposed run of an action.
class RendelInvocation {
  const RendelInvocation({
    required this.id,
    required this.name,
    required this.params,
    required this.risk,
  });

  /// Stable for this proposal, and re-sent unchanged when a turn resumes
  /// after a dropped stream. This is the idempotency key.
  final String id;
  final String name;
  final Map<String, dynamic> params;
  final RendelRisk risk;
}

/// A handler that also receives the invocation.
///
/// Use it when running the action twice would be worse than not running it:
/// record [RendelInvocation.id] with the effect, and return the recorded result
/// if you see the same id again. An app killed between running a destructive
/// handler and reporting the outcome is the case this exists for; the server
/// then believes the user never answered, and the model is free to propose
/// the same thing again.
typedef RendelInvocationHandler = Future<RendelResult> Function(RendelInvocation invocation);

/// A typed capability the copilot may propose. The handler runs inside the
/// host app with the user's own session — the copilot holds no credentials.
class RendelAction {
  RendelAction({
    required this.name,
    required this.description,
    required this.params,
    required this.risk,
    this.handler,
    this.onInvoke,
    this.confirmTemplate,
    this.confirmTemplates,
    this.timeout = const Duration(seconds: 15),
    this.sandboxResult,
    this.undoable = false,
    this.editable = const [],
    this.typeToConfirm,
    this.fullText,
    this.confirmLabel,
    this.confirmLabels,
  })  : assert(
          handler != null || onInvoke != null,
          'RendelAction needs a handler or an onInvoke.',
        ),
        assert(
          name.length <= 128 && _namePattern.hasMatch(name),
          'Action names must be snake_case: lowercase, starting with a letter, '
          'digits and underscores after it. The server rejects anything else, '
          'and it rejects the whole manifest, so one camelCase name takes every '
          'action down with it.',
        );

  /// The same expression the server enforces on a manifest.
  ///
  /// Checked here because failing there is a bad way to find out: the manifest
  /// POST returns one 400 for the whole document, the SDK logs it and carries
  /// on, and then every chat turn fails with `manifest_unknown` telling the
  /// developer to sync and retry, which cannot work. An assert names the
  /// actual mistake, at the line that made it.
  static final RegExp _namePattern = RegExp(r'^[a-z][a-z0-9_]*$');

  final String name;
  final String description;
  final RendelSchema params;
  final RendelRisk risk;

  /// The common path: parameters in, result out.
  final RendelHandler? handler;

  /// The idempotent path: the whole invocation, including its id.
  final RendelInvocationHandler? onInvoke;

  /// Feeds the server-synthesized confirmation card, e.g.
  /// `'Cancel order {order_id}? This cannot be undone.'`
  final String? confirmTemplate;

  /// The same sentence in other languages, keyed by BCP-47 tag.
  ///
  /// ```dart
  /// confirmTemplate: 'Cancel order {order_id}? This cannot be undone.',
  /// confirmTemplates: {
  ///   'tr': '{order_id} numaralı siparişi iptal edelim mi? Bu geri alınamaz.',
  ///   'de': 'Bestellung {order_id} stornieren? Das kann nicht rückgängig gemacht werden.',
  /// },
  /// ```
  ///
  /// The card is built by the server, which is where it belongs — a card the
  /// model words is a card the model can word into something the user did not
  /// agree to. The cost is that the one sentence someone reads before
  /// authorising something irreversible comes out of the server in whatever
  /// language you typed. This is how you fix that without giving the sentence
  /// back to the model.
  ///
  /// Matched on the locale the SDK sends: exact tag first, then the language,
  /// then [confirmTemplate]. Sixteen at most.
  final Map<String, String>? confirmTemplates;

  /// A [RendelRisk.destructive] action whose effect the user can still take
  /// back afterwards, such as an order that can be cancelled while it is
  /// being packed. Its confirmation card then does not say "This cannot be
  /// undone", and its confirm button is not drawn as a danger control.
  final bool undoable;

  /// Parameters the user may change on the confirmation card before they
  /// confirm: a quantity, a note, which of a few options. Each gets the
  /// control its type takes, and the server checks a change as it checks the
  /// model's call before the card is redrawn with it. Never an id, or an
  /// amount the app works out.
  ///
  /// ```dart
  /// editable: ['quantity'],
  /// ```
  final List<String> editable;

  /// A parameter the user types back before the confirm button arms ("type
  /// the app's name to delete it"). Only on an action that changes
  /// something, and never one in [editable]; the server checks it again.
  final String? typeToConfirm;

  /// A string parameter the card shows whole rather than as a short row (a
  /// page of text). With [RendelFullText.current] the card also shows what
  /// changes, from the text `Rendel.setCardSource` hands it.
  final RendelFullText? fullText;

  /// The confirm button's words ("Delete app"), up to 32 characters, and the
  /// same per language, matched like [confirmTemplates].
  final String? confirmLabel;
  final Map<String, String>? confirmLabels;

  /// How long the platform waits for this action before giving up on it.
  final Duration timeout;

  /// Milliseconds, for the wire and the manifest.
  int get timeoutMs => timeout.inMilliseconds;

  /// Runs whichever of the two handlers this action was built with.
  Future<RendelResult> run(RendelInvocation invocation) =>
      onInvoke != null ? onInvoke!(invocation) : handler!(invocation.params);

  /// Canned data returned instead of running [handler] when sandbox mode is
  /// active and this is set — for demos and tests without real side effects.
  final Map<String, dynamic>? sandboxResult;
}

/// A parameter a confirmation card carries in full (see [RendelAction.fullText]).
class RendelFullText {
  const RendelFullText(this.param, {this.current = false});

  final String param;

  /// Show what changes, from the text `Rendel.setCardSource` returns for the action.
  final bool current;

  Map<String, dynamic> toJson() => {'param': param, if (current) 'current': true};
}
