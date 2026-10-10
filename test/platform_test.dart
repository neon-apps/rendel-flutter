import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/core/batteries.dart';
import 'package:rendel/src/core/platform.dart';

/// What the host app no longer has to write.
///
/// Until 0.15 a host added three iOS usage strings and an Android permission,
/// and an iOS app missing any of them was closed by the system on the first
/// press of the paperclip or the microphone. Photos and Files need nothing
/// now, Android's permission ships in the SDK's manifest, and a missing
/// microphone or camera line hides that control instead of crashing the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rendel/platform');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final logged = <RendelLogRecord>[];
  setUp(() {
    logged.clear();
    RendelLog.sink = logged.add;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    RendelLog.sink = null;
    Rendel.resetForTest();
  });

  /// An Info.plist without [keys]: of the lines the SDK asks about, those.
  void infoPlistMissing(List<String> keys) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'missingUsageDescriptions');
      return [
        for (final key in call.arguments as List) if (keys.contains(key)) key,
      ];
    });
  }

  group('the microphone on iOS', () {
    test('is hidden, and says which lines are missing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      infoPlistMissing(['NSSpeechRecognitionUsageDescription']);
      expect(await RendelPlatform.microphoneReady(), isFalse);
      expect(logged.single.code, 'usage_description_missing');
      expect(logged.single.message, contains('NSSpeechRecognitionUsageDescription'));
    });

    test('is drawn when Info.plist has both lines', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      infoPlistMissing([]);
      expect(await RendelPlatform.microphoneReady(), isTrue);
      expect(logged, isEmpty);
    });

    test('is drawn when there is no native half to ask', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await RendelPlatform.microphoneReady(), isTrue);
    });
  });

  test('is never asked about on Android, whose permission ships in the SDK', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (_) async => fail('asked on Android'));
    expect(await RendelPlatform.microphoneReady(), isTrue);
  });

  testWidgets('an iOS thread with no microphone lines keeps the file tools and loses the mic',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    infoPlistMissing(RendelPlatform.microphoneUsageKeys);
    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(
        remoteConfig: false,
        httpClient: MockClient((_) async => http.Response(jsonEncode({'ok': true}), 200)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Rendel.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // No microphone leaves nothing for the middle, so the box is open.
    expect(find.bySemanticsLabel('Photos'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);
    expect(find.bySemanticsLabel('Speak instead of typing'), findsNothing);
    // Reset before the tree goes, while the override is still in force.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an iOS thread with no camera line offers Photos and Files only',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    infoPlistMissing(RendelPlatform.cameraUsageKeys);
    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(
        remoteConfig: false,
        onLog: logged.add,
        httpClient: MockClient((_) async => http.Response(jsonEncode({'ok': true}), 200)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Rendel.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Attach a file'));
    await tester.pumpAndSettle();

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Camera'), findsNothing);
    expect(logged.map((r) => r.message), contains(contains('NSCameraUsageDescription')));
    debugDefaultTargetPlatformOverride = null;
  });

  test('Photos asks the picker for no metadata, so iOS asks for no permission', () async {
    final picker = _RecordingPicker();
    ImagePickerPlatform.instance = picker;
    await pickImage();
    expect(picker.source, ImageSource.gallery);
    expect(picker.options?.requestFullMetadata, isFalse);
  });

  test('Camera asks the picker for the camera, at a size worth uploading', () async {
    final picker = _RecordingPicker();
    ImagePickerPlatform.instance = picker;
    await takePhoto();
    expect(picker.source, ImageSource.camera);
    expect(picker.options?.maxWidth, 2048);
  });

  group('Files', () {
    void picked(Map<String, Object?>? file) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'pickDocument');
        return file;
      });
    }

    test('names the type from the file name', () async {
      picked({'name': 'receipt.PDF', 'type': null, 'bytes': Uint8List.fromList([1, 2])});
      final file = await pickFile();
      expect(file?.name, 'receipt.PDF');
      expect(file?.mediaType, 'application/pdf');
      expect(file?.bytes, [1, 2]);
    });

    test('takes the provider\'s type for a name without one', () async {
      picked({'name': 'notes', 'type': 'text/plain', 'bytes': Uint8List(0)});
      expect((await pickFile())?.mediaType, 'text/plain');
    });

    test('is null when nothing was chosen', () async {
      picked(null);
      expect(await pickFile(), isNull);
    });

    test('reports a missing native half, not a cancel', () async {
      await expectLater(pickFile(), throwsA(isA<StateError>()));
    });
  });
}

class _RecordingPicker extends ImagePickerPlatform {
  ImageSource? source;
  ImagePickerOptions? options;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    this.source = source;
    this.options = options;
    return null;
  }
}
