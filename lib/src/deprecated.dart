// The names from before 0.32.0, when the SDK was neon_copilot. Each one is
// the new type under its old name, so code written against 0.31 compiles
// with only its import changed, and the analyzer points at every line still
// to rename. They go at 1.0.
library;

import 'package:flutter/animation.dart';

import '../rendel.dart';

@Deprecated('Use RendelAction. Renamed in 0.32.0.')
typedef NCAction = RendelAction;
@Deprecated('Use RendelInvocation. Renamed in 0.32.0.')
typedef NCInvocation = RendelInvocation;
@Deprecated('Use RendelInvocationHandler. Renamed in 0.32.0.')
typedef NCInvocationHandler = RendelInvocationHandler;
@Deprecated('Use RendelHandler. Renamed in 0.32.0.')
typedef NCHandler = RendelHandler;
@Deprecated('Use RendelResult. Renamed in 0.32.0.')
typedef NCResult = RendelResult;
@Deprecated('Use RendelRisk. Renamed in 0.32.0.')
typedef NCRisk = RendelRisk;
@Deprecated('Use RendelLog. Renamed in 0.32.0.')
typedef NCLog = RendelLog;
@Deprecated('Use RendelLogLevel. Renamed in 0.32.0.')
typedef NCLogLevel = RendelLogLevel;
@Deprecated('Use RendelLogRecord. Renamed in 0.32.0.')
typedef NCLogRecord = RendelLogRecord;
@Deprecated('Use RendelConfig. Renamed in 0.32.0.')
typedef NCConfig = RendelConfig;
@Deprecated('Use RendelAttachIcon. Renamed in 0.32.0.')
typedef NCAttachIcon = RendelAttachIcon;
@Deprecated('Use RendelAttachment. Renamed in 0.32.0.')
typedef NCAttachment = RendelAttachment;
@Deprecated('Use RendelAttachSource. Renamed in 0.32.0.')
typedef NCAttachSource = RendelAttachSource;
@Deprecated('Use RendelVoiceIcon. Renamed in 0.32.0.')
typedef NCVoiceIcon = RendelVoiceIcon;
@Deprecated('Use RendelSendIcon. Renamed in 0.32.0.')
typedef NCSendIcon = RendelSendIcon;
@Deprecated('Use RendelStrings. Renamed in 0.32.0.')
typedef NCStrings = RendelStrings;
@Deprecated('Use RendelStringsScope. Renamed in 0.32.0.')
typedef CopilotStringsScope = RendelStringsScope;
@Deprecated('Use RendelConfigStore. Renamed in 0.32.0.')
typedef NCConfigStore = RendelConfigStore;
@Deprecated('Use RendelMemoryConfigStore. Renamed in 0.32.0.')
typedef NCMemoryConfigStore = RendelMemoryConfigStore;
@Deprecated('Use RendelRemoteConfig. Renamed in 0.32.0.')
typedef NCRemoteConfig = RendelRemoteConfig;
@Deprecated('Use Rendel. Renamed in 0.32.0.')
typedef NeonCopilot = Rendel;
@Deprecated('Use RendelPairResult. Renamed in 0.32.0.')
typedef NCPairResult = RendelPairResult;
@Deprecated('Use RendelPairFailure. Renamed in 0.32.0.')
typedef NCPairFailure = RendelPairFailure;
@Deprecated('Use RendelEvent. Renamed in 0.32.0.')
typedef CopilotEvent = RendelEvent;
@Deprecated('Use RendelSchema. Renamed in 0.32.0.')
typedef NCSchema = RendelSchema;
@Deprecated('Use RendelSubmitOutcome. Renamed in 0.32.0.')
typedef NCSubmitOutcome = RendelSubmitOutcome;
@Deprecated('Use RendelLocalKeys. Renamed in 0.32.0.')
typedef NCLocalKeys = RendelLocalKeys;
@Deprecated('Use RendelLauncher. Renamed in 0.32.0.')
typedef CopilotLauncher = RendelLauncher;
@Deprecated('Use RendelDispatcher. Renamed in 0.32.0.')
typedef CopilotDispatcher = RendelDispatcher;
@Deprecated('Use RendelActionButton. Renamed in 0.32.0.')
typedef NCActionButton = RendelActionButton;
@Deprecated('Use RendelChip. Renamed in 0.32.0.')
typedef NCChip = RendelChip;
@Deprecated('Use RendelControlShell. Renamed in 0.32.0.')
typedef NCControlShell = RendelControlShell;
@Deprecated('Use RendelOverline. Renamed in 0.32.0.')
typedef NCOverline = RendelOverline;
@Deprecated('Use RendelPressable. Renamed in 0.32.0.')
typedef NCPressable = RendelPressable;
@Deprecated('Use RendelPulse. Renamed in 0.32.0.')
typedef NCPulse = RendelPulse;
@Deprecated('Use RendelSwap. Renamed in 0.32.0.')
typedef NCSwap = RendelSwap;
@Deprecated('Use RendelTheme. Renamed in 0.32.0.')
typedef CopilotTheme = RendelTheme;
@Deprecated('Use RendelThemeScope. Renamed in 0.32.0.')
typedef CopilotThemeScope = RendelThemeScope;
@Deprecated('Use RendelColors. Renamed in 0.32.0.')
typedef NCColors = RendelColors;
@Deprecated('Use RendelRadiusScale. Renamed in 0.32.0.')
typedef NCRadiusScale = RendelRadiusScale;
@Deprecated('Use RendelSpaceScale. Renamed in 0.32.0.')
typedef NCSpaceScale = RendelSpaceScale;
@Deprecated('Use RendelTextStyles. Renamed in 0.32.0.')
typedef NCTextStyles = RendelTextStyles;
@Deprecated('Use RendelTypeScale. Renamed in 0.32.0.')
typedef NCTypeScale = RendelTypeScale;
@Deprecated('Use RendelSizeScale. Renamed in 0.32.0.')
typedef NCSizeScale = RendelSizeScale;
@Deprecated('Use RendelMotionScale. Renamed in 0.32.0.')
typedef NCMotionScale = RendelMotionScale;
@Deprecated('Use RendelElevationScale. Renamed in 0.32.0.')
typedef NCElevationScale = RendelElevationScale;
@Deprecated('Use RendelShadowSpec. Renamed in 0.32.0.')
typedef NCShadowSpec = RendelShadowSpec;
@Deprecated('Use RendelStyle. Renamed in 0.32.0.')
typedef NCStyle = RendelStyle;
@Deprecated('Use RendelCardStyle. Renamed in 0.32.0.')
typedef NCCardStyle = RendelCardStyle;
@Deprecated('Use RendelCardLook. Renamed in 0.32.0.')
typedef NCCardLook = RendelCardLook;
@Deprecated('Use RendelPartLook. Renamed in 0.32.0.')
typedef NCPartLook = RendelPartLook;
@Deprecated('Use RendelButtonStyle. Renamed in 0.32.0.')
typedef NCButtonStyle = RendelButtonStyle;
@Deprecated('Use RendelProductStyle. Renamed in 0.32.0.')
typedef NCProductStyle = RendelProductStyle;
@Deprecated('Use RendelTrackerStyle. Renamed in 0.32.0.')
typedef NCTrackerStyle = RendelTrackerStyle;

@Deprecated('Use rendelEase. Renamed in 0.32.0.')
const Curve ncEase = rendelEase;
