// Tests for the Modulation Quick Reference screen.
//
// Coverage:
// - Dataset: the eight diagrams (six constellations in rising density + EVM
//   explainer + summary), their slugs, titles, and asset-path convention.
// - Graceful degradation (the load-bearing contract): when the manifest reports
//   the PNGs bundled, eight DarkRasterDiagramCards render; when nothing is
//   bundled, zero render and the screen still shows its intro + caveat (no broken
//   box, no crash). Mirrors the throughput-where / speedtest gating test.
// - The §8.16 Copy affordance exists and the summary copy carries the order ->
//   bits -> SNR/EVM table plus the representative-numbers caveat.
// - The representative-numbers caveat is shown as on-screen text (GL-005).
// - No RenderFlex overflow at 320/375/768/1280 widths.
// - No em dash in any authored string (house rule).
//
// The diagram PNGs are 2160×2700 source rasters; in the test environment
// Image.asset has no real bytes to decode, but the card's errorBuilder collapses
// it to SizedBox.shrink without throwing, so the screen pumps cleanly with the
// assets marked "bundled".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/modulation_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/modulation_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  tearDown(ModulationDiagrams.debugReset);

  group('ModulationDiagrams dataset', () {
    test('lists the eight diagrams in teaching order', () {
      expect(
        ModulationDiagrams.all.map((ModulationDiagram d) => d.slug).toList(),
        <String>[
          'constellation-bpsk',
          'constellation-qpsk',
          'constellation-16-qam',
          'constellation-64-qam',
          'constellation-256-qam',
          'constellation-1024-qam',
          'evm-error-vector-magnitude',
          'summary-order-bits-snr-evm',
        ],
      );
    });

    test('every diagram carries a non-empty title', () {
      for (final ModulationDiagram d in ModulationDiagrams.all) {
        expect(d.title, isNotEmpty, reason: d.slug);
      }
    });

    test('pathFor follows the assets/tool-diagrams/modulation convention', () {
      expect(
        ModulationDiagrams.pathFor('constellation-16-qam'),
        'assets/tool-diagrams/modulation/constellation-16-qam.png',
      );
    });

    test('isBundled gates on the manifest set', () {
      ModulationDiagrams.debugSetBundled(<String>{
        ModulationDiagrams.pathFor('constellation-bpsk'),
      });
      expect(ModulationDiagrams.isBundled('constellation-bpsk'), isTrue);
      expect(ModulationDiagrams.isBundled('constellation-qpsk'), isFalse);
    });

    test('no em dash in any title (house rule)', () {
      for (final ModulationDiagram d in ModulationDiagrams.all) {
        expect(d.title.contains('—'), isFalse, reason: d.slug);
      }
    });
  });

  group('ModulationScreen render', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const ModulationScreen()),
      );
      await tester.pump();
    }

    testWidgets('renders all eight diagram cards when bundled', (tester) async {
      ModulationDiagrams.debugSetBundled(<String>{
        for (final ModulationDiagram d in ModulationDiagrams.all)
          ModulationDiagrams.pathFor(d.slug),
      });
      await pumpScreen(tester);
      expect(find.byType(DarkRasterDiagramCard), findsNWidgets(8));
    });

    testWidgets('renders zero diagram cards but still shows intro when nothing '
        'is bundled', (tester) async {
      ModulationDiagrams.debugSetBundled(<String>{});
      await pumpScreen(tester);
      expect(find.byType(DarkRasterDiagramCard), findsNothing);
      // The teaching intro and the representative-numbers caveat still read.
      expect(find.textContaining('constellation maps'), findsOneWidget);
      expect(
        find.textContaining('representative order-of-magnitude'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes the Copy affordance carrying the summary + caveat',
        (tester) async {
      ModulationDiagrams.debugSetBundled(<String>{});
      await pumpScreen(tester);
      final Finder copy = find.byType(AppCopyAction);
      expect(copy, findsOneWidget);
      // The copy text builder runs at tap time; assert its content directly.
      final AppCopyAction action = tester.widget<AppCopyAction>(copy);
      final String? payload = action.textBuilder();
      expect(payload, isNotNull);
      expect(payload, contains('Modulation'));
      expect(payload, contains('1024-QAM\t1024\t10\t34 dB\t-35 dB'));
      expect(payload, contains('representative order-of-magnitude'));
      expect(payload!.contains('—'), isFalse); // no em dash
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      ModulationDiagrams.debugSetBundled(<String>{
        for (final ModulationDiagram d in ModulationDiagrams.all)
          ModulationDiagrams.pathFor(d.slug),
      });
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final double width in <double>[320, 375, 768, 1280]) {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        await pumpScreen(tester);
        expect(tester.takeException(), isNull,
            reason: 'overflow at ${width}px');
      }
    });
  });
}
