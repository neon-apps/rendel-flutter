/// Rendel — an AI copilot that operates your app.
library;

// Every name this library had before 0.32.0, kept working for now.
export 'src/deprecated.dart';

export 'src/core/action.dart'
    show RendelAction, RendelFullText, RendelInvocation, RendelInvocationHandler, RendelHandler, RendelResult, RendelRisk;
export 'src/core/log.dart' show RendelLog, RendelLogLevel, RendelLogRecord;
export 'src/core/route.dart' show RendelRouteParam, RendelRouteOpener;
export 'src/core/config.dart'
    show RendelConfig, RendelAttachIcon, RendelAttachment, RendelAttachSource, RendelVoiceIcon, RendelSendIcon, RendelThemeMode;
export 'src/core/strings.dart' show RendelStrings, RendelStringsScope;
// Runtime appearance and opening surface: what the console publishes and how
// a host decides where the last good payload is kept between launches.
export 'src/core/remote_config.dart'
    show RendelConfigStore, RendelMemoryConfigStore, RendelRemoteConfig;
export 'src/core/batteries.dart' show RendelDictationDenied;
export 'src/core/copilot.dart' show Rendel;
export 'src/core/pairing.dart' show RendelPairResult, RendelPairFailure;
export 'src/core/events.dart' show RendelEvent;
export 'src/core/followups.dart' show RendelFollowup;
export 'src/core/schema.dart' show RendelSchema;
// Part of RendelDispatcher's signature, so a host registering a custom
// builder has to be able to name it.
export 'src/engine/conversation_controller.dart' show RendelSubmitOutcome, NcSubmitOutcome;
export 'src/protocol/protocol.dart'
    show
        RendelLocalKeys,
        WireBlock,
        UIAction,
        ReplyAction,
        AppActionRef,
        ConfirmAction,
        CancelAction,
        OpenUrlAction,
        NavigateAction,
        CallAction,
        EmailAction,
        CopyAction,
        AddToCalendarAction;
// What RendelDispatcher.onUpload throws, so a host can catch it by type.
export 'src/transport/api_client.dart' show RendelUploadFailure;
export 'src/ui/launcher.dart' show RendelLauncher;
// The registry and what a builder receives, so a host can put a widget of
// its own in the catalog's place.
export 'src/ui/renderer/registry.dart'
    show ComponentRegistry, ComponentBuilder, RendelDispatcher;
// The catalog's own primitives, so a host-registered component presses,
// encloses and breathes like the built-ins rather than like Material.
export 'src/ui/renderer/blocks.dart'
    show
        // Exported so `info-card.mdx` and the model-facing catalog
        // description can be checked against the map rather than copied
        // from it by hand.
        infoCardIconNames,
        RendelActionButton,

        RendelChip,
        RendelControlShell,
        RendelOverline,
        RendelPressable,
        RendelPulse,
        RendelSwap;
export 'src/ui/theme.dart'
    show
        RendelTheme,
        RendelThemeScope,
        RendelColors,
        RendelRadiusScale,
        RendelSpaceScale,
        RendelTextStyles,
        RendelTypeScale,
        RendelSizeScale,
        RendelMotionScale,
        RendelElevationScale,
        RendelShadowSpec,
        RendelStyle,
        RendelCardStyle,
        RendelCardLook,
        RendelPartLook,
        RendelButtonStyle,
        RendelProductStyle,
        RendelTrackerStyle,
        RendelArrowStyle,
        RendelBackdrop,
        rendelEase,
        contrastRatio,
        auditContrast;
