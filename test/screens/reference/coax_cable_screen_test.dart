// Tests for the Coax Cable reference screen.
//
// The dataset originated as a verbatim port of the RF Tools PWA (app.js
// COAX_DATA). Wave-2 (2026-07-12, finding E) replaced the PWA's placeholder
// maxGhz column — a distributor "max operating frequency" catalog cap the PWA
// had copied and rounded to a uniform 6.0 GHz — with the true TE11 mode-cutoff
// (physics maximum) per L-com published datasheet cutoff rows / the validated
// computation. The LMR-100A velocity factor was also corrected 80 -> 66% per
// the Times/Pasternack datasheet. These tests pin the corrected values so a
// future edit cannot silently drift them, plus one phone-viewport widget test
// confirming the read-only screen renders without a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/coax_cable_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('coax data — physics-cutoff maxGhz (Wave-2 finding E)', () {
    CoaxCable cableFor(String name) =>
        CoaxCableScreen.coaxData.firstWhere((CoaxCable c) => c.name == name);

    test('eleven cable rows', () {
      expect(CoaxCableScreen.coaxData.length, 11);
    });

    test('LMR-400 is the standard Wi-Fi run: 50Ω, VF 85, 10.8 mm, 16.2 GHz', () {
      // maxGhz = 16.2 GHz TE11 cutoff (L-com LMR-400 datasheet published cutoff;
      // was a placeholder 6.0). Finding E §2.2/§2.3.
      final CoaxCable c = cableFor('LMR-400');
      expect(c.impedance, '50Ω');
      expect(c.vf, 85);
      expect(c.diameterMm, 10.8);
      expect(c.maxGhz, 16.2);
      expect(c.use, 'Standard Wi-Fi / cellular run');
    });

    test('RG-58 anchors the table: 50Ω, VF 66, 5.0 mm, 1 GHz', () {
      final CoaxCable c = cableFor('RG-58');
      expect(c.impedance, '50Ω');
      expect(c.vf, 66);
      expect(c.diameterMm, 5.0);
      expect(c.maxGhz, 1.0);
    });

    test('LMR-1200 safety fix: cutoff 5.2 GHz (below 6 GHz Wi-Fi), VF 88', () {
      // THE danger cell: the PWA showed 6.0 GHz, overstating a cable whose TE11
      // mode cutoff is 5.2 GHz. Finding E §2.3/§2.4.
      final CoaxCable c = cableFor('LMR-1200');
      expect(c.vf, 88);
      expect(c.diameterMm, 30.0);
      expect(c.maxGhz, 5.2);
    });

    test('LMR-100A velocity factor is 66% (datasheet), not 80%', () {
      // Times/Pasternack LMR-100A-FR datasheet VoP = 66%. Finding E §2.5.
      final CoaxCable c = cableFor('LMR-100A');
      expect(c.vf, 66);
      expect(c.maxGhz, 62.0);
    });

    test('the physics-cutoff set matches finding E for all six LMR cables', () {
      // L-com published cutoffs (200/400/600/1200) + validated computation
      // (100A/900). Finding E §2.3. No LMR cable still carries the 6.0 placeholder.
      final Map<String, double> expected = <String, double>{
        'LMR-100A': 62.0,
        'LMR-200': 39.0,
        'LMR-400': 16.2,
        'LMR-600': 10.3,
        'LMR-900': 7.0,
        'LMR-1200': 5.2,
      };
      expected.forEach((String name, double ghz) {
        expect(cableFor(name).maxGhz, ghz, reason: '$name cutoff');
      });
      expect(
        CoaxCableScreen.coaxData
            .where((CoaxCable c) => c.name.startsWith('LMR'))
            .every((CoaxCable c) => c.maxGhz != 6.0),
        isTrue,
        reason: 'no LMR cable keeps the placeholder 6.0 GHz',
      );
    });

    test('RG-6 is the only 75Ω entry and is flagged mismatched', () {
      final CoaxCable c = cableFor('RG-6');
      expect(c.impedance, '75Ω');
      expect(c.isMismatched, isTrue);
      // Exactly one 75Ω entry — every other cable is 50Ω.
      final int mismatched =
          CoaxCableScreen.coaxData.where((CoaxCable x) => x.isMismatched).length;
      expect(mismatched, 1);
    });

    test('every row uses ASCII hyphen-minus (no em dash, no Unicode minus)', () {
      for (final CoaxCable c in CoaxCableScreen.coaxData) {
        expect(c.name.contains('—'), isFalse, reason: 'no em dash in name');
        expect(c.use.contains('—'), isFalse, reason: 'no em dash in use');
        expect(c.name.contains('−'), isFalse, reason: 'no Unicode minus');
      }
      // The footnote keeps the data-glyph hyphen but never an em dash.
      expect(CoaxCableScreen.footnote.contains('—'), isFalse);
    });
  });

  group('CoaxCableScreen widget', () {
    testWidgets('renders title, heading, and anchor rows in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CoaxCableScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('Coax Cable'), findsWidgets);
        expect(find.text('Coax Cable Types'), findsOneWidget);
        // Load-bearing cable names render verbatim from the PWA dataset.
        expect(find.text('LMR-400'), findsOneWidget);
        expect(find.text('RG-58'), findsOneWidget);
        expect(find.text('RG-6'), findsOneWidget);
        // The typical-use note for the standard Wi-Fi run renders.
        expect(find.text('Standard Wi-Fi / cellular run'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CoaxCableScreen()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart _withViewport so the read-only reference
/// renders at phone width without a RenderFlex overflow.
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
