// Form v2 on the device (`design/FORM-V2.md`).
//
// The inputs claims, returns and applications need: the kinds with their own
// keyboards, a description that grows, several picks, a stepper, a date
// range, a long select with a search field, and files uploaded as they are
// picked. Each is held to the value shape the server takes, and every
// fixture and every submission here to the protocol's own schema.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

import 'wire_schema.dart';

Map<String, dynamic> _form(List<Map<String, dynamic>> fields, {String submit = 'Send claim'}) => {
      'id': 'b_claim',
      'type': 'form',
      'fallback_text': 'A claim form.',
      'props': {'form_id': 'claim', 'title': 'Report a damaged delivery', 'fields': fields, 'submit_label': submit},
    };

const _rooms = [
  {'label': 'Kitchen', 'value': 'kitchen'},
  {'label': 'Hall', 'value': 'hall'},
  {'label': 'Garage', 'value': 'garage'},
];

const _countries = [
  'Austria', 'Belgium', 'Denmark', 'Finland', 'France', 'Germany', 'Ireland', //
  'Italy', 'Netherlands', 'Norway', 'Portugal', 'Spain', 'Sweden',
];

/// Every new kind, prefilled where a prefill exists.
final _everyKind = _form([
  {'kind': 'email', 'name': 'email', 'label': 'Email', 'autofill': 'email', 'value': 'ada@example.com'},
  {'kind': 'tel', 'name': 'phone', 'label': 'Phone', 'autofill': 'tel', 'value': '+31 20 555 0100'},
  {'kind': 'url', 'name': 'link', 'label': 'Tracking link', 'value': 'https://track.example.com/1042'},
  {'kind': 'multiline', 'name': 'what', 'label': 'What happened', 'value': 'The box was crushed.'},
  {'kind': 'multi_select', 'name': 'rooms', 'label': 'Rooms', 'options': _rooms, 'value': ['kitchen', 'garage']},
  {'kind': 'number', 'name': 'pairs', 'label': 'Pairs', 'stepper': true, 'min': 1, 'max': 4, 'value': 2},
  {'kind': 'number', 'name': 'amount', 'label': 'Amount', 'min': 0, 'max': 500, 'value': '120'},
  {'kind': 'date_range', 'name': 'away', 'label': 'Away', 'value': ['2026-10-01', '2026-10-04']},
  {'kind': 'select', 'name': 'country', 'label': 'Country', 'searchable': true, 'options': [
    for (final name in _countries) {'label': name, 'value': name.substring(0, 2).toLowerCase()},
  ]},
  {'kind': 'upload', 'name': 'photos', 'label': 'Photos', 'accept': 'image', 'max_files': 2},
]);

final _numbers = _form([
  {'kind': 'number', 'name': 'pairs', 'label': 'Pairs', 'stepper': true, 'min': 1, 'max': 4, 'value': 3},
  {'kind': 'number', 'name': 'litres', 'label': 'Litres', 'stepper': true, 'min': 0, 'step': 0.1},
  {'kind': 'number', 'name': 'amount', 'label': 'Amount', 'max': 500, 'value': 900},
]);

final _photos = _form([
  {'kind': 'upload', 'name': 'photos', 'label': 'Photos', 'accept': 'image', 'max_files': 2, 'required': true},
]);

final _document = _form([
  {'kind': 'upload', 'name': 'receipt', 'label': 'Receipt', 'accept': 'document'},
]);

final _dates = _form([
  {'kind': 'date', 'name': 'on', 'label': 'Delivered on', 'min_date': '2026-09-01', 'max_date': '2026-09-30'},
  {'kind': 'date_range', 'name': 'stay', 'label': 'Stay', 'min_date': '2026-11-01', 'max_date': '2026-12-31',
   'value': ['2026-11-10', '2026-11-14']},
]);

const _upload1 = '8f0c6c1e-4b7a-4d55-9d1a-0c1f9a3e7b21';
const _upload2 = '1d9b2f40-6a3c-4e7b-8c55-2b7e0d4a9f13';

/// The pickers and the upload, scripted: each pick returns the next file, and
/// each upload waits on a completer the test resolves.
class _Files {
  final List<RendelAttachSource> picked = [];
  final List<String> uploaded = [];
  final List<Completer<String>> uploads = [];
  var _count = 0;

  Future<RendelAttachment?> pick(RendelAttachSource source) async {
    picked.add(source);
    _count++;
    final document = source == RendelAttachSource.files;
    return RendelAttachment(
      bytes: Uint8List.fromList([0, 1, 2]),
      name: document ? 'delivery-note-for-order-1042-from-neon-kicks.pdf' : 'photo$_count.jpg',
      mediaType: document ? 'application/pdf' : 'image/jpeg',
    );
  }

  Future<String> upload(RendelAttachment file) {
    uploaded.add(file.name);
    final done = Completer<String>();
    uploads.add(done);
    return done.future;
  }
}

void main() {
  test('every fixture is one the server could send', () {
    for (final fixture in [_everyKind, _numbers, _photos, _document, _dates]) {
      expect(wireBlockErrors(fixture), isEmpty, reason: fixture['props']['fields'].toString());
    }
  });

  final submitted = <Map<String, Object>>[];
  late _Files files;

  setUp(() {
    submitted.clear();
    files = _Files();
  });

  Future<WireBlock> pump(
    WidgetTester tester,
    Map<String, dynamic> wire, {
    bool canAttach = true,
    double scale = 1,
  }) async {
    // A copy: a form keeps its working values on its props, and the fixtures
    // are shared between tests.
    final block = WireBlock.tryParse(jsonDecode(jsonEncode(wire)) as Map<String, dynamic>)!;
    final dispatch = RendelDispatcher(
      onAction: (_) async => true,
      canHandle: (_) => true,
      onSubmitForm: (formId, values) async {
        submitted.add(values);
        // What the controller would send, held to what the server accepts.
        expect(
          schemaErrors({'form_id': formId, 'values': values},
              chatRequestSchema['properties']['form_submission'] as Map),
          isEmpty,
        );
        return RendelSubmitOutcome.sent;
      },
      onPickFile: canAttach ? files.pick : null,
      onUpload: canAttach ? files.upload : null,
    );
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
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

  Map values(WireBlock block) => block.props[RendelLocalKeys.values] as Map;

  /// Past the sheet's entrance. Not `pumpAndSettle`: an upload's ring turns
  /// until the upload lands, so a screen with one never settles.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> send(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('each kind sends the shape the wire takes', (tester) async {
    await pump(tester, _everyKind);

    await send(tester, 'Send claim');

    expect(submitted.single, {
      'email': 'ada@example.com',
      'phone': '+31 20 555 0100',
      'link': 'https://track.example.com/1042',
      'what': 'The box was crushed.',
      'rooms': ['kitchen', 'garage'],
      'pairs': 2,
      'amount': 120,
      'away_start': '2026-10-01',
      'away_end': '2026-10-04',
    });
  });

  testWidgets('the keyboard is the kind\'s own, and autofill says what a field is for', (tester) async {
    await pump(tester, _everyKind);

    TextField field(String value) =>
        tester.widgetList<TextField>(find.byType(TextField)).singleWhere((f) => f.controller?.text == value);

    expect(field('ada@example.com').keyboardType, TextInputType.emailAddress);
    expect(field('ada@example.com').autofillHints, [AutofillHints.email]);
    expect(field('+31 20 555 0100').keyboardType, TextInputType.phone);
    expect(field('+31 20 555 0100').autofillHints, [AutofillHints.telephoneNumber]);
    expect(field('https://track.example.com/1042').keyboardType, TextInputType.url);
    expect(field('https://track.example.com/1042').autofillHints, isNull);
    final note = field('The box was crushed.');
    expect(note.keyboardType, TextInputType.multiline);
    expect((note.minLines, note.maxLines), (3, 8));
    expect(find.byType(AutofillGroup), findsOneWidget);
  });

  testWidgets('a stepper steps by its step and holds to its bounds', (tester) async {
    final block = await pump(tester, _numbers);
    final plus = find.byIcon(Icons.add_rounded);
    final minus = find.byIcon(Icons.remove_rounded);

    await tester.tap(plus.first);
    await tester.pump();
    expect(values(block)['pairs'], 4);
    await tester.tap(plus.first);
    await tester.pump();
    expect(values(block)['pairs'], 4, reason: 'held at max');
    for (var i = 0; i < 5; i++) {
      await tester.tap(minus.first);
      await tester.pump();
    }
    expect(values(block)['pairs'], 1, reason: 'held at min');

    // 0.1 three times is 0.3, not 0.30000000000000004.
    for (var i = 0; i < 3; i++) {
      await tester.tap(plus.last);
      await tester.pump();
    }
    expect(values(block)['litres'], 0.3);
    expect(block.props[RendelLocalKeys.edited], containsAll(['pairs', 'litres']));

    // The adjustable node a screen reader swipes.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pairs')),
      isSemantics(value: '1', increasedValue: '2', hasIncreaseAction: true, hasDecreaseAction: false),
    );
  });

  testWidgets('a number past its max is refused on Send, in words', (tester) async {
    await pump(tester, _numbers);

    await send(tester, 'Send claim');

    expect(submitted, isEmpty);
    expect(find.text('Enter 500 or less.'), findsOneWidget);
  });

  testWidgets('a stepper sends the number it shows, untouched or not', (tester) async {
    final block = await pump(tester, _numbers);
    values(block)['amount'] = '20';

    await send(tester, 'Send claim');

    expect(submitted.single, {'pairs': 3, 'litres': 0, 'amount': 20});
  });

  group('a select with many options', () {
    testWidgets('opens on a search field that filters them', (tester) async {
      final block = await pump(tester, _everyKind);

      await tester.tap(find.text('Choose an option'));
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Austria'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Search'), 'ger');
      await tester.pump();
      expect(find.text('Germany'), findsOneWidget);
      expect(find.text('Austria'), findsNothing);

      await tester.tap(find.text('Germany'));
      await tester.pumpAndSettle();
      expect(values(block)['country'], 'ge');
    });

    testWidgets('gets one past twelve options whether or not it asked', (tester) async {
      await pump(tester, _form([
        {'kind': 'select', 'name': 'c', 'label': 'Country', 'options': [
          for (final name in _countries) {'label': name, 'value': name},
        ]},
        {'kind': 'select', 'name': 's', 'label': 'Size', 'options': _rooms},
      ]));

      await tester.tap(find.text('Choose an option').first);
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsOneWidget);
      // Shut again from its own field: the list opens in the row, not a sheet.
      await tester.tap(find.text('Choose an option').first);
      await tester.pumpAndSettle();
      expect(find.text('Austria'), findsNothing);

      await tester.tap(find.text('Choose an option').last);
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsNothing, reason: 'three options are read, not searched');
    });
  });

  testWidgets('multi_select starts from an array and ticks on and off', (tester) async {
    final block = await pump(tester, _everyKind);

    expect(tester.getSemantics(find.bySemanticsLabel('Kitchen')),
        isSemantics(hasCheckedState: true, isChecked: true, isInMutuallyExclusiveGroup: false));
    expect(tester.getSemantics(find.bySemanticsLabel('Hall')), isSemantics(isChecked: false));

    await tester.tap(find.text('Hall'));
    await tester.pump();
    expect(values(block)['rooms'], ['kitchen', 'hall', 'garage'], reason: 'in the options\' order');
    await tester.tap(find.text('Kitchen'));
    await tester.pump();
    expect(values(block)['rooms'], ['hall', 'garage']);
    expect(block.props[RendelLocalKeys.edited], {'rooms'});
  });

  group('an upload field', () {
    testWidgets('uploads as soon as a photo is picked, shows a ring, and sends the id', (tester) async {
      final block = await pump(tester, _photos);

      await tester.tap(find.text('Add a photo'));
      await settle(tester);
      // A photo comes from the library or the camera, never the file picker.
      expect(find.text('Photos'), findsWidgets);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Files'), findsNothing);
      await tester.tap(find.text('Camera'));
      await tester.pump();

      expect(files.picked, [RendelAttachSource.camera]);
      expect(files.uploaded, ['photo1.jpg'], reason: 'before Send, not on it');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('photo1.jpg, Loading'), findsOneWidget);

      // Send waits for the upload rather than sending a file it does not have.
      await tester.tap(find.text('Send claim'));
      await tester.pump();
      expect(submitted, isEmpty);
      expect(find.text('Sending…'), findsOneWidget);

      files.uploads.single.complete(_upload1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(submitted.single, {'photos': [_upload1]});
      expect(values(block)['photos'], [_upload1]);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('photo1.jpg'), findsOneWidget, reason: 'the receipt names the file, not its id');
    });

    testWidgets('takes a file off by its button, and stops adding at max_files', (tester) async {
      final block = await pump(tester, _photos);

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Add a photo'));
        await settle(tester);
        await tester.tap(find.text('Photos').last);
        await tester.pump();
      }
      files.uploads[0].complete(_upload1);
      files.uploads[1].complete(_upload2);
      await tester.pump();

      expect(values(block)['photos'], [_upload1, _upload2]);
      expect(find.text('Add a photo'), findsNothing, reason: 'max_files is 2');

      await tester.tap(find.bySemanticsLabel('Remove, photo1.jpg'));
      await tester.pump();

      expect(values(block)['photos'], [_upload2]);
      expect(find.text('Add a photo'), findsOneWidget);
      expect(block.props[RendelLocalKeys.edited], {'photos'});
    });

    testWidgets('says why an upload failed, and keeps the form open', (tester) async {
      await pump(tester, _photos);

      await tester.tap(find.text('Add a photo'));
      await settle(tester);
      await tester.tap(find.text('Photos').last);
      await tester.pump();
      await tester.tap(find.text('Send claim'));
      await tester.pump();
      files.uploads.single.completeError(const RendelUploadFailure('That file is over 20 MB.'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(submitted, isEmpty);
      expect(find.text('That file is over 20 MB.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Send claim'), findsOneWidget, reason: 'open again, not stuck sending');
    });

    testWidgets('a document opens the file picker without asking where from', (tester) async {
      // At twice the font size, where a long name has the least room.
      await pump(tester, _document, scale: 2);

      await tester.tap(find.text('Add a file'));
      await tester.pump();
      files.uploads.single.complete(_upload1);
      await tester.pump();

      expect(files.picked, [RendelAttachSource.files]);
      expect(find.text('delivery-note-for-order-1042-from-neon-kicks.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'the thumbnail holds its name');
    });

    testWidgets('draws, and adds nothing, where the build cannot upload', (tester) async {
      await pump(tester, _document, canAttach: false);

      await tester.tap(find.text('Add a file'));
      await tester.pumpAndSettle();

      expect(files.picked, isEmpty);
      expect(tester.getSemantics(find.bySemanticsLabel('Add a file')),
          isSemantics(isButton: true, isEnabled: false));
    });
  });

  group('dates', () {
    testWidgets('a date\'s month is held to min_date and max_date', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, _dates);

      await tester.tap(find.text('Choose a date'));
      await tester.pumpAndSettle();

      // Today, wherever it falls, is held into September; neither button
      // turns past the bounds.
      expect(find.text('September 2026'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Previous month')), isSemantics(isEnabled: false));
      expect(tester.getSemantics(find.bySemanticsLabel('Next month')), isSemantics(isEnabled: false));
      expect(find.byType(DatePickerDialog), findsNothing);
      semantics.dispose();
    });

    testWidgets('a range opens on the days it holds, inside its bounds, and sends both', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, _dates);

      expect(find.text('From'), findsOneWidget);
      expect(find.textContaining('Nov 14'), findsOneWidget);
      await tester.tap(find.textContaining('Nov 10'));
      await tester.pumpAndSettle();

      expect(find.text('November 2026'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Tuesday, November 10, 2026')), isSemantics(isSelected: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Previous month')), isSemantics(isEnabled: false));
      expect(find.byType(DateRangePickerDialog), findsNothing);
      await tester.tap(find.textContaining('Nov 10'));
      await tester.pumpAndSettle();
      semantics.dispose();

      await send(tester, 'Send claim');
      expect(submitted.single, {'stay_start': '2026-11-10', 'stay_end': '2026-11-14'});
    });

    testWidgets('a day outside the bounds, or a range that ends before it starts, is refused', (tester) async {
      await pump(tester, _form([
        {'kind': 'date', 'name': 'on', 'label': 'On', 'min_date': '2026-09-01', 'value': '2026-08-31'},
        {'kind': 'date_range', 'name': 'stay', 'label': 'Stay', 'max_date': '2026-12-31',
         'value': ['2026-12-30', '2027-01-02']},
        {'kind': 'date_range', 'name': 'back', 'label': 'Back', 'value': ['2026-11-14', '2026-11-10']},
      ]));

      await send(tester, 'Send claim');

      expect(submitted, isEmpty);
      expect(find.text('Pick 2026-09-01 or later.'), findsOneWidget);
      expect(find.text('Pick 2026-12-31 or earlier.'), findsOneWidget);
      expect(find.text('Pick 2026-11-14 or later.'), findsOneWidget);
    });

    testWidgets('a required range left empty is refused under its own field', (tester) async {
      await pump(tester, _form([
        {'kind': 'date_range', 'name': 'stay', 'label': 'Stay', 'required': true},
      ]));

      await send(tester, 'Send claim');

      expect(submitted, isEmpty);
      expect(find.text('Fill this in to continue.'), findsOneWidget);
    });
  });

  test('every new string exists in all six languages', () {
    const english = RendelStrings();
    expect(
      [english.uploadAdd, english.uploadAddPhoto, english.uploadRemove, english.searchOptions,
       english.dateRangeStart, english.dateRangeEnd],
      ['Add a file', 'Add a photo', 'Remove', 'Search', 'From', 'To'],
    );
    final turkish = RendelStrings.forLocale('tr');
    expect(
      [turkish.uploadAdd, turkish.uploadAddPhoto, turkish.uploadRemove, turkish.searchOptions,
       turkish.dateRangeStart, turkish.dateRangeEnd],
      ['Dosya ekle', 'Fotoğraf ekle', 'Kaldır', 'Ara', 'Başlangıç', 'Bitiş'],
    );
    for (final language in ['tr', 'de', 'fr', 'es', 'ar']) {
      final strings = RendelStrings.forLocale(language);
      for (final (name, said, en) in [
        ('uploadAdd', strings.uploadAdd, english.uploadAdd),
        ('uploadAddPhoto', strings.uploadAddPhoto, english.uploadAddPhoto),
        ('uploadRemove', strings.uploadRemove, english.uploadRemove),
        ('searchOptions', strings.searchOptions, english.searchOptions),
        ('dateRangeStart', strings.dateRangeStart, english.dateRangeStart),
        ('dateRangeEnd', strings.dateRangeEnd, english.dateRangeEnd),
        ('fieldAtLeast', strings.fieldAtLeast, english.fieldAtLeast),
        ('fieldAtMost', strings.fieldAtMost, english.fieldAtMost),
        ('fieldOnOrAfter', strings.fieldOnOrAfter, english.fieldOnOrAfter),
        ('fieldOnOrBefore', strings.fieldOnOrBefore, english.fieldOnOrBefore),
      ]) {
        expect(said, isNot(en), reason: '$name is still English in $language');
      }
      expect(strings.fieldAtLeastOf('3'), contains('3'), reason: language);
      expect(strings.fieldAtMostOf('9'), contains('9'), reason: language);
      expect(strings.fieldOnOrAfterOf('2026-11-01'), contains('2026-11-01'), reason: language);
      expect(strings.fieldOnOrBeforeOf('2026-12-31'), contains('2026-12-31'), reason: language);
    }
  });
}
