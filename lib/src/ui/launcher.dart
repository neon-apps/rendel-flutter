import 'package:flutter/material.dart';

import '../core/copilot.dart';
import 'renderer/blocks.dart' show RendelPressable;
import 'theme.dart';

/// The entry point button. You place it: a `floatingActionButton`, a row in a
/// settings list, anywhere the affordance belongs in your own layout. The SDK
/// positions nothing of its own but the bubble it shrinks into while a screen
/// it opened is in front, and pressing this then brings the copilot back
/// from it.
///
/// It presses like every other control in the SDK, because it is the same
/// control: an [RendelPressable], not a Material ripple.
///
/// It carries its word and nothing else. It used to lead with the turn mark,
/// which is withdrawn; a bolt is what every
/// actually does.
class RendelLauncher extends StatelessWidget {
  const RendelLauncher({super.key, this.label});

  /// Overrides both the code config's `launcherLabel` and anything the console
  /// published. Pass it only when this particular placement needs a different
  /// word from the rest of the app.
  final String? label;

  @override
  Widget build(BuildContext context) {
    // Rebuilds when a published config lands, so a kill switch or a renamed
    // launcher takes effect without a relaunch. The notifier ticks at most
    // once per fetch, so this costs nothing per frame.
    return ValueListenableBuilder<int>(
      valueListenable: Rendel.configRevision,
      builder: (context, _, __) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    // The launcher lives in the HOST's tree, outside the sheet that carries
    // the RendelThemeScope — so `of(context)` here always hit the scope's
    // paper() fallback, and a custom `fromTokens` brand or a
    // console-published palette never reached the one control that is always
    // on screen. The two shipped presets used to share an accent, which is
    // why every internal demo looked fine. Scope first (a host may wrap its own), then
    // the live static theme.
    final theme =
        context.dependOnInheritedWidgetOfExactType<RendelThemeScope>()?.theme ??
            Rendel.themeOf(context);
    // Nothing at all when the copilot is off: an affordance that opens a sheet
    // the SDK will refuse to present is worse than no affordance.
    if (!Rendel.isInitialized || !Rendel.isEnabled) {
      return const SizedBox.shrink();
    }
    final word = label ?? Rendel.config.launcherLabel;
    return RendelPressable(
      semanticLabel: Rendel.strings.openCopilot,
      onTap: () => Rendel.open(context),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: theme.space.xl,
          vertical: theme.space.md,
        ),
        decoration: BoxDecoration(
          color: theme.colors.accent,
          borderRadius: BorderRadius.circular(theme.radius.control),
          // The one control in the product that is always on screen is the
          // one that earns the deepest elevation. `accentEdge` is the
          // boundary WCAG 1.4.11 asks 3:1 of, which a host's raw accent often
          // does not clear against its own ground.
          border: Border.all(color: theme.accentEdge),
          boxShadow: theme.lift,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(word, style: theme.text.labelStrong),
          ],
        ),
      ),
    );
  }
}
