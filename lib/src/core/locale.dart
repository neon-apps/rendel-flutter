import 'dart:ui';

/// The language tag this run speaks, from the two things that can say.
///
/// The host's own wins. An app with a language picker knows what its user
/// chose and the phone does not: a device set to English running a Turkish app
/// should not make the copilot the one English thing on the screen. The
/// device's locale is the fallback, which is right for every app that never
/// thought about it.
///
/// Blank rather than null is the case worth handling here. A host reading its
/// own settings gets `''` before the user has picked one, and a tag out of a
/// config file arrives with a stray space; neither names a language, and
/// passing either on would cost the turn the device's perfectly good answer.
///
/// One function because two callers must agree: the handshake sends this tag
/// as `client.locale` and [RendelStrings.forLocale] picks the SDK's own words from
/// it. A copilot answering in Turkish under an English "Confirm" button is the
/// bug that comes of resolving it twice.
String resolveLocale(String? hostLocale) {
  final tag = hostLocale?.trim();
  if (tag != null && tag.isNotEmpty) return tag;
  return PlatformDispatcher.instance.locale.toLanguageTag();
}

/// The language the copilot will actually speak, once the app has said which
/// ones it is willing to speak.
///
/// The same rule the server applies to the answer, applied here to the SDK's
/// own words — because a thread whose prompt is Turkish and whose empty state
/// is English is one screen speaking two languages, and the user cannot tell
/// which of them is the mistake.
///
/// The device decides among the named languages; a device speaking none of
/// them gets the first, which is the app's own default. An empty list leaves
/// [resolveLocale] alone, which is what every build had before `languages`
/// existed.
String resolveSpokenLocale(String? hostLocale, List<String> languages) {
  final resolved = resolveLocale(hostLocale);
  if (languages.isEmpty) return resolved;
  final spoken = resolved.toLowerCase().replaceAll('_', '-').split('-').first;
  return languages.contains(spoken) ? resolved : languages.first;
}
