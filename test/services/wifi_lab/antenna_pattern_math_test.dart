// Unit tests for the Antenna Pattern model (Wi-Fi Lab, antenna-pattern).
// The numbers come from spec 14's "Done means" and the research brief §2-§3.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/antenna_pattern_math.dart';

void main() {
  group('closed-form relations', () {
    test('dBi = dBd + 2.15', () {
      expect(dbdToDbi(0), closeTo(2.15, 1e-12));
      expect(dbdToDbi(7.69), closeTo(9.84, 1e-12));
      expect(dbiToDbd(2.15), closeTo(0, 1e-12));
    });

    test('F.1336 θ3 = 34°, 17° and 6.8° at 5, 8 and 12 dBi (±0.5°)', () {
      expect(f1336OmniBeamwidthDeg(5), closeTo(34, 0.5));
      expect(f1336OmniBeamwidthDeg(8), closeTo(17, 0.5));
      expect(f1336OmniBeamwidthDeg(12), closeTo(6.8, 0.5));
      // The brief's caveat: at the dipole's gain the envelope gives 65.6°,
      // not 78°, because it is a planning envelope and not physics.
      expect(f1336OmniBeamwidthDeg(2.15), closeTo(65.6, 0.1));
    });

    test('31,000 and 41,253 on a 70° × 70° patch: 8.0 and 9.3 dBi', () {
      expect(gainFromBeamwidthsDbi(70, 70), closeTo(8.0, 0.05));
      expect(
        gainFromBeamwidthsDbi(70, 70, constant: kKrausIdealConstant),
        closeTo(9.3, 0.05),
      );
    });

    test('polarization mismatch: 45° is 3.01 dB, 90° is unbounded', () {
      expect(polarizationMismatchLossDb(0), closeTo(0, 1e-9));
      expect(polarizationMismatchLossDb(45), closeTo(3.01, 0.005));
      final double crossed = polarizationMismatchLossDb(90);
      expect(crossed.isInfinite || crossed > 100, isTrue);
    });
  });

  group('dipole', () {
    final GainGrid g = GainGrid.fromShape(const DipoleShape());

    test('peak 2.15 dBi', () {
      expect(g.peakDbi, closeTo(2.15, 0.02));
      expect(g.peakTheta, 90);
    });

    test('vertical half-power beamwidth 78° (±1°); horizontal is omni', () {
      final PatternCuts c = g.toCuts();
      expect(c.verticalBeamwidthDeg, closeTo(78, 1));
      expect(c.horizontalBeamwidthDeg, isNull);
      expect(c.looksOmni, isTrue);
    });
  });

  group('gain is not power', () {
    test('every parametric model radiates exactly what it is fed', () {
      for (final PatternShape s in <PatternShape>[
        const DipoleShape(),
        const CollinearShape(elements: 4, spacingWl: 0.75, tiltDeg: 6),
        const OmniF1336Shape(gainDbi: 12, tiltDeg: 0),
        const SectorShape(
          hBeamwidthDeg: 65,
          vBeamwidthDeg: 65,
          frontToBackDb: 30,
          sideLobeDb: 30,
          tiltDeg: 10,
        ),
      ]) {
        expect(
          GainGrid.fromShape(s).meanLinearGain,
          closeTo(1, 0.01),
          reason: '$s',
        );
      }
    });

    test('a higher-gain omni is stronger at the horizon and weaker above', () {
      final GainGrid low = GainGrid.fromShape(
        const OmniF1336Shape(gainDbi: 5, tiltDeg: 0),
      );
      final GainGrid high = GainGrid.fromShape(
        const OmniF1336Shape(gainDbi: 12, tiltDeg: 0),
      );
      expect(high.at(90, 0), greaterThan(low.at(90, 0)));
      expect(high.at(60, 0), lessThan(low.at(60, 0)));
      // The envelope's integrated peak tracks the slider within about 1 dB.
      expect(low.peakDbi, closeTo(5, 1));
      expect(high.peakDbi, closeTo(12, 1));
    });

    test('collinear: more elements, more gain, narrower beam', () {
      final GainGrid two = GainGrid.fromShape(
        const CollinearShape(elements: 2, spacingWl: 0.75, tiltDeg: 0),
      );
      final GainGrid eight = GainGrid.fromShape(
        const CollinearShape(elements: 8, spacingWl: 0.75, tiltDeg: 0),
      );
      expect(eight.peakDbi, greaterThan(two.peakDbi + 4));
      expect(
        eight.toCuts().verticalBeamwidthDeg!,
        lessThan(two.toCuts().verticalBeamwidthDeg!),
      );
    });

    test('electrical downtilt puts the collinear peak below the horizon', () {
      final GainGrid g = GainGrid.fromShape(
        const CollinearShape(elements: 6, spacingWl: 0.75, tiltDeg: 8),
      );
      expect(g.peakTheta, closeTo(98, 1));
      expect(g.toCuts().verticalPeakAngle, closeTo(8, 1));
    });
  });

  group('3GPP sector', () {
    test('65° × 65° element: half-power beamwidths come back as 65°', () {
      final PatternCuts c = GainGrid.fromShape(
        const SectorShape(
          hBeamwidthDeg: 65,
          vBeamwidthDeg: 65,
          frontToBackDb: 30,
          sideLobeDb: 30,
          tiltDeg: 0,
        ),
      ).toCuts();
      expect(c.horizontalBeamwidthDeg, closeTo(65, 1));
      expect(c.verticalBeamwidthDeg, closeTo(65, 1));
      expect(c.horizontalLossDb[180], closeTo(30, 0.01));
    });

    test('mechanical downtilt moves the peak down by the tilt', () {
      final GainGrid g = GainGrid.fromShape(
        const SectorShape(
          hBeamwidthDeg: 30,
          vBeamwidthDeg: 30,
          frontToBackDb: 30,
          sideLobeDb: 30,
          tiltDeg: 10,
        ),
      );
      expect(g.peakTheta, 100);
      expect(g.peakPhi, 0);
    });
  });

  group('reconstruction', () {
    PatternCuts tiltedSector() => GainGrid.fromShape(
      const SectorShape(
        hBeamwidthDeg: 30,
        vBeamwidthDeg: 30,
        frontToBackDb: 25,
        sideLobeDb: 20,
        tiltDeg: 10,
      ),
    ).toCuts();

    test('summing reproduces the horizontal cut and the front half of the '
        'vertical cut exactly', () {
      final PatternCuts input = tiltedSector();
      final GainGrid rebuilt = GainGrid.fromShape(
        ReconstructedShape(input, ReconstructionMethod.summing),
        peakDbi: input.peakGainDbi,
      );
      final PatternCuts out = rebuilt.toCuts();
      for (int a = 0; a < 360; a++) {
        expect(
          out.horizontalLossDb[a],
          closeTo(input.horizontalLossDb[a], 1e-9),
          reason: 'H $a',
        );
      }
      for (int t = 0; t <= 180; t++) {
        expect(
          out.frontVerticalLoss(t),
          closeTo(input.frontVerticalLoss(t), 1e-9),
          reason: 'V front theta $t',
        );
      }
    });

    test('summing is exact for an omni and for the 3GPP separable element', () {
      for (final PatternShape s in <PatternShape>[
        const CollinearShape(elements: 4, spacingWl: 0.75, tiltDeg: 6),
        const SectorShape(
          hBeamwidthDeg: 65,
          vBeamwidthDeg: 65,
          frontToBackDb: 30,
          sideLobeDb: 30,
          tiltDeg: 0,
        ),
      ]) {
        final GainGrid truth = GainGrid.fromShape(s);
        final PatternCuts cuts = truth.toCuts();
        final GainGrid est = GainGrid.fromShape(
          ReconstructedShape(cuts, ReconstructionMethod.summing),
          peakDbi: cuts.peakGainDbi,
        );
        expect(
          ReconstructionError.between(truth, est).rmsDb,
          lessThan(0.01),
          reason: '$s',
        );
      }
    });

    test('a tilted sector is not separable: both methods now miss, and '
        'they miss differently', () {
      final GainGrid truth = GainGrid.fromShape(
        const SectorShape(
          hBeamwidthDeg: 30,
          vBeamwidthDeg: 30,
          frontToBackDb: 25,
          sideLobeDb: 20,
          tiltDeg: 10,
        ),
      );
      final PatternCuts cuts = truth.toCuts();
      ReconstructionError err(ReconstructionMethod m) =>
          ReconstructionError.between(
            truth,
            GainGrid.fromShape(
              ReconstructedShape(cuts, m),
              peakDbi: cuts.peakGainDbi,
            ),
          );
      final ReconstructionError sum = err(ReconstructionMethod.summing);
      final ReconstructionError cross = err(ReconstructionMethod.crossWeighted);
      expect(sum.rmsDb, greaterThan(0.1));
      expect(cross.rmsDb, greaterThan(0.1));
      expect((sum.rmsDb - cross.rmsDb).abs(), greaterThan(0.05));
    });

    test('cross-weighted: the 0/0 at the peak is 0 dB', () {
      final PatternCuts cuts = GainGrid.fromShape(
        const SectorShape(
          hBeamwidthDeg: 65,
          vBeamwidthDeg: 65,
          frontToBackDb: 30,
          sideLobeDb: 30,
          tiltDeg: 0,
        ),
      ).toCuts();
      final ReconstructedShape s = ReconstructedShape(
        cuts,
        ReconstructionMethod.crossWeighted,
      );
      expect(s.lossDb(90, 0), 0);
      expect(s.relativePower(90, 0), 1);
      expect(s.lossDb(90, 40).isFinite, isTrue);
    });

    test('shaping above 1 narrows the beam and raises the gain', () {
      final PatternCuts cuts = tiltedSector();
      final GainGrid one = GainGrid.fromShape(
        ReconstructedShape(cuts, ReconstructionMethod.summing),
      );
      final GainGrid sharp = GainGrid.fromShape(
        ReconstructedShape(cuts, ReconstructionMethod.summing, shaping: 1.5),
      );
      expect(sharp.directivityDbi, greaterThan(one.directivityDbi));
      expect(
        sharp.toCuts().horizontalBeamwidthDeg!,
        lessThan(one.toCuts().horizontalBeamwidthDeg!),
      );
    });
  });

  group('angles', () {
    test('MSI vertical: 0 horizon, 90 down, 180 back horizon, 270 up', () {
      expect(msiVerticalDirection(0), (theta: 90, phi: 0));
      expect(msiVerticalDirection(90), (theta: 180, phi: 0));
      expect(msiVerticalDirection(180), (theta: 90, phi: 180));
      expect(msiVerticalDirection(270), (theta: 0, phi: 0));
      expect(msiVerticalDirection(4), (theta: 94, phi: 0));
      for (int t = 0; t <= 180; t++) {
        expect(msiVerticalDirection(msiVerticalOfFrontTheta(t)).theta, t);
      }
    });

    test('half-power beamwidth interpolates between samples', () {
      // A parabola in dB: 3 dB at ±10°.
      final List<double> loss = <double>[
        for (int a = 0; a < 360; a++)
          () {
            final double d = (a > 180 ? a - 360 : a).toDouble();
            return math.min(3 * (d / 10) * (d / 10), 40.0);
          }(),
      ];
      expect(halfPowerBeamwidthDeg(loss), closeTo(20, 0.1));
    });
  });
}
