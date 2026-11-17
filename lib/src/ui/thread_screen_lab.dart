part of 'thread_screen.dart';

/// The panel's look (`design/plans/sdk-look-a.md`, Tuna 2026-11-15): round
/// glass buttons floating at the top, the opening centred, the suggestions
/// as cards with a picture, and a message card at the foot: what you will
/// ask on top, attach, the microphone and send under it. The SDK's own controls do the work: the same
/// steps, read aloud, start over, close, field, attach menu and held mic.

/// A round glass button, 40 points as in the reference, in a 44-point target.
Widget _labRound(RendelTheme theme, {required Widget child, required String label, VoidCallback? onTap}) => RendelPressable(
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox(width: 44, height: 44, child: Center(child: LabGlass(circle: true, width: 40, height: 40, alignment: Alignment.center, child: child))),
    );

/// The team's row: glass under look A, the SDK's own card otherwise.
Widget _labOr(RendelTheme theme, {required double radius, required EdgeInsetsGeometry padding, required Decoration decoration, required Widget child}) =>
    RendelLab.of('look') == 'a' ? LabGlass(radius: radius, padding: padding, child: child) : Container(padding: padding, decoration: decoration, child: child);

class _LabTop extends StatefulWidget {
  const _LabTop({
    required this.onReset,
    required this.onBack,
    required this.onForward,
    required this.voice,
    required this.title,
    required this.sandbox,
    required this.fresh,
    this.paged = false,
    this.logoUrl,
    this.logoHeaders = const {},
    this.team,
  });
  final String title;

  /// A second page: back and forward join the menu.
  final bool paged;

  /// A test key: the badge that says so, always, between the buttons.
  final bool sandbox;

  /// The opening: its greeting says who this is, so the name waits for a page.
  final bool fresh;
  final String? logoUrl;
  final Map<String, String> logoHeaders;
  final VoidCallback? onReset;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final RendelVoice? voice;

  /// The conversation with the team, kept in the menu while a page is open.
  final (String, VoidCallback)? team;

  @override
  State<_LabTop> createState() => _LabTopState();
}

class _LabTopState extends State<_LabTop> {
  bool _menu = false;

  void _do(VoidCallback? action) {
    setState(() => _menu = false);
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final ink = theme.colors.onSurface;
    // Two strokes, the upper one longer: the menu's mark in the reference.
    final menuMark = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 18, height: 2.6, decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 6),
      Container(width: 12.5, height: 2.6, decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(2))),
    ]);
    // The page arrows in the family the host's own navigation uses, and the
    // SDK's own start-over glyph, as the header always drew them.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final (back, forward) = switch (theme.style.arrows) {
      RendelArrowStyle.chevron => (_Glyph.chevronBack, _Glyph.chevronForward),
      RendelArrowStyle.arrow => (_Glyph.arrowBack, _Glyph.arrowForward),
      RendelArrowStyle.ios => (_Glyph.iosBack, _Glyph.iosForward),
    };
    final rows = <(Widget Function(Color), String, VoidCallback?)>[
      if (widget.team case (final title, final open)) ((c) => Icon(Icons.forum_outlined, size: 20, color: c), title, open),
      ((c) => _HeaderGlyph.reset(color: c), strings.newConversation, widget.onReset),
      if (widget.paged) ...[
        ((c) => _HeaderGlyph.step(rtl ? forward : back, color: c), strings.previousPage, widget.onBack),
        ((c) => _HeaderGlyph.step(rtl ? back : forward, color: c), strings.nextPage, widget.onForward),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _labRound(theme, label: strings.menu, onTap: () => setState(() => _menu = !_menu), child: menuMark),
          // The name between the buttons, as on the team's page, with the
          // app's mark before it and the test badge under it.
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!widget.fresh)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.logoUrl case final logo?) ...[
                    Image.network(
                      logo,
                      headers: widget.logoHeaders,
                      height: 18,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      loadingBuilder: (context, child, progress) => progress == null ? child : const SizedBox(width: 18, height: 18),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: _HeaderName(title: widget.title, style: theme.text.heading.copyWith(fontSize: 15.5, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ]),
              if (widget.sandbox) ...[
                if (!widget.fresh) const SizedBox(height: 3),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: theme.space.sm, vertical: theme.space.hair),
                  // An outline, not a fill: a notice about the key, not a control.
                  decoration: BoxDecoration(border: Border.all(color: theme.accentEdge), borderRadius: BorderRadius.circular(theme.radius.control)),
                  // Never cut: it is the difference between a test key and a live one.
                  child: Text(strings.testMode, style: theme.text.overline.copyWith(color: theme.accentText), maxLines: 2, textAlign: TextAlign.center),
                ),
              ],
            ]),
          ),
          // As in the reference: read aloud and close share one glass capsule.
          if (widget.voice case final voice?)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
              child: LabGlass(
                radius: 20,
                height: 40,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: voice.on,
                    // A switch, so a screen reader says which, as the header's always was.
                    builder: (context, on, _) => Semantics(
                      toggled: on,
                      hint: strings.readAloud,
                      child: RendelPressable(
                        semanticLabel: strings.autoRead,
                        onTap: () => voice.setOn(!on),
                        child: SizedBox(width: 44, child: Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 21, color: on ? theme.colors.accent : ink)),
                      ),
                    ),
                  ),
                  RendelPressable(
                    semanticLabel: strings.closeCopilot,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: SizedBox(width: 44, child: Icon(Icons.close_rounded, size: 26, color: ink)),
                  ),
                ]),
              ),
            )
          else
            _labRound(theme, label: strings.closeCopilot, onTap: () => Navigator.of(context).maybePop(), child: Icon(Icons.close_rounded, size: 26, color: ink)),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: theme.motion.curve,
          alignment: Alignment.topLeft,
          child: !_menu
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: LabGlass(
                    width: 290,
                    padding: const EdgeInsets.all(6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final (icon, label, action) in rows)
                        RendelPressable(
                          semanticLabel: label,
                          onTap: action == null ? null : () => _do(action),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                            child: Row(children: [
                              SizedBox.square(dimension: 22, child: icon(action == null ? theme.colors.onSurfaceFaint : ink)),
                              const SizedBox(width: 12),
                              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.text.label.copyWith(fontSize: 16, color: action == null ? theme.colors.onSurfaceFaint : ink))),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ),
        ),
      ]),
    );
  }
}

/// The opening, centred: the day, then the greeting.
class _LabOpening extends StatelessWidget {
  const _LabOpening({required this.headline, required this.subtitle, required this.onOpen, this.recent, this.suggestions = const [], this.onPick});
  final String? headline;

  /// Suggestions with no picture, drawn as a list under the words (`_LabList`); empty draws none.
  final List<String> suggestions;
  final void Function(String)? onPick;

  /// The person's sorted conversations with the team, under the words.
  final Widget? recent;

  /// Empty is the customer's choice (nothing is drawn); null, the default line.
  final String? subtitle;

  /// A link in the subtitle, tapped: the host opens it.
  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final words = (headline?.trim().isNotEmpty ?? false) ? headline!.trim() : RendelStringsScope.of(context).emptyTitle;
    final day = MaterialLocalizations.of(context).formatMediumDate(DateTime.now());
    // Centred while it fits; scrolls on a small phone or at the largest text
    // rather than spilling under the cards.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Align(
      alignment: const Alignment(0, -0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(day, style: theme.text.body.copyWith(color: theme.colors.onSurfaceSoft, fontSize: 15.5)),
          const SizedBox(height: 6),
          // At most 1.6× the reader's size, as the opening always was (QA R7).
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.6,
            child: Text(words, textAlign: TextAlign.center, style: theme.text.display.copyWith(fontSize: 24, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
          ),
          if (subtitle == null || subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _LinkedText(
              subtitle?.trim() ?? RendelStringsScope.of(context).emptyBody,
              style: theme.text.body.copyWith(color: theme.colors.onSurfaceSoft),
              textAlign: TextAlign.center,
              onOpen: onOpen,
            ),
          ],
          if (suggestions.isNotEmpty && onPick != null) ...[
            const SizedBox(height: 26),
            _LabList(suggestions: suggestions, onPick: onPick!),
          ],
          if (recent case final recent?) ...[
            const SizedBox(height: 24),
            recent,
          ],
        ]),
      ),
          ),
        ),
      ),
    );
  }
}

/// True when no suggestion has a picture from the app: then they are a list
/// under the greeting (`_LabList`), not the row over the message card.
bool _noPictures(List<String> suggestions) => suggestions.every((s) => RendelLook.suggestionCards[s]?.image == null);

/// Suggestions with no picture (Tuna, 2026-11-17, B5 of the suggestions lab):
/// one glass card under the greeting, 22 round, a row 70 tall for each, the
/// title (17) over its line, a hairline between rows and a 32 round arrow at
/// the end. The web panel draws the same (`.rd-cards[data-list]`).
class _LabList extends StatelessWidget {
  const _LabList({required this.suggestions, required this.onPick});
  final List<String> suggestions;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final line = LabGlass.lineOf(theme);
    return SizedBox(
      width: double.infinity,
      child: LabGlass(
        radius: 22,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < suggestions.length; i++) ...[
            if (i > 0) Container(height: 0.5, color: line),
            _row(theme, suggestions[i]),
          ],
        ]),
      ),
    );
  }

  Widget _row(RendelTheme theme, String s) {
    final card = RendelLook.suggestionCards[s];
    return RendelPressable(
      semanticLabel: s,
      onTap: () => onPick(s),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 70),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(card?.title ?? s, maxLines: card == null ? 2 : 1, overflow: TextOverflow.ellipsis, style: theme.text.label.copyWith(fontSize: 17, fontWeight: FontWeight.w600, height: 1.2)),
                if (card?.line case final line?) ...[
                  const SizedBox(height: 2),
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.text.body.copyWith(fontSize: 15, color: theme.colors.onSurfaceSoft, height: 1.2)),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colors.onSurface.withValues(alpha: 0.06)),
              child: Icon(Icons.chevron_right_rounded, size: 18, color: theme.colors.onSurfaceSoft),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The suggestions as a row of cards over the message card, each with a picture.
class _LabCards extends StatelessWidget {
  const _LabCards({required this.suggestions, required this.onPick});
  final List<String> suggestions;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    // 55 points tall, 15 from the screen's edge, 9 apart and 11 above the
    // message card, as in the reference. Faded, in place, while + is open.
    return ValueListenableBuilder<bool>(
      valueListenable: LabPopover.anyOpen,
      builder: (context, menu, cards) => IgnorePointer(
        ignoring: menu,
        child: LabFade(visible: !menu, child: cards!),
      ),
      child: Transform.translate(
      offset: const Offset(0, 5.5),
      child: SizedBox(
      height: 55,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Out to the screen's edges, so the row runs off it.
        padding: const EdgeInsets.symmetric(horizontal: 15),
        clipBehavior: Clip.none,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, i) {
          final s = suggestions[i];
          final card = RendelLook.suggestionCards[s];
          return RendelPressable(
            semanticLabel: s,
            onTap: () => onPick(s),
            // As wide as its words, so the line under the title is read whole.
            child: LabGlass(
              radius: 18,
              constraints: const BoxConstraints(minWidth: 190, maxWidth: 300),
              padding: const EdgeInsets.fromLTRB(14, 7, 16, 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // No picture from the app, no place for one: the words alone.
                if (card?.image case final image?) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: image.startsWith('https://')
                        ? Image.network(image, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 32, height: 32))
                        : Image.asset(image, width: 32, height: 32, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 14),
                ],
                Flexible(
                  child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(card?.title ?? s, maxLines: card == null ? 2 : 1, overflow: TextOverflow.ellipsis, style: theme.text.label.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.2)),
                    if (card?.line case final line?)
                      Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.text.body.copyWith(fontSize: 15, color: theme.colors.onSurfaceSoft, height: 1.2)),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
      ),
      ),
    );
  }
}

/// Look A's notice for what did not work: a soft white card with a mark, in
/// the page's own words, and the way to try again beside it.
class _LabNotice extends StatelessWidget {
  const _LabNotice({required this.message, required this.retryLabel, required this.onRetry});
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final dark = theme.colors.onSurface.computeLuminance() > theme.colors.surface.computeLuminance();
    return Semantics(
      liveRegion: true,
      child: Padding(
        // As far in as the message card under it.
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
        child: LabGlass(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: dark ? const Color(0xFF3A2A1E) : const Color(0xFFF6E7D8), shape: BoxShape.circle),
              child: Icon(Icons.priority_high_rounded, size: 17, color: dark ? const Color(0xFFE3A06B) : const Color(0xFFB4642C)),
            ),
            const SizedBox(width: 11),
            Expanded(child: Text(message, style: theme.text.body.copyWith(fontSize: 14.5, height: 1.3, color: theme.colors.onSurface))),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              RendelPressable(
                semanticLabel: retryLabel,
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(color: theme.colors.surfaceSunk, borderRadius: BorderRadius.circular(999)),
                  child: Text(retryLabel, style: theme.text.label.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
