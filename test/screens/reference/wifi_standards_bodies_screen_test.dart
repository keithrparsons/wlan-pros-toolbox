// Tests for the Wi-Fi Standards & Industry Bodies reference screen.
//
// Layers:
//   1. Data fidelity (GL-005 + Keith's decisions): IEEE is ONE tile; Ecma is
//      kept and flagged context-only; the load-bearing bodies (IEEE, Wi-Fi
//      Alliance, ITU-R, ETSI) carry the right abbreviation, layer, and URL.
//      Glyph hygiene: no em dash, "Wi-Fi" not "WiFi", "802.1X" not "802.1x".
//   2. Logo resolver: a missing wordmark degrades to the badge (no broken
//      image); a present wordmark resolves a path; key is body-<abbrev>.
//   3. Widget render: the three-layer callout and the trademark callout are
//      present; the layer headers render; tiles render grouped by layer; the
//      context-only chip shows on Ecma; search filters; the logo slot degrades
//      to a badge when absent and renders an SvgPicture when present; the
//      website link fires the injected launcher; the regulator cross-link is
//      present; no overflow at 320 / 768.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/wifi_bodies_data.dart';
import 'package:wlan_pros_toolbox/data/wifi_bodies_logos.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_standards_bodies_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  WifiBody bodyFor(String abbrev) => kWifiBodies.firstWhere(
        (WifiBody b) => b.abbreviation == abbrev,
      );

  group('dataset fidelity (GL-005 + Keith decisions)', () {
    test('IEEE is ONE tile, named for the 802.11 Working Group', () {
      final List<WifiBody> ieee = kWifiBodies
          .where((WifiBody b) => b.abbreviation == 'IEEE')
          .toList();
      expect(ieee.length, 1, reason: 'IEEE must be a single tile, not split');
      expect(ieee.single.name, contains('802.11 Working Group'));
      expect(ieee.single.layer, BodyLayer.standards);
      expect(ieee.single.websiteUrl, 'https://www.ieee802.org/11/');
    });

    test('Ecma is kept and flagged context-only', () {
      final WifiBody ecma = bodyFor('Ecma');
      expect(ecma.contextOnly, isTrue);
      // It is the only context-only body.
      expect(
        kWifiBodies.where((WifiBody b) => b.contextOnly).length,
        1,
      );
    });

    test('load-bearing bodies carry the right layer + URL', () {
      final WifiBody wfa = bodyFor('WFA');
      expect(wfa.name, 'Wi-Fi Alliance');
      expect(wfa.layer, BodyLayer.certification);
      expect(wfa.websiteUrl, 'https://www.wi-fi.org');

      final WifiBody itu = bodyFor('ITU-R');
      expect(itu.layer, BodyLayer.spectrum);
      expect(itu.websiteUrl, 'https://www.itu.int/en/ITU-R/');

      final WifiBody etsi = bodyFor('ETSI');
      expect(etsi.layer, BodyLayer.standards);
      expect(etsi.websiteUrl, 'https://www.etsi.org');
    });

    test('every layer has at least one body; spectrum has ITU-R', () {
      for (final BodyLayer layer in BodyLayer.values) {
        expect(
          kWifiBodies.any((WifiBody b) => b.layer == layer),
          isTrue,
          reason: 'layer $layer is empty',
        );
      }
      final List<WifiBody> spectrum =
          kWifiBodies.where((WifiBody b) => b.layer == BodyLayer.spectrum).toList();
      expect(spectrum.single.abbreviation, 'ITU-R');
    });

    test('logo keys are lower-cased body-<abbrev> slugs', () {
      expect(bodyFor('WFA').logoKey, 'body-wfa');
      expect(bodyFor('IEEE').logoKey, 'body-ieee');
      expect(bodyFor('ITU-R').logoKey, 'body-itu-r');
      expect(bodyFor('Bluetooth SIG').logoKey, 'body-bluetooth-sig');
    });

    test('no em dash; Wi-Fi never WiFi; 802.1X never 802.1x in prose', () {
      for (final WifiBody b in kWifiBodies) {
        final List<String> prose = <String>[
          b.name,
          b.roleType,
          b.owns,
          b.whyCare,
        ];
        for (final String s in prose) {
          expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
          expect(s.contains('WiFi'), isFalse, reason: '"WiFi" in "$s"');
          expect(s.contains('802.1x'), isFalse, reason: 'lowercase x in "$s"');
        }
      }
    });
  });

  group('WifiBodiesLogos resolver', () {
    tearDown(WifiBodiesLogos.debugReset);

    test('missing logo → has() false, path() null (degrade to badge)', () {
      WifiBodiesLogos.debugSetBundled(const <String>{});
      expect(WifiBodiesLogos.has('body-wfa'), isFalse);
      expect(WifiBodiesLogos.path('body-wfa'), isNull);
    });

    test('present SVG logo → has() true, path() resolves, isSvg true', () {
      WifiBodiesLogos.debugSetBundled(<String>{
        'assets/standards-body-logos/body-wfa.svg',
      });
      expect(WifiBodiesLogos.has('body-wfa'), isTrue);
      expect(WifiBodiesLogos.path('body-wfa'),
          'assets/standards-body-logos/body-wfa.svg');
      expect(WifiBodiesLogos.isSvg('body-wfa'), isTrue);
    });

    test('PNG logo resolves with isSvg false', () {
      WifiBodiesLogos.debugSetBundled(<String>{
        'assets/standards-body-logos/body-ieee.png',
      });
      expect(WifiBodiesLogos.has('body-ieee'), isTrue);
      expect(WifiBodiesLogos.isSvg('body-ieee'), isFalse);
    });
  });

  group('WifiStandardsBodiesScreen widget', () {
    setUp(() {
      // No logo bundled by default → every tile shows its abbreviation badge.
      WifiBodiesLogos.debugSetBundled(const <String>{});
    });
    tearDown(WifiBodiesLogos.debugReset);

    testWidgets('lead callouts and a known body render', (tester) async {
      await _withViewport(tester, const Size(390, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const WifiStandardsBodiesScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('Wi-Fi Standards Bodies'), findsWidgets);
        // The three-layer teaching callout.
        expect(find.text('THREE LAYERS, THREE DIFFERENT JOBS'), findsOneWidget);
        // The IEEE-vs-WFA / trademark callout.
        expect(find.text('The one to get right'), findsOneWidget);
        // A layer header renders.
        expect(find.text('DEFINES THE RADIO'), findsOneWidget);
        // A known body renders.
        expect(find.text('Wi-Fi Alliance'), findsOneWidget);
      });
    });

    testWidgets('Ecma carries a CONTEXT ONLY chip', (tester) async {
      await _withViewport(tester, const Size(390, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: WifiStandardsBodiesScreen(
              bodies: <WifiBody>[bodyFor('Ecma')],
            ),
          ),
        );
        await tester.pump();

        expect(find.text('CONTEXT ONLY'), findsOneWidget);
        expect(find.text('Ecma International'), findsOneWidget);
      });
    });

    testWidgets('regulator cross-link to Regulatory Domains is present',
        (tester) async {
      // Tall surface: the lazy ListView only builds visible rows, and the new
      // IoT-adjacent layer (2026-06-09) pushed the regulator cross-link card
      // below the old 6000px viewport, so give it room to build.
      await _withViewport(tester, const Size(390, 14000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const WifiStandardsBodiesScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('REGULATES PER COUNTRY'), findsOneWidget);
      });
    });

    testWidgets('search filters the list as the user types', (tester) async {
      await _withViewport(tester, const Size(390, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const WifiStandardsBodiesScreen(),
          ),
        );
        await tester.pump();

        // "OpenRoaming" lives only in the WBA tile's owns/why-care prose.
        await tester.enterText(find.byType(TextField), 'openroaming');
        await tester.pumpAndSettle();

        expect(find.text('Wireless Broadband Alliance'), findsOneWidget);
        expect(find.text('Wi-Fi Alliance'), findsNothing);
      });
    });

    testWidgets('logo slot degrades to a badge when no logo is bundled',
        (tester) async {
      await _withViewport(tester, const Size(390, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: WifiStandardsBodiesScreen(
              bodies: <WifiBody>[bodyFor('WFA')],
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(SvgPicture), findsNothing);
        // The badge carries the abbreviation glyphs (WFA appears in the badge
        // and the accent abbreviation line).
        expect(find.text('WFA'), findsWidgets);
      });
    });

    testWidgets('logo slot renders an SvgPicture when the wordmark is bundled',
        (tester) async {
      WifiBodiesLogos.debugSetBundled(<String>{
        'assets/standards-body-logos/body-wfa.svg',
      });
      addTearDown(WifiBodiesLogos.debugReset);

      await _withViewport(tester, const Size(390, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: WifiStandardsBodiesScreen(
              bodies: <WifiBody>[bodyFor('WFA')],
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(SvgPicture), findsOneWidget);
      });
    });

    testWidgets('website link is tappable and fires the injected launcher',
        (tester) async {
      Uri? launched;
      await _withViewport(tester, const Size(390, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: WifiStandardsBodiesScreen(
              bodies: <WifiBody>[bodyFor('WFA')],
              launcher: (Uri u) async {
                launched = u;
                return true;
              },
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('https://www.wi-fi.org'));
        await tester.pump();

        expect(launched, isNotNull);
        expect(launched.toString(), 'https://www.wi-fi.org');
      });
    });

    testWidgets('renders without overflow at 320 and 768 widths',
        (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const WifiStandardsBodiesScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
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
