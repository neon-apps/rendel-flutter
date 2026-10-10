// A form draws no control of the platform's own (Web 0.23.0 did the same on
// the web): a select, a day, a time and a range of days open the SDK's own
// list or month in the field's row, a toggle is the SDK's own switch, and
// each still sends what it always sent.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

import 'wire_schema.dart';

Map<String, dynamic> _form(List<Map<String, dynamic>> fields) => {
      'id': 'b_pick',
      'type': 'form',
      'fallback_text': 'A form.',
      'props': {'form_id': 'pick', 'fields': fields, 'submit_label': 'Send'},
    };

const _sizes = [
  {'label': 'Small', 'value': 's'},
  {'label': 'Medium', 'value': 'm'},
  {'label': 'Large', 'value': 'l'},
];

final _every = _form([
  {'kind': 'select', 'name': 'size', 'label': 'Size', 'options': _sizes},
  {'kind': 'date', 'name': 'on', 'label': 'Delivered on', 'min_date': '2026-09-10', 'max_date': '2026-09-20'},
  {'kind': 'time', 'name': 'at', 'label': 'At', 'value': '09:37'},
  {'kind': 'date_range', 'name': 'stay', 'label': 'Stay', 'min_date': '2026-11-01', 'max_date': '2026-12-31'},
  {'kind': 'toggle', 'name': 'news', 'label': 'News'},
]);

const _material = DefaultMaterialLocalizations();
Finder _day(int y, int m, int d) => find.bySemanticsLabel(_material.formatFullDate(DateTime(y, m, d)));

void main() {
  test('the fixture is one the server could send', () {
    expect(wireBlockErrors(_every), isEmpty);
  });

  final submitted = <Map<String, Object>>[];
  setUp(submitted.clear);

  Future<WireBlock> pump(WidgetTester tester, Map<String, dynamic> wire, {bool clock24 = false}) async {
    final block = WireBlock.tryParse(jsonDecode(jsonEncode(wire)) as Map<String, dynamic>)!;
    final dispatch = RendelDispatcher(
      onAction: (_) async => true,
      canHandle: (_) => true,
      onSubmitForm: (formId, values) async {
        submitted.add(values);
        return RendelSubmitOutcome.sent;
      },
    );
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: clock24),
          child: child!,
        ),
        home: RendelThemeScope(
          theme: RendelTheme.paper(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Builder(builder: (context) => ComponentRegistry.build(context, block, dispatch)),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return block;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Nothing the platform draws: no Material picker, dialog, sheet or switch.
  void expectNoStockControl() {
    for (final type in [
      Switch, DatePickerDialog, TimePickerDialog, DateRangePickerDialog, Dialog, BottomSheet, //
      DropdownButton, PopupMenuButton, Checkbox, Radio, Slider,
    ]) {
      expect(find.byType(type), findsNothing, reason: '$type');
    }
  }

  testWidgets('every picker opens in its row, and none is the platform\'s', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, _every);
    expectNoStockControl();

    for (final opener in ['Choose an option', 'Choose a date', 'From', 'To']) {
      await tap(tester, find.text(opener));
      expectNoStockControl();
      await tap(tester, find.text(opener));
    }
    await tap(tester, find.text('9:37 AM'));
    expectNoStockControl();
    semantics.dispose();
  });

  testWidgets('a short select lists its options in the row, no search, and sends the one picked', (tester) async {
    final semantics = tester.ensureSemantics();
    final block = await pump(tester, _every);

    final trigger = find.bySemanticsLabel('Size, not chosen');
    expect(tester.getSemantics(trigger), isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));
    await tap(tester, find.text('Choose an option'));
    expect(find.text('Search'), findsNothing, reason: 'three options are read, not searched');
    expect(find.text('Medium'), findsOneWidget);
    // In the form's own column, under the field, not in a route over it.
    expect(tester.getRect(find.text('Medium')).top, greaterThan(tester.getRect(find.text('Size')).bottom));
    expect(tester.getRect(find.text('Medium')).bottom, lessThan(tester.getRect(find.text('Delivered on')).top));

    await tap(tester, find.text('Medium'));
    expect(find.text('Small'), findsNothing, reason: 'picking closes the list');
    expect((block.props[RendelLocalKeys.values] as Map)['size'], 'm');

    await tap(tester, find.text('Medium'));
    expect(tester.getSemantics(find.bySemanticsLabel('Medium').last), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Large')), isSemantics(isSelected: false));
    semantics.dispose();
  });

  testWidgets('Escape closes an open list', (tester) async {
    await pump(tester, _every);
    await tap(tester, find.text('Choose an option'));
    expect(find.text('Large'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Large'), findsNothing);
  });

  testWidgets('a day is picked from a month held to its bounds and sent as YYYY-MM-DD', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, _every);

    await tap(tester, find.text('Choose a date'));
    expect(find.text('September 2026'), findsOneWidget);
    // Before min_date and after max_date: drawn, not to be picked.
    expect(tester.getSemantics(_day(2026, 9, 5)), isSemantics(isButton: true, isEnabled: false));
    expect(tester.getSemantics(_day(2026, 9, 21)), isSemantics(isEnabled: false));
    expect(tester.getSemantics(_day(2026, 9, 15)), isSemantics(isEnabled: true, hasTapAction: true));
    await tap(tester, _day(2026, 9, 5));
    expect(find.text('September 2026'), findsOneWidget, reason: 'a day out of bounds picks nothing');

    await tap(tester, _day(2026, 9, 15));
    expect(find.text('September 2026'), findsNothing, reason: 'picking closes the month');
    expect(find.text('Sep 15, 2026'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('^Delivered on, '))).label,
        'Delivered on, Tuesday, September 15, 2026');

    await send(tester);
    expect(submitted.single, {'on': '2026-09-15', 'at': '09:37', 'news': false});
    semantics.dispose();
  });

  testWidgets('the week starts where the locale starts it, and the months turn', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, _form([
      {'kind': 'date', 'name': 'on', 'label': 'On', 'value': '2026-10-14'},
    ]));
    await tap(tester, find.text('Oct 14, 2026'));
    expect(find.text('October 2026'), findsOneWidget);
    // DefaultMaterialLocalizations is en-US, whose week starts on Sunday.
    final letters = tester.widgetList<Text>(find.byWidgetPredicate((w) => w is Text && w.data?.length == 1 && RegExp('[SMTWF]').hasMatch(w.data!)));
    expect(letters.take(7).map((t) => t.data), ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
    // October 2026 starts on a Thursday: the 1st sits under the fifth letter.
    expect(tester.getRect(find.text('1')).center.dx,
        moreOrLessEquals(tester.getRect(find.text('T').at(1)).center.dx, epsilon: 0.5));
    expect(tester.getSemantics(_day(2026, 10, 14)), isSemantics(isSelected: true));

    await tap(tester, find.bySemanticsLabel('Next month'));
    expect(find.text('November 2026'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Previous month'));
    await tap(tester, find.bySemanticsLabel('Previous month'));
    expect(find.text('September 2026'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a time is a list of quarter hours on the locale\'s clock, a time off the quarter in its place',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, _every);

    expect(find.text('9:37 AM'), findsOneWidget);
    await tap(tester, find.text('9:37 AM'));
    // Opened on the time it holds, between the quarters either side of it.
    final held = find.bySemanticsLabel('9:37 AM').last;
    expect(tester.getSemantics(held), isSemantics(isSelected: true));
    final top = tester.getRect(held).top;
    expect(tester.getRect(find.text('9:30 AM')).top, lessThan(top));
    expect(tester.getRect(find.text('9:45 AM')).top, greaterThan(top));

    await tap(tester, find.text('9:45 AM'));
    expect(find.text('9:45 AM'), findsOneWidget, reason: 'the field shows it, the list is shut');
    await send(tester);
    expect(submitted.single['at'], '09:45');
    semantics.dispose();
  });

  testWidgets('on a 24-hour clock the quarters read 09:45', (tester) async {
    await pump(tester, _every, clock24: true);
    await tap(tester, find.text('09:37'));
    expect(find.text('09:45'), findsOneWidget);
    expect(find.text('9:45 AM'), findsNothing);
  });

  testWidgets('a range: From goes on to To, To starts no earlier, and a later From clears it', (tester) async {
    final semantics = tester.ensureSemantics();
    final block = await pump(tester, _every);
    Map values() => block.props[RendelLocalKeys.values] as Map;

    await tap(tester, find.text('From'));
    expect(find.text('November 2026'), findsOneWidget, reason: 'today held into the bounds');
    await tap(tester, _day(2026, 11, 10));
    // To's month opened by itself, From's days before it out of reach.
    expect(find.text('November 2026'), findsOneWidget);
    expect(tester.getSemantics(_day(2026, 11, 9)), isSemantics(isEnabled: false));
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('^Stay, To, '))), isSemantics(isExpanded: true));
    await tap(tester, _day(2026, 11, 14));
    expect(find.text('November 2026'), findsNothing);
    expect([values()['stay_start'], values()['stay_end']], ['2026-11-10', '2026-11-14']);

    // A From after To clears To and opens it again.
    await tap(tester, find.textContaining('Nov 10'));
    await tap(tester, _day(2026, 11, 20));
    expect([values()['stay_start'], values()['stay_end']], ['2026-11-20', null]);
    expect(tester.getSemantics(_day(2026, 11, 15)), isSemantics(isEnabled: false));
    await tap(tester, _day(2026, 11, 22));

    await send(tester);
    expect(submitted.single['stay_start'], '2026-11-20');
    expect(submitted.single['stay_end'], '2026-11-22');
    semantics.dispose();
  });

  testWidgets('a toggle is the SDK\'s switch: toggled, flipped by the whole row, at least 44pt', (tester) async {
    final semantics = tester.ensureSemantics();
    final block = await pump(tester, _every);

    expect(find.byType(Switch), findsNothing);
    final node = find.bySemanticsLabel('News');
    expect(tester.getSemantics(node), isSemantics(hasToggledState: true, isToggled: false, hasTapAction: true));
    expect(tester.getSize(node).height, greaterThanOrEqualTo(44));

    await tap(tester, find.text('No'));
    expect((block.props[RendelLocalKeys.values] as Map)['news'], true);
    expect(tester.getSemantics(node), isSemantics(isToggled: true));
    semantics.dispose();
  });

  testWidgets('a bar chart keeps its cents and reads "Today", not "in Today"', (tester) async {
    final block = WireBlock.tryParse({
      'id': 'b_chart',
      'type': 'chart',
      'fallback_text': 'Spend by day.',
      'props': {
        'kind': 'bar',
        'unit': '€',
        'labels': ['Mon', 'Tue', 'Today'],
        'series': [
          {'data': [48.25, 12, 53.4]},
        ],
      },
    })!;
    await tester.pumpWidget(MaterialApp(
      home: RendelThemeScope(
        theme: RendelTheme.paper(),
        child: Scaffold(
          body: Builder(
            builder: (context) => ComponentRegistry.build(
              context,
              block,
              RendelDispatcher(onAction: (_) async => true, canHandle: (_) => true, onSubmitForm: (_, __) async => RendelSubmitOutcome.sent),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('53.40 €'), findsOneWidget);
    expect(find.text('Today, the highest'), findsOneWidget);
    expect(find.textContaining('in Today'), findsNothing);
  });

  test('the new words exist in all six languages', () {
    const english = RendelStrings();
    expect([english.previousMonth, english.nextMonth, english.readoutNow], ['Previous month', 'Next month', '{label}']);
    expect(english.readoutAt('Today', peak: true, now: true), 'Today, the highest');
    expect(english.readoutAt('Aug', peak: false), 'in Aug');
    for (final language in ['tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      expect(strings.previousMonth, isNot(english.previousMonth), reason: language);
      expect(strings.nextMonth, isNot(english.nextMonth), reason: language);
      expect(strings.readoutNowPeak, isNot(english.readoutNowPeak), reason: language);
      expect(strings.readoutNow, '{label}', reason: language);
    }
  });
}
