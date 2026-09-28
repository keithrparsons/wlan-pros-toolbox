// Tests for what the Wi-Fi Through a Wall stage DRAWS (WallWaveProfile).
//
// Keith, 2026-09-25: "The simulation for wall attenuation looks to change the
// FREQUENCY of the waveform. That is not true. The only thing that changes is
// the height of the wave, NOT the frequency."
//
// Default view: the drawn phase period inside the wall equals the air period,
// at any drawn band width. Optional "Show wavelength inside the material"
// view: the drawn inside period is the air period x 1/sqrt(e'), whatever the
// band width. Heights are dB above the noise floor (Keith, 2026-09-27): the
// drawn magnitude is (P - floor) / (Ptx - floor) with P = Ptx + 20 log10
// |fieldAt| in front, a straight dB ramp inside, Ptx - loss behind.
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

  group('heights are dB above the noise floor', () {
    double h(double dbm, double tx) =>
        WallWaveProfile.heightForDbm(dbm, txPowerDbm: tx);
    double db(double v) => 20 * math.log(v) / math.ln10;

    test('the mapping: 1 at Tx, 0 at the floor and below, linear in dB', () {
      for (final double tx in <double>[0, 20, 30]) {
        expect(h(tx, tx), closeTo(1, 1e-12));
        expect(h(kWallNoiseFloorDbm, tx), 0);
        expect(h(kWallNoiseFloorDbm - 40, tx), 0);
        expect(
          h((tx + kWallNoiseFloorDbm) / 2, tx),
          closeTo(0.5, 1e-12),
        );
      }
    });

    test('the floor is thermal noise in 20 MHz plus a 6 dB noise figure', () {
      final double thermal =
          kThermalNoiseDbmPerHz +
          10 * math.log(kWallNoiseBandwidthHz) / math.ln10;
      expect(thermal, closeTo(-101.0, 0.05));
      expect(thermal + kWallNoiseFigureDb, closeTo(kWallNoiseFloorDbm, 0.05));
    });

    for (final bool mode in <bool>[false, true]) {
      for (final MapEntry<String, SlabResult> w in walls.entries) {
        for (final double tx in <double>[0, 20, 30]) {
          test('${w.key}, material wavelength $mode, Tx $tx dBm', () {
            final SlabResult r = w.value;
            final WallWaveProfile p = WallWaveProfile(
              r,
              390,
              showMaterialWavelength: mode,
              txPowerDbm: tx,
            );
            // Continuous at both faces.
            final Complex before = p.phasorAtPx(p.frontPx - 1e-9);
            final Complex after = p.phasorAtPx(p.frontPx + 1e-9);
            expect((before - after).abs, lessThan(1e-6));
            final Complex endIn = p.phasorAtPx(p.frontPx + p.wallPx);
            final Complex startOut = p.phasorAtPx(
              p.frontPx + p.wallPx + 1e-9,
            );
            expect((endIn - startOut).abs, lessThan(1e-6));
            // Behind: Tx minus the exact transmission loss.
            final double behind = tx - r.transmissionLossDb;
            expect(p.behindDbm, closeTo(behind, 1e-9));
            expect(p.phasorAtPx(p.width).abs, closeTo(h(behind, tx), 1e-12));
            // In front: Ptx + 20 log10 |fieldAt|; the carrier is the
            // incident wave's phase, -k x.
            final double x = -p.side / 3;
            final Complex f = r.fieldAt(x);
            final Complex g = p.phasorAtPx(p.frontPx + x * p.airPxPerM);
            expect(g.abs, closeTo(h(tx + db(f.abs), tx), 1e-9));
            if (g.abs > 1e-9) {
              final double k0z =
                  2 *
                  math.pi /
                  r.props.lambdaAir *
                  math.cos(r.angleDeg * math.pi / 180);
              final double want = -k0z * x;
              final double dph = math.atan2(
                math.sin(g.arg - want),
                math.cos(g.arg - want),
              );
              expect(dph, closeTo(0, 1e-9));
            }
            // Inside: a straight ramp in dB between the exact face levels.
            final double front = tx + db(r.fieldAt(0).abs);
            for (final double frac in <double>[0.25, 0.5, 0.75]) {
              expect(
                p.levelDbmAtPx(p.frontPx + frac * p.wallPx),
                closeTo(front + frac * (behind - front), 1e-6),
              );
            }
          });
        }
      }
    }

    test('2 ft concrete at 5.5 GHz, Tx 20: still visible behind', () {
      final SlabResult r = WallSlab.compute(
        material: WallMaterial.concrete,
        fGhz: 5.5,
        thicknessM: 0.61,
      );
      final WallWaveProfile p = WallWaveProfile(
        r,
        1280,
        showMaterialWavelength: false,
        txPowerDbm: 20,
      );
      // Linear field would draw |T| ~ 1e-4 of the incident: a flat line.
      expect(r.t.abs, lessThan(1e-3));
      expect(p.belowFloorBehind, isFalse);
      expect(p.heightAtPx(p.width), greaterThan(0.3));
    });

    test('below the floor draws flat, and says so', () {
      final SlabResult r = WallSlab.compute(
        material: WallMaterial.concrete,
        fGhz: 6.5,
        thicknessM: 1,
      );
      final WallWaveProfile p = WallWaveProfile(
        r,
        1280,
        showMaterialWavelength: false,
        txPowerDbm: 0,
      );
      expect(p.belowFloorBehind, isTrue);
      expect(p.heightAtPx(p.width), 0);
    });

    test('Tx power moves the height behind, never the loss', () {
      final SlabResult r = WallSlab.compute(
        material: WallMaterial.concrete,
        fGhz: 5.5,
        thicknessM: 0.3,
      );
      double behindAt(double tx) => WallWaveProfile(
        r,
        700,
        showMaterialWavelength: false,
        txPowerDbm: tx,
      ).heightAtPx(700);
      expect(behindAt(30), greaterThan(behindAt(20)));
      expect(behindAt(20), greaterThan(behindAt(0)));
    });
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
