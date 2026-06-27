// Tests for the "Fix Your Own Wi-Fi" book entry (Book 3, 2026-06-12).
//
// Keith's consumer book is bundled FREE and surfaced as a compact home callout
// near "Check My Connection". These tests pin the two load-bearing invariants:
//
//   1. ASSET BUNDLED + REAL PDF — the book file exists on disk at the path the
//      app and pubspec agree on, is declared as a Flutter asset (so it ships in
//      every build, offline), and is a genuine PDF (`%PDF-` magic). The PDF is a
//      near-final PLACEHOLDER that Keith will swap when the final Vellum export
//      lands; the magic-byte check makes that swap safe (a non-PDF can't slip in
//      silently). Scanned via dart:io (the established bundled-asset test pattern
//      in this suite — no Flutter binding needed).
//
//   2. ENTRY ROUTES TO THE PDF VIEWER — the home callout renders, and tapping it
//      pushes the app's existing offline pdfx viewer (PdfReferenceScreen) with
//      the exact kFixYourOwnWifiBookAsset path. The viewer is asserted by type +
//      assetPath, never rendered (pdfx needs native PDFKit, absent in the
//      headless test env), so this never touches a platform channel.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _app({NavigatorObserver? observer}) => MaterialApp(
      theme: AppTheme.dark(),
      home: const HomeScreen(),
      navigatorObservers: observer == null
          ? const <NavigatorObserver>[]
          : <NavigatorObserver>[observer],
    );

/// Captures every pushed route so a routing assertion can read the pushed
/// widget WITHOUT mounting it. This is what keeps the book-routing test host
/// independent: we assert on the route's builder output (a pure widget
/// constructor), never on a rendered pdfx subtree (which throws
/// PlatformNotSupportedException on a headless host with no native PDF engine).
class _CapturingObserver extends NavigatorObserver {
  _CapturingObserver(this.pushed);

  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}

void main() {
  group('book asset is bundled and is a real PDF', () {
    test('the book PDF exists on disk at kFixYourOwnWifiBookAsset', () {
      final File book = File(kFixYourOwnWifiBookAsset);
      expect(
        book.existsSync(),
        isTrue,
        reason: 'the book PDF must exist at $kFixYourOwnWifiBookAsset '
            '(bundled in pubspec.yaml under assets/books/)',
      );
      // Non-trivial size — guards against an empty / truncated placeholder.
      expect(
        book.lengthSync(),
        greaterThan(1024),
        reason: 'the bundled book PDF looks empty/truncated',
      );
    });

    test('the bundled book begins with the %PDF- magic (swap-safe guard)', () {
      // The file is a near-final PLACEHOLDER Keith will swap for the final Vellum
      // export. This magic-byte check makes the swap safe: a non-PDF dropped at
      // this path fails CI before it can ship as the book.
      final List<int> head = File(kFixYourOwnWifiBookAsset).openSync().readSync(5);
      expect(
        String.fromCharCodes(head),
        '%PDF-',
        reason: 'the bundled book asset is not a PDF — check the swapped file',
      );
    });

    test('the book asset is declared in pubspec.yaml (ships in every build)', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains(kFixYourOwnWifiBookAsset),
        isTrue,
        reason: 'assets/books/fix-your-own-wifi.pdf must be declared in '
            'pubspec.yaml so it bundles offline into every build',
      );
    });
  });

  group('the home book callout routes to the offline PDF viewer', () {
    testWidgets('the "Fix Your Own Wi-Fi" entry renders in the front door', (
      tester,
    ) async {
      // markdown_widget's VisibilityDetector (sibling guide entry) leaves a
      // pending timer otherwise.
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      await _withViewport(tester, const Size(800, 1200), () async {
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();

        expect(find.text('Fix Your Own Wi-Fi'), findsOneWidget);
        expect(
          find.text('Learn and fix your Wi-Fi. The free book'),
          findsOneWidget,
        );
      });
    });

    testWidgets('tapping the entry opens PdfReferenceScreen on the book asset', (
      tester,
    ) async {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      final List<Route<dynamic>> pushed = <Route<dynamic>>[];
      final _CapturingObserver observer = _CapturingObserver(pushed);
      await _withViewport(tester, const Size(800, 1200), () async {
        await tester.pumpWidget(_app(observer: observer));
        await tester.pumpAndSettle();

        // Drop the initial home route so `pushed.last` is whatever the tap pushes.
        pushed.clear();
        await tester.tap(find.text('Fix Your Own Wi-Fi'));
        // DELIBERATELY no pump of the pushed route. The tap fires
        // Navigator.push synchronously, which notifies the observer (capturing
        // the route) — but the route's content is only built on a subsequent
        // frame. We never give it that frame, so PdfReferenceScreen is never
        // mounted and pdfx's initState/build (the only code that opens/renders a
        // PDF and throws PlatformNotSupportedException on a headless host) never
        // runs. The assertion reads the route's builder output, a pure const
        // widget constructor with no platform calls.

        expect(
          pushed,
          isNotEmpty,
          reason: 'tapping the book entry must push a route',
        );
        final Route<dynamic> route = pushed.last;
        expect(
          route,
          isA<MaterialPageRoute<dynamic>>(),
          reason: 'the book entry must push a MaterialPageRoute',
        );
        final BuildContext context = tester.element(find.byType(HomeScreen));
        final Widget routed =
            (route as MaterialPageRoute<dynamic>).builder(context);
        expect(routed, isA<PdfReferenceScreen>());
        final PdfReferenceScreen screen = routed as PdfReferenceScreen;
        expect(screen.assetPath, kFixYourOwnWifiBookAsset);
        expect(screen.title, 'Fix Your Own Wi-Fi');

        // Tear down without ever building the pushed pdfx route, then drain any
        // stray sync/async exception so nothing reaches teardown on either host.
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {});
        while (tester.takeException() != null) {}
      });
    });
  });
}
