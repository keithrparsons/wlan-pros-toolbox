@TestOn('browser')
library;

// Web-gate regression test for TestMyConnectionScreen (launch-critical, 2026-07-06).
//
// THE BUG THIS GUARDS: on Flutter web the screen crashed while building. Its
// initState constructed native services eagerly, and NetworkDetailsService's
// field initializer reads `Platform.isAndroid`, which throws
// `Unsupported operation: Platform._operatingSystem` in a browser (dart:io has
// no Platform on web). The URL changed, the screen never rendered, and the app
// hung — reproduced live in Chrome, identical on 1.6.1 and 1.7.0.
//
// WHY THIS FILE IS `@TestOn('browser')`: the default `flutter test` suite runs
// on the Dart VM, where `Platform.isAndroid` works fine and the crash CANNOT
// reproduce. Only a real web target exercises the dart:io web stub that throws.
// Run it with:  flutter test --platform chrome \
//   test/screens/tools/network/test_my_connection_web_gate_test.dart
//
// On the UNFIXED code this test fails red — pumpWidget throws the Platform error
// out of initState. On the fixed code initState bails before touching any native
// service and the screen renders NetworkUnavailableView (the honest "not
// available on the web version" state), so the test passes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  testWidgets(
    'Check My Connection renders NetworkUnavailableView on web instead of '
    'crashing in initState',
    (WidgetTester tester) async {
      // Production defaults: no sourceOverride, so the resolver picks the web
      // source in a browser. autoStart mirrors the home "Check My Connection"
      // hero path (arguments == true), which is where Keith hit the crash.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const TestMyConnectionScreen(autoStart: true),
        ),
      );
      await tester.pump();

      // The screen must render the shared web-unavailable fallback, not throw.
      expect(find.byType(NetworkUnavailableView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
