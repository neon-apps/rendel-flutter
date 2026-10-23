import 'package:flutter/material.dart';

import '../core/memory.dart';
import '../core/strings.dart';
import '../protocol/protocol.dart' show MemoryKind;
import 'renderer/blocks.dart' show RendelActionButton;
import 'theme.dart';

/// A note's last day, short, in the reader's language: "Nov 1".
///
/// The server keeps a note until the midnight UTC after its last day (the
/// turn's "today" is UTC's), so the day is read in UTC, a millisecond before
/// that midnight. Read in the device's own zone, Istanbul would show the day
/// after.
String memoryLastDay(BuildContext context, DateTime expiresAt) {
  final day = expiresAt.toUtc().subtract(const Duration(milliseconds: 1));
  return Localizations.of<MaterialLocalizations>(context, MaterialLocalizations)
          ?.formatShortMonthDay(day) ??
      '${day.day} ${RendelStringsScope.of(context).shortMonths[day.month - 1]}';
}

/// Opens "What I remember for you" (`design/plans/preference-memory.md`
/// §3.7) as a sheet over what is on screen, in [theme] and [strings], or in
/// the ones [context] is drawn in.
Future<void> showRendelMemory(
  BuildContext context, {
  required RendelMemory memory,
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
    builder: (_) => RendelThemeScope(
      theme: drawn,
      child: RendelStringsScope(strings: words, child: RendelMemorySheet(memory: memory)),
    ),
  );
}

/// Every note Rendel keeps for the person on this device: label and value,
/// "Noticed", "From the app" and "Until …" where they hold, Forget on each
/// the person may take back, and Forget all, asked once more in place.
class RendelMemorySheet extends StatefulWidget {
  const RendelMemorySheet({super.key, required this.memory});

  final RendelMemory memory;

  @override
  State<RendelMemorySheet> createState() => _RendelMemorySheetState();
}

class _RendelMemorySheetState extends State<RendelMemorySheet> {
  bool _loading = true;

  /// Null once loaded means it could not be read.
  RendelMemoryList? _list;

  /// Notes whose Forget is on its way.
  final Set<String> _forgetting = {};

  /// Forget all was pressed and is waiting for its answer.
  bool _asking = false;
  bool _forgettingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    final list = await widget.memory.list();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _list = list;
    });
  }

  Future<void> _forget(RendelMemoryNote note) async {
    setState(() => _forgetting.add(note.id));
    final gone = await widget.memory.forget(note.id);
    if (!mounted) return;
    setState(() {
      _forgetting.remove(note.id);
      final list = _list;
      if (gone && list != null) {
        _list = RendelMemoryList(
          enabled: list.enabled,
          notes: [for (final other in list.notes) if (other.id != note.id) other],
        );
      }
    });
  }

  Future<void> _forgetAll() async {
    setState(() => _forgettingAll = true);
    final done = await widget.memory.forgetAll();
    if (!mounted) return;
    setState(() {
      _forgettingAll = false;
      _asking = false;
      final list = _list;
      // The app's own facts stay; the server keeps them too.
      if (done && list != null) {
        _list = RendelMemoryList(
          enabled: list.enabled,
          notes: [for (final note in list.notes) if (!note.forgettable) note],
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final list = _list;
    final notes = list?.notes ?? const <RendelMemoryNote>[];
    final inset = theme.space.plate;

    final List<Widget> body;
    if (_loading) {
      body = [Text(strings.loading, style: theme.text.labelSoft)];
    } else if (list == null) {
      body = [
        Text(strings.turnFailed, style: theme.text.body),
        SizedBox(height: theme.space.md),
        RendelActionButton(label: strings.retry, quiet: true, onTap: _load),
      ];
    } else if (!list.enabled) {
      body = [Text(strings.memoryOff, style: theme.text.body)];
    } else if (notes.isEmpty) {
      body = [Text(strings.memoryEmpty, style: theme.text.body)];
    } else {
      body = [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colors.surfaceHigh,
            border: Border.all(color: theme.hairline),
            borderRadius: BorderRadius.circular(theme.radius.card),
          ),
          child: Column(
            children: [
              for (var i = 0; i < notes.length; i++) ...[
                if (i > 0) Container(height: 1, color: theme.hairline),
                _row(context, theme, strings, notes[i]),
              ],
            ],
          ),
        ),
        if (notes.any((note) => note.forgettable)) ...[
          SizedBox(height: theme.space.md),
          _asking
              ? _confirmAll(theme, strings)
              : RendelActionButton(
                  label: strings.memoryForgetAll,
                  quiet: true,
                  expand: true,
                  onTap: () => setState(() => _asking = true),
                ),
        ],
      ];
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(inset, theme.space.lg, inset, theme.space.md),
              child: Semantics(
                header: true,
                child: Text(strings.memoryTitle, style: theme.text.title),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: inset),
                children: body,
              ),
            ),
            if (list?.enabled ?? false)
              Padding(
                padding: EdgeInsets.fromLTRB(inset, theme.space.md, inset, theme.space.lg),
                child: Text(strings.memoryFooter, style: theme.text.caption),
              )
            else
              SizedBox(height: theme.space.lg),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, RendelTheme theme, RendelStrings strings, RendelMemoryNote note) {
    final tags = [
      if (note.kind == MemoryKind.learned) strings.memoryNoticed,
      if (note.kind == MemoryKind.set) strings.memoryFromApp,
      if (note.expiresAt case final at?) strings.memoryUntilOf(memoryLastDay(context, at)),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: theme.space.md, vertical: theme.space.sm),
      child: Row(
        children: [
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.name, style: theme.text.label),
                  SizedBox(height: theme.space.hair),
                  Text(note.value, style: theme.text.captionSoft),
                  if (tags.isNotEmpty) ...[
                    SizedBox(height: theme.space.xs),
                    Text(tags.join(' · '), style: theme.text.caption),
                  ],
                ],
              ),
            ),
          ),
          if (note.forgettable) ...[
            SizedBox(width: theme.space.sm),
            RendelActionButton(
              label: strings.memoryForget,
              quiet: true,
              onTap: _forgetting.contains(note.id) ? null : () => _forget(note),
            ),
          ],
        ],
      ),
    );
  }

  /// Forget all asked once more, as the SDK's own confirmation asks: the
  /// question on a plate, the action in danger (it cannot be taken back) and
  /// Go back beside it.
  Widget _confirmAll(RendelTheme theme, RendelStrings strings) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(theme.space.plate),
      decoration: BoxDecoration(
        color: theme.glass,
        border: Border.all(color: theme.hairline),
        borderRadius: BorderRadius.circular(theme.plateRadius),
      ),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.memoryForgetAllConfirm, style: theme.text.prose),
            SizedBox(height: theme.space.lg),
            Row(
              children: [
                Expanded(
                  child: RendelActionButton(
                    label: strings.memoryForgetAll,
                    expand: true,
                    danger: true,
                    onTap: _forgettingAll ? null : _forgetAll,
                  ),
                ),
                SizedBox(width: theme.space.sm),
                Expanded(
                  child: RendelActionButton(
                    label: strings.goBack,
                    quiet: true,
                    expand: true,
                    onTap: _forgettingAll ? null : () => setState(() => _asking = false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
