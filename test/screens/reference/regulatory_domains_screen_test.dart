// Tests for the Regulatory Domains reference screen — the per-jurisdiction
// directory that supersedes the older region-level FCC / ETSI / ITU summary.
//
// Layers:
//   1. Data fidelity (GL-005): the snapshot date and a few load-bearing records
//      (FCC / Ofcom / ETSI) match the Pax-verified dataset, and the abbreviation-
//      collision flags (NCC, TRA, CRA) are set so the UI can disambiguate. Glyph
//      hygiene: no em dash, "Wi-Fi" not "WiFi".
//   2. Logo resolver: a missing logo degrades to the badge (no broken image);
//      a present logo resolves a path; colliding abbreviations get distinct keys.
//   3. Widget render: the snapshot banner is present; a known regulator renders;
//      search filters; the logo slot degrades to a badge when absent
//      (debugSetBundled empty) and renders an SvgPicture when present; the
//      website link is a tappable that fires the injected launcher; no overflow
//      at 320 / 768.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/regulatory_domains_data.dart';
import 'package:wlan_pros_toolbox/data/regulatory_logos.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/regulatory_domains_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  RegulatoryDomain domainFor(String jurisdiction) =>
      kRegulatoryDomains.firstWhere(
        (RegulatoryDomain d) => d.jurisdiction == jurisdiction,
      );

  group('dataset fidelity (GL-005)', () {
    test('snapshot date is the verified 2026-06-08 snapshot', () {
      expect(kRegulatorySnapshotDate, '2026-06-08');
      expect(
        RegulatoryDomainsScreen.snapshotCaveat.contains('2026-06-08'),
        isTrue,
      );
    });

    test('FCC / Ofcom / ETSI carry the right regulator + URL', () {
      final RegulatoryDomain us = domainFor('United States');
      expect(us.abbreviation, 'FCC');
      expect(us.regulatorName, 'Federal Communications Commission');
      expect(us.websiteUrl, 'https://www.fcc.gov');

      final RegulatoryDomain uk = domainFor('United Kingdom');
      expect(uk.abbreviation, 'Ofcom');
      expect(uk.websiteUrl, 'https://www.ofcom.org.uk');

      final RegulatoryDomain eu =
          domainFor('European Union (CEPT/ETSI bloc)');
      expect(eu.abbreviation, 'ETSI');
      expect(eu.websiteUrl, 'https://www.etsi.org');
    });

    test('colliding abbreviations are flagged and get distinct logo keys', () {
      final RegulatoryDomain ncc = domainFor('Taiwan');
      final RegulatoryDomain nccNg = domainFor('Nigeria');
      expect(ncc.abbreviation, 'NCC');
      expect(nccNg.abbreviation, 'NCC');
      expect(ncc.abbreviationCollides, isTrue);
      expect(nccNg.abbreviationCollides, isTrue);
      // Distinct asset keys so the two NCCs never collide on one logo file.
      expect(ncc.logoKey, isNot(nccNg.logoKey));

      final RegulatoryDomain traOm = domainFor('Oman');
      final RegulatoryDomain traBh = domainFor('Bahrain');
      expect(traOm.abbreviation, 'TRA');
      expect(traBh.abbreviation, 'TRA');
      expect(traOm.logoKey, isNot(traBh.logoKey));
      expect(traOm.logoKey, 'regulator-tra-om');
      expect(traBh.logoKey, 'regulator-tra-bh');

      expect(domainFor('Qatar').abbreviationCollides, isTrue); // CRA
    });

    test('logo keys are lower-cased regulator-<abbrev> slugs', () {
      expect(domainFor('United States').logoKey, 'regulator-fcc');
      expect(domainFor('United Kingdom').logoKey, 'regulator-ofcom');
    });

    test('no em dash; Wi-Fi never WiFi in prose fields', () {
      for (final RegulatoryDomain d in kRegulatoryDomains) {
        final List<String> prose = <String>[
          d.jurisdiction,
          d.regulatorName,
          d.governingDocs,
          d.bandNotes,
        ];
        for (final String s in prose) {
          expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
          expect(s.contains('WiFi'), isFalse, reason: '"WiFi" in "$s"');
          expect(s.contains('802.1x'), isFalse, reason: 'lowercase x in "$s"');
        }
      }
    });
  });

  group('RegulatoryLogos resolver', () {
    tearDown(RegulatoryLogos.debugReset);

    test('missing logo → has() false, path() null (degrade to badge)', () {
      RegulatoryLogos.debugSetBundled(const <String>{});
      expect(RegulatoryLogos.has('regulator-fcc'), isFalse);
      expect(RegulatoryLogos.path('regulator-fcc'), isNull);
    });

    test('present SVG logo → has() true, path() resolves, isSvg true', () {
      RegulatoryLogos.debugSetBundled(<String>{
        'assets/regulator-logos/regulator-fcc.svg',
      });
      expect(RegulatoryLogos.has('regulator-fcc'), isTrue);
      expect(RegulatoryLogos.path('regulator-fcc'),
          'assets/regulator-logos/regulator-fcc.svg');
      expect(RegulatoryLogos.isSvg('regulator-fcc'), isTrue);
    });

    test('PNG logo resolves with isSvg false', () {
      RegulatoryLogos.debugSetBundled(<String>{
        'assets/regulator-logos/regulator-ofcom.png',
      });
      expect(RegulatoryLogos.has('regulator-ofcom'), isTrue);
      expect(RegulatoryLogos.isSvg('regulator-ofcom'), isFalse);
    });
  });

  group('RegulatoryDomainsScreen widget', () {
    setUp(() {
      // No logo bundled by default → every row shows its abbreviation badge.
      RegulatoryLogos.debugSetBundled(const <String>{});
    });
    tearDown(RegulatoryLogos.debugReset);

    testWidgets('snapshot banner is present and a known regulator renders',
        (tester) async {
      await _withViewport(tester, const Size(390, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RegulatoryDomainsScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('Regulatory Domains'), findsWidgets);
        // The ONE prominent snapshot banner.
        expect(find.text('SNAPSHOT VERIFIED 2026-06-08'), findsOneWidget);
        // A known regulator renders.
        expect(find.text('United States'), findsOneWidget);
        expect(find.text('Federal Communications Commission'), findsOneWidget);
      });
    });

    testWidgets('search filters the list as the user types', (tester) async {
      await _withViewport(tester, const Size(390, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RegulatoryDomainsScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('United Kingdom'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'ofcom');
        await tester.pumpAndSettle();

        // Ofcom (UK) survives the filter; FCC (US) is filtered out.
        expect(find.text('United Kingdom'), findsOneWidget);
        expect(find.text('United States'), findsNothing);
      });
    });

    testWidgets('logo slot degrades to a badge when no logo is bundled',
        (tester) async {
      // Default setUp bundled nothing → no SvgPicture, badges instead.
      await _withViewport(tester, const Size(390, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: RegulatoryDomainsScreen(
              domains: <RegulatoryDomain>[domainFor('United States')],
            ),
          ),
        );
        await tester.pump();

        // No logo asset → no SvgPicture; the abbreviation badge renders instead.
        expect(find.byType(SvgPicture), findsNothing);
        // The badge carries the abbreviation glyphs (FCC). Multiple "FCC" texts
        // exist (badge + accent abbreviation line); at least one is present.
        expect(find.text('FCC'), findsWidgets);
      });
    });

    testWidgets('logo slot renders an SvgPicture when the logo is bundled',
        (tester) async {
      RegulatoryLogos.debugSetBundled(<String>{
        'assets/regulator-logos/regulator-fcc.svg',
      });
      addTearDown(RegulatoryLogos.debugReset);

      await _withViewport(tester, const Size(390, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: RegulatoryDomainsScreen(
              domains: <RegulatoryDomain>[domainFor('United States')],
            ),
          ),
        );
        await tester.pump();

        // Bundled logo → the SVG slot renders (proves the gated wiring).
        expect(find.byType(SvgPicture), findsOneWidget);
      });
    });

    testWidgets('website link is tappable and fires the injected launcher',
        (tester) async {
      Uri? launched;
      await _withViewport(tester, const Size(390, 2000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: RegulatoryDomainsScreen(
              domains: <RegulatoryDomain>[domainFor('United States')],
              launcher: (Uri u) async {
                launched = u;
                return true;
              },
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('https://www.fcc.gov'));
        await tester.pump();

        expect(launched, isNotNull);
        expect(launched.toString(), 'https://www.fcc.gov');
      });
    });

    testWidgets('renders without overflow at 320 and 768 widths',
        (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 3000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const RegulatoryDomainsScreen(),
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
