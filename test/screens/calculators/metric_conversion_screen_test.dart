// Tests for the Metric (length) Conversion tool.
//
// The math is verified against the RF Tools PWA reference (app.js calcMetric,
// line 544), which pivots every value through meters with the factor table:
//   toM = { m:1, km:1000, mi:1609.344, ft:0.3048, cm:0.01, in:0.0254, nm:1852 }
// Expected values below come straight from those factors so the native app and
// PWA agree to the decimal.
//
// One widget test confirms the screen pumps and renders, wrapped in a
// phone-sized viewport (see test/widget_test.dart _withViewport) so the
// input-row + selector layout does not log a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/metric_conversion_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

void main() {
  group('Metric conversion math (pure) — matches PWA app.js calcMetric', () {
    test('meters-per-unit factors equal the PWA toM table exactly', () {
      expect(MetricConversionScreen.metersPerUnit(LengthUnit.m), 1.0);
      expect(MetricConversionScreen.metersPerUnit(LengthUnit.km), 1000.0);
      expect(MetricConversionScreen.metersPerUnit(LengthUnit.mi), 1609.344);
      expect(MetricConversionScreen.metersPerUnit(LengthUnit.ft), 0.3048);
      expect(MetricConversionScreen.metersPerUnit(LengthUnit.cm), 0.01);
      expect(MetricConversionScreen.metersPerUnit(LengthUnit.inch), 0.0254);
      expect(MetricConversionScreen.metersPerUnit(LengthUnit.nmi), 1852.0);
    });

    test('1 mi = 1609.344 m (PWA factor)', () {
      expect(
        MetricConversionScreen.convert(1, LengthUnit.mi, LengthUnit.m),
        closeTo(1609.344, 1e-9),
      );
    });

    test('1 nmi = 1852 m', () {
      expect(
        MetricConversionScreen.convert(1, LengthUnit.nmi, LengthUnit.m),
        closeTo(1852.0, 1e-9),
      );
    });

    test('1 km = 1000 m', () {
      expect(
        MetricConversionScreen.convert(1, LengthUnit.km, LengthUnit.m),
        closeTo(1000.0, 1e-9),
      );
    });

    test('1 ft = 0.3048 m', () {
      expect(
        MetricConversionScreen.convert(1, LengthUnit.ft, LengthUnit.m),
        closeTo(0.3048, 1e-12),
      );
    });

    test('1 in = 2.54 cm', () {
      expect(
        MetricConversionScreen.convert(1, LengthUnit.inch, LengthUnit.cm),
        closeTo(2.54, 1e-9),
      );
    });

    test('1 m = 100 cm', () {
      expect(
        MetricConversionScreen.convert(1, LengthUnit.m, LengthUnit.cm),
        closeTo(100.0, 1e-9),
      );
    });

    test('1 mi = 5280 ft', () {
      expect(
        MetricConversionScreen.convert(1, LengthUnit.mi, LengthUnit.ft),
        closeTo(5280.0, 1e-6),
      );
    });

    test('1 km = 0.539957 nmi (PWA factor)', () {
      expect(
        MetricConversionScreen.convert(1, LengthUnit.km, LengthUnit.nmi),
        closeTo(1000.0 / 1852.0, 1e-12),
      );
    });

    test('round-trip through any pair is the identity', () {
      const double v = 42.5;
      for (final LengthUnit from in LengthUnit.values) {
        for (final LengthUnit to in LengthUnit.values) {
          final double round = MetricConversionScreen.convert(
            MetricConversionScreen.convert(v, from, to),
            to,
            from,
          );
          expect(round, closeTo(v, 1e-9));
        }
      }
    });

    test('same-unit conversion is the identity', () {
      for (final LengthUnit u in LengthUnit.values) {
        expect(MetricConversionScreen.convert(7.0, u, u), closeTo(7.0, 1e-12));
      }
    });

    test('toMeters / fromMeters are inverse', () {
      final double meters =
          MetricConversionScreen.toMeters(3, LengthUnit.mi);
      expect(meters, closeTo(4828.032, 1e-9));
      expect(
        MetricConversionScreen.fromMeters(meters, LengthUnit.mi),
        closeTo(3, 1e-9),
      );
    });
  });

  group('Per-unit display precision — matches PWA fmt() decimals', () {
    test('decimals match the calcMetric fmt() calls', () {
      expect(MetricConversionScreen.decimalsFor(LengthUnit.m), 4);
      expect(MetricConversionScreen.decimalsFor(LengthUnit.km), 6);
      expect(MetricConversionScreen.decimalsFor(LengthUnit.mi), 6);
      expect(MetricConversionScreen.decimalsFor(LengthUnit.ft), 4);
      expect(MetricConversionScreen.decimalsFor(LengthUnit.cm), 2);
      expect(MetricConversionScreen.decimalsFor(LengthUnit.inch), 4);
      expect(MetricConversionScreen.decimalsFor(LengthUnit.nmi), 6);
    });
  });

  group('MetricConversionScreen widget', () {
    testWidgets('renders title, value label, and result label', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MetricConversionScreen(),
          ),
        );

        expect(find.text('Metric Conversion'), findsWidgets);
        expect(find.text('Value'), findsOneWidget);
        expect(find.text('Result'), findsOneWidget);
        // One text input: the value field.
        expect(find.byType(TextField), findsOneWidget);
      });
    });

    testWidgets('typing a value renders a finite converted result',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MetricConversionScreen(),
          ),
        );

        // Defaults are m → ft. 1 m = 3.2808 ft at 4-decimal PWA formatting.
        await tester.enterText(find.byType(TextField), '1');
        await tester.pump();
        expect(find.text('3.2808'), findsOneWidget);
      });
    });

    testWidgets('clearing the value blanks the result to an em-free dash',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MetricConversionScreen(),
          ),
        );

        await tester.enterText(find.byType(TextField), '1');
        await tester.pump();
        expect(find.text('3.2808'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(find.text('3.2808'), findsNothing);
        expect(find.text('—'), findsOneWidget);
      });
    });

    testWidgets('from/to unit pickers are the shared AppSelect, not _UnitMenu',
        (tester) async {
      // Migration guard — the two hand-rolled `_UnitMenu` DropdownButtons are
      // now AppSelect<LengthUnit> (§8.14 Select case: seven units).
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MetricConversionScreen(),
          ),
        );

        expect(find.byType(AppSelect<LengthUnit>), findsNWidgets(2));
      });
    });

    testWidgets('changing the To unit re-runs the conversion', (tester) async {
      // Verifies the migrated AppSelect onChanged is wired to _recompute.
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MetricConversionScreen(),
          ),
        );

        // Defaults m → ft; 1 m = 3.2808 ft.
        await tester.enterText(find.byType(TextField), '1');
        await tester.pump();
        expect(find.text('3.2808'), findsOneWidget);

        // The To-unit select is the second AppSelect. Open it and pick cm.
        // 1 m = 100.00 cm at the cm 2-decimal precision.
        final Finder toSelect = find.byType(AppSelect<LengthUnit>).at(1);
        await tester.tap(toSelect);
        await tester.pumpAndSettle();
        await tester.tap(find.text('cm').last);
        await tester.pumpAndSettle();

        expect(find.text('100.00'), findsOneWidget);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart _withViewport so widget pumps avoid a
/// RenderFlex overflow at phone width.
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
