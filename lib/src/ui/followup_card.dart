import 'package:flutter/material.dart';

import '../core/followups.dart';
import 'renderer/blocks.dart' show RendelPressable;
import 'theme.dart';

/// A follow-up as the SDK draws it: over the launcher while the thread is
/// closed, at the top of the thread once it is open. Its title, body and
/// button are the server's words; the cross is the only control of its own.
class RendelFollowupCard extends StatelessWidget {
  const RendelFollowupCard({
    super.key,
    required this.followup,
    required this.theme,
    required this.closeLabel,
    required this.onOpen,
    required this.onDismiss,
    this.raised = false,
  });

  final RendelFollowup followup;
  final RendelTheme theme;
  final String closeLabel;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  /// Floating over the app rather than inside the thread: it carries the
  /// launcher's elevation.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final space = theme.space;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: EdgeInsetsDirectional.fromSTEB(space.lg, space.md, space.sm, space.lg),
        decoration: BoxDecoration(
          color: theme.colors.surfaceRaised,
          borderRadius: BorderRadius.circular(theme.radius.card),
          border: Border.all(color: theme.colors.line),
          boxShadow: raised ? theme.lift : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: space.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(followup.title, style: theme.text.labelStrong),
                        SizedBox(height: space.xs),
                        Text(followup.body, style: theme.text.labelSoft),
                      ],
                    ),
                  ),
                ),
                RendelPressable(
                  semanticLabel: closeLabel,
                  onTap: onDismiss,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.close_rounded, size: 18, color: theme.colors.onSurfaceSoft),
                  ),
                ),
              ],
            ),
            SizedBox(height: space.sm),
            RendelPressable(
              semanticLabel: followup.button,
              onTap: onOpen,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: EdgeInsets.symmetric(horizontal: space.lg),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colors.accent,
                  borderRadius: BorderRadius.circular(theme.radius.control),
                ),
                child: Text(followup.button, style: theme.text.labelStrong.copyWith(color: theme.colors.onAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
