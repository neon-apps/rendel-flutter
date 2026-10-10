// The sheet `Rendel.open` presents the copilot in is an iOS page sheet: a
// little under the top safe area, its top corners rounded and never square,
// down to the bottom edge, over the app dimmed by a quarter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/ui/thread_screen.dart';

void main() {
  testWidgets('opens as a page sheet: 8 under the safe area, 24 at the top corners, to the bottom, over a 25% scrim',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    addTearDown(Rendel.resetForTest);
    await Rendel.init(
      appKey: 'nc_pk_test_example_000000000000000000000000',
      config: RendelConfig(
        httpClient: MockClient((_) async => http.Response('{"ok":true}', 200)),
        remoteConfig: false,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => Rendel.open(context), child: const Text('open'))),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(ThreadScreen));
    expect(sheet.top, 47 + 8);
    expect(sheet.bottom, 844);
    expect(sheet.width, 390);

    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(
      bottomSheet.shape,
      const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    );
    expect(bottomSheet.clipBehavior, Clip.antiAlias);
    expect(
      tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).map((b) => b.color),
      contains(const Color(0x40000000)),
    );
  });
}
