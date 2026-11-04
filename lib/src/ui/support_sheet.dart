import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/config.dart' show RendelAttachment, RendelAttachSource;
import '../core/strings.dart';
import '../core/support.dart';
import '../protocol/protocol.dart' show CancelAction, ConfirmAction, NavigateAction, RendelLocalKeys, UIAction, WireBlock;
import 'renderer/blocks.dart' show RendelActionButton, RendelPressable;
import 'renderer/registry.dart';
import 'theme.dart';

/// Opens the person's thread with the app's own team (human support, design/
/// plans/human-support.md §3.3) as a sheet over what is on screen, drawn as
/// design A (Tuna, 2026-11-03) and as the web SDK draws it: back to the
/// assistant, the team with who is helping and when they answer, the
/// person's bubbles on one side in the app's colour with "Read" once the team
/// read them, the team's white ones on the other under "Dana · Halden team",
/// what happened small in the middle, the team's auto-reply and what they ask
/// (the email the reply goes to, K14) in their column, and a pill to write in.
///
/// [onAction] carries out a tap on a card the team sent: a screen, a link, a
/// call. The sheet closes first when it opens a screen of the app.
///
/// Completes with how the person left it (Tuna, 2026-11-04: as on the web):
/// ✕ closes all of Rendel, the way back is to Rendel's page; null for a swipe
/// down, a tap outside or a screen of the app the page opened.
Future<SupportExit?> showRendelSupport(
  BuildContext context, {
  required RendelSupport support,
  required String team,
  String? assistant,
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
  return showModalBottomSheet<SupportExit>(
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
            assistant: assistant,
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

/// How the person left the team's page: ✕, or the way back to the assistant.
enum SupportExit { closed, back }

class RendelSupportSheet extends StatefulWidget {
  const RendelSupportSheet({
    super.key,
    required this.support,
    required this.team,
    this.assistant,
    required this.onAction,
    required this.canHandle,
    this.routeTitle,
    this.onPick,
    this.onUpload,
  });

  final RendelSupport support;
  final String team;

  /// What the assistant is called: the way back says it.
  final String? assistant;
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

  /// What the person had read, and the newest line there was, when this page
  /// opened: the team's first line between the two gets "New" above it, and
  /// the page opens there, once. Unknown until the thread's state is.
  ({int read, int last})? _newAfter;
  final GlobalKey _newMark = GlobalKey();
  bool _newShown = false;

  /// The person sorted it on this page: the card says so, where a sorted one opened later keeps its "Sorted" line.
  bool _sortedHere = false;

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
    // What the person had read when the page opened, taken before this read moves it.
    final state = widget.support.value.value.state;
    if (_newAfter == null && state != null) _newAfter = (read: state.userReadSeq, last: state.lastSeq);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toNewest();
      // Opened on lines the person had not read: the page opens at "New", once.
      if (!_newShown) WidgetsBinding.instance.addPostFrameCallback((_) => _toNew());
    });
  }

  int _drawn = 0;

  void _toNew() {
    final mark = _newMark.currentContext;
    if (mark == null || _newShown || !mounted) return;
    _newShown = true;
    Scrollable.ensureVisible(mark, alignment: 0.02);
  }

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
    // The line waits for the address, or for the other open conversation: it goes back in the field.
    if ((sent == 'contact_required' || sent == 'another_open') && mounted) setState(() => _input.text = text);
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
    final asked = v.entries.any((e) => e.author == RendelSupportAuthorKind.user);
    // The first line always goes (the server takes it); the one after it waits for an email.
    final needsContact = (state?.contactRequired ?? false) && asked;
    final justHanded = !resolved && !v.entries.any((e) => e.author == RendelSupportAuthorKind.agent);
    final typing = v.typingUntil != null && v.typingUntil!.isAfter(DateTime.now());
    final agent = state?.agentName;
    final team = strings.supportTeamOf(widget.team);
    if (_newAfter == null && state != null) _newAfter = (read: state.userReadSeq, last: state.lastSeq);
    final unseen = _newAfter;

    // A speaker's lines within five minutes are one run, as the web SDK groups them; a marker ends one.
    final items = <Object>[];
    _Run? run;
    var newPlaced = false;
    final lastMarker = v.entries.where((e) => e.marker).lastOrNull;
    for (final entry in v.entries) {
      if (entry.marker) {
        run = null;
        // Sorted on this page: the card at the end says it, so the server's own line about it steps aside.
        if (resolved && _sortedHere && identical(entry, lastMarker) && (entry.markerKind?.endsWith('resolved') ?? false)) continue;
        items.add(entry);
        continue;
      }
      // "New" above the team's first line the person had not read when the page opened.
      if (!newPlaced && unseen != null && entry.author == RendelSupportAuthorKind.agent && entry.seq > unseen.read && entry.seq <= unseen.last) {
        newPlaced = true;
        run = null;
        items.add(_NewMark(entry.createdAt));
      }
      final mine = entry.author == RendelSupportAuthorKind.user;
      final who = mine ? strings.supportYou : (entry.authorName != null ? '${entry.authorName} · $team' : team);
      final key = '${mine ? 'me' : 'team'}:$who';
      if (run != null && run.key == key && entry.createdAt.difference(run.at) <= _runGap) {
        run.entries.add(entry);
        run.at = entry.createdAt;
      } else {
        run = _Run(key: key, mine: mine, who: who, avatar: entry.authorName ?? widget.team, at: entry.createdAt, entries: [entry]);
        items.add(run);
      }
    }
    // "Read ✓" under the person's newest run the team has read (design A).
    final readSeq = state?.teamReadSeq ?? 0;
    final readRun = items.whereType<_Run>().where((r) => r.mine && readSeq >= r.entries.last.seq).lastOrNull;
    final column = _teamColumn(context, theme, strings, needsContact: needsContact, asked: asked);
    final lines = <Widget>[
      for (final item in items)
        switch (item) {
          _Run() => _run(context, theme, strings, item, read: identical(item, readRun)),
          _NewMark() => _newLine(context, theme, strings, item.at),
          _ => _event(context, theme, strings, item as RendelSupportEntry),
        },
      if (column != null) column,
      if (v.pending.isNotEmpty) _pending(theme, strings, v.pending),
      // Newest of all: someone from the team is writing.
      if (typing)
        Semantics(
          label: strings.supportTypingOf(agent ?? widget.team),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _avatar(theme, agent ?? widget.team),
              const SizedBox(width: 8),
              _bubble(theme, _TypingDots(color: theme.colors.onSurfaceFaint), mine: false, last: true),
            ],
          ),
        ),
      if (resolved && _sortedHere) _sorted(theme, strings),
    ];

    return SafeArea(
      top: false,
      child: SizedBox(
        height: math.max(MediaQuery.sizeOf(context).height * 0.88 - MediaQuery.viewInsetsOf(context).bottom, 200),
        child: ColoredBox(
          color: Color.alphaBlend(theme.colors.onSurface.withValues(alpha: 0.015), theme.colors.surfaceRaised),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(context, theme, strings, resolved: resolved),
              Container(height: 1, color: theme.colors.onSurface.withValues(alpha: 0.06)),
              Expanded(
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                        itemCount: lines.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
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
              Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, theme.space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_note case final note?)
                      Padding(
                        padding: EdgeInsets.only(bottom: theme.space.xs),
                        child: Semantics(liveRegion: true, child: Text(note, style: theme.text.caption)),
                      ),
                    // "I'm sorted" while the conversation is open; before the team has written, the way back (K4).
                    if (!resolved)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _chip(
                            theme,
                            label: justHanded ? strings.supportMistake : strings.supportSorted,
                            onTap: justHanded
                                ? () async {
                                    final navigator = Navigator.of(context);
                                    await widget.support.resolve();
                                    navigator.maybePop();
                                  }
                                : () {
                                    setState(() => _sortedHere = true);
                                    widget.support.resolve();
                                  },
                          ),
                        ),
                      ),
                    // Sorted, while another of theirs is open: that one is where they write.
                    if (v.otherOpen case final other?) _otherOpen(theme, strings, other),
                    // Closed is not the end: a line reopens the thread, in place (plan §4.2).
                    if (!needsContact && v.otherOpen == null) _composer(theme, strings, resolved: resolved),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Back to the assistant, the team with who is helping and when they answer, and a way out: close, or the tick of a sorted conversation.
  Widget _head(BuildContext context, RendelTheme theme, RendelStrings strings, {required bool resolved}) {
    final state = widget.support.value.value.state;
    final here = state?.teamHere ?? false;
    // Green while the team is here, amber while it is away: there is no status palette, so these are drawn for legibility on the page.
    final tone = Color.lerp(here ? const Color(0xFF2E7D4F) : const Color(0xFFB7791F), theme.colors.onSurface, 0.12)!;
    return Container(
      color: theme.colors.surfaceRaised.withValues(alpha: 0.92),
      padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
      child: Row(
        children: [
          // The way back keeps to its own size; the team and their presence line take the room between.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: strings.supportBack,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).maybePop(SupportExit.back),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chevron_left_rounded, size: 24, color: theme.accentText),
                        Flexible(child: Text(widget.assistant ?? 'Rendel', style: theme.text.body.copyWith(color: theme.accentText, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _avatar(theme, state?.agentName ?? widget.team, size: 36),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(strings.supportTeamOf(widget.team), style: theme.text.body.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colors.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        resolved ? _sortedOn(context, strings) : (state?.presence ?? (here ? strings.supportHere : strings.supportAway)),
                        style: theme.text.caption.copyWith(fontSize: 12.5, color: resolved ? theme.colors.onSurfaceSoft : tone),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 32,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: resolved
                  ? Semantics(
                      label: strings.supportSortedTitle,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: theme.colors.accent, shape: BoxShape.circle),
                        child: Icon(Icons.check_rounded, size: 18, color: theme.colors.onAccent),
                      ),
                    )
                  : IconButton(
                      tooltip: null,
                      onPressed: () => Navigator.of(context).maybePop(SupportExit.closed),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colors.onSurface.withValues(alpha: 0.07),
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                      ),
                      icon: Icon(Icons.close_rounded, size: 17, color: theme.colors.onSurfaceSoft, semanticLabel: strings.closeDetail),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Sorted on 28 Oct", from its last "sorted" line; "Sorted" when it has none.
  String _sortedOn(BuildContext context, RendelStrings strings) {
    final at = widget.support.value.value.entries.where((e) => e.markerKind?.endsWith('resolved') ?? false).lastOrNull?.createdAt;
    return at == null ? strings.supportSortedMark : strings.supportSortedOnOf(_day(context, at));
  }

  /// "Oct 28", in the app's language.
  String _day(BuildContext context, DateTime at) => MaterialLocalizations.of(context).formatShortMonthDay(at.toLocal());

  /// "New · 09:41" across the page, above what the person had not read yet.
  Widget _newLine(BuildContext context, RendelTheme theme, RendelStrings strings, DateTime at) {
    final rule = Expanded(child: Container(height: 1, color: theme.colors.accent.withValues(alpha: 0.35)));
    return Padding(
      key: _newMark,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('${strings.supportNewMark} · ${_time(context, at)}', style: theme.text.caption.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.accentText)),
          ),
          rule,
        ],
      ),
    );
  }

  /// Sorted, while another of the person's conversations is open: a way to it.
  Widget _otherOpen(RendelTheme theme, RendelStrings strings, String other) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardShell(theme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(liveRegion: true, child: Text(strings.supportOtherOpen, style: _heading(theme))),
              const SizedBox(height: 10),
              _attached(theme, strings.supportGoTo, () {
                _newAfter = null;
                _newShown = false;
                widget.support.show(other);
              }),
            ],
          ),
        ),
      );

  /// What happened (who joined, who passed it on): small and quiet in the middle, with its time.
  /// Sorted and opened again are a line across the page of their own.
  Widget _event(BuildContext context, RendelTheme theme, RendelStrings strings, RendelSupportEntry entry) {
    final time = _time(context, entry.createdAt);
    final kind = entry.markerKind;
    if (kind == 'resolved' || kind == 'auto_resolved' || kind == 'reopened') {
      final sorted = kind != 'reopened';
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: Color.alphaBlend(theme.colors.onSurface.withValues(alpha: 0.05), theme.colors.surfaceRaised), borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sorted) ...[Icon(Icons.check_rounded, size: 14, color: theme.accentText), const SizedBox(width: 6)],
              Text(
                sorted ? '${strings.supportSortedMark} · ${_day(context, entry.createdAt)}' : '${strings.supportOpenedAgain} · $time',
                style: theme.text.caption.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: theme.colors.onSurfaceSoft),
              ),
            ],
          ),
        ),
      );
    }
    final text = entry.text;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(text == null || text.isEmpty ? time : '$text · $time', style: theme.text.caption.copyWith(fontSize: 12.5, color: theme.colors.onSurfaceFaint), textAlign: TextAlign.center),
    );
  }

  /// One speaker's run: the team's under who wrote it with their avatar at its foot; the person's with its time, and "Read" once the team read it.
  Widget _run(BuildContext context, RendelTheme theme, RendelStrings strings, _Run run, {required bool read}) {
    final column = Column(
      crossAxisAlignment: run.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!run.mine)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2),
            child: ExcludeSemantics(child: Text(run.who, style: _meta(theme).copyWith(fontSize: 12))),
          ),
        for (final (i, entry) in run.entries.indexed) _entry(context, theme, strings, entry, mine: run.mine, first: i == 0, last: i == run.entries.length - 1),
        if (run.mine)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(read ? '${_time(context, run.entries.last.createdAt)} · ${strings.supportRead}' : _time(context, run.entries.last.createdAt), style: _meta(theme))),
                if (read) ...[const SizedBox(width: 3), Icon(Icons.check_rounded, size: 12, color: theme.colors.onSurfaceFaint)],
              ],
            ),
          ),
      ],
    );
    return _side(theme, mine: run.mine, avatar: run.avatar, child: column);
  }

  /// A run on its side: the person's on the end, the team's on the start beside who wrote it.
  Widget _side(RendelTheme theme, {required bool mine, required String avatar, required Widget child}) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.82, 300.0);
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[_avatar(theme, avatar), const SizedBox(width: 8)],
        Flexible(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child)),
      ],
    );
  }

  Widget _entry(BuildContext context, RendelTheme theme, RendelStrings strings, RendelSupportEntry entry, {required bool mine, required bool first, required bool last}) {
    final who = mine ? strings.supportYou : (entry.authorName ?? widget.team);
    final ink = mine ? theme.colors.onAccent : theme.colors.onSurface;
    final hasText = entry.text?.isNotEmpty ?? false;
    final bubbles = <Widget>[
      if (hasText) Text(entry.text!),
      for (final url in entry.pictures)
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(url, width: 132, height: 99, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.image_outlined, color: ink)),
        ),
      for (final file in entry.files)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 16, color: ink),
            const SizedBox(width: 8),
            Flexible(child: Text(file, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
    ];
    final parts = <Widget>[
      for (final (i, b) in bubbles.indexed)
        _bubble(theme, b, mine: mine, last: last && i == bubbles.length - 1 && entry.blocks.isEmpty, picture: b is ClipRRect),
      for (final raw in entry.blocks)
        if (_unopened(raw))
          Text(strings.loading, style: theme.text.caption)
        else if (WireBlock.tryParse(_asDrawn(entry, raw)) case final block?)
          // A card the team sent, in their column: who prepared it, then the card to act on.
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(14),
            decoration: _cardShell(theme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (raw['type'] == 'confirm_card' && !mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 16, color: theme.accentText),
                        const SizedBox(width: 6),
                        Flexible(child: Text(strings.supportPreparedByOf(who), style: theme.text.caption.copyWith(color: theme.accentText, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                // A line's cards arrive whole, drawn ready.
                ComponentRegistry.build(context, block..ready = true, _dispatch),
              ],
            ),
          ),
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

  /// What is still on its way: faded while it goes; dimmed, with how to send it again in red, when it did not.
  Widget _pending(RendelTheme theme, RendelStrings strings, List<RendelSupportPending> pending) {
    return _side(
      theme,
      mine: true,
      avatar: strings.supportYou,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, line) in pending.indexed) ...[
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
              child: Opacity(
                opacity: line.failed ? 0.55 : 0.62,
                child: _bubble(theme, Text(line.text), mine: true, last: i == pending.length - 1),
              ),
            ),
            if (line.failed)
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () => widget.support.retry(line.clientMsgId),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 13, color: theme.danger),
                        const SizedBox(width: 4),
                        Flexible(child: Text(strings.supportUnsent, style: _meta(theme).copyWith(color: theme.danger, fontWeight: FontWeight.w500))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          if (pending.any((line) => !line.failed))
            Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 0), child: Text(strings.supportSending, style: _meta(theme))),
        ],
      ),
    );
  }

  /// The team's side at the end of the page while it waits: their auto-reply about when they answer, and what they
  /// ask of the person (where to send the reply, the code it got, a read of their account).
  Widget? _teamColumn(BuildContext context, RendelTheme theme, RendelStrings strings, {required bool needsContact, required bool asked}) {
    final v = widget.support.value.value;
    final state = v.state;
    final resolved = state?.resolved ?? false;
    final contact = state?.contactState ?? 'not_needed';
    // The optional box is for the wait: once the team is talking, it gives the page back.
    final offersContact = !needsContact && contact == 'none' && asked && !v.entries.any((e) => e.author == RendelSupportAuthorKind.agent);
    final items = <Widget>[
      if (state?.expectation case final expectation? when state!.mode != 'human')
        _bubble(
          theme,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.schedule_rounded, size: 16, color: theme.accentText)),
              const SizedBox(width: 8),
              Flexible(child: Text(expectation, style: const TextStyle(fontSize: 15))),
            ],
          ),
          mine: false,
          last: false,
          auto: true,
        ),
      if (needsContact || offersContact) _contactCard(theme, strings, required: needsContact),
      if (contact == 'stated' && !resolved) _codeCard(theme, strings),
      // A read the team asked for that waits for the person's yes, in the server's words.
      for (final ask in v.asks)
        _plate(theme, [
          Text(ask.text, style: _heading(theme)),
          SizedBox(height: theme.space.sm),
          Row(
            children: [
              Expanded(child: RendelActionButton(label: strings.confirm, expand: true, onTap: () => widget.support.answerLookup(ask.lookupId, allow: true))),
              SizedBox(width: theme.space.sm),
              RendelActionButton(label: strings.goBack, quiet: true, onTap: () => widget.support.answerLookup(ask.lookupId, allow: false)),
            ],
          ),
        ]),
    ];
    if (items.isEmpty) return null;
    final team = strings.supportTeamOf(widget.team);
    return _side(
      theme,
      mine: false,
      avatar: widget.team,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2), child: ExcludeSemantics(child: Text(team, style: _meta(theme).copyWith(fontSize: 12)))),
          for (final (i, item) in items.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 4), child: item),
        ],
      ),
    );
  }

  /// Sorted: a quiet card at the end, and the box to write in stays.
  Widget _sorted(RendelTheme theme, RendelStrings strings) => Semantics(
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 16, 10, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(theme.colors.accent.withValues(alpha: 0.09), theme.colors.surfaceRaised),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: theme.colors.accent, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 16, color: theme.colors.onAccent),
              ),
              const SizedBox(height: 6),
              Text(strings.supportSortedTitle, style: theme.text.body.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600, color: theme.colors.onSurface), textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Text(strings.supportSortedBodyOf(widget.team), style: theme.text.caption.copyWith(fontSize: 13.5), textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  /// One bubble: the person's in the app's colour, the team's white with a faint ring; the run's last carries the tail on its own side.
  Widget _bubble(RendelTheme theme, Widget child, {required bool mine, required bool last, bool auto = false, bool picture = false}) {
    const round = Radius.circular(20);
    const tail = Radius.circular(6);
    return Container(
      padding: picture ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: mine
            ? theme.colors.accent
            : auto
                ? Color.alphaBlend(theme.colors.accent.withValues(alpha: 0.09), theme.colors.surfaceRaised)
                : theme.colors.surfaceRaised,
        borderRadius: mine
            ? BorderRadiusDirectional.only(topStart: round, topEnd: round, bottomStart: round, bottomEnd: last ? tail : round)
            : BorderRadiusDirectional.only(topStart: round, topEnd: round, bottomEnd: round, bottomStart: last ? tail : round),
        boxShadow: mine || auto
            ? null
            : [
                BoxShadow(color: theme.colors.onSurface.withValues(alpha: 0.05), offset: const Offset(0, 1), blurRadius: 1),
                BoxShadow(color: theme.colors.onSurface.withValues(alpha: 0.05), spreadRadius: 1),
              ],
      ),
      child: DefaultTextStyle.merge(
        style: theme.text.body.copyWith(color: mine ? theme.colors.onAccent : theme.colors.onSurface, fontSize: 16, height: 1.32),
        child: child,
      ),
    );
  }

  /// A speaker's initial in a circle, in the app's colour, lightly.
  Widget _avatar(RendelTheme theme, String name, {double size = 26}) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.alphaBlend(theme.colors.accent.withValues(alpha: 0.14), theme.colors.surfaceRaised),
            border: Border.all(color: theme.colors.surfaceRaised, width: 2),
          ),
          child: Text(
            name.trim().isEmpty ? '·' : name.trim().characters.first.toUpperCase(),
            style: theme.text.caption.copyWith(color: theme.accentText, fontWeight: FontWeight.w700, fontSize: size * 0.42, height: 1),
          ),
        ),
      );

  /// A small chip above the box: "I'm sorted", or the way back to the assistant before the team has written.
  Widget _chip(RendelTheme theme, {required String label, required VoidCallback onTap}) => RendelPressable(
        semanticLabel: label,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: theme.colors.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [BoxShadow(color: theme.colors.onSurface.withValues(alpha: 0.08), spreadRadius: 1)],
          ),
          child: Text(label, style: theme.text.caption.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, color: theme.accentText)),
        ),
      );

  /// A card in the team's column: white, with a faint ring and a soft shadow.
  BoxDecoration _cardShell(RendelTheme theme) => BoxDecoration(
        color: theme.colors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: theme.colors.onSurface.withValues(alpha: 0.06), spreadRadius: 1),
          BoxShadow(color: theme.colors.shadow.withValues(alpha: 0.2), offset: const Offset(0, 14), blurRadius: 30, spreadRadius: -22),
        ],
      );

  String _time(BuildContext context, DateTime at) => MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));
  TextStyle _meta(RendelTheme theme) => theme.text.caption.copyWith(fontSize: 11.5, color: theme.colors.onSurfaceFaint, fontFeatures: const [FontFeature.tabularFigures()]);

  /// A confirm card the team sent that has no confirmation yet: this phone mints it, once, when it is first drawn.
  bool _unopened(Map<String, dynamic> raw) {
    if (raw['type'] != 'confirm_card') return false;
    final props = raw['props'];
    final id = props is Map ? props['invocation_id'] : null;
    if (id is String && id.isNotEmpty) return false;
    final entry = widget.support.value.value.entries.where((e) => e.blocks.contains(raw)).firstOrNull;
    // Refused for good: drawn as not answered (_asDrawn).
    if (entry != null && widget.support.refusedCards.contains(entry.id)) return false;
    if (entry != null && _opening.add(entry.id)) unawaited(widget.support.openCard(entry.id));
    return true;
  }

  /// A card as it is drawn: one the server would not open on this phone is not answered.
  Map<String, dynamic> _asDrawn(RendelSupportEntry entry, Map<String, dynamic> raw) {
    if (raw['type'] != 'confirm_card' || !widget.support.refusedCards.contains(entry.id)) return raw;
    final props = raw['props'];
    return {
      ...raw,
      'props': {if (props is Map<String, dynamic>) ...props, RendelLocalKeys.resolved: 'abandoned'},
    };
  }

  /// A card's heading: `labelStrong` is drawn on the accent, these cards are not.
  TextStyle _heading(RendelTheme theme) => theme.text.labelStrong.copyWith(color: theme.colors.onSurface);

  /// One box like the assistant's own: the paperclip, the words, and send once there is something to send.
  Widget _composer(RendelTheme theme, RendelStrings strings, {bool resolved = false}) {
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
        // A white pill: a round + to attach, the words, and a round send in the app's colour.
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colors.surfaceRaised,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: theme.colors.onSurface.withValues(alpha: 0.08), spreadRadius: 1)],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (canAttach)
                IconButton(
                  tooltip: null,
                  onPressed: _attaching ? null : () => setState(() => _menu = !_menu),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colors.onSurface.withValues(alpha: 0.07),
                    minimumSize: const Size(36, 36),
                    fixedSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                  ),
                  icon: Icon(Icons.add_rounded, size: 20, color: theme.colors.onSurfaceSoft, semanticLabel: strings.attachFile),
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
                  style: theme.text.body.copyWith(color: theme.colors.onSurface, fontSize: 16),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    counterText: '',
                    // Always the team, never the one person in it (Tuna, 2026-11-03); a sorted one says a line opens it again.
                    hintText: resolved ? strings.supportReopenHint : strings.supportWriteTeamOf(widget.team),
                    hintStyle: theme.text.body.copyWith(color: theme.colors.onSurfaceFaint),
                    contentPadding: EdgeInsets.symmetric(horizontal: canAttach ? 4 : 12, vertical: 8),
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
                      disabledBackgroundColor: theme.colors.accent.withValues(alpha: 0.4),
                      minimumSize: const Size(36, 36),
                      fixedSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                    ),
                    icon: Icon(Icons.arrow_upward_rounded, size: 18, color: theme.colors.onAccent, semanticLabel: strings.sendMessage),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Where the reply can reach the person (K14), as a card in the team's column: checked by the API's own rule,
  /// said under the field once they leave it or tap Save, and from then on with each change.
  Widget _contactCard(RendelTheme theme, RendelStrings strings, {required bool required}) {
    final problem = supportEmailProblem(_email.text);
    final warning = _emailRefused ??
        (_emailWarned && problem != null ? (problem == 'empty' ? strings.supportContactEmpty : strings.supportContactInvalid) : null);
    return _plate(theme, [
      Text(required ? strings.supportContactAsk : strings.supportContactOptional, style: _heading(theme)),
      const SizedBox(height: 10),
      _group(
        theme,
        glyph: Icons.mail_outline_rounded,
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
          // Save keeps the field and its keyboard: the room under it, where the warning comes, is kept above them too.
          scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 88),
          style: theme.text.body,
          decoration: _bare(theme, strings.supportContactPlaceholder),
          onChanged: (_) {
            if (_emailWarned || _emailRefused != null) setState(() => _emailRefused = null);
          },
          onSubmitted: (_) => _saveEmail(strings),
        ),
        button: _attached(theme, strings.supportContactSend, () => _saveEmail(strings)),
      ),
      if (warning != null) _warning(theme, warning),
      Padding(padding: const EdgeInsets.fromLTRB(2, 6, 2, 0), child: Text(strings.supportContactWhy, style: _meta(theme).copyWith(fontSize: 12))),
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
        const SizedBox(height: 8),
      ],
      Text(strings.supportCodeLabel, style: _heading(theme)),
      const SizedBox(height: 10),
      _group(
        theme,
        glyph: Icons.lock_outline_rounded,
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
        button: _attached(theme, strings.confirm, () => _verify(strings)),
      ),
      if (_codeWrong) _warning(theme, strings.supportCodeWrong),
    ]);
  }

  /// The field with its mark and its button attached, as one control; red, with the warning under it, while wrong.
  Widget _group(RendelTheme theme, {required IconData glyph, required Widget field, required Widget button, required bool invalid}) => Container(
        height: 46,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: invalid ? Color.alphaBlend(theme.danger.withValues(alpha: 0.08), theme.colors.surfaceRaised) : theme.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: invalid ? theme.danger : theme.colors.onSurface.withValues(alpha: 0.1), width: 1.5),
        ),
        child: Row(children: [Icon(glyph, size: 18, color: theme.colors.onSurfaceSoft), const SizedBox(width: 8), Expanded(child: field), const SizedBox(width: 6), button]),
      );

  /// The button inside a field: small, in the app's colour.
  Widget _attached(RendelTheme theme, String label, VoidCallback onTap) => RendelPressable(
        semanticLabel: label,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: theme.colors.accent, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: theme.text.caption.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colors.onAccent)),
        ),
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
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
        child: Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.error_rounded, size: 15, color: theme.danger)),
              const SizedBox(width: 5),
              Expanded(child: Text(text, style: theme.text.caption.copyWith(fontSize: 12.5, color: theme.danger))),
            ],
          ),
        ),
      );

  /// What the page asks of the person (an email, a code, a read): a card in the team's column.
  Widget _plate(RendelTheme theme, List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: _cardShell(theme),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      );
}

/// How long one speaker's lines keep reading as one run (`GROUP_MS` in the web SDK).
const _runGap = Duration(minutes: 5);

/// Where the lines the person had not read begin.
class _NewMark {
  _NewMark(this.at);
  final DateTime at;
}

class _Run {
  _Run({required this.key, required this.mine, required this.who, required this.avatar, required this.at, required this.entries});
  final String key;
  final bool mine;

  /// "Dana · Halden team" over the team's run.
  final String who;

  /// Whose initial is in the circle at its foot.
  final String avatar;

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
