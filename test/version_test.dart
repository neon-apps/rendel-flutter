import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/src/core/config.dart';
import 'package:rendel/src/core/version.dart';

/// The version the SDK says it is, and the version it is.
///
/// Two places have to agree — the constant the wire carries and the pubspec
/// pub installs — and nothing checked that they did. They disagreed by
/// eleven releases.
void main() {
  test('the wire version is the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(sdkVersion, 'flutter/$declared');
  });

  test('a bare config reports it', () {
    expect(const RendelConfig().sdkVersion, sdkVersion);
  });
}
