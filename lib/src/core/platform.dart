import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log.dart';

/// What the host app's own platform files are missing, for the controls that
/// need them — and the Files app, which the SDK opens itself.
///
/// The microphone and the camera need something, and only on iOS: Photos and
/// Files open pickers that need no permission, and Android's permissions ship
/// in the SDK's manifest. iOS terminates an app that touches the microphone
/// or the camera without its usage strings — the host's first sight of a
/// missing line used to be their app closing — and no package can add them.
/// So the SDK looks, and draws no control rather than one that kills the app.
class RendelPlatform {
  RendelPlatform._();

  static const _channel = MethodChannel('rendel/platform');

  /// The voice's hold on the audio: on while an answer is read aloud (other
  /// sound ducked under it, heard with the silent switch on), let go after so
  /// the sound it ducked comes back up. Nothing where there is no native half.
  static Future<void> voiceSession(bool active) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('voiceSession', active);
    } on MissingPluginException {
      // A test, or a host on a build of the native half from before it.
    } on PlatformException catch (err) {
      RendelLog.warn('voice_session_failed', 'the audio session did not ${active ? 'start' : 'stop'}: ${err.message}');
    }
  }

  /// The lines the built-in microphone needs in `ios/Runner/Info.plist`.
  static const microphoneUsageKeys = [
    'NSMicrophoneUsageDescription',
    'NSSpeechRecognitionUsageDescription',
  ];

  /// The line the composer's Camera needs in `ios/Runner/Info.plist`.
  static const cameraUsageKeys = ['NSCameraUsageDescription'];

  static Future<bool>? _microphone;
  static Future<bool>? _camera;

  /// Whether the built-in microphone may be drawn. Asked once per process;
  /// Info.plist does not change while the app runs.
  static Future<bool> microphoneReady() =>
      _microphone ??= _check(microphoneUsageKeys, 'the microphone');

  /// Whether the composer may offer Camera. Asked once per process, like the
  /// microphone.
  static Future<bool> cameraReady() =>
      _camera ??= _check(cameraUsageKeys, 'the camera');

  static Future<bool> _check(List<String> keys, String control) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return true;
    try {
      final missing = await _channel.invokeListMethod<String>(
            'missingUsageDescriptions',
            keys,
          ) ??
          const <String>[];
      if (missing.isEmpty) return true;
      final them = missing.length > 1 ? 'them' : 'it';
      RendelLog.warn(
        'usage_description_missing',
        '$control is hidden: ios/Runner/Info.plist has no '
            '${missing.join(' or ')}. iOS closes an app that uses '
            '$control without $them. Add $them in your own words and rebuild.',
      );
      return false;
    } on MissingPluginException {
      // No native half behind the channel — a test, or a build from before
      // the plugin was added that has only been hot-restarted since. Nothing
      // is known to be missing.
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// The system's document picker: one PDF, text file or picture. Null when
  /// somebody closed it without choosing.
  ///
  /// The SDK's own native code rather than a picker package; see
  /// `RendelPlugin.swift` for why.
  static Future<({String name, String? type, Uint8List bytes})?>
      pickDocument() async {
    final file =
        await _channel.invokeMapMethod<String, Object?>('pickDocument');
    if (file == null) return null;
    return (
      name: file['name'] as String,
      type: file['type'] as String?,
      bytes: file['bytes'] as Uint8List,
    );
  }

  /// The device's own event editor, filled in, for an `add_to_calendar`
  /// button: the user saves it, or does not. True once the editor is up.
  ///
  /// The SDK's own native code again (`RendelPlugin`): Android's insert
  /// intent, and iOS's `EKEventEditViewController` from iOS 17, work without
  /// a calendar permission, where a calendar package asks for one to write
  /// the event itself. Before iOS 17 the editor needs the host's
  /// `NSCalendarsUsageDescription`, and without it this is false rather than
  /// a closed app. A missing end is left to the editor's own default.
  static Future<bool> addToCalendar({
    required String title,
    required DateTime startsAt,
    DateTime? endsAt,
    String? location,
    String? notes,
  }) async {
    try {
      final opened = await _channel.invokeMethod<bool>('addToCalendar', {
        'title': title,
        'starts_at': startsAt.millisecondsSinceEpoch,
        if (endsAt != null) 'ends_at': endsAt.millisecondsSinceEpoch,
        if (location != null) 'location': location,
        if (notes != null) 'notes': notes,
      });
      return opened ?? false;
    } on MissingPluginException {
      // No native half: a test, or a platform the plugin has no code for.
      return false;
    } on PlatformException catch (err) {
      RendelLog.warn('calendar_failed', 'the event editor could not be opened', error: err);
      return false;
    }
  }

  /// Forgets the answers. For `Rendel.resetForTest`, which is the one
  /// place a process pretends to start again.
  static void resetForTest() {
    _microphone = null;
    _camera = null;
  }
}
