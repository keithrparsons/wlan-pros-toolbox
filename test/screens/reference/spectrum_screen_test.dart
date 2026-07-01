// Tests for the Spectrum Ref reference screen.
//
// Two layers (mirrors wifi_channels_screen_test.dart):
//  1. Data assertions against the public `SpectrumScreen.bands` const — the
//     same single source the UI renders. Locks the key frequency allocations
//     (2.4 / 5 / 6 GHz ranges, UNII DFS sub-bands, channel counts) to the
//     values ported from the rf-tools-pwa `spectrum` tool (www/app.js:
//     buildSpectrumRef() `bands`). Catches any silent drift from the PWA.
//  2. One widget test in a phone viewport — pumps the screen, asserts the
//     title and default (2.4 GHz) fact sheet render, then switches to 6 GHz
//     and checks a 6 GHz fact appears, all without overflow.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/spectrum_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('SpectrumScreen dataset', () {
    SpectrumBandInfo bandOf(SpectrumBand b) =>
        SpectrumScreen.bands.firstWhere((SpectrumBandInfo i) => i.band == b);

    test('covers exactly the three bands, in 2.4 / 5 / 6 order', () {
      expect(
        SpectrumScreen.bands.map((SpectrumBandInfo i) => i.band),
        <SpectrumBand>[
          SpectrumBand.ghz24,
          SpectrumBand.ghz5,
          SpectrumBand.ghz6,
        ],
      );
    });

    test('2.4 GHz spans 2400-2483.5 MHz with 83.5 MHz total (US), without Ch 14',
        () {
      // App-wide the 2.4 GHz band is stated WITHOUT Ch 14 (Keith, 2026-06-30),
      // matching the band reference (rf_bands_data.dart): the ISM edge is
      // 2483.5 MHz, an 83.5 MHz span. Ch 14's 2484 MHz center sits above it.
      final SpectrumBandInfo b = bandOf(SpectrumBand.ghz24);
      expect(b.range, '2400 - 2483.5 MHz');
      expect(b.total, '83.5 MHz (US)');
      expect(b.nonOverlap, '3 channels at 20 MHz: 1, 6, 11');
    });

    test('5 GHz UNII-1 begins at 5150 MHz and band spans to 5850 MHz', () {
      final SpectrumBandInfo b = bandOf(SpectrumBand.ghz5);
      expect(b.range, '5150 - 5850 MHz (US UNII-1/2A/2C/3)');
      expect(b.total, '~580 MHz usable (US UNII-1/2A/2C/3)');
    });

    test('5 GHz DFS row names the UNII-2A 5250-5350 and 2C 5470-5725 ranges',
        () {
      final SpectrumBandInfo b = bandOf(SpectrumBand.ghz5);
      expect(b.dfs, contains('UNII-2A (5250-5350 MHz)'));
      expect(b.dfs, contains('UNII-2C (5470-5725 MHz)'));
    });

    test('6 GHz spans 5925-7125 MHz with 1200 MHz total', () {
      final SpectrumBandInfo b = bandOf(SpectrumBand.ghz6);
      expect(b.range, '5925 - 7125 MHz');
      expect(b.total, '1200 MHz');
    });

    test('6 GHz lists 14 PSC channels and AFC (no DFS)', () {
      final SpectrumBandInfo b = bandOf(SpectrumBand.ghz6);
      expect(b.nonOverlap, contains('14 PSC'));
      expect(b.dfs, contains('No DFS'));
      expect(b.dfs, contains('AFC'));
    });

    test('every band exposes all eight fact rows in PWA order', () {
      for (final SpectrumBandInfo b in SpectrumScreen.bands) {
        expect(
          b.facts.map((f) => f.$1),
          <String>[
            'Total spectrum',
            'Standards',
            'Channels (US)',
            'Non-overlapping',
            'Channel widths',
            'DFS / Radar',
            'Co-existence',
            'Key notes',
          ],
          reason: '${b.label} must carry the eight PWA fact rows in order',
        );
        // No fact may be blank — every value is ported, none fabricated/empty.
        for (final (String k, String v) in b.facts) {
          expect(v.trim(), isNotEmpty, reason: '${b.label} / $k is empty');
        }
      }
    });

    test('co-existence row carries the band common interferers', () {
      expect(bandOf(SpectrumBand.ghz24).coexist, contains('Bluetooth'));
      expect(bandOf(SpectrumBand.ghz5).coexist, contains('radar'));
      expect(bandOf(SpectrumBand.ghz6).coexist, contains('microwave backhaul'));
    });
  });

  group('Regulatory domains by geography (BF6-12)', () {
    RegulatoryDomain byGeo(String name) => SpectrumScreen.regulatoryDomains
        .firstWhere((RegulatoryDomain d) => d.geography == name);

    test('carries the major geographies with their regulators', () {
      expect(byGeo('United States').acronym, 'FCC');
      expect(byGeo('Canada').acronym, 'ISED (IC)');
      expect(byGeo('United Kingdom').acronym, 'Ofcom');
      expect(byGeo('European Union').acronym, 'ETSI');
      expect(byGeo('Australia').acronym, 'ACMA');
      expect(byGeo('Japan').acronym, 'MIC');
    });

    test('lists at least the six core domains plus a few more', () {
      expect(
        SpectrumScreen.regulatoryDomains.length,
        greaterThanOrEqualTo(6),
      );
    });

    test('no domain row has an empty field', () {
      for (final RegulatoryDomain d in SpectrumScreen.regulatoryDomains) {
        expect(d.geography.trim(), isNotEmpty);
        expect(d.regulator.trim(), isNotEmpty);
        expect(d.acronym.trim(), isNotEmpty);
      }
    });
  });

  group('SpectrumScreen widget', () {
    testWidgets('renders title + 2.4 GHz fact sheet, switches to 6 GHz, '
        'in a 375x900 phone viewport without overflow', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        final List<Object> overflow = <Object>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          if (details.exception.toString().contains('overflowed')) {
            overflow.add(details.exception);
          }
        };
        addTearDown(() => FlutterError.onError = previous);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const SpectrumScreen()),
        );
        await tester.pump();

        // Title + default 2.4 GHz fact sheet.
        expect(find.text('Spectrum Ref'), findsOneWidget);
        expect(find.text('2400 - 2483.5 MHz'), findsOneWidget);
        expect(find.text('83.5 MHz (US)'), findsOneWidget);

        // Switch to 6 GHz and confirm a 6 GHz fact appears.
        await tester.tap(find.text('6 GHz'));
        await tester.pumpAndSettle();
        expect(find.text('5925 - 7125 MHz'), findsOneWidget);
        expect(find.text('1200 MHz'), findsOneWidget);

        expect(
          overflow,
          isEmpty,
          reason: 'Spectrum screen overflowed at 375x900: '
              '${overflow.map((Object e) => e.toString()).join("; ")}',
        );
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1200), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: const SpectrumScreen()),
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
/// Mirrors test/widget_test.dart `_withViewport`.
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
