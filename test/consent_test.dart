import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/analytics.dart';
import 'package:rendel/src/core/screens.dart';

/// Consent mode (KVKK, demo persona test): taps and screen views wait for the app to say yes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> sent;
  final analytics = RendelAnalytics.instance;
  final screens = RendelScreens.instance;
  Map<String, dynamic> tap() => {'type': 'tap', 'screen': '/', 'role': 'button', 'locator': 'b', 'platform': 'flutter', 'at': 'x'};
  Map<String, dynamic> view() => {'type': 'screen_view', 'screen': '/', 'at': 'x'};
  List<Object?> kinds() {
    screens.flush();
    return [for (final i in sent) if (i['type'] != 'session') i['type']];
  }

  setUp(() {
    Rendel.resetForTest();
    sent = [];
    screens.send = sent.addAll;
  });

  group('with the setting on', () {
    setUp(() => analytics.capture = const RendelCapture(consent: true));

    test('sends no tap or screen view before the app says yes', () {
      screens.add(tap());
      screens.add(view());
      expect(kinds(), isEmpty);
    });

    test('sends them after true', () {
      Rendel.setAnalyticsConsent(true);
      screens.add(tap());
      screens.add(view());
      expect(kinds(), ['tap', 'screen_view']);
    });

    test('false stops them and drops what waits', () {
      Rendel.setAnalyticsConsent(true);
      screens.add(tap());
      Rendel.setAnalyticsConsent(false);
      screens.add(view());
      expect(kinds(), isEmpty);
    });

    test("leaves the app's own events alone", () {
      screens.add({'type': 'event', 'name': 'signed_up', 'at': 'x'});
      expect(kinds(), ['event']);
    });
  });

  group('before the config has been read', () {
    setUp(() => analytics.captureKnown = false);

    test('holds them, then sends them if the setting is off', () {
      screens.add(tap());
      expect(kinds(), isEmpty);
      analytics.captureKnown = true;
      screens.consentChanged();
      expect(kinds(), ['tap']);
    });

    test('drops them if the setting is on', () {
      screens.add(tap());
      analytics
        ..capture = const RendelCapture(consent: true)
        ..captureKnown = true;
      screens.consentChanged();
      expect(kinds(), isEmpty);
    });
  });

  test('with the setting off nothing changes, and an explicit no still counts', () {
    screens.add(tap());
    expect(kinds(), ['tap']);
    sent.clear();
    Rendel.setAnalyticsConsent(false);
    screens.add(tap());
    expect(kinds(), isEmpty);
  });

  test('reads the setting from the config, off unless it says', () {
    expect(RendelCapture.parse({'consent': true}).consent, isTrue);
    expect(RendelCapture.parse({}).consent, isFalse);
    expect(const RendelCapture(consent: true).isDefault, isFalse);
  });
}
