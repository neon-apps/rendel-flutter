import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/support.dart';
import 'lab/lab.dart' show LabGlass;
import 'renderer/blocks.dart' show RendelPressable;
import 'theme.dart';

/// Recent on Rendel's start, and the page behind it (Tuna, 2026-11-03,
/// "1 · Recent", and only the team's: "sadece customer support ile
/// chatleştiyse"): the person's conversations with the app's team, a sorted
/// one opening as it was. The web panel draws the same (`.rd-recent`,
/// `.rd-support-list`).

/// The person's last three sorted conversations under the suggestions; the
/// open one keeps its row at the top. Nothing while there is none.
class RendelSupportRecent extends StatelessWidget {
  const RendelSupportRecent({
    super.key,
    required this.threads,
    required this.team,
    required this.onOpen,
    required this.onSeeAll,
  });

  final List<RendelSupportThread> threads;
  final String team;
  final void Function(String threadId) onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final shown = threads.where((t) => t.resolved && _spoken(t)).take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(strings.supportRecent, style: _kicker(theme)),
                ),
              ),
              RendelPressable(
                semanticLabel: strings.supportSeeAll,
                onTap: onSeeAll,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Center(
                    child: Text(
                      strings.supportSeeAll,
                      style: theme.text.caption.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.accentText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _ThreadCard(threads: shown, team: team, onOpen: onOpen),
      ],
    );
  }
}

/// "With the Halden team": every conversation with the team, this week's and
/// earlier, with a search over them. A tap closes it and opens that one; ✕
/// closes it and then [onClose] (all of Rendel, as on the web).
Future<void> showRendelSupportList(
  BuildContext context, {
  required List<RendelSupportThread> threads,
  required Future<List<RendelSupportThread>?> Function() reload,
  required String team,
  required RendelTheme theme,
  required RendelStrings strings,
  required void Function(String threadId) onOpen,
  VoidCallback? onClose,
}) {
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: rendelSheetMotion(context),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: theme.colors.surfaceRaised,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(theme.radius.hero),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    // The keyboard takes the bottom of the screen while the search is typed in: the list sits on it.
    builder:
        (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: RendelThemeScope(
            theme: theme,
            child: RendelStringsScope(
              strings: strings,
              child: _SupportList(
                threads: threads,
                reload: reload,
                team: team,
                onClose: onClose,
                onOpen: (id) {
                  Navigator.of(sheetContext).pop();
                  onOpen(id);
                },
              ),
            ),
          ),
        ),
  );
}

/// Lowercase for search, with I, İ, ı and i as one letter: Dart's
/// toLowerCase knows no Turkish, so "kırık" would miss "KIRIK".
String _searchFold(String s) =>
    s.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase().replaceAll('ı', 'i');

/// A conversation someone wrote in: one opened with no words (an older SDK's "Contact us") is left out of the lists.
bool _spoken(RendelSupportThread t) => t.title.trim().isNotEmpty || t.last != null;

class _SupportList extends StatefulWidget {
  const _SupportList({
    required this.threads,
    required this.reload,
    required this.team,
    this.onClose,
    required this.onOpen,
  });

  final List<RendelSupportThread> threads;
  final Future<List<RendelSupportThread>?> Function() reload;
  final String team;
  final VoidCallback? onClose;
  final void Function(String threadId) onOpen;

  @override
  State<_SupportList> createState() => _SupportListState();
}

class _SupportListState extends State<_SupportList> {
  late List<RendelSupportThread> _threads = widget.threads;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Read again: a conversation may have moved since Recent was.
    widget.reload().then((threads) {
      if (threads != null && mounted) setState(() => _threads = threads);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final q = _searchFold(_search.text.trim());
    final all = [
      for (final t in _threads)
        if (_spoken(t) &&
            (q.isEmpty ||
                _searchFold('${t.title} ${t.last?.text ?? ''} ${t.agent ?? ''}')
                    .contains(q)))
          t,
    ];
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final week = [
      for (final t in all)
        if (!t.lastMessageAt.isBefore(weekAgo)) t,
    ];
    final earlier = [
      for (final t in all)
        if (t.lastMessageAt.isBefore(weekAgo)) t,
    ];
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.88 -
              MediaQuery.viewInsetsOf(context).bottom)
          .clamp(200.0, double.infinity),
      child: ColoredBox(
        color: Color.alphaBlend(
          theme.colors.onSurface.withValues(alpha: 0.015),
          theme.colors.surfaceRaised,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The team's page's own head (look A, sdk-18): 44pt round glass back and close, the title centred
            // in all the room between them, as the support sheet draws it.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  _roundButton(
                    theme,
                    icon: Icons.chevron_left_rounded,
                    label: strings.supportBack,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        strings.supportAllOf(widget.team),
                        textAlign: TextAlign.center,
                        style: theme.text.body.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colors.onSurface,
                        ),
                        // Two lines, as the web's: "Lunar Kozmetik (web)
                        // ekibiyle tüm sohbetler" was cut on a phone (T02).
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  _roundButton(
                    theme,
                    icon: Icons.close_rounded,
                    label: strings.closeCopilot,
                    onTap: () {
                      Navigator.of(context).maybePop();
                      widget.onClose?.call();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colors.surfaceRaised,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colors.onSurface.withValues(alpha: 0.08),
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: theme.colors.onSurfaceFaint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.search,
                            style: theme.text.body.copyWith(
                              color: theme.colors.onSurface,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: strings.supportSearch,
                              hintStyle: theme.text.body.copyWith(
                                color: theme.colors.onSurfaceFaint,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (all.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                      child: Text(
                        strings.supportSearchNone,
                        style: theme.text.body.copyWith(
                          fontSize: 14,
                          color: theme.colors.onSurfaceSoft,
                        ),
                      ),
                    ),
                  if (week.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Text(
                        strings.supportThisWeek,
                        style: _kicker(theme),
                      ),
                    ),
                    _ThreadCard(
                      threads: week,
                      team: widget.team,
                      onOpen: widget.onOpen,
                      locale: locale,
                    ),
                  ],
                  if (earlier.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Text(
                        strings.supportEarlier,
                        style: _kicker(theme),
                      ),
                    ),
                    _ThreadCard(
                      threads: earlier,
                      team: widget.team,
                      onOpen: widget.onOpen,
                      locale: locale,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 44pt round glass button, as the support sheet's head draws its own.
Widget _roundButton(RendelTheme theme, {required IconData icon, required String label, required VoidCallback onTap}) => RendelPressable(
  semanticLabel: label,
  onTap: onTap,
  child: SizedBox(
    width: 44,
    height: 44,
    child: Center(
      child: LabGlass(circle: true, width: 40, height: 40, alignment: Alignment.center, child: Icon(icon, size: 26, color: theme.colors.onSurface)),
    ),
  ),
);

TextStyle _kicker(RendelTheme theme) => theme.text.caption.copyWith(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: theme.colors.onSurfaceSoft,
);

/// Conversations in one white card, a hairline between them.
class _ThreadCard extends StatelessWidget {
  const _ThreadCard({
    required this.threads,
    required this.team,
    required this.onOpen,
    this.locale,
  });

  final List<RendelSupportThread> threads;
  final String team;
  final void Function(String threadId) onOpen;
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colors.onSurface.withValues(alpha: 0.06),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: theme.colors.shadow.withValues(alpha: 0.2),
            offset: const Offset(0, 14),
            blurRadius: 28,
            spreadRadius: -24,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < threads.length; i++) ...[
              if (i > 0)
                Container(
                  height: 1,
                  color: theme.colors.onSurface.withValues(alpha: 0.06),
                ),
              RendelSupportThreadItem(
                thread: threads[i],
                team: team,
                onTap: () => onOpen(threads[i].threadId),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One conversation with the team: open or sorted, the person's first line, where it stands, and when.
class RendelSupportThreadItem extends StatelessWidget {
  const RendelSupportThreadItem({
    super.key,
    required this.thread,
    required this.team,
    required this.onTap,
  });

  final RendelSupportThread thread;
  final String team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final t = thread;
    // A conversation opened before anyone wrote in it has no first line to be named by (apps-15).
    final title = t.title.trim().isNotEmpty ? t.title : strings.supportRowTitleOf(team);
    String said(({bool mine, String text}) last) =>
        '${last.mine ? strings.supportYou : (t.agent ?? team)}: ${last.text}';
    // Waiting, until a time on the person's own clock (C4).
    final waiting = supportBackOn(context, strings, waiting: t.waiting, backAt: t.backAt).waiting;
    final line =
        t.resolved
            // Closed by Support's switch (K1): said so, never "Sorted".
            ? (t.closedOff
                ? strings.supportClosedMark
                : t.agent != null
                ? strings.supportSortedWithOf(t.agent!)
                : strings.supportSortedMark)
            : (t.unread > 0 && t.last != null
                ? said(t.last!)
                : (waiting ?? (t.last != null ? said(t.last!) : '')));
    final material = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final today =
        t.lastMessageAt.year == now.year &&
        t.lastMessageAt.month == now.month &&
        t.lastMessageAt.day == now.day;
    final when =
        today
            ? material.formatTimeOfDay(TimeOfDay.fromDateTime(t.lastMessageAt))
            : material.formatShortMonthDay(t.lastMessageAt);
    return RendelPressable(
      semanticLabel: [
        title,
        if (line.isNotEmpty) line,
        if (t.unread > 0) strings.supportUnreadOf(t.unread) else when,
      ].join('. '),
      onTap: onTap,
      pressedScale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.alphaBlend(
                    (t.resolved
                        ? theme.colors.onSurface.withValues(alpha: 0.06)
                        : theme.colors.accent.withValues(alpha: 0.14)),
                    theme.colors.surfaceRaised,
                  ),
                ),
                child:
                    t.resolved
                        ? Icon(
                          t.closedOff ? Icons.lock_outline_rounded : Icons.check_rounded,
                          size: 15,
                          color: theme.accentText,
                        )
                        : Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: theme.colors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.text.body.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (line.isNotEmpty)
                      Text(
                        line,
                        style: theme.text.caption.copyWith(fontSize: 12.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (t.unread > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colors.accent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    t.unread > 9 ? '9+' : '${t.unread}',
                    style: theme.text.caption.copyWith(
                      color: theme.colors.onAccent,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                )
              else
                Text(
                  when,
                  style: theme.text.caption.copyWith(
                    fontSize: 12,
                    color: theme.colors.onSurfaceFaint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [rendelSupportBack] with the page's own clock and calendar words (the host
/// app's localizations, as every date the support pages draw): when the team
/// is back, on the person's own clock (C4).
({String? presence, String? waiting, String? expectation}) supportBackOn(
  BuildContext context,
  RendelStrings strings, {
  String? presence,
  String? waiting,
  String? expectation,
  String? backAt,
}) {
  final material = MaterialLocalizations.of(context);
  return rendelSupportBack(
    strings,
    presence: presence,
    waiting: waiting,
    expectation: expectation,
    backAt: backAt,
    time: (at) => material.formatTimeOfDay(TimeOfDay.fromDateTime(at)),
    day: material.formatMediumDate,
  );
}
