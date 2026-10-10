import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/src/core/batteries.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// What a card's link does in an app that wired nothing.
///
/// Until 0.20 there was no default opener, so "Go to the product" on a card
/// did nothing in an app that had followed the quickstart to the letter. These
/// pin the default: https, in an in-app browser, the external one when there
/// is none, and never a crash in the host when neither works.
class _Browser extends UrlLauncherPlatform {
  _Browser({this.inApp = true, this.fails = false});

  final bool inApp;
  final bool fails;
  final List<(String, PreferredLaunchMode)> opened = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (fails) throw StateError('no browser');
    opened.add((url, options.mode));
    return options.mode == PreferredLaunchMode.inAppBrowserView ? inApp : true;
  }
}

void main() {
  test('opens a link in an in-app browser', () async {
    final browser = _Browser();
    UrlLauncherPlatform.instance = browser;
    await openLink('https://shop.example.com/jeans/42');
    expect(browser.opened, [('https://shop.example.com/jeans/42', PreferredLaunchMode.inAppBrowserView)]);
  });

  test('falls back to the external browser where there is no in-app one', () async {
    final browser = _Browser(inApp: false);
    UrlLauncherPlatform.instance = browser;
    await openLink('https://shop.example.com/jeans/42');
    expect(browser.opened.map((call) => call.$2), [
      PreferredLaunchMode.inAppBrowserView,
      PreferredLaunchMode.externalApplication,
    ]);
  });

  test('opens nothing but https', () async {
    final browser = _Browser();
    UrlLauncherPlatform.instance = browser;
    for (final url in ['http://shop.example.com', 'javascript:alert(1)', 'tel:123', 'not a url']) {
      await openLink(url);
    }
    expect(browser.opened, isEmpty);
  });

  test('a browser that fails is logged, not thrown into the host', () async {
    UrlLauncherPlatform.instance = _Browser(fails: true);
    await expectLater(openLink('https://shop.example.com'), completes);
  });
}
