// Tests for what the Wi-Fi Through a Wall stage DRAWS (WallWaveProfile).
//
// Keith, 2026-09-25: "The simulation for wall attenuation looks to change the
// FREQUENCY of the waveform. That is not true. The only thing that changes is
// the height of the wave, NOT the frequency."
//
// Default view: the drawn phase period inside the wall equals the air period,
// for a normal wall and for a thin wall whose band is widened to stay
// visible. Optional "Show wavelength inside the material" view: the drawn
// inside period is the air period x 1/sqrt(e'), whether or not the band was
// widened (the widening used to stretch it). Heights still come from the
// physics: the drawn magnitude equals |fieldAt| at the faces and |T| behind.

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
  // 102 mm concrete fills ~100 px at 390; 1 mm plasterboard at 2.4 GHz is
  // ~1 px true scale, so its band is widened to 3 px.
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
    'plasterboard 1 mm, 2.437 GHz (widened)': WallSlab.compute(
      material: WallMaterial.plasterboard,
      fGhz: 2.437,
      thicknessM: 0.001,
    ),
    'concrete 102 mm, 5.5 GHz, 50 deg TM': WallSlab.compute(
      material: WallMaterial.concrete,
      fGhz: 5.5,
      thicknessM: 0.102,
      angleDeg: 50,
      polarization: Polarization.tm,
    ),
  };

  test('the 1 mm wall really is widened at phone width', () {
    final WallWaveProfile p = WallWaveProfile(
      walls['plasterboard 1 mm, 2.437 GHz (widened)']!,
      390,
      showMaterialWavelength: false,
    );
    expect(p.widened, isTrue);
    expect(
      WallWaveProfile(
        walls['concrete 102 mm, 5.5 GHz']!,
        390,
        showMaterialWavelength: false,
      ).widened,
      isFalse,
    );
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
    for (final double mm in <double>[1, 12.7, 102]) {
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
          // Mid-wall height is |fieldAt| at the matching depth.
          final double mid = p.frontPx + p.wallPx / 2;
          expect(
            p.phasorAtPx(mid).abs,
            closeTo(r.fieldAt(r.thicknessM / 2).abs, 1e-12),
          );
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
