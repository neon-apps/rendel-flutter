import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/config.dart'
    show RendelAttachIcon, RendelAttachment, RendelAttachSource, RendelSendIcon, RendelVoiceIcon;
import '../engine/conversation_controller.dart';
import '../protocol/protocol.dart' show NavigateAction, ReplyAction, UIAction;
import '../transport/api_client.dart' show RendelUploadFailure;
import 'renderer/blocks.dart'
    show
        BlockEnter,
        RendelActionButton,
        RendelChip,
        RendelPage,
        RendelPhoto,
        RendelPressable,
        RendelOverline,
        RendelPulse,
        RendelSwap,
        balancedWidth,
        readsFlatOnPage;
import 'renderer/registry.dart';
import '../core/log.dart';
import '../core/strings.dart';
import 'theme.dart';

/// The conversation surface: header, one answer to a page, composer.
///
/// The shell runs on the same scales as the catalog it holds — no font size,
/// gap, duration or press response is written here that a block could not also
/// use, and its two controls are the catalog's own [RendelPressable] rather than
/// Material's ripple — so the page reads as the frame around the components
/// rather than as a second design.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.controller,
    this.title = 'Copilot',
    this.logoUrl,
    this.logoHeaders = const {},
    this.headline,
    this.subtitle,
    this.suggestions = const [],
    this.strings = const RendelStrings(),
    this.composerHint,
    this.attachIcon = RendelAttachIcon.plus,
    this.voiceIcon = RendelVoiceIcon.microphone,
    this.sendIcon = RendelSendIcon.arrowUp,
    this.onPickAttachment,
    this.attachSources = RendelAttachSource.values,
    this.onDictate,
    this.onStopDictating,
    this.dictationLevel,
    this.onNavigate,
  });

  final ConversationController controller;

  /// What the copilot is called in this app. Shown in the header.
  final String title;

  /// The customer's published logo, shown before the name. Null draws the
  /// header exactly as it did before a logo could be published at all.
  ///
  /// Built by `Rendel` from the host's own `apiBaseUrl`, never taken from
  /// a payload: the published theme carries an id, not an address.
  final String? logoUrl;

  /// Sent with the logo request. The app's own key, as every other call sends.
  final Map<String, String> logoHeaders;

  /// The customer's own headline for an empty thread, from
  /// `RendelConfig.emptyStateTitle`. Null leaves the SDK's translated one.
  final String? headline;

  /// The line under the empty thread's headline. Name what this app can
  /// actually do, in the user's words. Null keeps the domain-free default.
  final String? subtitle;

  /// Opening prompts for the empty thread. An empty list keeps the empty
  /// state text-only.
  final List<String> suggestions;

  /// The words the SDK supplies itself. Passed in rather than read off the
  /// facade so this widget stays constructible on its own — the gallery and
  /// every widget test build one without calling `init`.
  final RendelStrings strings;

  /// The words in the message box before anyone has typed. Null takes
  /// [RendelStrings.composerHint], which is translated; this is the customer's
  /// override of it.
  final String? composerHint;

  /// The three glyphs in the composer. Passed in for the same reason the
  /// strings are: this widget is constructible without `init`.
  final RendelAttachIcon attachIcon;
  final RendelVoiceIcon voiceIcon;
  final RendelSendIcon sendIcon;

  /// The picker and the recogniser, from `RendelConfig` or the SDK's own. Null
  /// for either leaves that control undrawn.
  final Future<RendelAttachment?> Function(RendelAttachSource source)?
      onPickAttachment;

  /// What the "+" offers. One source skips the menu and picks from it
  /// directly: a host's own picker, which stands in for all three.
  final List<RendelAttachSource> attachSources;
  final Future<String?> Function(void Function(String partial) onPartial)?
      onDictate;

  /// Ends a dictation on a second press. Null keeps the control un-pressable
  /// while the recogniser is listening.
  final VoidCallback? onStopDictating;

  /// How loud the speaker is, 0 to 1, for voice mode's glow. The SDK's own
  /// recogniser reports it; a host's does not, and the glow only breathes.
  final ValueListenable<double>? dictationLevel;

  /// Opens one of the app's screens the way the presentation wants it: the
  /// panel shrinking into the bubble while the app navigates under it. Null
  /// opens it with nothing around it, through the controller.
  final Future<bool> Function(NavigateAction action)? onNavigate;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _input = TextEditingController();

  /// How tall the composer floating over the page is, so the page can
  /// scroll its foot out from under it.
  final _dock = ValueNotifier<double>(0);

  /// How tall the header floating over an answer page is, for the same
  /// reason at the other end.
  final _head = ValueNotifier<double>(0);
  late final RendelDispatcher _dispatch;

  /// What the blocks of a detail talk back through.
  late final RendelDispatcher _detailDispatch;

  @override
  void initState() {
    super.initState();
    _dispatch = RendelDispatcher(
      onAction: _act,
      onSubmitForm: widget.controller.submitForm,
      canHandle: widget.controller.handles,
      onSelect: (block, id, shown) =>
          widget.controller.select(block, id, shown: shown),
      onChoose: (block, ids, shown, {otherText, lit = Duration.zero}) => widget.controller
          .choose(block, ids, shown: shown, otherText: otherText, lit: lit),
      onRate: (block, score, {comment}) => widget.controller.rate(block, score, comment: comment),
      routeTitle: _routeTitle,
      // A form's upload field picks and uploads the way the composer does,
      // so a photo of the damage costs the host no second picker or path.
      onPickFile: widget.onPickAttachment,
      fileSources: widget.attachSources,
      onUpload: _upload,
    );
    // Over a detail a reply, a form sent or an option picked is a question:
    // the sheet goes first and the answer opens as a new page. A link opens
    // and the sheet stays.
    _detailDispatch = RendelDispatcher(
      onAction: (action) => action is ReplyAction
          ? _overDetail(() => widget.controller.tapAction(action))
          : _act(action),
      onSubmitForm: (id, values) =>
          _overDetail(() => widget.controller.submitForm(id, values)),
      canHandle: widget.controller.handles,
      onSelect: (block, id, shown) =>
          _overDetail(() => widget.controller.select(block, id, shown: shown)),
      onChoose: (block, ids, shown, {otherText, lit = Duration.zero}) => _overDetail(() =>
          widget.controller.choose(block, ids, shown: shown, otherText: otherText, lit: lit)),
      // A rating asks nothing, so the sheet stays over it.
      onRate: (block, score, {comment}) => widget.controller.rate(block, score, comment: comment),
      routeTitle: _routeTitle,
      onPickFile: widget.onPickAttachment,
      fileSources: widget.attachSources,
      onUpload: _upload,
    );
    widget.controller.addListener(_turnPages);
    final c = widget.controller;
    // A conversation that already has answers opens on the newest, with the
    // ones before it a step back; one asked before this screen existed is not
    // written over it again.
    if (c.pages.isEmpty) {
      c.pages.addAll(_answers(c));
      c.page = c.pages.length - 1;
    }
    _question = _lastQuestion(c);
    _wasBusy = c.busy;
  }

  /// A tap, and a screen of the app opened the way the presentation opens
  /// one.
  Future<bool> _act(UIAction action) {
    final navigate = widget.onNavigate;
    if (action is NavigateAction && navigate != null) return navigate(action);
    return widget.controller.tapAction(action);
  }

  String? _routeTitle(String route) => widget.controller.routes[route]?.title;

  Future<String> _upload(RendelAttachment file) =>
      widget.controller.api.upload(file.bytes, file.mediaType);

  @override
  void dispose() {
    widget.controller.removeListener(_turnPages);
    _input.dispose();
    _dock.dispose();
    _head.dispose();
    super.dispose();
  }

  /// Files already uploaded, waiting for the turn that will carry them.
  ///
  /// Uploaded when the host's picker returns rather than at send time, so the
  /// wait is spent while the user is still typing and a file the server
  /// refuses is refused before they have composed a question around it.
  final List<_Pending> _attachments = [];
  bool _attaching = false;
  bool _dictating = false;
  String? _attachError;

  Future<void> _pickAttachment(RendelAttachSource source) async {
    final pick = widget.onPickAttachment;
    if (pick == null || _attaching || widget.controller.busy) return;

    final RendelAttachment? picked;
    try {
      picked = await pick(source);
    } catch (_) {
      // The host's own picker threw. Theirs to log; ours to not leave a
      // paperclip that has silently stopped working.
      if (!mounted) return;
      setState(() => _attachError = widget.strings.attachFailed);
      return;
    }
    if (!mounted || picked == null) return;

    final waiting = _Pending(
      id: null,
      name: picked.name,
      mediaType: picked.mediaType,
      bytes: picked.bytes,
    );
    setState(() {
      _attaching = true;
      _attachError = null;
      _attachments.add(waiting);
    });
    try {
      final id = await widget.controller.api
          .upload(waiting.bytes, waiting.mediaType);
      if (!mounted) return;
      setState(() {
        final at = _attachments.indexOf(waiting);
        if (at != -1) _attachments[at] = waiting.withId(id);
      });
    } on RendelUploadFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _attachments.remove(waiting);
        // The server's sentence, in the app's language; ours when the reply
        // was not one the server wrote.
        _attachError = failure.message ?? widget.strings.attachFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _attachments.remove(waiting);
        _attachError = widget.strings.attachFailed;
      });
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  /// Voice mode: what the microphone opens instead of the message box.
  ///
  /// The words are written over the conversation as they are heard, and the
  /// question goes out on its own when the speaker stops — there is no box to
  /// read it back from, as on the device this was asked to look like. Then
  /// voice mode closes: the question is written over the page and the pill
  /// takes it from there. The pill stops listening and sends; a tap anywhere
  /// else lets it go.
  bool _voice = false;
  String _heard = '';
  bool _voiceCancelled = false;

  Future<void> _dictate() async {
    // Second press ends it, where the host gave us something to end it with.
    if (_dictating) {
      widget.onStopDictating?.call();
      return;
    }
    final dictate = widget.onDictate;
    if (dictate == null || widget.controller.busy) return;

    setState(() {
      _dictating = true;
      _attachError = null;
      _voice = true;
      _heard = '';
      _voiceCancelled = false;
    });
    try {
      final text = await dictate((partial) {
        if (!mounted || _voiceCancelled) return;
        // Live, as they are heard. The point of dictation is watching it
        // happen; words that appear only once you stop are a transcript.
        setState(() => _heard = partial);
      });
      if (!mounted || _voiceCancelled) return;
      final words = text?.trim() ?? '';
      if (words.isEmpty) {
        /* Nothing at all was captured.
        
           A recogniser that cannot reach a microphone — a simulator with no
           audio input, a device that handed the session to something else —
           reports a clean, immediate end rather than an error. Left alone,
           voice mode opened and shut under the user's finger and said
           nothing. */
        setState(() {
          _voice = false;
          _attachError = widget.strings.nothingHeard;
        });
        return;
      }
      // Already written out live as it was heard, so it is not revealed
      // again word by word.
      _spoken = true;
      _send(words);
      _spoken = false;
      setState(() => _voice = false);
    } catch (err) {
      if (!mounted) return;
      /* The recogniser failed, which is not silence.

         This read 'That could not be heard. Try again.' — in English under a
         Turkish thread — and the reason went nowhere. The host's error is
         logged so the console shows what the platform said, and the sentence
         names the recogniser rather than the microphone. */
      RendelLog.warn('dictation_failed', 'the host recogniser failed', error: err);
      setState(() {
        _voice = false;
        _attachError = widget.strings.dictationFailed;
      });
    } finally {
      if (mounted) setState(() => _dictating = false);
    }
  }

  /// A tap away from voice mode while it listens: nothing is sent.
  void _cancelVoice() {
    _voiceCancelled = true;
    widget.onStopDictating?.call();
    setState(() => _voice = false);
  }

  /// The failed turn's sentence, in the host's language.
  ///
  /// The controller names its own errors and keeps English text for the logs;
  /// the words for the screen are here, where the strings are. A code the
  /// server sent keeps the server's message, which arrives in the app's
  /// language already.
  String? _turnError(ConversationController c) {
    final s = widget.strings;
    return switch (c.errorCode) {
      'confirmation_expired' => s.confirmationExpired,
      'turn_failed' => s.turnFailed,
      'copilot_stalled' => s.copilotStalled,
      'stream_dropped' => s.streamDropped,
      'no_answer' => s.noAnswer,
      _ => c.errorText,
    };
  }

  void _send([String? preset]) {
    final typed = preset ?? _input.text;
    // A photograph with nothing typed is a real message, and the wire asks for
    // a sentence. The file's own name is the truest one available — and it is
    // useful rather than filler, because the model then knows the picture it
    // was handed is called `receipt-may.pdf`.
    final text = typed.trim().isEmpty && _attachments.isNotEmpty
        ? _attachments.map((pending) => pending.name).join(', ')
        : typed;
    if (text.trim().isEmpty) return;

    /* Nothing goes out half-uploaded: an id that does not exist yet is a file
       the turn would silently not carry. The send control is off while one is
       in flight, and this is the belt to that brace. */
    if (_attachments.any((pending) => pending.id == null)) return;
    final ids = [for (final pending in _attachments) pending.id!];
    _input.clear();
    setState(() {
      _attachments.clear();
      _attachError = null;
    });
    final spoken = _spoken;
    _overDetail(() {
      _spoken = spoken;
      final sent = widget.controller.send(text, attachments: ids);
      _spoken = false;
      return sent;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final controller = widget.controller;

    // Published above everything the page draws, so a block deep in the
    // catalog can reach the host's words without every builder in the product
    // growing a parameter. Same shape as the theme scope, and for the same
    // reason.
    return RendelStringsScope(
      strings: widget.strings,
      child: _build(context, theme, controller),
    );
  }

  Widget _build(
    BuildContext context,
    RendelTheme theme,
    ConversationController controller,
  ) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.92,
      // A page draws its wash and its fades to the sheet's edge, so the
      // sheet's corner has to cut them.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // A page sits on the raised ground, as a sheet of paper does.
        color: theme.colors.surfaceRaised,
        // The sheet's own corner is the largest radius in the system: it is
        // the boundary between the host's app and the copilot, and a 14pt
        // corner on a full-height sheet reads as a rendering accident.
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(theme.radius.hero),
        ),
      ),
      child: Column(
        children: [
          // The header floats over the page; see [_pageChrome].
          Expanded(
            child: ListenableBuilder(
              // `structure`, not the controller: a streamed token changes one
              // message and must not rebuild the list, the error bar and the
              // composer's TextField with it.
              listenable: controller.structure,
              builder: (context, _) => Stack(
                children: [
                  // A page's ground gives way to a slow pastel wash while a
                  // question is asked: plainly busy, without a spinner in the
                  // middle of the screen.
                  Positioned.fill(
                    child: _Wash(
                      on: _asked != null,
                      ground: theme.colors.surfaceRaised,
                    ),
                  ),
                  Positioned.fill(child: _body(theme, controller)),
                  ..._pageChrome(theme, controller),
                  // A card opened over the page, under the composer.
                  if (_detail != null)
                    Positioned.fill(
                      child: _DetailSheet(
                        key: ObjectKey(_detail),
                        detail: _detail!,
                        closing: _closing,
                        onClose: _closeDetail,
                        onClosed: _detailClosed,
                        dock: _dock,
                        body: _page(controller, _detail!.answers, detail: true),
                      ),
                    ),
                  /* The composer floats over the page rather than under it.

                     The page runs to the bottom edge and scrolls behind the
                     "+", the microphone and the keyboard, seen through a
                     frosted, half-clear ground — the way the system draws its
                     own bars. The page pads its foot by the dock's height,
                     so nothing is left under it for good. */
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    // Under voice mode the "+", the microphone and the keyboard
                    // step aside; it draws the microphone where it was.
                    child: IgnorePointer(
                      ignoring: _voice,
                      child: ExcludeSemantics(
                      excluding: _voice,
                      child: AnimatedOpacity(
                        opacity: _voice ? 0 : 1,
                        duration: theme.motion.swap,
                        // There for a screen reader from the frame voice mode
                        // closes; whether it is at all is the exclusion's
                        // business above.
                        alwaysIncludeSemantics: true,
                        child: _SizeReporter(
                      onHeight: (height) => _dock.value = height,
                      child: _Dock(
                        children: [
                          _ErrorSlot(
                            // An upload the server refused speaks from the same
                            // strip a failed turn does. It is the one place in
                            // this screen the user already looks for "that did
                            // not work", and a second error surface would be a
                            // second thing to learn.
                            message: _attachError ?? _turnError(controller),
                            retryLabel: widget.strings.retry,
                            onRetry: _attachError == null && controller.canRetry
                                ? controller.retry
                                : null,
                          ),
                          _Composer(
                            input: _input,
                            busy: controller.busy,
                            status: _status(controller),
                            primary: _primary(controller),
                            onSend: _send,
                            hint: widget.composerHint,
                            attachIcon: widget.attachIcon,
                            voiceIcon: widget.voiceIcon,
                            sendIcon: widget.sendIcon,
                            attachments: _attachments,
                            attaching: _attaching,
                            onRemoveAttachment: (index) =>
                                setState(() => _attachments.removeAt(index)),
                            sources: widget.attachSources,
                            // Null when there is no picker, which is what keeps
                            // the control from being drawn at all.
                            onAttach: widget.onPickAttachment == null
                                ? null
                                : _pickAttachment,
                            onVoice: widget.onDictate == null ? null : _dictate,
                          ),
                        ],
                      ),
                    ),
                      ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : theme.motion.settle,
                      // There from its first frame for a screen reader,
                      // whatever it looks like while it fades in.
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        alwaysIncludeSemantics: true,
                        child: child,
                      ),
                      child: !_voice
                          ? const SizedBox.shrink()
                          : _VoiceMode(
                              key: const ValueKey('voice'),
                              heard: _heard,
                              level: widget.dictationLevel,
                              voiceIcon: widget.voiceIcon,
                              onStop: widget.onStopDictating,
                              onCancel: _cancelVoice,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(RendelTheme theme, ConversationController controller) {
    return ValueListenableBuilder<double>(
      valueListenable: _dock,
      // A page draws its own opening screen, which only dissolves when the
      // first question is asked.
      builder: (context, dock, _) => _pageBody(theme, controller, dock),
    );
  }

  /* ——— one answer to a screen (`design/PAGES.md`) ———

     A thread is a record; this is a reading surface. The question is written
     over the screen while the page under it dissolves, the answer is drawn on
     a fresh page from the top, and the answers before it are a step back
     rather than a scroll back. Nothing is thrown away: `controller.messages`
     still holds the whole conversation, every turn is still sent and written
     down, and Conversations shows all of it.

     The question itself is never a bubble. On a screen that holds one answer
     the heading is the answer's own first line, and a bubble repeating what
     the person just asked costs the top of the screen for nothing. */

  /// The page's side padding.
  static const double _pageInset = 20;

  /// The question being asked, written over the screen until its answer
  /// starts. Null when nothing is.
  String? _asked;

  /// Whether [_asked] was spoken, and so is shown whole; and whether the
  /// question being sent right now is.
  bool _askedWhole = false;
  bool _spoken = false;

  /// The newest question this screen has seen, so the next one is noticed
  /// whichever way it was sent: typed, a suggestion, a quick reply, spoken.
  RendelMessage? _question;
  bool _wasBusy = false;

  /// The assistant's turns that have something to show, oldest first. A
  /// card's detail is not one of them.
  List<RendelMessage> _answers(ConversationController controller) => [
        for (final m in controller.messages)
          if (m.role == 'assistant' && m.blocks.isNotEmpty && m.detail == null) m,
      ];

  RendelMessage? _lastQuestion(ConversationController controller) =>
      controller.messages.reversed.where((m) => m.role == 'user').firstOrNull;

  /// Keeps the pages in step with the conversation.
  ///
  /// A question drops the pages after the one it was asked from, and is
  /// written over the screen; its answer becomes the newest page the moment
  /// it has a block to show, and the question goes. A turn that ends with
  /// nothing to show gives the screen back as it was.
  void _turnPages() {
    if (!mounted) return;
    final c = widget.controller;
    var changed = false;
    void dropLater() {
      if (c.page < c.pages.length - 1) {
        c.pages.removeRange(c.page + 1, c.pages.length);
      }
    }

    final question = _lastQuestion(c);
    if (question != null && !identical(question, _question)) {
      _question = question;
      // A card opened over its page is asked with no question over the
      // screen, and is no page: the pages after the one it is on stay.
      if (question.detail == null) {
        dropLater();
        final words = question.blocks.firstOrNull?.props['markdown'];
        _asked = words is String ? words : '';
        _askedWhole = _spoken;
        changed = true;
      }
    }
    final newest = c.messages.lastOrNull;
    if (newest != null &&
        newest.role == 'assistant' &&
        newest.blocks.isNotEmpty &&
        newest.detail == null &&
        !c.pages.contains(newest)) {
      dropLater();
      c.pages.add(newest);
      c.page = c.pages.length - 1;
      _asked = null;
      changed = true;
    }
    if (_wasBusy && !c.busy && _asked != null) {
      _asked = null;
      changed = true;
    }
    _wasBusy = c.busy;
    // An answer the conversation no longer holds is no page.
    final before = c.pages.length;
    c.pages.removeWhere((m) => !c.messages.contains(m));
    if (c.pages.length != before) {
      c.page = math.min(c.page, c.pages.length - 1);
      changed = true;
    }
    if (c.messages.isEmpty && _asked != null) {
      _asked = null;
      changed = true;
    }
    // A new conversation has no details, open or not.
    if (_detail != null && !c.details.containsValue(_detail)) {
      _detail = null;
      _closing = false;
      _afterClose = null;
      changed = true;
    }
    if (changed) setState(() {});
  }

  /* ——— a card opened over its page (`design/DETAIL.md`) ——— */

  /// The card open over the page, or null; and whether it is sliding away,
  /// with what waits for it to go.
  RendelDetail? _detail;
  bool _closing = false;
  VoidCallback? _afterClose;

  /// Opens [card] over the page: its head at once, from the card, and its
  /// detail asked for under it. A card opened before shows what was fetched,
  /// without a request.
  void _openDetail(RendelDetail card, String? reply) {
    if (_detail != null) return;
    final c = widget.controller;
    final known = c.details[card.key];
    if (known != null && (known.answered || identical(c.detail, known) && c.busy)) {
      setState(() => _detail = known);
      return;
    }
    if (c.busy) return;
    final asked = known ?? card;
    c.details[asked.key] = asked;
    setState(() => _detail = asked);
    unawaited(c.send(reply ?? widget.strings.detailAskAbout(asked.title), detail: asked));
  }

  /// Slides the sheet away, then does [then]. The page under it is as it was
  /// left, scroll and all: it never went anywhere.
  void _closeDetail([VoidCallback? then]) {
    if (_detail == null) return then?.call();
    if (_closing) {
      final before = _afterClose;
      _afterClose = () {
        before?.call();
        then?.call();
      };
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _detail = null);
      return then?.call();
    }
    setState(() {
      _closing = true;
      _afterClose = then;
    });
  }

  void _detailClosed() {
    final then = _afterClose;
    setState(() {
      _detail = null;
      _closing = false;
      _afterClose = null;
    });
    then?.call();
  }

  /// A question asked over a detail: the sheet goes first, and the answer
  /// opens as a new page. While a turn is still open nothing would be sent,
  /// so nothing closes.
  Future<T> _overDetail<T>(Future<T> Function() ask) {
    if (_detail == null || widget.controller.busy) return ask();
    final asked = Completer<T>();
    _closeDetail(() => asked.complete(ask()));
    return asked.future;
  }

  /// The first action under the open detail, lit beside the microphone once
  /// its turn is done; with no detail open, the first screen of the app the
  /// page offers (`design/NAVIGATE.md`). Null when there is none this build
  /// can carry out.
  ({String label, VoidCallback onTap, bool go})? _primary(ConversationController c) {
    final detail = _detail;
    if (detail == null) return c.busy || _asked != null ? null : _firstScreen(c);
    if (_closing || c.busy) return null;
    for (final answer in detail.answers) {
      for (final block in answer.blocks) {
        if (block.type != 'actions' || !block.ready) continue;
        final items = block.props['items'];
        final first = items is List && items.isNotEmpty ? items.first : null;
        final label = first is Map ? first['label'] : null;
        final action = first is Map ? UIAction.tryParse(first['action']) : null;
        if (label is! String || action == null || !c.handles(action)) return null;
        return (label: label, onTap: () => _detailDispatch.onAction(action), go: false);
      }
    }
    return null;
  }

  /// The first item of the first `screens` block on the page on screen.
  ({String label, VoidCallback onTap, bool go})? _firstScreen(ConversationController c) {
    final at = c.page;
    if (at < 0 || at >= c.pages.length) return null;
    for (final block in c.pages[at].blocks) {
      if (block.type != 'screens' || !block.ready) continue;
      final items = block.props['items'];
      final first = items is List && items.isNotEmpty ? items.first : null;
      final title = first is Map ? first['title'] : null;
      final action = first is Map ? UIAction.tryParse(first['action']) : null;
      if (title is! String || action is! NavigateAction || !c.handles(action)) return null;
      return (label: title, onTap: () => _dispatch.onAction(action), go: true);
    }
    return null;
  }

  /// What the pill in the microphone's place says while a turn is in flight.
  /// Null when none is.
  String? _status(ConversationController controller) {
    if (!controller.busy) return null;
    final s = widget.strings;
    // A card's detail says so for the whole of its turn.
    if (controller.detail != null) return s.statusDetail;
    // A handler running on this device is the app being checked, whatever
    // the server last said.
    if (controller.phase == RendelPhase.runningAction) return s.statusAction;
    return switch (controller.turnStatus) {
      'action' => s.statusAction,
      'composing' => s.statusComposing,
      _ => s.statusThinking,
    };
  }

  void _step(int by) => setState(() => widget.controller.page += by);

  /// What floats over a page: the fades into its ground at both ends, the
  /// header with back and forward, and the question while it is asked.
  List<Widget> _pageChrome(RendelTheme theme, ConversationController controller) {
    final ground = theme.colors.surfaceRaised;
    final asking = _asked != null;
    final still = MediaQuery.disableAnimationsOf(context);
    // Back and forward wait for the turn: the page it is drawing is the one
    // a step would leave.
    final idle = !controller.busy && !asking;
    return [
      // The page fades under the header and above the composer, so neither
      // sits on a line of text. Hidden while the page is dissolved.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: asking ? 0 : 1,
            duration: still ? Duration.zero : theme.motion.settle,
            child: ValueListenableBuilder<double>(
              valueListenable: _head,
              builder: (context, head, _) => SizedBox(
                height: _topFade(head),
                child: _Fade(
                  ground: ground,
                  top: true,
                  // Solid behind the header's controls, whose bottom is the
                  // header's own bottom inset above its foot.
                  solid: (head - theme.space.md) / _topFade(head),
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        height: 128,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: asking ? 0 : 1,
            duration: still ? Duration.zero : theme.motion.settle,
            child: _Fade(ground: ground, top: false),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _SizeReporter(
          onHeight: (height) => _head.value = height,
          child: _Header(
            title: widget.title,
            logoUrl: widget.logoUrl,
            logoHeaders: widget.logoHeaders,
            sandbox: controller.sandbox,
            onBack: idle && controller.page > -1 ? () => _step(-1) : null,
            onForward: idle && controller.page < controller.pages.length - 1
                ? () => _step(1)
                : null,
          ),
        ),
      ),
      // The question, written over the screen until the answer starts.
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<double>(
            valueListenable: _dock,
            builder: (context, dock, _) => AnimatedSwitcher(
              duration: still ? Duration.zero : theme.motion.settle,
              layoutBuilder: (current, previous) => Stack(
                children: [...previous, if (current != null) current],
              ),
              child: _asked == null
                  ? const SizedBox.shrink()
                  : Align(
                      key: ObjectKey(_question),
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 0, 24, dock + 40),
                        child: _Asked(text: _asked!, whole: _askedWhole),
                      ),
                    ),
            ),
          ),
        ),
      ),
    ];
  }

  /// How far the fade under the header reaches: just past the header.
  ///
  /// The brief's 112 is measured on the prototype's phone, from the top of a
  /// 54pt status bar the sheet does not have; what it describes is a fade
  /// solid behind the controls and clear a little under them, which is this.
  static double _topFade(double head) => head + 16;

  Widget _pageBody(
    RendelTheme theme,
    ConversationController controller,
    double dock,
  ) {
    final pages = controller.pages;
    final at = controller.page;
    final shown = at >= 0 && at < pages.length ? pages[at] : null;
    return ValueListenableBuilder<double>(
      valueListenable: _head,
      builder: (context, head, _) => _Dissolve(
        on: _asked != null,
        // The opening screen keeps what it has always had; only the dissolve
        // is new to it.
        child: shown == null
            ? Padding(
                padding: EdgeInsets.only(top: head, bottom: dock),
                child: _EmptyState(
                  headline: widget.headline,
                  subtitle: widget.subtitle,
                  suggestions: widget.suggestions,
                  onPick: _send,
                ),
              )
            // Its own list per page, so a new page, and one stepped back to,
            // opens at the top.
            : ListView(
                key: ObjectKey(shown),
                padding: EdgeInsets.fromLTRB(
                  _pageInset,
                  head + 8,
                  _pageInset,
                  dock + 40,
                ),
                children: [_page(controller, [shown], bar: head)],
              ),
      ),
    );
  }

  /// One answer as one composition: flat sections, 30 apart, 14 under a
  /// heading and 26 under the lede.
  ///
  /// A [detail] is the answer under a card's head: its summary and tags 14
  /// below what is above them, its actions 20, the rest 30.
  Widget _page(
    ConversationController controller,
    List<RendelMessage> answers, {
    bool detail = false,
    double bar = 0,
  }) {
    return ListenableBuilder(
      listenable: Listenable.merge(answers),
      builder: (context, _) {
        final blocks = [for (final answer in answers) ...answer.blocks];
        final dispatch = detail ? _detailDispatch : _dispatch;
        final lede = blocks.indexWhere((block) => block.type == 'text');
        double gap(int i) {
          final after = i == 0 ? null : blocks[i - 1].type;
          if (detail) {
            if (i == lede || blocks[i].type == 'tags') return 14;
            if (blocks[i].type == 'actions') return 20;
            return after == 'section' ? 14 : 30;
          }
          return i == 0
              ? 0
              : after == 'section'
                  ? 14
                  : i - 1 == lede
                      ? 26
                      : 30;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < blocks.length; i++)
              Padding(
                padding: EdgeInsets.only(top: gap(i)),
                child: RendelPage(
                  flat: readsFlatOnPage(blocks[i].type),
                  inset: _pageInset,
                  lede: i == lede,
                  detail: detail,
                  onOpen: detail ? null : _openDetail,
                  // The header floats over the page, so what pins to the
                  // page's top pins under it.
                  bar: bar,
                  // A node of its own per block, which nothing inside a
                  // block can guarantee. Every `Semantics` in the catalog is
                  // `container: false`, so without this a whole answer
                  // collapsed into one node: a six-block answer measured as a
                  // single label carrying four unrelated sentences and a stray
                  // `value=30%` from the progress bar inside it, and a
                  // two-block answer put the prose inside a button's label.
                  child: Semantics(
                    container: true,
                    // And explicit children. `container: true` alone only
                    // moved the collapse down a level: an annotation node
                    // absorbs every compatible descendant, so `info_card`
                    // came back as one button whose name was the title, the
                    // body and the CTA run together.
                    explicitChildNodes: true,
                    child: RepaintBoundary(
                      child: BlockEnter(
                        key: ValueKey(blocks[i].id),
                        id: blocks[i].id,
                        seen: controller.enteredBlockIds,
                        // Built under the page's scope, which a builder handed
                        // this method's context would not see. `text` is not
                        // swapped: it never draws a skeleton, and a swap would
                        // restart its size animation at every line wrap of
                        // the live paragraph.
                        child: Builder(
                          builder: (context) => blocks[i].type == 'text'
                              ? ComponentRegistry.build(context, blocks[i], dispatch)
                              : RendelSwap(
                                  stateKey: blocks[i].ready ? 'ready' : 'pending',
                                  child: ComponentRegistry.build(
                                    context,
                                    blocks[i],
                                    dispatch,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A composer affordance that is not built yet.
///
/// Disabled rather than absent, and rather than live-looking. Pressing it does
/// nothing AND it looks like pressing it does nothing, which is the difference
/// that matters: the row is easier to agree on with its contents in place, and
/// "here, not yet" is a true thing to say.
class _ComposerTool extends StatelessWidget {
  const _ComposerTool({
    required this.icon,
    required this.label,
    this.onTap,
    this.pending = false,
  });

  final IconData icon;
  final String label;

  /// Whether this control is mid-flight — an upload running. Drawn at the
  /// disabled weight so the row does not look live while it is busy, without
  /// the glyph moving.
  final bool pending;

  /// Null keeps the original behaviour: drawn, disabled, and announced as not
  /// available yet. The voice control is still that, and saying so is the
  /// difference between "here, not yet" and a button that lies.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    if (onTap != null || pending) {
      return RendelPressable(
        semanticLabel: label,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: theme.type.heading,
            color: pending
                ? theme.onComposerFaint.withValues(alpha: 0.55)
                : theme.onComposerFaint,
          ),
        ),
      );
    }
    return Semantics(
      label: '$label — not available yet',
      enabled: false,
      button: true,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(
          icon,
          // The box's own quiet ink: this sits INSIDE the composer, and on a
          // brand that darkened it the thread's faint ink is the one colour
          // guaranteed not to be readable there.
          size: theme.type.heading,
          color: theme.onComposerFaint.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.sandbox,
    this.logoUrl,
    this.logoHeaders = const {},
    this.onBack,
    this.onForward,
  });

  final String title;
  final bool sandbox;

  /// A step back through the pages and forward again. Null is "nothing that
  /// way", which spends the button rather than removing it, so the pair never
  /// moves under a thumb.
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  /// The customer's mark, fetched from their own API with their own key.
  /// Null when none is published, which is what every header did before a
  /// logo was possible.
  final String? logoUrl;
  final Map<String, String> logoHeaders;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    // Filled, not tinted: accent ink on a 12% accent wash measures
    // 2.8:1, and this badge is the difference between a test key and
    // a live one — which is why it drops to a second line intact
    // rather than losing a word. A Row could only ever share out a
    // width neither child fits in: at 320pt and the largest OS text
    // size the badge alone wants 135 of the 200 available.
    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.space.sm,
        vertical: theme.space.hair,
      ),
      // An outline, not a fill. The badge is a notice about the
      // key, not something the reader can act on, and the accent
      // means "you can act" everywhere else in the catalog. It
      // keeps the hue — a developer has to notice it — in the
      // form the system reserves for accent-as-type.
      decoration: BoxDecoration(
        border: Border.all(color: theme.accentEdge),
        borderRadius: BorderRadius.circular(theme.radius.control),
      ),
      child: Text(
        RendelStringsScope.of(context).testMode,
        style:
            theme.text.overline.copyWith(color: theme.accentText),
        maxLines: 1,
      ),
    );
    final row = Row(
        children: [
          // Back and forward at the leading edge. No rule under the header:
          // the page fades out beneath it instead.
          _PageSteps(onBack: onBack, onForward: onForward),
          SizedBox(width: theme.space.md),
          // The mark before the name, and never instead of it.
          //
          // A logo is a picture of a word at best and a picture of a shape
          // usually, so a header that replaced the name with one would be a
          // header a screen reader reads as nothing. `errorBuilder` collapses
          // it to zero width: a 404 from the API — no logo published, an
          // object that went missing — has to leave the header looking the way
          // it did before anyone uploaded anything, not leave a broken frame
          // in it.
          if (logoUrl != null) ...[
            Image.network(
              logoUrl!,
              headers: logoHeaders,
              height: 20,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(width: 20, height: 20),
            ),
            SizedBox(width: theme.space.sm),
          ],
          Expanded(child: RendelOverline(title, maxLines: 1)),
          RendelPressable(
            semanticLabel: RendelStringsScope.of(context).closeCopilot,
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox(
              height: 44,
              width: 44,
              child: Icon(
                Icons.close_rounded,
                size: theme.type.display,
                color: theme.colors.onSurfaceFaint,
              ),
            ),
          ),
        ],
      );
    return Container(
      // Directional: the leading inset is the 16pt edge every block in the
      // thread shares, and physically pinned it landed on the wrong side in
      // RTL, putting the title 8pt out of line with the body underneath it.
      padding: EdgeInsetsDirectional.fromSTEB(
        theme.space.plate,
        theme.space.lg,
        theme.space.sm,
        theme.space.md,
      ),
      // Back and forward take the room the badge would have beside the name,
      // so it has a line of its own under them.
      child: sandbox
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [row, SizedBox(height: theme.space.xs), badge],
            )
          : row,
    );
  }
}

/// Back and forward through the pages a conversation has opened: a glass pill
/// holding two round buttons, at the header's leading edge.
class _PageSteps extends StatelessWidget {
  const _PageSteps({required this.onBack, required this.onForward});

  final VoidCallback? onBack;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final shape = BorderRadius.circular(theme.radius.control);
    // No drop shadow, for the reason `_Glass` gives: under a translucent
    // fill Flutter paints it through the glass as a smudge.
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colors.surfaceHigh.withValues(alpha: 0.72),
            border: Border.all(color: theme.hairline),
            borderRadius: shape,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PageStep(
                  icon: rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                  label: strings.previousPage,
                  onTap: onBack,
                ),
                _PageStep(
                  icon: rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  label: strings.nextPage,
                  onTap: onForward,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One step through the pages. Spent rather than absent at either end: a
/// button that comes and goes moves the one beside it.
class _PageStep extends StatelessWidget {
  const _PageStep({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.28 : 1,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 24, color: theme.colors.onSurface),
          ),
        ),
      ),
    );
  }
}

/// Holds the error bar's space so a failed turn does not shove the composer
/// down in a single frame.
class _ErrorSlot extends StatelessWidget {
  const _ErrorSlot({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String? message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // The one replacement in the SDK that used to animate height only: an
    // error succeeded by a different error of the same height — a stream
    // failure then the idle timeout — was swapped with no gesture at all.
    return RendelSwap(
      alignment: Alignment.bottomCenter,
      stateKey: message ?? 'none',
      child: message == null
          ? const SizedBox(width: double.infinity)
          : _ErrorBar(
              message: message!,
              retryLabel: retryLabel,
              onRetry: onRetry,
            ),
    );
  }
}

/// A failed turn, with the one control that helps. The message says what
/// happened; it does not apologise and it does not blame the network in the
/// abstract.
class _ErrorBar extends StatelessWidget {
  const _ErrorBar({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;

  /// `RendelStrings.retry`. It was the literal 'Try again' — the one control in
  /// the bar, in English under whatever language the message was in.
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      width: double.infinity,
      // Asymmetric, so directional: the message takes the thread's 16pt
      // leading inset and the button the tighter trailing one. Physically
      // pinned, RTL handed the message the 8 and the button the 16.
      padding: EdgeInsetsDirectional.fromSTEB(
        theme.space.plate,
        theme.space.sm,
        theme.space.sm,
        theme.space.sm,
      ),

      decoration: BoxDecoration(
        color: theme.colors.surfaceSunk,
        border: Border(top: BorderSide(color: theme.colors.line)),
      ),
      // Two flex-1 children split the row 50/50 whatever either needs, so at
      // 320pt the message was a constant 144pt and the button a constant 94 at
      // every text scale: from 1.6 the SDK's only recovery control read
      // "Try / ag...", and every error string the SDK ships was cut by 2.0.
      // Below the width where both fit, they stack.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The flag has to sit on the node that carries the words. On the
          // container it annotated a node with no label of its own, so the
          // one announcement this bar exists to make was never made.
          final words = Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: theme.text.body,
              // Three lines then an ellipsis. Unbounded, the message grew the
              // bar without limit at large text sizes, and the bar sits
              // between the thread and the composer.
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          );
          if (onRetry == null) return words;

          // What the button costs: its widest word at this text size, plus the
          // padding around it.
          final scaler = MediaQuery.textScalerOf(context);
          final button =
              scaler.scale(theme.type.label) * 6 + theme.space.xl * 2;
          final stacked = constraints.maxWidth - button - theme.space.sm <
              theme.size.trailing;
          final retry = RendelActionButton(
            label: retryLabel,
            quiet: true,
            onTap: onRetry,
            expand: stacked,
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [words, SizedBox(height: theme.space.sm), retry],
            );
          }
          return Row(
            children: [
              Expanded(child: words),
              SizedBox(width: theme.space.sm),
              retry,
            ],
          );
        },
      ),
    );
  }
}

/// The empty thread teaches. Suggestions are the host's own, so they name
/// things this app can actually do rather than advertising the category — and
/// so does the line above them, which is why the default names no verbs the
/// host might not have.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.headline,
    required this.subtitle,
    required this.suggestions,
    required this.onPick,
  });

  final String? headline;
  final String? subtitle;
  final List<String> suggestions;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    // Left-aligned and opened by the turn, not centred. A centred empty
    // state is a poster; this one is the first line of the conversation the
    // reader is about to have, and it sits where that conversation will.
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(theme.space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // The customer's own words first, then the SDK's translated
              // ones. Unlike the line below it, an EMPTY headline is not a
              // choice anybody asked for — a thread opening on nothing but a
              // subtitle reads as a page that failed to load — so a blank one
              // falls back rather than clearing.
              (headline?.trim().isNotEmpty ?? false)
                  ? headline!
                  : RendelStringsScope.of(context).emptyTitle,
              style: theme.text.display,
            ),
            // An EMPTY subtitle is a choice — the console lets a customer
            // clear the line — and a null one means they never said. The
            // first renders nothing; the second renders the default.
            if (subtitle == null || subtitle!.isNotEmpty) ...[
              SizedBox(height: theme.space.sm),
              Text(
                subtitle ?? RendelStringsScope.of(context).emptyBody,
                style: theme.text.body,
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              SizedBox(height: theme.space.xl),
              Wrap(
                alignment: WrapAlignment.start,
                spacing: theme.space.sm,
                runSpacing: theme.space.sm,
                children: [
                  // The same chip the catalog draws for quick_replies: the
                  // empty state is a preview of the conversation, not a
                  // separate look.
                  for (final suggestion in suggestions)
                    RendelChip(label: suggestion, onTap: () => onPick(suggestion)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The composer's ground: a frosted, half-clear band the thread scrolls
/// behind, from the composer down to the bottom edge — or to the keyboard,
/// which the sheet does not make room for on its own.
class _Dock extends StatelessWidget {
  const _Dock({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = keyboard > 0
        ? keyboard + theme.space.sm
        : math.max(MediaQuery.paddingOf(context).bottom, 12.0);
    final ground = theme.colors.surface;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.55],
              colors: [
                ground.withValues(alpha: 0),
                ground.withValues(alpha: 0.14),
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports its child's height after every layout that changed it.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // After the frame: a listener that rebuilds during layout is an error.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

enum _Mode { rest, menu, text }

/// The bottom of the thread, the same composer the console's phones draw.
///
/// At rest it is three controls: a round "+" on the left, the microphone as
/// the one filled pill in the middle, and a round keyboard on the right. The
/// keyboard opens the message box, two lines tall before anything is
/// written; the "+" opens a menu of Photos, Camera and Files. Each rises out
/// of the row rather than replacing it in a frame. A box left empty settles
/// back to rest at a tap anywhere else.
///
/// A microphone that is off leaves nothing for the middle, so the box is all
/// there is, and its tools carry the three sources; an attach glyph that is
/// off takes the "+" and the tools with it.
class _Composer extends StatefulWidget {
  const _Composer({
    required this.input,
    required this.busy,
    this.status,
    this.primary,
    required this.onSend,
    required this.hint,
    required this.attachIcon,
    required this.voiceIcon,
    required this.sendIcon,
    required this.attachments,
    required this.attaching,
    required this.sources,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onVoice,
  });

  final TextEditingController input;
  final bool busy;

  /// What an answer page's turn is doing, said by the pill drawn in the
  /// microphone's place. Null leaves the composer as it always was.
  final String? status;

  /// The first action of a card opened over its page, lit beside the
  /// microphone (`design/DETAIL.md`), or the page's first screen of the app
  /// ([go], `design/NAVIGATE.md`). Null draws the microphone alone.
  final ({String label, VoidCallback onTap, bool go})? primary;
  final VoidCallback onSend;
  final String? hint;

  /// Files already uploaded and waiting on this turn.
  final List<_Pending> attachments;
  final bool attaching;

  /// Where a file can come from. One source is a host's own picker: the "+"
  /// opens it with no menu.
  final List<RendelAttachSource> sources;

  /// Null when there is no picker. The control is then not drawn.
  final void Function(RendelAttachSource source)? onAttach;
  final void Function(int index) onRemoveAttachment;

  /// Opens voice mode. Null when there is no recogniser.
  final VoidCallback? onVoice;
  final RendelAttachIcon attachIcon;
  final RendelVoiceIcon voiceIcon;
  final RendelSendIcon sendIcon;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _focus = FocusNode();
  var _mode = _Mode.rest;

  @override
  void didUpdateWidget(_Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A question on its way puts the box away: the pill says what is
    // happening, and the page needs the room the keyboard took.
    if (oldWidget.status == null && widget.status != null) {
      _focus.unfocus();
      _mode = _Mode.rest;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _voice =>
      widget.voiceIcon != RendelVoiceIcon.off && widget.onVoice != null;

  bool get _attach =>
      widget.attachIcon != RendelAttachIcon.off &&
      widget.onAttach != null &&
      widget.sources.isNotEmpty;

  /// Open whenever something is in it: a file or an upload does not fold
  /// away under the user.
  _Mode get _shown {
    if (widget.status != null &&
        widget.attachments.isEmpty &&
        !widget.attaching) {
      return _Mode.rest;
    }
    if (!_voice) return _Mode.text;
    if (widget.attachments.isNotEmpty || widget.attaching) return _Mode.text;
    return _mode;
  }

  void _type() {
    setState(() => _mode = _Mode.text);
    // The field exists from the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _plus() {
    if (widget.sources.length == 1) return _pick(widget.sources.single);
    setState(() => _mode = _mode == _Mode.menu ? _Mode.rest : _Mode.menu);
  }

  void _pick(RendelAttachSource source) {
    // What was picked shows in the box, beside whatever is written with it.
    setState(() => _mode = _Mode.text);
    widget.onAttach!(source);
  }

  // Voice mode opens over the thread; the row stays as it is under it.
  void _listen() => widget.onVoice!();

  void _away() {
    _focus.unfocus();
    if (_mode == _Mode.menu ||
        (_mode == _Mode.text && widget.input.text.trim().isEmpty)) {
      setState(() => _mode = _Mode.rest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return TapRegion(
      onTapOutside: (_) => _away(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, theme.space.lg, 12, 0),
        child: switch (_shown) {
          _Mode.rest => _rest(theme),
          _Mode.menu => _menu(theme),
          _Mode.text => _box(theme),
        },
      ),
    );
  }

  IconData get _attachGlyph => switch (widget.attachIcon) {
        RendelAttachIcon.image => Icons.image_outlined,
        RendelAttachIcon.paperclip => Icons.attach_file_rounded,
        _ => Icons.add_rounded,
      };

  Widget _rest(RendelTheme theme) {
    final strings = RendelStringsScope.of(context);
    final status = widget.status;
    final primary = widget.primary;
    final still = MediaQuery.disableAnimationsOf(context);
    return _Arrive(
      key: const ValueKey(_Mode.rest),
      child: Padding(
        // 2 at the sides, not 6, as on the web: the room goes to a lit
        // action's label.
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_attach)
              _Round(
                icon: _attachGlyph,
                label: strings.attachFile,
                onTap: widget.busy ? null : _plus,
              )
            else
              const SizedBox(width: _Round.side),
            // While an answer page is on its way, a pill in the microphone's
            // place says what the turn is doing.
            Flexible(
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : theme.motion.settle,
                // Said from its first frame, however faint it still is.
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  alwaysIncludeSemantics: true,
                  child: child,
                ),
                child: status != null
                    ? _StatusPill(key: const ValueKey('status'), label: status)
                    : Row(
                        key: const ValueKey('mic'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MicPill(
                            icon: switch (widget.voiceIcon) {
                              RendelVoiceIcon.waveform => Icons.graphic_eq_rounded,
                              _ => Icons.mic_rounded,
                            },
                            label: strings.speak,
                            onTap: widget.busy ? null : _listen,
                            // A circle beside a lit action, as on the web, so
                            // at 360pt "Add to basket" and "Track my order"
                            // read whole; at 92 they cut off past ~9 letters.
                            width: primary == null ? 128 : 52,
                          ),
                          if (primary != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: _Arrive(
                                key: ValueKey(primary.label),
                                child: _LitAction(
                                  label: primary.label,
                                  onTap: primary.onTap,
                                  go: primary.go,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            _Round(
              icon: Icons.keyboard_outlined,
              label: strings.typeMessage,
              onTap: status != null ? null : _type,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(RendelTheme theme) {
    return _Arrive(
      key: const ValueKey(_Mode.menu),
      alignment: Alignment.bottomLeft,
      child: Align(
        alignment: AlignmentDirectional.bottomStart,
        child: LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth * 0.64),
            child: IntrinsicWidth(
              child: Container(
                /* The same glass as the box it opens from.
                
                   It was a plate at 94%: over a page with any colour on it the
                   menu read as a second app rather than as the composer
                   opening. The shadow stays — it lifts the menu off what it
                   covers, which the composer never has to do. */
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colors.shadow.withValues(alpha: 0.3),
                      offset: const Offset(0, 22),
                      blurRadius: 44,
                      spreadRadius: -18,
                    ),
                  ],
                ),
                child: _Glass(
                  radius: 26,
                  tint: theme.colors.composer,
                  edge: theme.composerEdge,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final source in widget.sources)
                          RendelPressable(
                            semanticLabel: _label(source),
                            onTap: () => _pick(source),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _glyph(source),
                                    size: 24,
                                    color: theme.colors.onComposer,
                                  ),
                                  const SizedBox(width: 14),
                                  Text(
                                    _label(source),
                                    style: theme.text.prose.copyWith(
                                      color: theme.colors.onComposer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One source is the host's own picker, drawn with the app's attach glyph.
  IconData _glyph(RendelAttachSource source) => widget.sources.length == 1
      ? _attachGlyph
      : switch (source) {
          RendelAttachSource.photos => Icons.image_outlined,
          RendelAttachSource.camera => Icons.photo_camera_outlined,
          RendelAttachSource.files => Icons.description_outlined,
        };

  String _label(RendelAttachSource source) {
    final strings = RendelStringsScope.of(context);
    if (widget.sources.length == 1) return strings.attachFile;
    return switch (source) {
      RendelAttachSource.photos => strings.photos,
      RendelAttachSource.camera => strings.camera,
      RendelAttachSource.files => strings.files,
    };
  }

  Widget _box(RendelTheme theme) {
    /* The hint was the literal 'Ask anything', and `RendelStrings.composerHint`
       has carried a translated one since the strings existed. The customer's
       published hint beats both. */
    final strings = RendelStringsScope.of(context);
    final attachments = widget.attachments;
    final busy = widget.busy;

    return _Arrive(
      key: const ValueKey(_Mode.text),
      /* One box, two rows: what you are writing, and what you can do with it.

         The border is the part that matters: WCAG 1.4.11 asks 3:1 of the
         boundary that identifies a control, and `composerEdge` is the token
         derived for it against whatever ground the box is drawn on. */
      child: _Glass(
        radius: theme.radius.card,
        tint: theme.colors.composer,
        edge: theme.composerEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // What is already attached, above the line you are writing.
            // Inside the box: these belong to the message being composed,
            // and each one removes itself, because picking the wrong file is
            // the most likely thing to go wrong here.
            if (attachments.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  theme.space.md,
                  theme.space.md,
                  theme.space.md,
                  0,
                ),
                child: Wrap(
                  spacing: theme.space.sm,
                  runSpacing: theme.space.sm,
                  children: [
                    for (var i = 0; i < attachments.length; i++)
                      _AttachmentCard(
                        pending: attachments[i],
                        onRemove: () => widget.onRemoveAttachment(i),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                theme.space.md + 2,
                theme.space.sm,
                theme.space.md,
                0,
              ),
              // Merged so the field carries a name once the hint is gone;
              // a TextField's only label is its hint, which the framework
              // drops from semantics as soon as the user types.
              child: MergeSemantics(
                child: Semantics(
                  label: strings.messageField,
                  child: TextField(
                    controller: widget.input,
                    focusNode: _focus,
                    enabled: !busy,
                    // Two lines before anything is written: room to see a
                    // question taking shape, not a single-line search box.
                    minLines: 2,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onSend(),
                    style: theme.text.prose.copyWith(
                      color: theme.colors.onComposer,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          busy ? strings.working : (widget.hint ?? strings.composerHint),
                      hintStyle: theme.text.prose.copyWith(
                        color: theme.onComposerFaint,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: theme.space.sm,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                theme.space.xs,
                0,
                theme.space.xs,
                theme.space.xs,
              ),
              child: Row(
                children: [
                  if (_attach)
                    for (final source in widget.sources)
                      _ComposerTool(
                        icon: _glyph(source),
                        label: _label(source),
                        // Off while an upload is in flight or a turn is
                        // running: a second picker over the first is a way to
                        // lose the file the user already chose.
                        onTap: widget.attaching || busy
                            ? null
                            : () => _pick(source),
                        pending: widget.attaching,
                      ),
                  const Spacer(),
                  // Only the button depends on what has been typed, so only
                  // the button rebuilds on a keystroke.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.input,
                    builder: (context, value, _) {
                      // Live only when there is something to send, and a
                      // photograph on its own is something to send.
                      final enabled = !busy &&
                          !widget.attaching &&
                          (value.text.trim().isNotEmpty ||
                              attachments.isNotEmpty);
                      final still = MediaQuery.disableAnimationsOf(context);
                      return RendelPressable(
                        semanticLabel: strings.sendMessage,
                        onTap: enabled ? widget.onSend : null,
                        // The press target keeps its 44pt floor; the circle
                        // is drawn inside it.
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: AnimatedContainer(
                              duration:
                                  still ? Duration.zero : theme.motion.swap,
                              curve: theme.motion.curve,
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: enabled
                                    ? theme.colors.accent
                                    : theme.onComposerFaint
                                        .withValues(alpha: 0.35),
                                // The rim every accent fill in the catalog
                                // carries: an icon-only button is identified
                                // by its fill alone, which is what WCAG
                                // 1.4.11 asks 3:1 of.
                                border: Border.all(
                                  color: enabled
                                      ? theme.accentEdge
                                      : Colors.transparent,
                                ),
                              ),
                              // The glyph eases with its own plate.
                              child: TweenAnimationBuilder<Color?>(
                                duration:
                                    still ? Duration.zero : theme.motion.swap,
                                curve: theme.motion.curve,
                                tween: ColorTween(
                                  end: enabled
                                      ? theme.colors.onAccent
                                      : theme.colors.composer,
                                ),
                                builder: (context, ink, _) => Icon(
                                  switch (widget.sendIcon) {
                                    RendelSendIcon.paperPlane => Icons.send_rounded,
                                    RendelSendIcon.arrowRight =>
                                      Icons.arrow_forward_rounded,
                                    _ => Icons.arrow_upward_rounded,
                                  },
                                  size: 18,
                                  color: ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round control at rest: the "+" and the keyboard. Half-clear, so the
/// thread shows through it the way it shows through the dock.
class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.label, required this.onTap});

  static const double side = 46;

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return RendelPressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colors.composer.withValues(alpha: 0.7),
          border: Border.all(color: theme.composerEdge),
          boxShadow: [
            BoxShadow(
              color: theme.colors.shadow.withValues(alpha: 0.25),
              offset: const Offset(0, 8),
              blurRadius: 20,
              spreadRadius: -12,
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 22,
          color: onTap == null ? theme.onComposerFaint : theme.colors.onComposer,
        ),
      ),
    );
  }
}

/// The microphone: the one filled control at rest, in the app's accent, set
/// in a ring of the composer's own ground.
class _MicPill extends StatelessWidget {
  const _MicPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.width = 128,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return RendelPressable(
      semanticLabel: label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : theme.motion.settle,
        curve: theme.motion.curve,
        width: width,
        height: 52,
        decoration: BoxDecoration(
          color: theme.colors.accent,
          borderRadius: BorderRadius.circular(26),
          // Painted in order: the drop shadow, the edge, then the ring.
          boxShadow: [
            BoxShadow(
              color: theme.colors.shadow.withValues(alpha: 0.35),
              offset: const Offset(0, 14),
              blurRadius: 28,
              spreadRadius: -14,
            ),
            BoxShadow(color: theme.composerEdge, spreadRadius: 5),
            // The composer's glass, as the box is drawn.
            BoxShadow(
              color: theme.colors.composer.withValues(alpha: _Glass.tintAlpha),
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, size: 24, color: theme.colors.onAccent),
      ),
    );
  }
}

/// Rises into place once, when it first appears: fading in, a few points
/// low and a touch small. Keyed by what it holds, so the row, the box and the
/// menu each arrive when they replace one another. Nothing leaves with an
/// animation, which keeps one message field on screen at a time.
class _Arrive extends StatefulWidget {
  const _Arrive({
    super.key,
    required this.child,
    this.alignment = Alignment.bottomCenter,
  });

  final Widget child;

  /// Where it grows from.
  final Alignment alignment;

  @override
  State<_Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<_Arrive> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: rendelEase);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller.duration = RendelThemeScope.of(context).motion.settle;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      // The control is there from its first frame, whatever it looks like.
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 8 * (1 - _curve.value)),
          child: Transform.scale(
            scale: 0.96 + 0.04 * _curve.value,
            alignment: widget.alignment,
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Voice mode, over everything under the header.
///
/// A frosted wash in the app's accent, and a soft glow rising from the
/// bottom — an ellipse wider than the screen whose top edge the conversation
/// blurs under — that swells with the speaker's voice. The words are written
/// in the middle as they arrive. The console's Test page and the web SDK draw
/// the same.
class _VoiceMode extends StatefulWidget {
  const _VoiceMode({
    super.key,
    required this.heard,
    required this.level,
    required this.voiceIcon,
    required this.onStop,
    required this.onCancel,
  });

  final String heard;
  final ValueListenable<double>? level;
  final RendelVoiceIcon voiceIcon;

  /// Stops listening and sends. Null when the recogniser cannot be stopped.
  final VoidCallback? onStop;
  final VoidCallback onCancel;

  @override
  State<_VoiceMode> createState() => _VoiceModeState();
}

class _VoiceModeState extends State<_VoiceMode>
    with SingleTickerProviderStateMixin {
  // The glow's slow drift, so it is alive between words.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _drift.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final colors = theme.colors;
    final glow = Color.lerp(colors.surface, Colors.white, 0.88)!;
    final lavender = Color.lerp(colors.accent, const Color(0xFF7D8CF2), 0.55)!;

    return LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          final height = box.maxHeight;
          final domeHeight = height * 0.66;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // The wash: light, so the conversation stays readable up top.
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.30),
                        gradient: RadialGradient(
                          center: const Alignment(1, -1),
                          radius: 1.1,
                          colors: [
                            colors.accent.withValues(alpha: 0.20),
                            colors.accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-1, -0.3),
                            radius: 1.2,
                            colors: [
                              lavender.withValues(alpha: 0.22),
                              lavender.withValues(alpha: 0),
                            ],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              // The glow.
              Positioned(
                left: -width * 0.35,
                right: -width * 0.35,
                bottom: -height * 0.18,
                height: domeHeight,
                child: ValueListenableBuilder<double>(
                  valueListenable: widget.level ?? const _Silent(),
                  builder: (context, level, child) => TweenAnimationBuilder<double>(
                    tween: Tween(end: 1 + 0.07 * level),
                    duration: const Duration(milliseconds: 160),
                    builder: (context, swell, child) => Transform.scale(
                      scale: swell,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                    child: child,
                  ),
                  child: AnimatedBuilder(
                    animation: _drift,
                    builder: (context, child) {
                      final t = Curves.easeInOut.transform(_drift.value);
                      return Transform.translate(
                        offset: Offset(
                          width * (-0.04 + 0.08 * t),
                          domeHeight * (0.02 - 0.04 * t),
                        ),
                        child: child,
                      );
                    },
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              stops: const [0, 0.62, 0.88, 1],
                              colors: [
                                glow,
                                glow.withValues(alpha: 0.82),
                                glow.withValues(alpha: 0.40),
                                glow.withValues(alpha: 0),
                              ],
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // A tap anywhere but the microphone lets the question go. Its
              // own layer, under the words and the pill, so it takes no
              // label of theirs; the pill is the way to it for a reader.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: widget.onCancel,
                ),
              ),
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // The words.
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.09,
                      ),
                      child: Semantics(
                        container: true,
                        liveRegion: true,
                        child: Text(
                          widget.heard.isEmpty
                              ? '${strings.listening}…'
                              : widget.heard,
                          textAlign: TextAlign.center,
                          style: theme.text.body.copyWith(
                            fontSize: 17,
                            height: 1.35,
                            fontWeight: widget.heard.isEmpty
                                ? FontWeight.w500
                                : FontWeight.w600,
                            color: widget.heard.isEmpty
                                ? colors.onSurface.withValues(alpha: 0.45)
                                : colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: math.max(MediaQuery.paddingOf(context).bottom, 18),
                      ),
                      child: SizedBox(
                        height: 60,
                        child: Center(
                          child: _Breathing(
                            child: _MicPill(
                              icon: switch (widget.voiceIcon) {
                                RendelVoiceIcon.waveform =>
                                  Icons.graphic_eq_rounded,
                                _ => Icons.mic_rounded,
                              },
                              label: strings.stopListening,
                              onTap: widget.onStop,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
  }
}

/// A level that never moves, for a host's recogniser that reports none.
class _Silent extends ValueListenable<double> {
  const _Silent();

  @override
  double get value => 0;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// A file the user picked and the server accepted, waiting for its turn.
/// A file waiting on the composer, as the thing it is.
///
/// A filename in a pill was what this used to be, and it was wrong twice over:
/// a photograph is recognised by looking at it, not by reading
/// `image_picker_33893816-5E2E-495D…`, and a document is recognised by its
/// name and its size, which the pill had room for neither of.
///
/// So a picture shows itself and a document says what it is. Both carry the
/// same corner control, because the most likely thing to go wrong here is
/// picking the wrong file.
class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.pending, required this.onRemove});

  final _Pending pending;
  final VoidCallback onRemove;

  static const double _side = 92;

  /// The remove control: what is drawn, and what is pressed.
  ///
  /// `RendelPressable` floors every target at 44pt, and a decorated box handed
  /// that floor paints to it — so the "20pt" circle of 0.10.1 rendered as a
  /// 44pt one, the width of half the card, and nobody's numbers said so. The
  /// target keeps its floor; the circle is centred in it, and the box is
  /// pushed out so the circle overhangs the corner by [_overhang].
  static const double _dot = 22;
  static const double _target = 44;
  static const double _overhang = 6;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);

    return SizedBox(
      width: _side,
      height: _side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(theme.radius.card),
              child: pending.isImage
                  ? Image.memory(
                      pending.bytes,
                      fit: BoxFit.cover,
                      // A picture that cannot be decoded is still a file that
                      // was uploaded, so it falls back to the document face
                      // rather than to a broken-image glyph.
                      errorBuilder: (context, _, __) => _document(theme),
                    )
                  : _document(theme),
            ),
          ),
          /* While the bytes are going up.
          
             A scrim over the card and the catalog's breathing dot: the file
             is visibly there and visibly not ready, which is the difference
             between a slow upload and a picker that did nothing. No remove
             control yet — there is no id to cancel and the upload is seconds
             at most. */
          if (pending.id == null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(theme.radius.card),
                child: ColoredBox(
                  color: theme.colors.surface.withValues(alpha: 0.62),
                  child: Center(
                    child: RendelPulse(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: theme.colors.onSurface,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned(
              top: -_overhang - (_target - _dot) / 2,
              right: -_overhang - (_target - _dot) / 2,
              child: RendelPressable(
                semanticLabel: RendelStringsScope.of(context).removeFileNamed(pending.name),
                onTap: onRemove,
                child: SizedBox(
                  width: _target,
                  height: _target,
                  child: Center(
                    child: Container(
                      width: _dot,
                      height: _dot,
                      decoration: BoxDecoration(
                        color: theme.colors.onSurface,
                        shape: BoxShape.circle,
                        // A ring in the composer's own ground, so the control
                        // reads as sitting on top of the card rather than
                        // punched into it.
                        border:
                            Border.all(color: theme.colors.composer, width: 2),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: theme.colors.surface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _document(RendelTheme theme) {
    return Container(
      padding: EdgeInsets.all(theme.space.sm),
      color: theme.colors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: theme.type.title,
            color: theme.colors.onSurfaceSoft,
          ),
          const Spacer(),
          Text(
            pending.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.text.caption.copyWith(color: theme.colors.onSurface),
          ),
          Text(
            pending.size,
            maxLines: 1,
            style: theme.text.caption.copyWith(
              color: theme.colors.onSurfaceFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pending {
  const _Pending({
    required this.id,
    required this.name,
    required this.mediaType,
    required this.bytes,
  });

  _Pending withId(String uploaded) => _Pending(
        id: uploaded,
        name: name,
        mediaType: mediaType,
        bytes: bytes,
      );

  /// Null while the upload is still in flight. The card exists from the moment
  /// the file is chosen — a picker that closes onto an unchanged screen reads
  /// as a picker that failed — and the id arrives a moment later.
  final String? id;
  final String name;
  final String mediaType;

  /// Kept for the preview, not for the wire — the upload has already happened
  /// by the time one of these exists. A picture the user chose is the only
  /// honest thumbnail of itself, and they came in memory anyway.
  final Uint8List bytes;

  bool get isImage => mediaType.startsWith('image/');

  /// Rounded the way a file manager rounds it: nobody needs three decimals of
  /// a photograph.
  String get size {
    final kb = bytes.length / 1024;
    if (kb < 1) return '${bytes.length} B';
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// A glyph that grows and shrinks while something is live.
///
/// Scale rather than the catalog's `RendelPulse`, which fades: a control that is
/// recording has to look like it is recording, and breathing reads as alive
/// where a fade reads as broken. It borrows the same motion tokens, so it
/// keeps time with everything else the thread animates.
class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});

  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  // No theme lookup in the initialisers: the scope is not reachable yet.
  late final AnimationController _controller = AnimationController(vsync: this);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  late final Animation<double> _scale =
      Tween<double>(begin: 1, end: 1.18).animate(_curve);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = RendelThemeScope.of(context).motion;
    _controller.duration = motion.breath;
    _curve.curve = motion.breathCurve;
    if (_started) return;
    _started = true;
    // Somebody who asked for less motion still has to know it is on; the
    // accent colour carries that, and nothing moves.
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// The composer's box as glass: what is behind it — the page, its wash —
/// shows through blurred, under a thin light edge at the top.
///
/// Less than half the composer's own colour, so the colour behind it is
/// plainly there; the words in it are the composer's ink, which the lights
/// behind — pastel, and faint — do not take far from the composer.
class _Glass extends StatelessWidget {
  const _Glass({
    required this.radius,
    required this.tint,
    required this.edge,
    required this.child,
  });

  /// How much of the composer's colour the glass keeps.
  ///
  /// It was 0.40, which over a pale ground is a white plate: the page behind
  /// it stopped at the composer's edge instead of passing under it. The blur
  /// is what makes it legible, not the fill.
  static const tintAlpha = 0.20;

  final double radius;
  final Color tint;
  final Color edge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    /* No drop shadow. Flutter paints a box's shadow under the whole box, not
       only outside it as CSS does, and through glass that shows as a grey
       smudge in the middle of the composer. The edge carries the shape. */
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: tintAlpha),
            border: Border.all(color: edge),
            borderRadius: shape,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.08],
              colors: [
                Colors.white.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ——— answer pages (`design/PAGES.md`) ———
//
// The timings below are the brief's own, which belong to the page and to
// nothing in the catalog: the question's 150ms a word, the 500ms dissolve,
// the wash's 600ms fade and 6s drift, the ring's 900ms turn.

/// The microphone's place while an answer page is on its way: the lit fill
/// the primary action wears, a small turning ring, and what the turn is
/// doing, the words crossfading as they change.
class _StatusPill extends StatelessWidget {
  const _StatusPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final ink = theme.colors.onAccent;
    // A fade-through, as every swap in the SDK is: the old step is gone
    // before the new one shows, so the two never sit on each other.
    Widget words = AnimatedSwitcher(
      duration: still ? Duration.zero : theme.motion.settle,
      switchOutCurve: theme.motion.swapOut,
      switchInCurve: theme.motion.swapIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, if (current != null) current],
      ),
      child: Text(
        label,
        key: ValueKey(label),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.text.label.copyWith(fontSize: 14.5, color: ink),
      ),
    );
    // A longer step widens the pill rather than snapping it: the words'
    // room eases, inside the pill, so its corners stay round. No size
    // animation at all under reduced motion: see `RendelSwap`.
    if (!still) {
      words = AnimatedSize(
        duration: theme.motion.settle,
        curve: theme.motion.curve,
        alignment: AlignmentDirectional.centerStart,
        child: words,
      );
    }
    final pill = Container(
      height: 52,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 20, 0),
      decoration: _litPill(theme),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Ring(color: ink),
          const SizedBox(width: 10),
          Flexible(child: words),
        ],
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: pill,
    );
  }
}

/// The lit fill the primary action wears, as a pill 52 high.
BoxDecoration _litPill(RendelTheme theme) {
  const unpainted = BorderSide(width: 1, style: BorderStyle.none);
  return BoxDecoration(
    gradient: theme.litFill,
    border: const Border(
      top: BorderSide(color: RendelTheme.litEdge),
      left: unpainted,
      right: unpainted,
      bottom: unpainted,
    ),
    borderRadius: BorderRadius.circular(26),
    boxShadow: RendelTheme.litShadow,
  );
}

/// A card's first action beside the microphone while its detail is open, or
/// the page's first screen of the app.
class _LitAction extends StatelessWidget {
  const _LitAction({required this.label, required this.onTap, this.go = false});

  final String label;
  final VoidCallback onTap;

  /// Opens a screen of the app: the ↗ the screen's card ends with follows
  /// the label.
  final bool go;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return RendelPressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        height: 52,
        // The web's widths (Web 0.23.0): with the microphone a circle beside
        // it, ~14 letters fit at a 360pt screen.
        padding: EdgeInsets.symmetric(horizontal: go ? 14 : 18),
        decoration: _litPill(theme),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.text.labelStrong.copyWith(fontSize: go ? 14.5 : 15),
              ),
            ),
            if (go) ...[
              const SizedBox(width: 6),
              Icon(Icons.north_east_rounded, size: 15, color: theme.text.labelStrong.color),
            ],
          ],
        ),
      ),
    );
  }
}

/// A 14pt ring turning while the turn is in flight: one lit quarter on a
/// faint track. Still under reduced motion.
class _Ring extends StatefulWidget {
  const _Ring({required this.color});

  final Color color;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _turn,
      child: CustomPaint(
        size: const Size.square(14),
        painter: _RingPainter(widget.color),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawOval(rect, stroke..color = color.withValues(alpha: 0.3));
    canvas.drawArc(rect, -math.pi * 0.75, math.pi / 2, false, stroke..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

/// The question, written over the screen as it is asked: centred, large, a
/// word every 150ms coming out of a blur.
class _Asked extends StatefulWidget {
  const _Asked({required this.text, this.whole = false});

  final String text;

  /// Shown at once: a spoken question, already written out live by voice
  /// mode as it was heard.
  final bool whole;

  @override
  State<_Asked> createState() => _AskedState();
}

class _AskedState extends State<_Asked> with SingleTickerProviderStateMixin {
  static const _perWord = 150;
  static const _settle = 260;

  late final List<String> _words =
      widget.text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  late final int _total = _words.length * _perWord + _settle;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _total),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.whole || MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    } else {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// How far word [index] has come in, 0 to 1.
  double _shown(int index) =>
      ((_reveal.value * _total - (index + 1) * _perWord) / _settle).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final style = theme.text.title.copyWith(
      fontSize: 26,
      height: 1.25,
      letterSpacing: -0.02 * 26,
    );
    final words = _words.join(' ');
    return Semantics(
      liveRegion: true,
      label: widget.text,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: balancedWidth(
            words,
            style,
            box.maxWidth,
            MediaQuery.textScalerOf(context),
            Directionality.of(context),
          ),
          child: AnimatedBuilder(
            animation: _reveal,
            builder: (context, _) => Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < _words.length; i++)
                    TextSpan(
                      text: i == _words.length - 1 ? _words[i] : '${_words[i]} ',
                      style: style.copyWith(foreground: _ink(theme, _shown(i))),
                    ),
                ],
              ),
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
        ),
      ),
    );
  }

  Paint _ink(RendelTheme theme, double shown) {
    final paint = Paint()
      ..color = theme.colors.onSurface.withValues(alpha: 0.12 + 0.88 * shown);
    if (shown < 1) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * (1 - shown));
    }
    return paint;
  }
}

/// The page making way for a question: blurred, faded and a touch smaller,
/// and back again as the answer arrives. The same widgets either way, so
/// nothing under it is rebuilt from scratch when it starts or stops.
class _Dissolve extends StatelessWidget {
  const _Dissolve({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: on ? 1 : 0),
      duration: still ? Duration.zero : const Duration(milliseconds: 500),
      curve: rendelEase,
      builder: (context, t, child) => Opacity(
        opacity: 1 - 0.75 * t,
        child: Transform.scale(
          scale: 1 - 0.02 * t,
          child: ImageFiltered(
            enabled: t > 0,
            // 14px of CSS blur.
            imageFilter: ImageFilter.blur(sigmaX: 7 * t, sigmaY: 7 * t),
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// A page's ground fading in over its edge: solid for the first [solid] of
/// it at the top, from 55% down at the bottom.
class _Fade extends StatelessWidget {
  const _Fade({required this.ground, required this.top, this.solid = 0.55});

  final Color ground;
  final bool top;
  final double solid;

  @override
  Widget build(BuildContext context) {
    final clear = ground.withValues(alpha: 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, top ? solid.clamp(0.0, 1.0) : 0.55, 1],
          colors: top ? [ground, ground, clear] : [clear, ground, ground],
        ),
      ),
    );
  }
}

/// The ambient wash behind a question: three soft lights, yellow, lavender
/// and peach, over the page's ground, drifting slowly while it shows. On a
/// deep ground the same hues at 18%.
class _Wash extends StatefulWidget {
  const _Wash({required this.on, required this.ground});

  final bool on;
  final Color ground;

  @override
  State<_Wash> createState() => _WashState();
}

class _WashState extends State<_Wash> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Wash oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Drifting only while it shows, and never under reduced motion.
  void _sync() {
    final drift = widget.on && !MediaQuery.disableAnimationsOf(context);
    if (drift && !_drift.isAnimating) {
      _drift.repeat(reverse: true);
    } else if (!drift && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final deep = theme.colors.onSurface.computeLuminance() >
        theme.colors.surface.computeLuminance();
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.on ? 1 : 0,
        duration: still ? Duration.zero : const Duration(milliseconds: 600),
        curve: rendelEase,
        child: AnimatedBuilder(
          animation: _drift,
          builder: (context, _) => CustomPaint(
            painter: _WashPainter(
              ground: widget.ground,
              deep: deep,
              at: Curves.easeInOut.transform(_drift.value),
            ),
          ),
        ),
      ),
    );
  }
}

class _WashPainter extends CustomPainter {
  _WashPainter({required this.ground, required this.deep, required this.at});

  final Color ground;
  final bool deep;

  /// Where the drift is, 0 to 1.
  final double at;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    // The lights are laid out on a field 160% of the screen that slides
    // across it, as a CSS background of that size moving from 0% to 100%.
    final field = size * 1.6;
    final origin = Offset(
      -(field.width - size.width) * at,
      -(field.height - size.height) * at,
    );
    void light(double x, double y, double rx, double ry, Color color, double alpha) {
      final tone = color.withValues(alpha: deep ? 0.18 : alpha);
      canvas
        ..save()
        ..translate(origin.dx + field.width * x, origin.dy + field.height * y)
        ..scale(field.width * rx, field.height * ry);
      canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = RadialGradient(
            colors: [tone, tone.withValues(alpha: 0)],
            stops: const [0, 0.72],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
      );
      canvas.restore();
    }

    // Bottom layer first: the first light the brief names is the one on top.
    light(0.25, 0.88, 0.70, 0.50, const Color(0xFFFAD0C0), 0.85);
    light(0.90, 0.50, 0.65, 0.50, const Color(0xFFD0C8F6), 0.90);
    light(0.15, 0.25, 0.70, 0.45, const Color(0xFFFEF7AF), 0.95);
  }

  @override
  bool shouldRepaint(_WashPainter old) =>
      old.at != at || old.ground != ground || old.deep != deep;
}

// ——— a card opened over its page (`design/DETAIL.md`) ———
//
// The timings are the brief's own: the sheet's 460ms rise and 320ms fall,
// and the 240ms the top fade and the dots take.

/// A card opened over the page it was on, covering the whole copilot under
/// the composer, with its own scroll: the card's pictures, its name and what
/// it said of itself at once, and the answer's blocks under them as they
/// arrive. The page under it is never touched.
class _DetailSheet extends StatefulWidget {
  const _DetailSheet({
    super.key,
    required this.detail,
    required this.closing,
    required this.onClose,
    required this.onClosed,
    required this.dock,
    required this.body,
  });

  final RendelDetail detail;

  /// Sliding away; [onClosed] once it has.
  final bool closing;
  final VoidCallback onClose;
  final VoidCallback onClosed;

  /// The composer's height, which the end of the sheet scrolls clear of.
  final ValueListenable<double> dock;

  /// The answer's blocks.
  final Widget body;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(vsync: this);
  bool _started = false;

  /// Scrolled past the pictures: the sheet fades under the close button, as
  /// a page does under its header. Over the pictures it does not, so a
  /// picture runs to the top edge.
  bool _past = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 1;
    } else {
      _slide.animateTo(1, duration: const Duration(milliseconds: 460), curve: rendelEase);
    }
  }

  @override
  void didUpdateWidget(_DetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.closing && widget.closing) {
      _slide
          .animateBack(
            0,
            duration: const Duration(milliseconds: 320),
            curve: const Cubic(0.4, 0, 1, 1),
          )
          .then((_) {
        if (mounted) widget.onClosed();
      });
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final detail = widget.detail;
    final ground = theme.colors.surfaceRaised;
    final meta = [detail.subtitle, detail.price]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' · ');
    // The close button's foot, which the top fade is solid down to.
    final bar = theme.space.lg + 40;
    return LayoutBuilder(
      builder: (context, box) {
        final hero = math.min(330.0, box.maxHeight * 0.45);
        final pictures = detail.images.isNotEmpty;
        return AnimatedBuilder(
          animation: _slide,
          builder: (context, child) => FractionalTranslation(
            translation: Offset(0, 1 - _slide.value),
            child: child,
          ),
          child: PopScope(
            // The system back closes the sheet, not the copilot.
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) widget.onClose();
            },
            // Over the page, for a screen reader too.
            child: BlockSemantics(
              child: ColoredBox(
                color: ground,
                child: Stack(
                  children: [
                    NotificationListener<ScrollUpdateNotification>(
                      onNotification: (note) {
                        if (note.metrics.axis != Axis.vertical) return false;
                        final past =
                            note.metrics.pixels > (pictures ? hero - 80 : 0);
                        if (past != _past) setState(() => _past = past);
                        return false;
                      },
                      child: ValueListenableBuilder<double>(
                        valueListenable: widget.dock,
                        builder: (context, dock, _) => ListView(
                          padding: EdgeInsets.only(bottom: dock + 40),
                          children: [
                            if (pictures)
                              _Hero(
                                images: detail.images,
                                height: hero,
                                alt: detail.title,
                              ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                _ThreadScreenState._pageInset,
                                pictures ? 26 : bar + 16,
                                _ThreadScreenState._pageInset,
                                0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      detail.title,
                                      textAlign: TextAlign.center,
                                      style: theme.text.title.copyWith(
                                        fontSize: 25,
                                        height: 1.2,
                                        letterSpacing: -0.02 * 25,
                                      ),
                                    ),
                                  ),
                                  if (meta.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      meta,
                                      textAlign: TextAlign.center,
                                      style: theme.text.body.copyWith(
                                        fontSize: 13.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  widget.body,
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: bar + 32,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _past ? 1 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          child: _Fade(
                            ground: ground,
                            top: true,
                            solid: bar / (bar + 32),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 128,
                      child: IgnorePointer(
                        child: _Fade(ground: ground, top: false),
                      ),
                    ),
                    PositionedDirectional(
                      top: theme.space.lg,
                      start: theme.space.plate,
                      child: _GlassRound(
                        icon: Icons.close_rounded,
                        label: strings.closeDetail,
                        onTap: widget.onClose,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A card's pictures, full bleed, one to a screen and snapping, with a dot
/// for each under them when there is more than one.
class _Hero extends StatefulWidget {
  const _Hero({required this.images, required this.height, required this.alt});

  final List<String> images;
  final double height;

  /// What the first picture is of.
  final String alt;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  int _at = 0;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final images = widget.images;
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          PageView(
            onPageChanged: (at) => setState(() => _at = at),
            children: [
              for (var i = 0; i < images.length; i++)
                RendelPhoto(
                  url: images[i],
                  height: widget.height,
                  alt: i == 0 ? widget.alt : null,
                ),
            ],
          ),
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < images.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: still
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                        curve: rendelEase,
                        width: i == _at ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          // The light page's ink in either theme: the dots
                          // sit on the photograph, which a catalogue shoots
                          // on a pale ground, not on the page.
                          color: const Color(0xFF171615)
                              .withValues(alpha: i == _at ? 0.75 : 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A round glass button, 40 across: the sheet's close.
class _GlassRound extends StatelessWidget {
  const _GlassRound({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    // As the page's back and forward are drawn, and with no drop shadow for
    // the same reason.
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colors.surfaceHigh.withValues(alpha: 0.72),
                border: Border.all(color: theme.hairline),
              ),
              child: Icon(icon, size: 20, color: theme.colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
