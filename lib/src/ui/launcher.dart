import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copilot.dart';
import '../core/events.dart';
import '../core/followups.dart';
import 'followup_card.dart';
import 'renderer/blocks.dart' show RendelPressable;
import 'theme.dart';

/// The entry point button. You place it: a `floatingActionButton`, a row in a
/// settings list, anywhere the affordance belongs in your own layout. The SDK
/// positions nothing of its own but the bubble it shrinks into while a screen
/// it opened is in front; this hides itself while the bubble is up, so one
/// way in is on screen. A button of your own should do the same, listening
/// to [Rendel.minimised].
///
/// It presses like every other control in the SDK, because it is the same
/// control: an [RendelPressable], not a Material ripple.
///
/// It carries its word and nothing else. It used to lead with the turn mark,
/// which is withdrawn; a bolt is what every
/// actually does.
///
/// A follow-up waiting for this person (`Rendel.followup`) shows over it,
/// anchored to it in the app's overlay, while the thread is closed.
class RendelLauncher extends StatefulWidget {
  const RendelLauncher({super.key, this.label});

  /// Overrides both the code config's `launcherLabel` and anything the console
  /// published. Pass it only when this particular placement needs a different
  /// word from the rest of the app.
  final String? label;

  @override
  State<RendelLauncher> createState() => _RendelLauncherState();
}

class _RendelLauncherState extends State<RendelLauncher> {
  final _link = LayerLink();
  OverlayEntry? _popup;
  StreamSubscription<RendelEvent>? _events;

  @override
  void initState() {
    super.initState();
    RendelFollowups.instance.current.addListener(_schedule);
    Rendel.minimised.addListener(_schedule);
    Rendel.configRevision.addListener(_schedule);
    _events = Rendel.events.listen((_) => _schedule());
    _schedule();
  }

  @override
  void dispose() {
    RendelFollowups.instance.current.removeListener(_schedule);
    Rendel.minimised.removeListener(_schedule);
    Rendel.configRevision.removeListener(_schedule);
    _events?.cancel();
    _popup?.remove();
    _popup = null;
    super.dispose();
  }

  /// After the frame: an overlay is not changed while the tree builds.
  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

  /// The popup is up while a follow-up waits and the thread is closed.
  void _sync() {
    if (!mounted) return;
    final show = RendelFollowups.instance.current.value != null &&
        Rendel.isInitialized &&
        Rendel.isEnabled &&
        !Rendel.isOpen &&
        !Rendel.minimised.value;
    if (!show) {
      _popup?.remove();
      _popup = null;
      return;
    }
    if (_popup == null) {
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) return;
      overlay.insert(_popup = OverlayEntry(builder: _buildPopup));
    } else {
      _popup!.markNeedsBuild();
    }
    RendelFollowups.instance.shown();
  }

  Widget _buildPopup(BuildContext overlayContext) {
    final waiting = RendelFollowups.instance.current.value;
    if (waiting == null || !mounted) return const SizedBox.shrink();
    final theme = context.dependOnInheritedWidgetOfExactType<RendelThemeScope>()?.theme ?? Rendel.themeOf(context);
    // Over the launcher, opening toward the screen: from its right edge in a
    // left-to-right app, from its left in a right-to-left one.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final width = (MediaQuery.sizeOf(overlayContext).width - 2 * theme.space.lg).clamp(0.0, 320.0);
    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: rtl ? Alignment.topLeft : Alignment.topRight,
        followerAnchor: rtl ? Alignment.bottomLeft : Alignment.bottomRight,
        offset: Offset(0, -theme.space.md),
        child: Material(
          type: MaterialType.transparency,
          child: RendelFollowupCard(
            followup: waiting,
            theme: theme,
            raised: true,
            closeLabel: Rendel.strings.closeDetail,
            onOpen: () => unawaited(Rendel.openFollowup(context)),
            onDismiss: Rendel.dismissFollowup,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(link: _link, child: _launcher(context));

  Widget _launcher(BuildContext context) {
    // Rebuilds when a published config lands, so a kill switch or a renamed
    // launcher takes effect without a relaunch. The notifier ticks at most
    // once per fetch, so this costs nothing per frame.
    return ValueListenableBuilder<int>(
      valueListenable: Rendel.configRevision,
      // Hidden while the bubble is up: it is the way back then, and one way
      // in is all a screen shows (Tuna, 2026-10-13).
      builder: (context, _, __) => ValueListenableBuilder<bool>(
        valueListenable: Rendel.minimised,
        builder: (context, minimised, _) => minimised ? const SizedBox.shrink() : _build(context),
      ),
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
    final word = widget.label ?? Rendel.config.launcherLabel;
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
