// Keith, 2026-09-27, on 5 in (127 mm) plasterboard at 2.4 GHz: "Why is the
// radio wave changing frequency inside the wall? The RF does NOT change
// frequency." The drawn height inside the band rippled (the standing wave
// bounced off the back face, 13 px per ripple, over the old 8 px averaging
// threshold), so the green wave wiggled 3 to 4 times inside a 44 px band.
//
// Rule: in the DEFAULT view, the drawn envelope inside the wall is smooth
// and monotonic at every thickness, material and band.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';

/// Sign changes of the slope of the drawn envelope inside the band, sampled
/// every half px.
int _turns(WallWaveProfile p) {
  final List<double> hs = <double>[
    for (double u = 0; u <= p.wallPx; u += 0.5)
      p.phasorAtPx(p.frontPx + u).abs,
  ];
  int turns = 0;
  double lastSign = 0;
  for (int i = 1; i < hs.length; i++) {
    final double d = hs[i] - hs[i - 1];
    if (d.abs() < 1e-12) continue;
    final double s = d.sign;
    if (lastSign != 0 && s != lastSign) turns++;
    lastSign = s;
  }
  return turns;
}

void main() {
  test("Keith's screenshot: 127 mm plasterboard, 2.4 GHz", () {
    final SlabResult r = WallSlab.compute(
      material: WallMaterial.plasterboard,
      fGhz: 2.437,
      thicknessM: 0.127,
    );
    for (final double width in <double>[390, 700, 1280]) {
      final WallWaveProfile p = WallWaveProfile(
        r,
        width,
        showMaterialWavelength: false,
        labelWidthPx: 26,
      );
      expect(_turns(p), 0, reason: 'width $width');
    }
  });

  test('every material, band and thickness: monotonic inside', () {
    final List<String> bad = <String>[];
    for (final WallMaterial m in WallMaterial.values) {
      for (final double f in <double>[2.437, 5.5, 6.5]) {
        for (final double mm in <double>[
          10, 12.7, 20, 25.4, 40, 63.5, 102, 127, 200, 300, 450, 610, 1000,
        ]) {
          final WallWaveProfile p = WallWaveProfile(
            WallSlab.compute(material: m, fGhz: f, thicknessM: mm / 1000),
            700,
            showMaterialWavelength: false,
            labelWidthPx: 26,
          );
          if (_turns(p) != 0) bad.add('${m.name} $f GHz $mm mm');
        }
      }
    }
    expect(bad, isEmpty);
  });

  test('in front the carrier is one even wavelength (no warped cycles)', () {
    // Under a dB height the standing wave's own uneven phase drew as
    // flat-topped cycles; the carrier is the incident phase instead.
    for (final WallMaterial m in <WallMaterial>[
      WallMaterial.concrete,
      WallMaterial.metal,
      WallMaterial.glass,
    ]) {
      final SlabResult r = WallSlab.compute(
        material: m,
        fGhz: 5.5,
        thicknessM: 0.2,
      );
      final WallWaveProfile p = WallWaveProfile(
        r,
        700,
        showMaterialWavelength: false,
      );
      final double k = 2 * math.pi / r.props.lambdaAir / p.airPxPerM;
      for (double px = 1; px < p.frontPx - 1; px += 7) {
        final double d = p.phaseAtPx(px + 1) - p.phaseAtPx(px);
        expect(d, closeTo(-k, 1e-9), reason: '${m.name} at $px px');
      }
    }
  });
}
