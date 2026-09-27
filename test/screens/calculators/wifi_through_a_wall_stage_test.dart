// Tests for what the Wi-Fi Through a Wall stage DRAWS (WallWaveProfile).
//
// Keith, 2026-09-25: "The simulation for wall attenuation looks to change the
// FREQUENCY of the waveform. That is not true. The only thing that changes is
// the height of the wave, NOT the frequency."
//
// Default view: the drawn phase period inside the wall equals the air period,
// at any drawn band width. Optional "Show wavelength inside the material"
// view: the drawn inside period is the air period x 1/sqrt(e'), whatever the
// band width. Heights still come from the physics: the drawn magnitude
// equals |fieldAt| at the faces and |T| behind.
//
// The band is NOT to scale (Keith, 2026-09-27: "at 1cm only one pixel
// difference, at 1m the two vertical lines should be no more than 3X the
// width of the word 'wall'"): 1 px between the edge lines at 1 cm, 3x the
// "Wall" label at 1 m, linear in log10(thickness) between.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/complex.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Least-squares slope of the unwrapped phase (rad per px) over [a, b].
double _phaseSlope(WallWaveProfile p, double a, double b, {int n = 400}) {
  final List<double> xs = <double>[];
  final List<double> ys = <double>[];
  double prev = 0;
  double offset = 0;
  for (int i = 0; i < n; i++) {
    final double px = a + (b - a) * i / (n - 1);
    final Complex z = p.phasorAtPx(px);
    double ph = z.arg;
    if (i > 0) {
      double dph = ph + offset - prev;
      while (dph > math.pi) {
        offset -= 2 * math.pi;
        dph -= 2 * math.pi;
      }
      while (dph < -math.pi) {
        offset += 2 * math.pi;
        dph += 2 * math.pi;
      }
    }
    ph += offset;
    prev = ph;
    xs.add(px);
    ys.add(ph);
  }
  final double mx = xs.reduce((double s, double v) => s + v) / n;
  final double my = ys.reduce((double s, double v) => s + v) / n;
  double num = 0, den = 0;
  for (int i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  return num / den;
}

double _insideSlope(WallWaveProfile p) {
  final double inset = p.wallPx * 0.05;
  return _phaseSlope(p, p.frontPx + inset, p.frontPx + p.wallPx - inset);
}

double _behindSlope(WallWaveProfile p) =>
    _phaseSlope(p, p.frontPx + p.wallPx + 1, p.width);

SlabResult _lossless(double eps, double mm) => WallSlab.computeFor(
  props: MaterialProperties(
    material: WallMaterial.plasterboard,
    fGhz: 2.437,
    epsReal: eps,
    sigma: 0,
  ),
  thicknessM: mm / 1000,
);

void main() {
  // The band is drawn on the log scale, so these span it: 1 cm (the floor,
  // a 2 px band) to 1 m (the cap).
  final Map<String, SlabResult> walls = <String, SlabResult>{
    'concrete 102 mm, 5.5 GHz': WallSlab.compute(
      material: WallMaterial.concrete,
      fGhz: 5.5,
      thicknessM: 0.102,
    ),
    'plasterboard 12.7 mm, 2.437 GHz': WallSlab.compute(
      material: WallMaterial.plasterboard,
      fGhz: 2.437,
      thicknessM: 0.0127,
    ),
    'plasterboard 10 mm, 2.437 GHz (1 px gap)': WallSlab.compute(
      material: WallMaterial.plasterboard,
      fGhz: 2.437,
      thicknessM: 0.01,
    ),
    'concrete 1 m, 2.437 GHz (cap)': WallSlab.compute(
      material: WallMaterial.concrete,
      fGhz: 2.437,
      thicknessM: 1,
    ),
    'concrete 102 mm, 5.5 GHz, 50 deg TM': WallSlab.compute(
      material: WallMaterial.concrete,
      fGhz: 5.5,
      thicknessM: 0.102,
      angleDeg: 50,
      polarization: Polarization.tm,
    ),
  };

  group('drawn wall width, not to scale', () {
    for (final double width in <double>[390, 1280]) {
      for (final double stroke in <double>[1, 2]) {
        test('1 cm: exactly 1 px between the edge lines, '
            '$width px, stroke $stroke', () {
          final double w = WallWaveProfile.drawnWallPx(
            thicknessMm: 10,
            width: width,
            edgeStrokePx: stroke,
            labelWidthPx: 26,
          );
          // Lines of width `stroke` centred on each edge leave w - stroke.
          expect(w - stroke, closeTo(1, 1e-12));
        });
        test('1 m: 3x the label, and never wider, $width px, '
            'stroke $stroke', () {
          double at(double mm) => WallWaveProfile.drawnWallPx(
            thicknessMm: mm,
            width: width,
            edgeStrokePx: stroke,
            labelWidthPx: 26,
          );
          expect(at(1000), closeTo(78, 1e-9));
          expect(at(5000), closeTo(78, 1e-9));
        });
      }
    }

    test('10 cm sits halfway, and the width rises with log thickness', () {
      double at(double mm) => WallWaveProfile.drawnWallPx(
        thicknessMm: mm,
        width: 800,
        labelWidthPx: 30,
      );
      expect(at(100), closeTo((at(10) + at(1000)) / 2, 1e-9));
      double prev = at(10);
      for (int i = 1; i <= 200; i++) {
        final double mm = 10 * math.pow(100, i / 200).toDouble();
        final double w = at(mm);
        expect(w, greaterThan(prev));
        prev = w;
      }
    });

    test('the cap is 3x the Wall label as the painter measures it', () {
      const TextStyle big = TextStyle(fontSize: 22);
      const TextStyle small = TextStyle(fontSize: 11);
      final double capBig = WallWaveProfile.drawnWallPx(
        thicknessMm: 1000,
        width: 2000,
        labelWidthPx: wallLabelWidth(big),
      );
      expect(capBig, closeTo(3 * wallLabelWidth(big), 1e-9));
      expect(wallLabelWidth(big), greaterThan(wallLabelWidth(small)));
    });

    test('a squeezed low-loss wall shows no ripple faster than the wave', () {
      // 1 m of glass at 2.4 GHz: the true inside ripple is ~2.5 cm, which
      // would draw at ~2 px in a 78 px band and read as a faster wave.
      final SlabResult r = WallSlab.compute(
        material: WallMaterial.glass,
        fGhz: 2.437,
        thicknessM: 1,
      );
      final WallWaveProfile p = WallWaveProfile(
        r,
        1280,
        showMaterialWavelength: false,
        labelWidthPx: 26,
      );
      expect(p.rippleAveraged, isTrue);
      // The drawn height across the band, one sample per px, never turns
      // round more often than once per kWallRippleMinPx.
      final List<double> hs = <double>[
        for (double u = 0; u <= p.wallPx; u += 1)
          p.phasorAtPx(p.frontPx + u).abs,
      ];
      int turns = 0;
      for (int i = 1; i < hs.length - 1; i++) {
        if ((hs[i] - hs[i - 1]) * (hs[i + 1] - hs[i]) < 0) turns++;
      }
      expect(turns, lessThan(hs.length / kWallRippleMinPx));
    });

    test('a thin wall keeps the exact height (ripple drawn long enough)', () {
      final WallWaveProfile p = WallWaveProfile(
        walls['plasterboard 12.7 mm, 2.437 GHz']!,
        390,
        showMaterialWavelength: false,
      );
      expect(p.rippleAveraged, isFalse);
    });

    test('the air fills the rest, on the air scale', () {
      final WallWaveProfile p = WallWaveProfile(
        walls['concrete 1 m, 2.437 GHz (cap)']!,
        390,
        showMaterialWavelength: false,
        labelWidthPx: 26,
      );
      expect(p.wallPx, closeTo(78, 1e-9));
      expect(p.frontPx, closeTo((390 - 78) / 2, 1e-9));
      expect(p.side, closeTo(1.5 * p.result.props.lambdaAir, 1e-12));
      expect(p.airPxPerM, closeTo(p.frontPx / p.side, 1e-9));
    });
  });

  group('DEFAULT: drawn period inside equals the air period', () {
    for (final MapEntry<String, SlabResult> w in walls.entries) {
      for (final double width in <double>[390, 1280]) {
        test('${w.key} at $width px', () {
          final WallWaveProfile p = WallWaveProfile(
            w.value,
            width,
            showMaterialWavelength: false,
          );
          final double air = _behindSlope(p);
          final double inside = _insideSlope(p);
          expect(inside, closeTo(air, air.abs() * 1e-6));
          // And the air slope is the true air wavelength on the air scale.
          final double k0z =
              2 *
              math.pi /
              w.value.props.lambdaAir *
              math.cos(w.value.angleDeg * math.pi / 180);
          expect(air, closeTo(-k0z / p.airPxPerM, air.abs() * 1e-6));
        });
      }
    }
  });

  group('TOGGLE ON: inside/air period ratio = 1/sqrt(e\'), band or not', () {
    for (final double mm in <double>[10, 12.7, 102, 1000]) {
      for (final double eps in <double>[2.73, 6.31]) {
        test('lossless e\' = $eps, $mm mm', () {
          final WallWaveProfile p = WallWaveProfile(
            _lossless(eps, mm),
            390,
            showMaterialWavelength: true,
          );
          final double periodRatio = _behindSlope(p) / _insideSlope(p);
          expect(periodRatio, closeTo(1 / math.sqrt(eps), 1e-6));
        });
      }
    }

    test('lossy concrete within 1% of 1/sqrt(e\')', () {
      final WallWaveProfile p = WallWaveProfile(
        walls['concrete 102 mm, 5.5 GHz']!,
        390,
        showMaterialWavelength: true,
      );
      expect(
        _behindSlope(p) / _insideSlope(p),
        closeTo(1 / math.sqrt(5.24), 0.01 / math.sqrt(5.24)),
      );
    });

    test('the default view differs from it (the old drawing)', () {
      final WallWaveProfile on = WallWaveProfile(
        walls['concrete 102 mm, 5.5 GHz']!,
        390,
        showMaterialWavelength: true,
      );
      expect(_behindSlope(on) / _insideSlope(on), lessThan(0.5));
    });
  });

  group('heights still come from the physics', () {
    for (final bool mode in <bool>[false, true]) {
      for (final MapEntry<String, SlabResult> w in walls.entries) {
        test('${w.key}, material wavelength $mode', () {
          final SlabResult r = w.value;
          final WallWaveProfile p = WallWaveProfile(
            r,
            390,
            showMaterialWavelength: mode,
          );
          // Continuous at the front face, |T| at the back face and behind.
          final Complex before = p.phasorAtPx(p.frontPx - 1e-9);
          final Complex after = p.phasorAtPx(p.frontPx + 1e-9);
          expect((before - after).abs, lessThan(1e-6));
          expect(
            p.phasorAtPx(p.frontPx + p.wallPx).abs,
            closeTo(r.t.abs, 1e-9),
          );
          final Complex endIn = p.phasorAtPx(p.frontPx + p.wallPx);
          final Complex startOut = p.phasorAtPx(p.frontPx + p.wallPx + 1e-9);
          expect((endIn - startOut).abs, lessThan(1e-6));
          expect(p.phasorAtPx(p.width).abs, closeTo(r.t.abs, 1e-12));
          // Mid-wall height is |fieldAt| at the matching depth, or its mean
          // over one ripple period when the ripple is too short to draw.
          final double mid = p.frontPx + p.wallPx / 2;
          final double dm = r.thicknessM / 2;
          double want = r.fieldAt(dm).abs;
          if (p.rippleAveraged) {
            final double h = p.ripplePeriodM / 2;
            double sum = 0;
            const int n = 4000;
            for (int i = 0; i < n; i++) {
              sum += r.fieldAt(dm - h + 2 * h * (i + 0.5) / n).abs;
            }
            want = sum / n;
          }
          expect(p.phasorAtPx(mid).abs, closeTo(want, 2e-3));
          // In front it is the physics' field itself.
          final double x = -p.side / 3;
          final Complex f = r.fieldAt(x);
          final Complex g = p.phasorAtPx(p.frontPx + x * p.airPxPerM);
          expect((f - g).abs, lessThan(1e-9));
        });
      }
    }
  });

  testWidgets('the wavelength switch is off by default and toggles', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(390, 844), disableAnimations: true),
          child: WifiThroughAWallScreen(initial: WallConfig()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Show wavelength inside the material'), findsOneWidget);
    expect(find.textContaining('Frequency never changes.'), findsOneWidget);
    final Finder sw = find.byType(Switch).first;
    expect(tester.widget<Switch>(sw).value, isFalse);
    final Finder painter = find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is WallWavePainter,
    );
    expect(
      (tester.widget<CustomPaint>(painter).painter! as WallWavePainter)
          .showMaterialWavelength,
      isFalse,
    );
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(sw).value, isTrue);
    expect(
      (tester.widget<CustomPaint>(painter).painter! as WallWavePainter)
          .showMaterialWavelength,
      isTrue,
    );
  });
}
