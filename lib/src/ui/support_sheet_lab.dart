part of 'support_sheet.dart';
// ignore_for_file: invalid_use_of_protected_member

/// The panel's look on the team's thread (`design/plans/sdk-look-a.md` §8):
/// round glass buttons at the top with the team named between them, and the
/// same message card as the assistant's, on the SDK's own thread.

/// Near the 4,000 characters a line may hold, how much of it is used: "3,812 / 4,000", as on the web (sdk-19).
Widget? _supportCount(BuildContext context, {required int currentLength, required bool isFocused, required int? maxLength}) {
  if (maxLength == null || currentLength < maxLength * 0.9) return null;
  final digits = MaterialLocalizations.of(context);
  return Padding(
    padding: const EdgeInsetsDirectional.only(end: 13),
    child: Text('${digits.formatDecimal(currentLength)} / ${digits.formatDecimal(maxLength)}', style: RendelThemeScope.of(context).text.caption.copyWith(fontSize: 12)),
  );
}

Widget _labRoundButton(RendelTheme theme, {required IconData icon, required String label, required VoidCallback onTap}) => RendelPressable(
  semanticLabel: label,
  onTap: onTap,
  child: SizedBox(width: 44, height: 44, child: Center(child: LabGlass(circle: true, width: 40, height: 40, alignment: Alignment.center, child: Icon(icon, size: 26, color: theme.colors.onSurface)))),
);

extension _LabSupport on _RendelSupportSheetState {
  Widget labHead(BuildContext context, RendelTheme theme, RendelStrings strings, {required bool resolved}) {
    final state = widget.support.value.value.state;
    final here = state?.teamHere ?? false;
    final tone = Color.lerp(here ? const Color(0xFF2E7D4F) : const Color(0xFFB7791F), theme.colors.onSurface, 0.12)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          _labRoundButton(theme, icon: Icons.chevron_left_rounded, label: strings.supportBack, onTap: () => Navigator.of(context).maybePop(SupportExit.back)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    strings.supportTeamOf(widget.team),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.text.body.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colors.onSurface),
                  ),
                ),
                // No thread yet (K3): nothing is known of the team, so nothing is said.
                if (state != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!resolved) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)), const SizedBox(width: 6)],
                      Flexible(
                        child: Text(
                          _status(context, strings, state, resolved: resolved),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.text.caption.copyWith(fontSize: 13, color: theme.colors.onSurfaceSoft),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // ✕ closes all of Rendel, and says so, as the web's does (sdk-22).
          _labRoundButton(theme, icon: Icons.close_rounded, label: strings.closeCopilot, onTap: () => Navigator.of(context).maybePop(SupportExit.closed)),
        ],
      ),
    );
  }

  /// [ask] is the question and its button, drawn as the card's first row.
  Widget labComposer(RendelTheme theme, RendelStrings strings, {bool resolved = false, Widget? ask}) {
    final canAttach = widget.onPick != null && widget.onUpload != null;
    final ink = theme.colors.onSurface;
    // As on the assistant's side, one for one: + opens the same sources over
    // the message card, in the same glass, and a tap anywhere else closes them.
    final Widget menu = TapRegion(
        groupId: this,
        child: LabArrive(
          key: const ValueKey('lab-support-menu'),
          alignment: Alignment.bottomLeft,
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            child: LayoutBuilder(
              builder:
                  (context, constraints) => ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth * 0.64),
                    child: IntrinsicWidth(
                      child: LabGlass(
                        radius: 24,
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final source in widget.sources)
                              RendelPressable(
                                semanticLabel: _sourceLabel(source, strings),
                                onTap: () {
                                  setState(() => _menu = false);
                                  _attach(source, strings);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                  child: Row(
                                    children: [
                                      Icon(
                                        switch (source) {
                                          RendelAttachSource.photos => Icons.image_outlined,
                                          RendelAttachSource.camera => Icons.photo_camera_outlined,
                                          RendelAttachSource.files => Icons.description_outlined,
                                        },
                                        size: 24,
                                        color: ink,
                                      ),
                                      const SizedBox(width: 14),
                                      Text(_sourceLabel(source, strings), style: theme.text.prose.copyWith(color: ink)),
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
      );
    final composer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabArrive(
          key: const ValueKey('lab-support-card'),
          child: LabGlass(
            radius: 24,
            padding: EdgeInsets.fromLTRB(2, ask == null ? 8 : 0, 2, 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Across the card, over the words.
                if (ask != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: ask),
                TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 4000,
                  buildCounter: _supportCount,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => widget.support.typing(),
                  onSubmitted: (_) => _send(),
                  style: theme.text.body.copyWith(color: ink, fontSize: theme.type.body),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: resolved ? strings.supportReopenHint : strings.supportWriteTeamOf(widget.team),
                    hintStyle: theme.text.body.copyWith(fontSize: theme.type.body, color: theme.colors.onSurfaceFaint.withValues(alpha: 0.8)),
                    contentPadding: const EdgeInsets.fromLTRB(13, 6, 13, 6),
                  ),
                ),
                Row(
                  children: [
                    if (canAttach)
                      RendelPressable(
                        semanticLabel: strings.attachFile,
                        onTap: _attaching ? null : () => widget.sources.length == 1 ? _attach(widget.sources.single, strings) : setState(() => _menu = !_menu),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(color: ink.withValues(alpha: ink.computeLuminance() > 0.5 ? 0.10 : 0.05), shape: BoxShape.circle),
                              child: Icon(Icons.add_rounded, size: 19, color: ink),
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _input,
                      builder: (context, value, _) {
                        final ready = value.text.trim().isNotEmpty;
                        return RendelPressable(
                          semanticLabel: strings.sendMessage,
                          onTap: ready ? _send : null,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 29,
                                height: 29,
                                decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
                                child: Icon(Icons.arrow_upward_rounded, size: 18, color: theme.colors.surfaceRaised),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
    // The sources open over the card, not in its place: nothing above jumps.
    return TapRegion(
      groupId: this,
      onTapOutside: (_) {
        if (_menu) setState(() => _menu = false);
      },
      child: LabPopover(groupId: this, open: _menu && canAttach, popover: menu, child: composer),
    );
  }

  String _sourceLabel(RendelAttachSource source, RendelStrings strings) => switch (source) {
    RendelAttachSource.photos => strings.photos,
    RendelAttachSource.camera => strings.camera,
    RendelAttachSource.files => strings.files,
  };
}
