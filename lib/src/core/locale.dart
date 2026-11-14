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

/// The languages the persona answers in, as published in the console
/// (`languages` on the app config): set when a config is applied
/// (`Rendel._apply`), empty until then and for a persona that names none.
List<String> rendelPublishedLanguages = const [];

/// The language of the SDK's own words (Tuna, 2026-11-14): the app's locale
/// when it gives one; else the phone's language, when it is one the
/// assistant answers in; else English, when the assistant answers in
/// English; else the first language it answers in, so the screen never
/// speaks two languages before an answer says which.
///
/// Those are the app's `languages` when it names some, else the persona's
/// [published] ones ([rendelPublishedLanguages]). Named nowhere, every
/// language is answered and the phone's stands, which is what every build
/// had before `languages` existed. [device] stands in for the phone's own
/// tag in a test, where `PlatformDispatcher.instance` cannot be set.
String resolveSpokenLocale(
  String? hostLocale,
  List<String> languages, {
  List<String>? published,
  String? device,
}) {
  final tag = hostLocale?.trim();
  if (tag != null && tag.isNotEmpty) return tag;
  final phone = device ?? resolveLocale(null);
  final answered = languages.isNotEmpty ? languages : (published ?? rendelPublishedLanguages);
  if (answered.isEmpty) return phone;
  final spoken = phone.toLowerCase().replaceAll('_', '-').split('-').first;
  if (answered.contains(spoken)) return phone;
  return answered.contains('en') ? 'en' : answered.first;
}
