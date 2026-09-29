// Pins the Floor coverage model (spec 46, Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/46-mount-height.md "Done means").

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/antenna_pattern_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/floor_coverage_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';

final GainGrid _dipole = GainGrid.fromShape(const DipoleShape());
final GainGrid _omni8 = GainGrid.fromShape(
  const OmniF1336Shape(gainDbi: 8, tiltDeg: 0),
);
final GainGrid _omni4 = GainGrid.fromShape(
  const OmniF1336Shape(gainDbi: 4, tiltDeg: 0),
);
final GainGrid _sector = GainGrid.fromShape(
  const SectorShape(
    hBeamwidthDeg: 65,
    vBeamwidthDeg: 65,
    frontToBackDb: 30,
    sideLobeDb: 30,
    tiltDeg: 0,
  ),
);

FloorLink _link(
  GainGrid g, {
  double h = 9,
  bool turned = false,
  double apTx = 20,
  double clientTx = 14,
  WifiBand band = WifiBand.band5,
}) => FloorLink(
  grid: g,
  turned: turned,
  heightM: h,
  apTxDbm: apTx,
  clientTxDbm: clientTx,
  band: band,
);

void main() {
  group('geometry', () {
    test('slant distance and the angle below the horizon', () {
      expect(FloorGeometry.slantM(0, 9), closeTo(8, 1e-12));
      expect(FloorGeometry.slantM(6, 9), closeTo(10, 1e-12));
      expect(FloorGeometry.depressionDeg(8, 9), closeTo(45, 1e-9));
    });

    test('not turned: theta = 90 + atan((h - 1) / x), behind is phi 180', () {
      final FloorDirection d = FloorGeometry.direction(8, 9, turned: false);
      expect(d.thetaDeg, closeTo(135, 1e-9));
      expect(d.phiDeg, 0);
      expect(
        FloorGeometry.direction(0, 9, turned: false).thetaDeg,
        closeTo(180, 1e-9),
      );
      expect(FloorGeometry.direction(-8, 9, turned: false).phiDeg, 180);
      // Far away the floor approaches the horizon.
      expect(
        FloorGeometry.direction(1e6, 9, turned: false).thetaDeg,
        closeTo(90, 1e-3),
      );
    });

    test('turned 90 degrees: straight down is the antenna\'s boresight', () {
      expect(
        FloorGeometry.direction(0, 9, turned: true).thetaDeg,
        closeTo(90, 1e-9),
      );
      expect(
        FloorGeometry.direction(8, 9, turned: true).thetaDeg,
        closeTo(135, 1e-9),
      );
      expect(
        FloorGeometry.direction(-8, 9, turned: true).thetaDeg,
        closeTo(45, 1e-9),
      );
    });

    test('gain is interpolated between grid rows', () {
      final double a = _dipole.at(120, 0);
      final double b = _dipole.at(121, 0);
      expect(gainTowardDbi(_dipole, 120.5, 0), closeTo((a + b) / 2, 1e-12));
      expect(gainTowardDbi(_dipole, 180, 0), _dipole.at(180, 0));
    });
  });

  group('the link', () {
    test('downlink = AP TX + G - PL + client gain, with the log-distance '
        'path loss at the band\'s channel', () {
      final FloorLink l = _link(_dipole);
      final FloorPoint p = l.at(10);
      final double r = math.sqrt(100 + 64);
      final double pl = FsplMath.logDistanceDb(r, 5500, 3);
      expect(l.freqMHz, 5500);
      expect(p.pathLossDb, closeTo(pl, 1e-9));
      expect(
        p.downlinkDbm,
        closeTo(20 + p.gainDbi - pl + l.clientGainDbi, 1e-9),
      );
      expect(p.uplinkDbm, closeTo(14 + l.clientGainDbi + p.gainDbi - pl, 1e-9));
    });

    test('uplink - downlink = client TX - AP TX at every x, every antenna', () {
      for (final (GainGrid g, bool turned) in <(GainGrid, bool)>[
        (_dipole, false),
        (_omni8, false),
        (_sector, true),
        (_sector, false),
      ]) {
        for (final double h in <double>[3, 9, 15]) {
          final FloorLink l = _link(
            g,
            h: h,
            turned: turned,
            apTx: 23,
            clientTx: 11,
          );
          for (double x = -30; x <= 60; x += 0.7) {
            final FloorPoint p = l.at(x);
            expect(p.uplinkDbm - p.downlinkDbm, closeTo(11 - 23, 1e-9));
          }
        }
      }
    });

    test('6 dB more AP power moves every downlink point up 6 dB and no '
        'uplink point', () {
      final FloorLink a = _link(_dipole);
      final FloorLink b = _link(_dipole, apTx: 26);
      for (double x = 0; x <= 40; x += 1) {
        expect(b.at(x).downlinkDbm - a.at(x).downlinkDbm, closeTo(6, 1e-9));
        expect(b.at(x).uplinkDbm, closeTo(a.at(x).uplinkDbm, 1e-9));
      }
      // The cell grows; the hole under the AP shrinks but does not close.
      expect(b.cell().radiusM!, greaterThan(a.cell().radiusM!));
      expect(b.cell().holeM, isNotNull);
      expect(b.cell().holeM!, lessThan(a.cell().holeM!));
    });
  });

  group('the lessons (spec 46 Done means)', () {
    test('the dipole has a null directly below', () {
      final FloorLink l = _link(_dipole);
      expect(l.nullBelow, isTrue);
      final FloorPoint below = l.at(0);
      expect(below.gainDbi, closeTo(_dipole.peakDbi - kGridFloorDb, 1e-9));
      // The null is far under the floor a metre away.
      expect(below.downlinkDbm, lessThan(l.at(1).downlinkDbm - 30));
    });

    test('at 9 m the dipole leaves a hole under the AP; at 3 m it barely '
        'does', () {
      final FloorCell high = _link(_dipole).cell();
      final FloorCell low = _link(_dipole, h: 3).cell();
      expect(high.holeM, isNotNull);
      expect(high.holeM!, greaterThan(2));
      expect(low.holeM ?? 0, lessThan(0.5));
      // The same dipole higher up: weaker straight below and nearby.
      for (final double x in <double>[0, 2, 4, 8]) {
        expect(
          _link(_dipole).at(x).downlinkDbm,
          lessThan(_link(_dipole, h: 3).at(x).downlinkDbm),
        );
      }
    });

    test('at 9 m the higher-gain omni gives less than the dipole on the '
        'floor under the AP (1 to 8 m out, inside 45 degrees of straight '
        'down)', () {
      final FloorLink omni = _link(_omni8);
      final FloorLink dip = _link(_dipole);
      for (double x = 1; x <= 8; x += 0.5) {
        expect(
          omni.at(x).downlinkDbm,
          lessThan(dip.at(x).downlinkDbm),
          reason: 'x = $x m',
        );
      }
      // It never reaches -67 dBm anywhere on this floor.
      expect(omni.cell().isEmpty, isTrue);
    });

    test('raising the omni-by-gain from 4 to 8 dBi lowers the floor 5 to '
        '20 m out at 9 m', () {
      for (double x = 5; x <= 20; x += 1) {
        expect(
          _link(_omni8).at(x).downlinkDbm,
          lessThan(_link(_omni4).at(x).downlinkDbm),
          reason: 'x = $x m',
        );
      }
    });

    test('MODEL LIMIT: near straight down both omnis sit on the F.1336 '
        'envelope\'s 30 dB floor, so the model cannot rank them there', () {
      // OmniF1336Shape stops 30 dB under its peak (antenna_pattern_math.dart,
      // floorDb). Within about 4 m of the point under a 9 m AP both the 4 and
      // the 8 dBi omni are on that floor, so the 8 dBi one reads higher by
      // the difference in peaks. The readouts say how far under the peak
      // straight down is; this test keeps the limit visible.
      for (final double x in <double>[0, 1, 2]) {
        expect(_link(_omni8).at(x).belowPeakDb, closeTo(30, 1e-6));
        expect(_link(_omni4).at(x).belowPeakDb, closeTo(30, 1e-6));
      }
    });

    test('a directional aimed down beats the omni directly below and out to '
        '8 m', () {
      final FloorLink dir = _link(_sector, turned: true);
      for (final GainGrid omni in <GainGrid>[_omni8, _dipole]) {
        for (double x = 0; x <= 8; x += 0.5) {
          expect(
            dir.at(x).downlinkDbm,
            greaterThan(_link(omni).at(x).downlinkDbm),
          );
        }
      }
      expect(dir.nullBelow, isFalse);
      expect(dir.cell().holeM, isNull);
      expect(dir.at(0).downlinkDbm, greaterThan(kFloorTargetDbm));
    });
  });

  group('the floor cell', () {
    test('edges sit on -67 dBm to within a millimetre', () {
      final FloorLink l = _link(_dipole);
      final FloorCell c = l.cell();
      expect(c.segments, hasLength(1));
      for (final double e in <double>[c.holeM!, c.radiusM!]) {
        expect(l.at(e - 0.002).downlinkDbm - kFloorTargetDbm, isNot(0));
        final bool inner = l.at(e - 0.002).downlinkDbm >= kFloorTargetDbm;
        final bool outer = l.at(e + 0.002).downlinkDbm >= kFloorTargetDbm;
        expect(inner, isNot(outer));
      }
    });

    test('an empty cell and one that runs past the search edge', () {
      final FloorCell none = _link(_dipole, apTx: 0).cell();
      expect(none.isEmpty, isTrue);
      expect(none.radiusM, isNull);
      final FloorLink loud = FloorLink(
        grid: _dipole,
        turned: false,
        heightM: 3,
        apTxDbm: 30,
        exponent: 2,
      );
      expect(loud.cell().reachesSearchEdge, isTrue);
    });

    test('vendor guidance height is 25 ft', () {
      expect(kVendorOmniHeightM, closeTo(7.62, 1e-9));
    });
  });
}
