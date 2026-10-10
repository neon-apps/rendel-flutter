import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart' show RendelAttachment, RendelAttachSource;
import 'log.dart';
import 'platform.dart';
import 'remote_config.dart' show RendelConfigStore;

/// What the composer's two controls do when the host wires nothing.
///
/// Until 0.12 the SDK shipped no picker and no recogniser, and neither
/// control was drawn until the host supplied one. The reasoning was sound —
/// no forced plugin, no version conflict, the app's own permission prompt —
/// and the cost was 150 lines copied into every host, carrying every
/// subtlety a microphone has. The first real integration copied them
/// wrongly, and the microphone read as broken for a day. A copilot that has
/// to be assembled is not the product; one that works the moment the
/// dependency is in is.
///
/// So these are the defaults. `RendelConfig.onPickAttachment` and
/// `RendelConfig.onDictate` still replace them, for an app that has a picker its
/// users already know; `RendelAttachIcon.off` and `RendelVoiceIcon.off` remove the
/// controls altogether.

/// Thrown by a dictation when the person refused the microphone or speech
/// recognition. The thread then says where to allow it, with a button to the
/// app's settings, rather than that recognition is unavailable. A host's own
/// `RendelConfig.onDictate` may throw it too.
class RendelDictationDenied implements Exception {
  const RendelDictationDenied();

  @override
  String toString() => 'RendelDictationDenied: microphone or speech recognition permission refused';
}

/// The SDK's own recogniser: `speech_to_text`, on the device.
///
/// One instance per thread. A session can end four ways — a final result, a
/// pause, an error, or [stop] — and only one of them delivers a result, so
/// every ending goes through one place, and that place knows which it was.
class RendelSpeech {
  RendelSpeech({this.locale});

  /// The language to listen for, when the device carries a model for it.
  /// Null, or a language the device does not have, listens in the device's
  /// own — half-right beats a session that fails the instant it starts.
  final String? locale;

  final _speech = SpeechToText();

  /// How loud the speaker is, 0 to 1, while a session listens. Voice mode's
  /// glow swells with it. Scaled against the quietest and loudest levels this
  /// session has reported, because the platforms report on different scales.
  final level = ValueNotifier<double>(0);

  /// True once a session is actually listening. The first press asks for the
  /// permissions, and the thread waits for this before it says "Listening",
  /// which it otherwise said behind the system's own prompt.
  final started = ValueNotifier<bool>(false);
  double? _quietest;
  double? _loudest;

  Completer<String?>? _dictation;
  var _heard = '';
  SpeechRecognitionError? _failure;

  /// Whether a session has actually begun. `onStatus` can report
  /// `notListening` before `listen` is ever called; without this the dictation
  /// closed the instant it opened.
  var _listening = false;

  /// The errors that mean nobody spoke, rather than that nothing could listen.
  static const _silence = {'error_no_match', 'error_speech_timeout', 'error_retry'};

  /// The errors that mean the person said no to a permission.
  static const _refused = {'error_permission', 'error_insufficient_permissions'};

  /// `RendelConfig.onDictate`, built in.
  Future<String?> dictate(void Function(String partial) onPartial) async {
    final bool ready;
    try {
      // The callbacks are set on the first `initialize` and kept.
      ready = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            /* One turn of the event loop late, on purpose.

               A recogniser that fails reports its ending first and its error
               second — on iOS, `done`, the error, then `done` again. Ending on
               the first `done` completed the future with null, the thread said
               nothing was heard, and the error that would have explained it
               arrived to a dictation already closed. */
            Future<void>.delayed(Duration.zero, _end);
          }
        },
        onError: (error) {
          _failure = error;
          _end();
        },
      );
    } catch (err) {
      // Nothing behind the channel: a platform the plugin does not build for,
      // or a test. The thread says recognition is unavailable, and logs this.
      throw StateError('speech_to_text is not available here: $err');
    }
    // False is a refused permission or a device with no recogniser — not
    // silence, so not null.
    if (!ready) {
      var refused = false;
      try {
        refused = !await _speech.hasPermission;
      } catch (_) {
        // A platform that cannot say: treated as unavailable, as before.
      }
      if (refused) throw const RendelDictationDenied();
      throw StateError('speech recognition is unavailable');
    }

    /* A session that has not finished letting go.

       iOS takes a moment to release the audio session, and `listen` during
       that window quietly does not start. That is why a microphone worked for
       the first few presses and then stopped. */
    if (_speech.isListening) {
      await _speech.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    _heard = '';
    _failure = null;
    _quietest = null;
    _loudest = null;
    level.value = 0;
    final completer = Completer<String?>();
    _dictation = completer;
    _listening = true;

    try {
      await _speech.listen(
        onResult: (result) {
          _heard = result.recognizedWords;
          // Straight through, so the words appear while they are being said.
          onPartial(_heard);
          if (result.finalResult) _end();
        },
        onSoundLevelChange: _heardLevel,
        listenOptions: SpeechListenOptions(
          localeId: await _availableLocale(locale),
          partialResults: true,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      _listening = false;
      _dictation = null;
      rethrow;
    }

    // And if it did not start after all, say so now rather than leaving a lit
    // microphone attached to a future nobody will complete.
    if (!_speech.isListening) {
      _end();
    } else {
      started.value = true;
    }

    return completer.future;
  }

  void _heardLevel(double raw) {
    final quietest = _quietest = math.min(_quietest ?? raw, raw);
    final loudest = _loudest = math.max(_loudest ?? raw, raw);
    level.value = loudest - quietest < 1 ? 0 : (raw - quietest) / (loudest - quietest);
  }

  /// `RendelConfig.onStopDictating`, built in. Stopping fires `onStatus`, which
  /// completes the future [dictate] returned.
  void stop() => unawaited(_speech.stop());

  void _end() {
    if (!_listening) return;
    _listening = false;
    level.value = 0;
    started.value = false;
    final pending = _dictation;
    final failure = _failure;
    _dictation = null;
    _failure = null;
    if (pending == null || pending.isCompleted) return;
    final text = _heard.trim();
    if (text.isEmpty && failure != null && _refused.contains(failure.errorMsg)) {
      pending.completeError(const RendelDictationDenied());
      return;
    }
    if (text.isEmpty && failure != null && !_silence.contains(failure.errorMsg)) {
      // Nothing heard because nothing could listen. The thread says so, and
      // logs the message, instead of sending somebody to check the microphone.
      pending.completeError(StateError(failure.errorMsg));
      return;
    }
    pending.complete(text.isEmpty ? null : text);
  }

  /// The requested language when the device carries it, and null — the
  /// device's own — when it does not. Forcing a locale with no model behind
  /// it fails the session with a permanent error the instant it starts.
  Future<String?> _availableLocale(String? wanted) async {
    if (wanted == null) return null;
    final target = wanted.toLowerCase().replaceAll('-', '_');
    final language = target.split('_').first;
    final locales = await _speech.locales();
    for (final l in locales) {
      if (l.localeId.toLowerCase().replaceAll('-', '_') == target) return l.localeId;
    }
    for (final l in locales) {
      if (l.localeId.toLowerCase().startsWith(language)) return l.localeId;
    }
    return null;
  }
}

/// The SDK's own way to open a link: `url_launcher`, in an in-app browser.
///
/// `RendelConfig.onOpenUrl`, built in. Until 0.20 there was no default, and a
/// card's "Go to the product" button did nothing in an app that had followed
/// the quickstart to the letter — the handler was mentioned only in the
/// reference. That is the same lesson the picker and the microphone taught:
/// a copilot that has to be assembled is not the product.
///
/// In-app rather than out to Safari or Chrome, so closing the page puts the
/// user back in the conversation they were having. A device with no in-app
/// browser gets the external one. https only, which the protocol already
/// guarantees; anything else is refused here as well.
Future<void> openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  try {
    if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (err) {
    // A tap that cannot be honoured is not a crash in somebody else's app.
    RendelLog.warn('open_url_failed', 'the link could not be opened', error: err);
  }
}

/// Hands [url] to the operating system, for an `open_url` marked `external`:
/// a maps link opens the maps app, a wallet link the wallet. Reports whether
/// anything opened.
///
/// Not [openLink]: an in-app browser would show the maps website inside the
/// copilot, which is the one thing a directions button must not do. Not the
/// host's `onOpenUrl` either, which opens pages; this opens apps. https only,
/// as every link on the wire is.
Future<bool> openExternally(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (err) {
    RendelLog.warn('open_external_failed', 'the link could not be handed to the system', error: err);
    return false;
  }
}

/// Opens this app's page in the iOS Settings app, where a refused microphone
/// is allowed again. iOS only: Android has no URL for it that `url_launcher`
/// can open, so the thread offers the button on iOS alone.
Future<bool> openAppSettings() async {
  try {
    return await launchUrl(Uri.parse('app-settings:'), mode: LaunchMode.externalApplication);
  } catch (err) {
    RendelLog.warn('settings_failed', 'the app settings could not be opened', error: err);
    return false;
  }
}

/// Opens the dialler with [phone] filled in, for a `call` button. Reports
/// whether anything opened.
///
/// A `tel:` URI handed to the platform, not [openLink], which opens https
/// alone. And without asking `canLaunchUrl` first: on Android 11 and later
/// that answers no for any scheme the app's manifest does not list under
/// `<queries>`, which would make a working dialler look missing, while the
/// launch itself needs no such line. Separators are dropped because they are
/// for the eye, and a dialler that is handed `%20` has been handed a worse
/// number.
Future<bool> dial(String phone) async {
  final number = phone.replaceAll(RegExp(r'[\s().\-]'), '');
  if (number.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: 'tel', path: number), mode: LaunchMode.externalApplication);
  } catch (err) {
    RendelLog.warn('call_failed', 'the dialler could not be opened', error: err);
    return false;
  }
}

/// Opens the mail app with a message to [address], for a `contact` block's
/// email channel. Reports whether anything opened.
///
/// A `mailto:` URI handed to the platform, as [dial] hands it `tel:`, and for
/// the same reason without asking `canLaunchUrl` first. Nothing is written
/// into the message and nothing is sent: the user does both.
Future<bool> mail(String address) async {
  final to = address.trim();
  if (to.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: 'mailto', path: to), mode: LaunchMode.externalApplication);
  } catch (err) {
    RendelLog.warn('mail_failed', 'the mail app could not be opened', error: err);
    return false;
  }
}

/// The SDK's own pickers: the "+" menu's Photos, Camera and Files.
///
/// `RendelConfig.onPickAttachment`, built in. Until 0.23 it was Photos alone — a
/// copilot is asked about a photograph far more often than about a document,
/// and the picker that reaches documents was a second plugin on every host.
/// Files is the SDK's own native code now, and Camera is the same plugin
/// Photos already was, so all three come with the dependency.
Future<RendelAttachment?> pickFrom(RendelAttachSource source) => switch (source) {
      RendelAttachSource.photos => pickImage(),
      RendelAttachSource.camera => takePhoto(),
      RendelAttachSource.files => pickFile(),
    };

/// Photos: `image_picker`, from the photo library.
Future<RendelAttachment?> pickImage() async {
  final XFile? file;
  try {
    // Without the full metadata — EXIF the model never sees — the picker
    // needs no photo-library permission on iOS, so the host's Info.plist
    // needs no line for Photos. With it, iOS asks for the library and
    // closes an app that has no NSPhotoLibraryUsageDescription.
    file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
  } catch (err) {
    // Nothing behind the channel. The thread says the file could not be
    // attached, and logs this.
    throw StateError('image_picker is not available here: $err');
  }
  return file == null ? null : _attachmentOf(file);
}

/// Camera: `image_picker`, from the camera. The photograph is attached the
/// moment it is taken; there is no second step.
///
/// The system asks for the camera the first time, in the words of the
/// host's `NSCameraUsageDescription`. The thread does not offer Camera at all
/// without that line (`RendelPlatform.cameraReady`), because iOS closes the app.
Future<RendelAttachment?> takePhoto() async {
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      // A phone's full sensor is 12 to 48 megapixels; the model reads a
      // receipt or a rash as well at 2048, and the upload is a tenth of it.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
      requestFullMetadata: false,
    );
  } catch (err) {
    // A refused camera lands here too: image_picker throws `camera_access_denied`.
    throw StateError('the camera could not be opened: $err');
  }
  return file == null ? null : _attachmentOf(file);
}

/// Files: the system's document picker — a PDF, a text file or a picture.
Future<RendelAttachment?> pickFile() async {
  final ({String name, String? type, Uint8List bytes})? file;
  try {
    file = await RendelPlatform.pickDocument();
  } catch (err) {
    throw StateError('the document picker could not be opened: $err');
  }
  if (file == null) return null;
  return RendelAttachment(
    bytes: file.bytes,
    name: file.name,
    mediaType:
        _mediaTypeOf(file.name) ?? file.type ?? 'application/octet-stream',
  );
}

Future<RendelAttachment> _attachmentOf(XFile file) async {
  // By name, not by `mimeType`: on iOS the latter is null more often than
  // not, and a wrong type confuses the model rather than the upload. The
  // plugin keeps PNG and GIF as they are and writes everything else as JPEG.
  return RendelAttachment(
    bytes: await file.readAsBytes(),
    name: file.name,
    mediaType: _mediaTypeOf(file.name) ?? 'image/jpeg',
  );
}

String? _mediaTypeOf(String name) =>
    switch (name.split('.').last.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'jpg' || 'jpeg' => 'image/jpeg',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      _ => null,
    };

/// The SDK's own storage for the two strings it has to keep between launches:
/// the install's anonymous device id, and the published config it paints
/// from before the network answers.
///
/// Neither was kept by default. The recipe was in `RendelConfig`'s documentation,
/// three lines on `shared_preferences`, and nobody wrote it — so every cold
/// start was a new device: the console's Users page filled with one row per
/// launch of the same phone, per-device rate limits reset each time, and the
/// memory the copilot kept about a person was attached to an id that never
/// came back. The preferences plugin is here now, and both stores default to
/// it. `RendelConfig.deviceIdStore` and `configStore` still replace them.
class RendelPreferencesStore implements RendelConfigStore {
  const RendelPreferencesStore(this.key);

  /// The preferences key. One per stored string; the two must differ.
  final String key;

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}
