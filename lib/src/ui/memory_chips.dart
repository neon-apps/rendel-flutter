import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../protocol/protocol.dart' show MemoryChange, MemoryKind, MemoryOp;
import 'memory_sheet.dart' show memoryLastDay;
import 'renderer/blocks.dart' show RendelPressable;
import 'theme.dart';

/// What an answer did to the person's memory, as quiet lines at its foot
/// (`design/plans/preference-memory.md` §3.3, §3.7): "Based on your …
/// preference" first, one line for every note it relied on, then each save,
/// change and forget in the order they came. A save carries Undo. The words
/// open "What I remember for you".
///
/// A footer piece of its own, so the answer's other footer controls sit
/// beside it rather than inside it.
class RendelMemoryChips extends StatelessWidget {
  const RendelMemoryChips({
    super.key,
    required this.changes,
    required this.onUndo,
    required this.onOpen,
  });

  final List<MemoryChange> changes;
  final void Function(MemoryChange change) onUndo;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = RendelStringsScope.of(context);
    final used = [for (final change in changes) if (change.op == MemoryOp.used) change];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (used.length == 1)
          _MemoryChip(
            icon: Icons.bookmark_border_rounded,
            words: strings.memoryUsedOf(used.single.name),
            onOpen: onOpen,
          )
        else if (used.length > 1)
          _MemoryChip(
            icon: Icons.bookmark_border_rounded,
            words: strings.memoryUsedManyOf(used.length),
            onOpen: onOpen,
          ),
        for (final change in changes)
          if (change.op != MemoryOp.used)
            _MemoryChip(
              icon: change.op == MemoryOp.forgotten || change.undone
                  ? Icons.bookmark_remove_outlined
                  : Icons.bookmark_added_outlined,
              words: _words(context, strings, change),
              onOpen: onOpen,
              onUndo: change.op == MemoryOp.saved && change.id != null && !change.undone
                  ? () => onUndo(change)
                  : null,
            ),
      ],
    );
  }

  static String _words(BuildContext context, RendelStrings strings, MemoryChange change) {
    final until = switch (change.expiresAt) {
      final at? => memoryLastDay(context, at),
      null => null,
    };
    return switch (change.op) {
      MemoryOp.forgotten when change.key == '*' => strings.memoryForgottenAll,
      MemoryOp.forgotten => strings.memoryForgottenOf(change.name),
      MemoryOp.updated => strings.memoryUpdatedOf(change.name),
      MemoryOp.saved when change.undone => strings.memoryUndone,
      MemoryOp.saved when change.kind == MemoryKind.learned => strings.memoryNotedOf(change.name, until: until),
      MemoryOp.saved => strings.memorySavedOf(change.name, until: until),
      MemoryOp.used => strings.memoryUsedOf(change.name),
    };
  }
}

/// One line: a bookmark and the words, which open the sheet, and Undo at its
/// end while there is a save to take back.
class _MemoryChip extends StatelessWidget {
  const _MemoryChip({
    required this.icon,
    required this.words,
    required this.onOpen,
    this.onUndo,
  });

  final IconData icon;
  final String words;
  final VoidCallback onOpen;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final undo = RendelStringsScope.of(context).memoryUndo;
    // The thumbs' own ink and size, beside which these sit.
    final faint = theme.colors.onSurface.withValues(alpha: 0.55);
    return Row(
      children: [
        Flexible(
          child: RendelPressable(
            semanticLabel: words,
            onTap: onOpen,
            pressedScale: 0.98,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: faint),
                  SizedBox(width: theme.space.xs + theme.space.hair),
                  Flexible(
                    child: Text(words, style: theme.text.body.copyWith(fontSize: 13, color: faint)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onUndo != null) ...[
          SizedBox(width: theme.space.sm),
          RendelPressable(
            semanticLabel: undo,
            onTap: onUndo,
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: theme.space.xs),
                child: Text(undo, style: theme.text.labelEmphasis.copyWith(fontSize: 13)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
