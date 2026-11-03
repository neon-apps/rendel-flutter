import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/config.dart' show RendelAttachment, RendelAttachSource;
import '../core/strings.dart';
import '../core/support.dart';
import '../protocol/protocol.dart' show CancelAction, ConfirmAction, NavigateAction, UIAction, WireBlock;
import 'renderer/blocks.dart' show RendelActionButton, RendelPressable;
import 'renderer/registry.dart';
import 'theme.dart';

/// Opens the person's thread with the app's own team (human support, design/
/// plans/human-support.md §3.3) as a sheet over what is on screen, drawn as a
/// messaging app is and as the web SDK draws it: the team's name and whether
/// they are here, the person's lines on one side in the app's colour and the
/// team's on the other under who wrote them, a speaker's lines within five
/// minutes as one run with its time (never "Seen" or "Read": K9), the email
/// the reply goes to when nobody could reach the person otherwise (K14), and
/// one box to write in.
///
/// [onAction] carries out a tap on a card the team sent: a screen, a link, a
/// call. The sheet closes first when it opens a screen of the app.
Future<void> showRendelSupport(
  BuildContext context, {
  required RendelSupport support,
  required String team,
  required Future<bool> Function(UIAction action) onAction,
  required bool Function(UIAction action) canHandle,
  String? Function(String route)? routeTitle,
  Future<RendelAttachment?> Function(RendelAttachSource source)? onPick,
  Future<String> Function(RendelAttachment file)? onUpload,
  RendelTheme? theme,
  RendelStrings? strings,
}) {
  final drawn = theme ?? RendelThemeScope.of(context);
  final words = strings ?? RendelStringsScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: drawn.colors.surfaceRaised,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(drawn.radius.hero)),
    ),
    clipBehavior: Clip.antiAlias,
    // The keyboard takes the bottom of the screen: the page sits on it, and the place to write stays in sight.
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: RendelThemeScope(
        theme: drawn,
        child: RendelStringsScope(
          strings: words,
          child: RendelSupportSheet(
            support: support,
            team: team,
            onAction: onAction,
            canHandle: canHandle,
            routeTitle: routeTitle,
            onPick: onPick,
            onUpload: onUpload,
          ),
        ),
      ),
    ),
  );
}

class RendelSupportSheet extends StatefulWidget {
  const RendelSupportSheet({
    super.key,
    required this.support,
    required this.team,
    required this.onAction,
    required this.canHandle,
    this.routeTitle,
    this.onPick,
    this.onUpload,
  });

  final RendelSupport support;
  final String team;
  final Future<bool> Function(UIAction action) onAction;
  final bool Function(UIAction action) canHandle;
  final String? Function(String route)? routeTitle;

  /// Picks a photo or a file, and uploads it; without them the page takes text only.
  final Future<RendelAttachment?> Function(RendelAttachSource source)? onPick;
  final Future<String> Function(RendelAttachment file)? onUpload;

  @override
  State<RendelSupportSheet> createState() => _RendelSupportSheetState();
}

class _RendelSupportSheetState extends State<RendelSupportSheet> with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String? _note;
  Timer? _typingEnds;
  bool _attaching = false;

  /// The paperclip's two choices, under the box, while open.
  bool _menu = false;

  /// The email card: whether the person has left the field or tapped Save (a warning shows from then on), what the
  /// server refused, and that the address went; the code card's wrong code.
  final FocusNode _emailFocus = FocusNode();
  bool _emailWarned = false;
  String? _emailRefused;
  bool _contactSaved = false;
  bool _codeWrong = false;

  /// A line landed while the person had scrolled up to read: the pill brings them back.
  bool _newBelow = false;

  /// Cards the team sent that this phone asked to open, so each is minted once.
  final Set<String> _opening = {};

  late final RendelDispatcher _dispatch = RendelDispatcher(
    onAction: (action) async {
      // A confirm card the team sent answers through Support: never a turn.
      if (action is ConfirmAction || action is CancelAction) {
        final confirm = action is ConfirmAction;
        final id = action is ConfirmAction ? action.invocationId : (action as CancelAction).invocationId;
        final done = await widget.support.decideCard(id, confirm: confirm);
        final ok = done == 'succeeded' || done == 'declined';
        if (mounted) setState(() => _note = ok ? null : RendelStringsScope.of(context).turnFailed);
        return ok;
      }
      if (action is NavigateAction && mounted) Navigator.of(context).maybePop();
      return widget.onAction(action);
    },
    onSubmitForm: (_, __) async => throw UnsupportedError('A card the team sends carries no form.'),
    canHandle: widget.canHandle,
    routeTitle: widget.routeTitle,
  );

  @override
  void initState() {
    super.initState();
    // Leaving the field with something in it is when a wrong address is said, never while the first letters go in.
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus && _email.text.trim().isNotEmpty && !_emailWarned && mounted) setState(() => _emailWarned = true);
    });
    WidgetsBinding.instance.addObserver(this);
    widget.support.value.addListener(_changed);
    // The stream follows a thread, so it opens once the thread is read.
    unawaited(widget.support.load().then((_) {
      if (mounted) widget.support.watch(true);
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // In the background the stream would only hold a socket; on return the thread is read again.
    final on = state == AppLifecycleState.resumed;
    widget.support.watch(on);
    if (on) unawaited(widget.support.load());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    widget.support.read();
    final until = widget.support.value.value.typingUntil;
    _typingEnds?.cancel();
    if (until != null && until.isAfter(DateTime.now())) {
      _typingEnds = Timer(until.difference(DateTime.now()) + const Duration(milliseconds: 50), () {
        if (mounted) setState(() {});
      });
    }
    final lines = widget.support.value.value.entries.length;
    final grew = lines != _drawn;
    _drawn = lines;
    final following = !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
    if (grew && !following) {
      setState(() => _newBelow = true);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _toNewest());
  }

  int _drawn = 0;

  void _toNewest() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    if (_newBelow && mounted) setState(() => _newBelow = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.support.value.removeListener(_changed);
    widget.support.watch(false);
    _typingEnds?.cancel();
    _input.dispose();
    _email.dispose();
    _emailFocus.dispose();
    _code.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final sent = await widget.support.send(text);
    // The line waits for the address: it goes back in the field, the card asks.
    if (sent == 'contact_required' && mounted) setState(() => _input.text = text);
  }

  /// Picks, uploads and sends a file as its own line (K11: a picture or a PDF).
  Future<void> _attach(RendelAttachSource source, RendelStrings strings) async {
    final pick = widget.onPick;
    final upload = widget.onUpload;
    if (pick == null || upload == null || _attaching) return;
    setState(() {
      _attaching = true;
      _note = null;
    });
    try {
      final file = await pick(source);
      if (file == null) return;
      final id = await upload(file);
      await widget.support.send('', attachmentIds: [id], fileName: file.name);
    } catch (_) {
      if (mounted) setState(() => _note = strings.attachFailed);
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  /// Sends only an address the server would take; what it refuses is said under the field.
  Future<void> _saveEmail(RendelStrings strings) async {
    setState(() {
      _emailWarned = true;
      _emailRefused = null;
    });
    if (supportEmailProblem(_email.text) != null) return _emailFocus.requestFocus();
    final result = await widget.support.contact(_email.text.trim());
    if (!mounted) return;
    setState(() {
      switch (result) {
        case 'invalid':
          _emailRefused = strings.supportContactInvalid;
        case 'failed':
          _emailRefused = strings.turnFailed;
        default:
          _email.clear();
          _emailWarned = false;
          _contactSaved = true;
      }
    });
  }

  Future<void> _verify(RendelStrings strings) async {
    final ok = await widget.support.verify(_code.text.trim());
    if (mounted) {
      setState(() {
        _codeWrong = !ok;
        if (ok) _contactSaved = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final v = widget.support.value.value;
    final state = v.state;
    final resolved = state?.resolved ?? false;
    final contact = state?.contactState ?? 'not_needed';
    // The first line always goes (the server takes it); the one after it waits for an email.
    final needsContact = (state?.contactRequired ?? false) && v.entries.any((e) => e.author == RendelSupportAuthorKind.user);
    // The optional box is for the wait: once the team is talking, it gives the page back.
    final offersContact = !needsContact &&
        contact == 'none' &&
        v.entries.any((e) => e.author == RendelSupportAuthorKind.user) &&
        !v.entries.any((e) => e.author == RendelSupportAuthorKind.agent);
    final justHanded = !resolved && !v.entries.any((e) => e.author == RendelSupportAuthorKind.agent);
    final typing = v.typingUntil != null && v.typingUntil!.isAfter(DateTime.now());
    final agent = state?.agentName;

    // A speaker's lines within five minutes are one run, as the web SDK groups them; a marker ends one.
    final items = <Object>[];
    _Run? run;
    for (final entry in v.entries) {
      if (entry.marker) {
        run = null;
        items.add(entry.text ?? '');
        continue;
      }
      final mine = entry.author == RendelSupportAuthorKind.user;
      final who = mine ? strings.supportYou : (entry.authorName ?? widget.team);
      final key = '${mine ? 'me' : 'team'}:$who';
      if (run != null && run.key == key && entry.createdAt.difference(run.at) <= _runGap) {
        run.entries.add(entry);
        run.at = entry.createdAt;
      } else {
        run = _Run(key: key, mine: mine, who: who, at: entry.createdAt, entries: [entry]);
        items.add(run);
      }
    }
    final lines = <Widget>[
      for (final item in items) item is _Run ? _run(context, theme, strings, item) : _marker(theme, item as String),
      if (v.pending.isNotEmpty) _pending(theme, strings, v.pending),
      if (state?.expectation case final expectation? when state!.mode != 'human') _wait(context, theme, expectation),
      // Newest of all: someone from the team is writing.
      if (typing)
        Semantics(
          label: strings.supportTypingOf(agent ?? widget.team),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _avatar(theme, agent ?? widget.team),
              const SizedBox(width: 8),
              _bubble(theme, _TypingDots(color: theme.colors.onSurfaceSoft), mine: false, first: true),
            ],
          ),
        ),
      // The server's own line says it closed when the last thing that happened was closing it.
      if (resolved && !(v.entries.lastOrNull?.marker ?? false)) _marker(theme, strings.supportClosed),
    ];

    return SafeArea(
      top: false,
      child: SizedBox(
        height: math.max(MediaQuery.sizeOf(context).height * 0.88 - MediaQuery.viewInsetsOf(context).bottom, 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(theme.space.sm, theme.space.md, theme.space.md, theme.space.sm),
              child: Row(
                children: [
                  IconButton(
                    tooltip: null,
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colors.surfaceRaised,
                      side: BorderSide(color: theme.hairline),
                    ),
                    icon: Icon(Icons.close_rounded, size: 18, color: theme.colors.onSurface, semanticLabel: strings.supportBack),
                  ),
                  SizedBox(width: theme.space.xs),
                  _avatar(theme, agent ?? widget.team, size: 36),
                  SizedBox(width: theme.space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(strings.supportTeamOf(widget.team), style: theme.text.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                // No status green in the theme (`danger`'s note): here is the app's own colour.
                                color: (state?.teamHere ?? false) ? theme.colors.accent : theme.colors.onSurfaceFaint,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text((state?.teamHere ?? false) ? strings.supportHere : strings.supportAway, style: theme.text.caption),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // The one thing the person can do about the conversation itself.
                  if (justHanded)
                    _action(theme, label: strings.supportBack, onTap: () async {
                      final navigator = Navigator.of(context);
                      await widget.support.resolve();
                      navigator.maybePop();
                    })
                  else if (!resolved)
                    _action(theme, label: strings.supportSorted, icon: Icons.check_rounded, onTap: () => widget.support.resolve()),
                ],
              ),
            ),
            Container(height: 1, color: theme.hairline),
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // The conversation sits on the panel's own ground with a breath of the app's colour; the team's lines and the cards are raised on it.
                  Positioned.fill(child: ColoredBox(color: Color.alphaBlend(theme.colors.accent.withValues(alpha: 0.03), theme.colors.surface))),
                  Semantics(
                    liveRegion: true,
                    child: ListView.separated(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(14, theme.space.md, 14, theme.space.md),
                      itemCount: lines.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, i) => lines[i],
                    ),
                  ),
                  if (_newBelow)
                    Padding(
                      padding: EdgeInsets.only(bottom: theme.space.xs),
                      child: RendelActionButton(label: strings.supportNewLine, onTap: _toNewest),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: theme.hairline),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, theme.space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (needsContact || offersContact) _contactCard(theme, strings, required: needsContact),
                  if (contact == 'stated' && !resolved) _codeCard(theme, strings),
                  // A read the team asked for that waits for the person's yes, in the server's words.
                  for (final ask in v.asks)
                    _plate(theme, [
                      Text(ask.text, style: _heading(theme)),
                      SizedBox(height: theme.space.sm),
                      Row(
                        children: [
                          Expanded(
                            child: RendelActionButton(
                              label: strings.goBack,
                              quiet: true,
                              expand: true,
                              onTap: () => widget.support.answerLookup(ask.lookupId, allow: false),
                            ),
                          ),
                          SizedBox(width: theme.space.sm),
                          Expanded(
                            child: RendelActionButton(
                              label: strings.confirm,
                              expand: true,
                              onTap: () => widget.support.answerLookup(ask.lookupId, allow: true),
                            ),
                          ),
                        ],
                      ),
                    ]),
                  if (_note case final note?)
                    Padding(
                      padding: EdgeInsets.only(bottom: theme.space.xs),
                      child: Semantics(liveRegion: true, child: Text(note, style: theme.text.caption)),
                    ),
                  // Closed is not the end: a line within the week reopens the thread (plan §4.2).
                  if (!needsContact) _composer(theme, strings),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One speaker's run: who wrote it (the team's), its lines, and its time.
  Widget _run(BuildContext context, RendelTheme theme, RendelStrings strings, _Run run) {
    final column = Column(
      crossAxisAlignment: run.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!run.mine)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 3),
            child: ExcludeSemantics(child: Text(run.who, style: _who(theme))),
          ),
        for (final (i, entry) in run.entries.indexed) _entry(context, theme, strings, entry, mine: run.mine, first: i == 0),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
          child: Text(_time(context, run.entries.last.createdAt), style: _meta(theme)),
        ),
      ],
    );
    return _side(theme, mine: run.mine, who: run.who, child: column);
  }

  /// A run on its side: the person's on the end, the team's on the start beside who wrote it.
  Widget _side(RendelTheme theme, {required bool mine, required String who, required Widget child, bool meta = true}) {
    final width = MediaQuery.sizeOf(context).width * 0.8;
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          // Beside the run's last line, not its time.
          Padding(padding: EdgeInsets.only(bottom: meta ? 19 : 0), child: _avatar(theme, who)),
          const SizedBox(width: 8),
        ],
        Flexible(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child)),
      ],
    );
  }

  Widget _entry(BuildContext context, RendelTheme theme, RendelStrings strings, RendelSupportEntry entry, {required bool mine, required bool first}) {
    final who = mine ? strings.supportYou : (entry.authorName ?? widget.team);
    final ink = mine ? theme.colors.onAccent : theme.colors.onSurface;
    final hasText = entry.text?.isNotEmpty ?? false;
    final parts = <Widget>[
      if (hasText) _bubble(theme, Text(entry.text!), mine: mine, first: first),
      for (final (i, file) in entry.files.indexed)
        _bubble(
          theme,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 16, color: ink),
              const SizedBox(width: 8),
              Flexible(child: Text(file, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
          mine: mine,
          first: first && !hasText && i == 0,
        ),
      for (final raw in entry.blocks)
        if (_unopened(raw))
          Text(strings.loading, style: theme.text.caption)
        else if (WireBlock.tryParse(raw) case final block?)
          // A line's cards arrive whole, drawn ready and as wide as the run.
          SizedBox(width: double.infinity, child: ComponentRegistry.build(context, block..ready = true, _dispatch)),
    ];
    return Semantics(
      container: true,
      label: who,
      child: Padding(
        padding: EdgeInsets.only(top: first ? 0 : 3),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, part) in parts.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 3), child: part),
          ],
        ),
      ),
    );
  }

  /// What is still on its way: faded while it goes, outlined with a way to send it again when it did not.
  Widget _pending(RendelTheme theme, RendelStrings strings, List<RendelSupportPending> pending) {
    return _side(
      theme,
      mine: true,
      who: strings.supportYou,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, line) in pending.indexed) ...[
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
              child: Opacity(
                opacity: line.failed ? 1 : 0.62,
                child: _bubble(theme, Text(line.text), mine: true, first: i == 0, failed: line.failed),
              ),
            ),
            if (line.failed)
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () => widget.support.retry(line.clientMsgId),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 15, color: theme.danger),
                        const SizedBox(width: 5),
                        Text(strings.supportUnsent, style: theme.text.caption.copyWith(color: theme.danger, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          if (pending.any((line) => !line.failed))
            Padding(padding: const EdgeInsets.fromLTRB(6, 3, 6, 0), child: Text(strings.supportSending, style: _meta(theme))),
        ],
      ),
    );
  }

  /// When the team will answer, while nobody has: a quiet note on the team's side, not a box.
  Widget _wait(BuildContext context, RendelTheme theme, String expectation) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: _mark(theme, Icons.schedule_rounded, size: 28, circle: true)),
          const SizedBox(width: 8),
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(top: 5, right: MediaQuery.sizeOf(context).width * 0.1),
              child: Text(expectation, style: theme.text.caption),
            ),
          ),
        ],
      );

  /// The app's colour, lightly, behind a glyph: the wait note's, a card's.
  Widget _mark(RendelTheme theme, IconData glyph, {double size = 34, bool circle = false}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.alphaBlend(theme.colors.accent.withValues(alpha: 0.12), theme.colors.surfaceRaised),
          borderRadius: circle ? null : BorderRadius.circular(12),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          border: Border.all(color: theme.colors.accent.withValues(alpha: 0.18)),
        ),
        child: Icon(glyph, size: size * 0.52, color: theme.accentText),
      );

  /// What happened to the conversation itself, across the page between hairlines.
  Widget _marker(RendelTheme theme, String text) => Row(
        children: [
          Expanded(child: Container(height: 1, color: theme.hairline)),
          Flexible(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(text, style: theme.text.caption, textAlign: TextAlign.center),
            ),
          ),
          Expanded(child: Container(height: 1, color: theme.hairline)),
        ],
      );

  /// One bubble: the person's in the app's colour, the team's on the page's own; a run's lines meet at their side's corners.
  Widget _bubble(RendelTheme theme, Widget child, {required bool mine, required bool first, bool failed = false}) {
    const round = Radius.circular(20);
    const joined = Radius.circular(6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: failed ? theme.colors.surfaceRaised : (mine ? theme.colors.accent : theme.colors.surfaceRaised),
        boxShadow: failed
            ? null
            : [
                mine
                    ? BoxShadow(color: theme.colors.accent.withValues(alpha: 0.35), offset: const Offset(0, 6), blurRadius: 14, spreadRadius: -10)
                    : BoxShadow(color: theme.colors.onSurface.withValues(alpha: 0.06), offset: const Offset(0, 1), blurRadius: 2),
              ],
        borderRadius: mine
            ? BorderRadiusDirectional.only(topStart: round, bottomStart: round, topEnd: first ? round : joined, bottomEnd: joined)
            : BorderRadiusDirectional.only(topEnd: round, bottomEnd: round, topStart: first ? round : joined, bottomStart: joined),
        border: failed ? Border.all(color: theme.danger, width: 1.5) : (mine ? null : Border.all(color: theme.hairline)),
      ),
      child: DefaultTextStyle.merge(
        style: theme.text.body.copyWith(color: mine && !failed ? theme.colors.onAccent : theme.colors.onSurface, height: 1.42),
        child: child,
      ),
    );
  }

  /// A speaker's initial in a circle.
  Widget _avatar(RendelTheme theme, String name, {double size = 28}) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          // The team's circles carry the app's colour, lightly: who answers is the app.
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.alphaBlend(theme.colors.accent.withValues(alpha: 0.12), theme.colors.surfaceRaised),
            border: Border.all(color: theme.colors.accent.withValues(alpha: 0.18)),
          ),
          child: Text(
            name.trim().isEmpty ? '·' : name.trim().characters.first.toUpperCase(),
            style: theme.text.caption.copyWith(color: theme.accentText, fontWeight: FontWeight.w600, fontSize: size * 0.42, height: 1),
          ),
        ),
      );

  /// "I'm sorted", or "Back to the assistant" before anyone from the team has written: a button, in the header.
  Widget _action(RendelTheme theme, {required String label, IconData? icon, required VoidCallback onTap}) => RendelPressable(
        semanticLabel: label,
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colors.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: theme.colors.onSurface), const SizedBox(width: 6)],
              Text(label, style: theme.text.caption.copyWith(color: theme.colors.onSurface, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  String _time(BuildContext context, DateTime at) => MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));
  TextStyle _who(RendelTheme theme) => theme.text.caption.copyWith(fontWeight: FontWeight.w600);
  TextStyle _meta(RendelTheme theme) => theme.text.caption.copyWith(fontSize: 11.5, color: theme.colors.onSurfaceFaint, fontFeatures: const [FontFeature.tabularFigures()]);

  /// A confirm card the team sent that has no confirmation yet: this phone mints it, once, when it is first drawn.
  bool _unopened(Map<String, dynamic> raw) {
    if (raw['type'] != 'confirm_card') return false;
    final props = raw['props'];
    final id = props is Map ? props['invocation_id'] : null;
    if (id is String && id.isNotEmpty) return false;
    final entry = widget.support.value.value.entries.where((e) => e.blocks.contains(raw)).firstOrNull;
    if (entry != null && _opening.add(entry.id)) unawaited(widget.support.openCard(entry.id));
    return true;
  }

  /// A card's heading: `labelStrong` is drawn on the accent, these cards are not.
  TextStyle _heading(RendelTheme theme) => theme.text.labelStrong.copyWith(color: theme.colors.onSurface);

  /// One box like the assistant's own: the paperclip, the words, and send once there is something to send.
  Widget _composer(RendelTheme theme, RendelStrings strings) {
    final canAttach = widget.onPick != null && widget.onUpload != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_menu && canAttach)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colors.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.hairline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (source, glyph, label) in [
                  (RendelAttachSource.photos, Icons.image_outlined, strings.photos),
                  (RendelAttachSource.files, Icons.description_outlined, strings.files),
                ])
                  RendelPressable(
                    semanticLabel: label,
                    onTap: () {
                      setState(() => _menu = false);
                      _attach(source, strings);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      child: Row(
                        children: [
                          Icon(glyph, size: 22, color: theme.colors.onSurface),
                          const SizedBox(width: 12),
                          Text(label, style: theme.text.body),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.colors.composer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.composerEdge),
            boxShadow: [BoxShadow(color: theme.colors.shadow.withValues(alpha: 0.18), offset: const Offset(0, 10), blurRadius: 24, spreadRadius: -18)],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (canAttach)
                IconButton(
                  tooltip: null,
                  onPressed: _attaching ? null : () => setState(() => _menu = !_menu),
                  icon: Icon(Icons.attach_file_rounded, color: theme.colors.onComposer, semanticLabel: strings.attachFile),
                ),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 4000,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => widget.support.typing(),
                  onSubmitted: (_) => _send(),
                  style: theme.text.body.copyWith(color: theme.colors.onComposer),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    counterText: '',
                    // Always the team, never the one person in it (Tuna, 2026-11-03).
                    hintText: strings.supportWriteTeamOf(widget.team),
                    hintStyle: theme.text.body.copyWith(color: theme.colors.onSurfaceFaint),
                    contentPadding: EdgeInsets.symmetric(horizontal: canAttach ? 2 : 12, vertical: 10),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (context, value, _) {
                  final ready = value.text.trim().isNotEmpty;
                  return IconButton(
                    tooltip: null,
                    onPressed: ready ? _send : null,
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colors.accent,
                      disabledBackgroundColor: theme.colors.accent.withValues(alpha: 0.35),
                    ),
                    icon: Icon(Icons.arrow_upward_rounded, size: 20, color: theme.colors.onAccent, semanticLabel: strings.sendMessage),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Where the reply can reach the person (K14): checked by the API's own rule, said under the field once they
  /// leave it or tap Save, and from then on with each change.
  Widget _contactCard(RendelTheme theme, RendelStrings strings, {required bool required}) {
    final problem = supportEmailProblem(_email.text);
    final warning = _emailRefused ??
        (_emailWarned && problem != null ? (problem == 'empty' ? strings.supportContactEmpty : strings.supportContactInvalid) : null);
    return _plate(theme, [
      _cardHead(theme, Icons.mail_outline_rounded, required ? strings.supportContactAsk : strings.supportContactOptional, strings.supportContactWhy),
      SizedBox(height: theme.space.sm + 4),
      _group(
        theme,
        invalid: warning != null,
        field: TextField(
          controller: _email,
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          style: theme.text.body,
          decoration: _bare(theme, strings.supportContactPlaceholder),
          onChanged: (_) {
            if (_emailWarned || _emailRefused != null) setState(() => _emailRefused = null);
          },
          onSubmitted: (_) => _saveEmail(strings),
        ),
        button: RendelActionButton(label: strings.supportContactSend, onTap: () => _saveEmail(strings)),
      ),
      if (warning != null) _warning(theme, warning),
    ]);
  }

  /// The code the address got, to show it is theirs; just after the address went, the card says it did.
  Widget _codeCard(RendelTheme theme, RendelStrings strings) {
    return _plate(theme, [
      if (_contactSaved) ...[
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 17, color: theme.accentText),
              const SizedBox(width: 6),
              Expanded(child: Text(strings.supportContactSaved, style: theme.text.caption.copyWith(color: theme.colors.onSurface, fontWeight: FontWeight.w500))),
            ],
          ),
        ),
        SizedBox(height: theme.space.sm + 4),
      ],
      _cardHead(theme, Icons.lock_outline_rounded, strings.supportCodeLabel, null),
      SizedBox(height: theme.space.sm + 4),
      _group(
        theme,
        invalid: _codeWrong,
        field: TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          style: theme.text.body,
          decoration: _bare(theme, null).copyWith(counterText: ''),
          onSubmitted: (_) => _verify(strings),
        ),
        button: RendelActionButton(label: strings.confirm, onTap: () => _verify(strings)),
      ),
      if (_codeWrong) _warning(theme, strings.supportCodeWrong),
    ]);
  }

  /// A card's mark, title and why.
  Widget _cardHead(RendelTheme theme, IconData glyph, String title, String? why) => Row(
        crossAxisAlignment: why == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: _mark(theme, glyph)),
          SizedBox(width: theme.space.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: _heading(theme)),
                if (why != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(why, style: theme.text.caption)),
              ],
            ),
          ),
        ],
      );

  /// The field and its button as one control, as the box to write in is; outlined in the warning's colour while wrong.
  Widget _group(RendelTheme theme, {required Widget field, required Widget button, required bool invalid}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: theme.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: invalid ? theme.danger : theme.colors.lineStrong, width: invalid ? 1.5 : 1),
        ),
        child: Row(children: [Expanded(child: field), const SizedBox(width: 6), button]),
      );

  InputDecoration _bare(RendelTheme theme, String? hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: theme.text.body.copyWith(color: theme.colors.onSurfaceFaint),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      );

  /// What is wrong with what was written, under its field.
  Widget _warning(RendelTheme theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
        child: Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.warning_amber_rounded, size: 16, color: theme.danger)),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: theme.text.caption.copyWith(color: theme.danger))),
            ],
          ),
        ),
      );

  /// What the page asks of the person (an email, a code, a read): a raised card, never a grey slab.
  Widget _plate(RendelTheme theme, List<Widget> children) => Container(
        margin: EdgeInsets.only(bottom: theme.space.sm),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colors.surfaceRaised,
          border: Border.all(color: theme.hairline),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: theme.colors.shadow.withValues(alpha: 0.2), offset: const Offset(0, 12), blurRadius: 26, spreadRadius: -18)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      );
}

/// How long one speaker's lines keep reading as one run (`GROUP_MS` in the web SDK).
const _runGap = Duration(minutes: 5);

class _Run {
  _Run({required this.key, required this.mine, required this.who, required this.at, required this.entries});
  final String key;
  final bool mine;
  final String who;

  /// When its newest line was written.
  DateTime at;
  final List<RendelSupportEntry> entries;
}

/// Three dots rising in turn while someone from the team writes; still when the device asks for no motion.
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat.stop();
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: AnimatedBuilder(
        animation: _beat,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                child: Transform.translate(
                  offset: Offset(0, -3 * _lift((_beat.value - i * 0.125) % 1)),
                  child: Opacity(
                    opacity: 0.45 + 0.55 * _lift((_beat.value - i * 0.125) % 1),
                    child: Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Up in the first third of a beat, down by the second, still after.
  double _lift(double t) => t < 0.3 ? math.sin(t / 0.3 * math.pi) : 0;
}
