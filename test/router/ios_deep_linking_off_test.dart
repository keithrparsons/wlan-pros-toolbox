// The WLAN Pros Live Shortcut hands control back with
// `wlanprostoolbox://live-done`. With Flutter deep linking on (its default when
// Info.plist is silent), the engine turns that URL into pushNamed('/'), which
// is the home screen, on top of the running live tool. Keith's iPhone Duo log,
// 8 NOV 2026: UIOpenURLAction at 14:22:04, Test My Connection gone at 13%.
// The app uses no deep links, so the flag must be present and false.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS Info.plist turns Flutter deep linking off', () {
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    final RegExp flagFalse = RegExp(
      r'<key>FlutterDeepLinkingEnabled</key>\s*<false\s*/>',
    );
    expect(plist, matches(flagFalse));
  });
}
