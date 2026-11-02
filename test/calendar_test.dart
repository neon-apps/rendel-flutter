import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/src/core/batteries.dart';

/// `add_to_calendar` on iOS, without EventKit.
///
/// App Store Connect scans a binary rather than running it: inSepo's build 6
/// was refused (ITMS-90683, 2026-11-02) because the SDK's iOS half named
/// `EKEventStore` and the host's Info.plist had no `NSCalendarsUsageDescription`,
/// a line the app never needed since the editor runs outside the app from
/// iOS 17. The SDK links no EventKit now, and nothing a host writes can bring
/// that refusal back. These keep it that way.
void main() {
  test('the iOS plugin names nothing from EventKit', () {
    // The code, not the comments, which say why there is none.
    final swift = File('ios/rendel/Sources/rendel/RendelPlugin.swift')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(swift, isNot(contains('import EventKit')));
    expect(swift, isNot(matches(RegExp(r'\bEK[A-Z]\w+'))), reason: 'EKEventStore, EKEvent, EKEventEditViewController…');
    expect(File('ios/rendel.podspec').readAsStringSync(), isNot(contains('EventKit')));
    expect(File('ios/rendel/Package.swift').readAsStringSync(), isNot(contains('EventKit')));
  });

  test('the calendar file is the API\'s, with the event in UTC in its query', () {
    final url = calendarEventUrl(
      'https://api.rendel.ai',
      title: 'Fitting; room 2, with Ayşe',
      startsAt: DateTime.parse('2026-10-14T10:00:00+02:00'),
      endsAt: DateTime.parse('2026-10-14T10:45:00+02:00'),
      location: 'Haarlemmerstraat 24',
    );
    final uri = Uri.parse(url);
    expect(uri.scheme, 'https');
    expect(uri.host, 'api.rendel.ai');
    expect(uri.path, '/v1/calendar/event.ics');
    expect(uri.queryParameters, {
      'title': 'Fitting; room 2, with Ayşe',
      'starts_at': '2026-10-14T08:00:00.000Z',
      'ends_at': '2026-10-14T08:45:00.000Z',
      'location': 'Haarlemmerstraat 24',
    });
  });

  test('an end, a place or notes that were not given are not sent', () {
    final uri = Uri.parse(calendarEventUrl('https://api.rendel.ai', title: 'x', startsAt: DateTime.utc(2026, 10, 14, 8)));
    expect(uri.queryParameters.keys, ['title', 'starts_at']);
  });
}
