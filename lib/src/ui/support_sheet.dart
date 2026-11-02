import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/config.dart' show RendelAttachment, RendelAttachSource;
import '../core/strings.dart';
import '../core/support.dart';
import '../protocol/protocol.dart' show CancelAction, ConfirmAction, NavigateAction, UIAction, WireBlock;
import 'renderer/blocks.dart' show RendelActionButton;
import 'renderer/registry.dart';
import 'theme.dart';

/// Opens the person's thread with the app's own team (human support, design/
/// plans/human-support.md §3.3) as a sheet over what is on screen: the team's
/// name and whether they are here, the lines with an author whenever the
/// speaker changes (never "Seen"), the email the reply goes to when nobody
/// could reach the person otherwise (K14), and a field to write in.
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
    backgroundColor: drawn.colors.surface,
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

  Future<void> _saveEmail(RendelStrings strings) async {
    final result = await widget.support.contact(_email.text.trim());
    if (!mounted) return;
    setState(() {
      _note = switch (result) {
        'invalid' => strings.supportContactPlaceholder,
        'failed' => strings.turnFailed,
        _ => strings.supportContactSaved,
      };
    });
  }

  Future<void> _verify(RendelStrings strings) async {
    final ok = await widget.support.verify(_code.text.trim());
    if (mounted) setState(() => _note = ok ? null : strings.supportCodeWrong);
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final v = widget.support.value.value;
    final state = v.state;
    final inset = theme.space.plate;
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

    final lines = <Widget>[];
    String? lastAuthor;
    for (final entry in v.entries) {
      final author = entry.marker ? 'system' : '${entry.author.name}:${entry.authorName ?? ''}';
      lines.add(_line(context, theme, strings, entry, captioned: author != lastAuthor));
      lastAuthor = author;
    }
    for (final pending in v.pending) {
      lines.add(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(theme, pending.text, faded: !pending.failed),
          if (pending.failed)
            RendelActionButton(label: strings.supportUnsent, quiet: true, onTap: () => widget.support.retry(pending.clientMsgId)),
        ],
      ));
    }
    if (typing) lines.add(Text(strings.supportTypingOf(state?.agentName ?? widget.team), style: theme.text.captionSoft));
    if (state?.expectation case final expectation? when state!.mode != 'human') {
      lines.add(Text(expectation, style: theme.text.caption));
    }
    // The server's own line says it closed when the last thing that happened was closing it.
    if (resolved && !(v.entries.lastOrNull?.marker ?? false)) lines.add(Text(strings.supportClosed, style: theme.text.caption));

    return SafeArea(
      top: false,
      child: SizedBox(
        height: math.max(MediaQuery.sizeOf(context).height * 0.88 - MediaQuery.viewInsetsOf(context).bottom, 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(inset, theme.space.lg, theme.space.sm, theme.space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(strings.supportTeamOf(widget.team), style: theme.text.title),
                    ),
                  ),
                  Text((state?.teamHere ?? false) ? strings.supportHere : strings.supportAway, style: theme.text.caption),
                  IconButton(
                    tooltip: null,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded, color: theme.colors.onSurfaceSoft, semanticLabel: strings.supportBack),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: ListView.separated(
                      controller: _scroll,
                      padding: EdgeInsets.symmetric(horizontal: inset, vertical: theme.space.sm),
                      itemCount: lines.length,
                      separatorBuilder: (_, __) => SizedBox(height: theme.space.sm),
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
              padding: EdgeInsets.fromLTRB(inset, theme.space.sm, inset, theme.space.md),
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
                  if (!needsContact) _composer(theme, strings, state),
                  SizedBox(height: theme.space.xs),
                  // One way out: the header's close is "back to the assistant" everywhere else.
                  if (justHanded)
                    RendelActionButton(
                      label: strings.supportMistake,
                      quiet: true,
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        await widget.support.resolve();
                        navigator.maybePop();
                      },
                    )
                  else if (!resolved)
                    RendelActionButton(label: strings.supportSorted, quiet: true, onTap: () => widget.support.resolve()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, RendelTheme theme, RendelStrings strings, RendelSupportEntry entry, {required bool captioned}) {
    if (entry.marker) {
      return Center(child: Text(entry.text ?? '', style: theme.text.caption, textAlign: TextAlign.center));
    }
    final who = entry.author == RendelSupportAuthorKind.user ? strings.supportYou : (entry.authorName ?? widget.team);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.createdAt.toLocal()));
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (captioned)
            Padding(
              padding: EdgeInsets.only(bottom: theme.space.hair),
              child: Text('$who · $time', style: theme.text.caption),
            ),
          if (entry.text case final text? when text.isNotEmpty) _text(theme, text),
          for (final file in entry.files)
            Padding(
              padding: EdgeInsets.only(top: theme.space.hair),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_file_rounded, size: 16, color: theme.colors.onSurfaceSoft),
                  SizedBox(width: theme.space.hair),
                  Flexible(child: Text(file, style: theme.text.caption, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          for (final raw in entry.blocks)
            if (_unopened(raw))
              Padding(
                padding: EdgeInsets.only(top: theme.space.xs),
                child: Text(strings.loading, style: theme.text.caption),
              )
            else if (WireBlock.tryParse(raw) case final block?)
              Padding(
                padding: EdgeInsets.only(top: theme.space.xs),
                child: ComponentRegistry.build(context, block..ready = true, _dispatch),
              ),
        ],
      ),
    );
  }

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

  /// A line of the thread: flat on the page, as the assistant's answers are (PAGES.md).
  Widget _text(RendelTheme theme, String text, {bool faded = false}) =>
      Opacity(opacity: faded ? 0.6 : 1, child: Text(text, style: theme.text.body));

  /// A card's heading: `labelStrong` is drawn on the accent, these cards are not.
  TextStyle _heading(RendelTheme theme) => theme.text.labelStrong.copyWith(color: theme.colors.onSurface);

  InputDecoration _field(RendelTheme theme, String? hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        contentPadding: EdgeInsets.symmetric(horizontal: theme.space.sm, vertical: theme.space.xs + 4),
        filled: true,
        fillColor: theme.colors.surfaceHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.hairline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.hairline)),
      );

  Widget _composer(RendelTheme theme, RendelStrings strings, RendelSupportState? state) {
    final name = state?.agentName;
    final hint = name != null ? strings.supportWriteToOf(name) : strings.supportWriteTeamOf(widget.team);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.onPick != null && widget.onUpload != null) ...[
          IconButton(
            tooltip: null,
            onPressed: _attaching ? null : () => _attach(RendelAttachSource.photos, strings),
            icon: Icon(Icons.image_outlined, color: theme.colors.onSurfaceSoft, semanticLabel: strings.photos),
          ),
          IconButton(
            tooltip: null,
            onPressed: _attaching ? null : () => _attach(RendelAttachSource.files, strings),
            icon: Icon(Icons.description_outlined, color: theme.colors.onSurfaceSoft, semanticLabel: strings.attachFile),
          ),
        ],
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            maxLength: 4000,
            textInputAction: TextInputAction.send,
            onChanged: (_) => widget.support.typing(),
            onSubmitted: (_) => _send(),
            style: theme.text.body,
            decoration: _field(theme, hint).copyWith(counterText: ''),
          ),
        ),
        SizedBox(width: theme.space.xs),
        IconButton(
          tooltip: null,
          onPressed: _send,
          icon: Icon(Icons.arrow_upward_rounded, color: theme.colors.accent, semanticLabel: strings.sendMessage),
        ),
      ],
    );
  }

  Widget _contactCard(RendelTheme theme, RendelStrings strings, {required bool required}) {
    return _plate(theme, [
      Text(required ? strings.supportContactAsk : strings.supportContactOptional, style: _heading(theme)),
      SizedBox(height: theme.space.xs),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: theme.text.body,
              decoration: _field(theme, strings.supportContactPlaceholder),
              onSubmitted: (_) => _saveEmail(strings),
            ),
          ),
          SizedBox(width: theme.space.xs),
          RendelActionButton(label: strings.supportContactSend, onTap: () => _saveEmail(strings)),
        ],
      ),
      SizedBox(height: theme.space.xs),
      Text(strings.supportContactWhy, style: theme.text.caption),
    ]);
  }

  Widget _codeCard(RendelTheme theme, RendelStrings strings) {
    return _plate(theme, [
      Text(strings.supportCodeLabel, style: theme.text.caption),
      SizedBox(height: theme.space.xs),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofillHints: const [AutofillHints.oneTimeCode],
              style: theme.text.body,
              decoration: _field(theme, null).copyWith(counterText: ''),
              onSubmitted: (_) => _verify(strings),
            ),
          ),
          SizedBox(width: theme.space.xs),
          RendelActionButton(label: strings.confirm, quiet: true, onTap: () => _verify(strings)),
        ],
      ),
    ]);
  }

  Widget _plate(RendelTheme theme, List<Widget> children) => Container(
        margin: EdgeInsets.only(bottom: theme.space.sm),
        padding: EdgeInsets.all(theme.space.md),
        decoration: BoxDecoration(
          color: theme.glass,
          border: Border.all(color: theme.hairline),
          borderRadius: BorderRadius.circular(theme.plateRadius),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      );
}
