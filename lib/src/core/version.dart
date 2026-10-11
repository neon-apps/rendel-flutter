/// The version this build of the SDK reports, as `flutter/<pubspec version>`.
///
/// Sent with every turn and every manifest sync: the console prints it beside
/// the manifest, and the API compares it with the floor an operator can set.
/// It was a literal `'flutter/0.1.0'` in `RendelConfig`, so eleven releases in,
/// every app still introduced itself as the first one — and a floor of any
/// height would have refused them all. `version_test.dart` fails the build
/// when this and `pubspec.yaml` disagree.
const String sdkVersion = 'flutter/0.46.4';
