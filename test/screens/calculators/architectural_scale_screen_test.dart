// Tests for the Architectural Scale calculator.
//
// The math is pure and unit-agnostic once a scale reduces to its ratio R
// (= real ÷ drawn, dimensionless). Expected values below are derived from the
// imperial rule (12 ÷ inches-per-foot), the engineer's rule (feet-per-inch ×
// 12), and the millimetre-base unit conversions, so the app agrees to the
// decimal with a hand check.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/architectural_scale_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

void main() {
  group('Scale ratios (pure) — imperial / engineer\'s / metric rules', () {
    test('architectural fractional-inch ratios', () {
      expect(ArchitecturalScaleScreen.scaleById('1-4in-1ft').ratio, 48);
      expect(ArchitecturalScaleScreen.scaleById('1-8in-1ft').ratio, 96);
      expect(ArchitecturalScaleScreen.scaleById('1-2in-1ft').ratio, 24);
      expect(ArchitecturalScaleScreen.scaleById('1in-1ft').ratio, 12);
      expect(ArchitecturalScaleScreen.scaleById('1-16in-1ft').ratio, 192);
    });

    test('engineer\'s decimal ratios', () {
      expect(ArchitecturalScaleScreen.scaleById('1in-20ft').ratio, 240);
      expect(ArchitecturalScaleScreen.scaleById('1in-50ft').ratio, 600);
      expect(ArchitecturalScaleScreen.scaleById('1in-100ft').ratio, 1200);
    });

    test('metric ratios are the scale itself', () {
      expect(ArchitecturalScaleScreen.scaleById('metric-1-50').ratio, 50);
      expect(ArchitecturalScaleScreen.scaleById('metric-1-100').ratio, 100);
    });

    test('ratioLabel renders 1:N', () {
      expect(ArchitecturalScaleScreen.scaleById('1-4in-1ft').ratioLabel, '1:48');
      expect(ArchitecturalScaleScreen.scaleById('metric-1-100').ratioLabel, '1:100');
    });

    test('the catalog default is 1/4" = 1\'-0" (1:48)', () {
      final s = ArchitecturalScaleScreen.scaleById(
        ArchitecturalScaleScreen.defaultScaleId,
      );
      expect(s.ratio, 48);
      expect(s.family, ScaleFamily.architectural);
    });

    test('every scale id is unique and every ratio is finite and positive', () {
      final ids = ArchitecturalScaleScreen.scales.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final s in ArchitecturalScaleScreen.scales) {
        expect(s.ratio.isFinite && s.ratio > 0, isTrue, reason: s.id);
      }
    });
  });

  group('Drawn ↔ real (pure) — matches the hand check', () {
    test('3.5 in on a 1:96 sheet is 28 ft', () {
      expect(
        ArchitecturalScaleScreen.drawnToReal(
          3.5, DrawnUnit.inches, 96, RealUnit.feet),
        closeTo(28.0, 1e-9),
      );
    });

    test('45 ft real at 1:48 draws at 11.25 in', () {
      expect(
        ArchitecturalScaleScreen.realToDrawn(
          45, RealUnit.feet, 48, DrawnUnit.inches),
        closeTo(11.25, 1e-9),
      );
    });

    test('metric: 100 mm on a 1:50 plan is 5 m', () {
      expect(
        ArchitecturalScaleScreen.drawnToReal(
          100, DrawnUnit.mm, 50, RealUnit.meters),
        closeTo(5.0, 1e-9),
      );
    });

    test('metric reverse: 5 m real at 1:50 draws at 100 mm', () {
      expect(
        ArchitecturalScaleScreen.realToDrawn(
          5, RealUnit.meters, 50, DrawnUnit.mm),
        closeTo(100.0, 1e-9),
      );
    });

    test('drawn→real and real→drawn are inverses (cross-unit)', () {
      const double ratio = 48;
      final real = ArchitecturalScaleScreen.drawnToReal(
          2.5, DrawnUnit.inches, ratio, RealUnit.meters);
      final backToDrawn = ArchitecturalScaleScreen.realToDrawn(
          real, RealUnit.meters, ratio, DrawnUnit.inches);
      expect(backToDrawn, closeTo(2.5, 1e-9));
    });

    test('cm drawing unit converts (10 cm on 1:100 is 10 m)', () {
      expect(
        ArchitecturalScaleScreen.drawnToReal(
            10, DrawnUnit.cm, 100, RealUnit.meters),
        closeTo(10.0, 1e-9),
      );
    });
  });

  group('Formatting (pure)', () {
    test('feet-inches from decimal feet', () {
      expect(ArchitecturalScaleScreen.formatFeetInches(28.0), '28 ft 0 in');
      expect(ArchitecturalScaleScreen.formatFeetInches(28.5), '28 ft 6 in');
      // 11.9166.. ft rounds inches up and carries at 12.
      expect(ArchitecturalScaleScreen.formatFeetInches(11.99), '12 ft 0 in');
    });

    test('nearest-1/16 inch fraction, reduced', () {
      expect(ArchitecturalScaleScreen.formatInchFraction(11.25), '11-1/4 in');
      expect(ArchitecturalScaleScreen.formatInchFraction(0.5), '1/2 in');
      expect(ArchitecturalScaleScreen.formatInchFraction(12.0), '12 in');
      expect(ArchitecturalScaleScreen.formatInchFraction(3.0625), '3-1/16 in');
    });

    test('general length format trims whole numbers', () {
      expect(ArchitecturalScaleScreen.fmtLength(28.0), '28');
      expect(ArchitecturalScaleScreen.fmtLength(11.25), '11.25');
      expect(ArchitecturalScaleScreen.fmtLength(null), '—');
      expect(ArchitecturalScaleScreen.fmtLength(double.infinity), '—');
    });

    test('ratio number trims whole vs fractional', () {
      expect(ArchitecturalScaleScreen.trimRatio(48), '48');
      expect(ArchitecturalScaleScreen.trimRatio(48.5), '48.50');
    });
  });

  group('ArchitecturalScaleScreen widget', () {
    testWidgets('renders title, selectors, and the default ratio', (tester) async {
      await _withViewport(tester, const Size(390, 1000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ArchitecturalScaleScreen(),
          ),
        );

        expect(find.text('Architectural Scale'), findsWidgets);
        expect(find.text('Scale family'), findsOneWidget);
        expect(find.text('Scale'), findsOneWidget);
        // Two AppSelects: family + scale.
        expect(find.byType(AppSelect<ScaleFamily>), findsOneWidget);
        expect(find.byType(AppSelect<String>), findsOneWidget);
        // The default scale 1/4" = 1'-0" shows its ratio 1:48 (readout + likely
        // the reference row) — at least once.
        expect(find.text('1:48'), findsWidgets);
      });
    });

    testWidgets('drawn→real: 3.5 in on the default 1/4" (1:48) sheet reads 14 ft',
        (tester) async {
      await _withViewport(tester, const Size(390, 1000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ArchitecturalScaleScreen(),
          ),
        );

        // Default direction Drawn → Real, default units in / ft, default scale
        // 1/4" = 1'-0" (1:48). 3.5 in × 48 = 168 in = 14 ft.
        await tester.enterText(find.byType(TextField), '3.5');
        await tester.pump();

        expect(find.text('14'), findsWidgets);
        // Friendly feet-inches companion.
        expect(find.text('≈ 14 ft 0 in'), findsOneWidget);
      });
    });

    testWidgets('clearing the measurement blanks the result to a dash',
        (tester) async {
      await _withViewport(tester, const Size(390, 1000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ArchitecturalScaleScreen(),
          ),
        );

        await tester.enterText(find.byType(TextField), '10');
        await tester.pump();
        // Some finite result renders (10 in × 48 = 480 in = 40 ft).
        expect(find.text('40'), findsWidgets);

        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        // Result blanks to the em-free dash.
        expect(find.text('—'), findsWidgets);
      });
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
