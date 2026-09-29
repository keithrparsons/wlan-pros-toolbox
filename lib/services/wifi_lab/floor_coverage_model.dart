// Floor coverage: what an AP's antenna pattern puts on the floor at a given
// mounting height (Wi-Fi Classroom, antenna-pattern, Floor coverage view).
//
// CLEAN-ROOM BUILD (2026-09-29) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/46-mount-height.md, from
// Deliverables/2026-09-29-classroom-eight-features/PLAN.md "Feature 7". No
// other lab's page or code was opened. Sources:
//   - the gain in each direction: the Antenna Pattern gain grid
//     (antenna_pattern_math.dart: ITU-R F.1336-5 omni envelope, dipole and
//     collinear closed forms, 3GPP TR 38.901 directional element), unchanged;
//   - path loss: RateVsRangeMath.pathLossDb, i.e. FsplMath.logDistanceDb,
//     PL(d) = FSPL(1 m) + 10 n log10(d), the model Rate vs Range and Uplink
//     vs Downlink use, unchanged;
//   - reciprocity (Balanis, Antenna Theory, 4th ed.): an antenna's gain in a
//     direction is the same transmitting and receiving, so the AP's G(theta)
//     toward a client appears in both directions of the link;
//   - the 25 ft (7.6 m) omni height: vendor guidance, not a standard. HPE
//     Aruba Airheads Community thread "Warehouse high ceiling" (2018), quoting
//     a vendor presentation; Cisco Community thread "High Ceilings" (2013), a
//     Cisco employee's reply.
//
// GEOMETRY. The AP is at height h, the client's antenna 1 m above the floor,
// x metres away along the floor. The slant distance is
// r = sqrt(x^2 + (h - 1)^2). In the antenna's own frame (theta = zenith, 0
// up, 90 horizon, 180 down; phi = azimuth, 0 = front):
//   - not turned (an omni on a ceiling, a directional on a wall):
//     theta = 90 + atan((h - 1) / x), phi = 0 in front (x >= 0), 180 behind;
//   - turned 90 degrees (a directional on a ceiling, aimed down; an omni on
//     a wall): theta = 90 + atan(x / (h - 1)), phi = 0. The view is taken
//     from the side on which a downtilt leans the beam toward +x.
//
// EACH DIRECTION.
//   downlink(x) = AP transmit power + G(theta, phi) - PL(r) + client gain
//   uplink(x)   = client EIRP + G(theta, phi) - PL(r)
// with AP transmit power = peak EIRP - peak gain and client EIRP = client
// transmit power + client gain. So uplink - downlink = client transmit
// power - AP transmit power at every x: the pattern and the path are shared.
//
// Pure Dart, no Flutter imports. Pinned by
// test/services/wifi_lab/floor_coverage_model_test.dart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import '../../data/channel_frequency_data.dart';
import 'antenna_pattern_math.dart';
import 'rate_vs_range_math.dart';
import 'uplink_downlink_model.dart' show UdConfig, kUdChannels;

/// Height of the client's antenna above the floor, m.
const double kClientHeightM = 1;

/// The downlink level the floor cell is measured at, dBm.
const double kFloorTargetDbm = -67;

/// Mount height range, m.
const double kMountHeightMinM = 3;
const double kMountHeightMaxM = 15;

/// One notch of the mount height slider, m.
const double kMountHeightStepM = 0.5;

/// The vendor guidance height for an ordinary omni: 25 ft, in metres.
const double kVendorOmniHeightFt = 25;
const double kVendorOmniHeightM = kVendorOmniHeightFt * 0.3048;

/// How far out the floor cell is searched, m.
const double kFloorSearchM = 300;

/// Step of the floor cell search before each edge is bisected, m.
const double kFloorSearchStepM = 0.05;

/// When straight down is this far under the peak, the readouts call it the
/// pattern's null.
const double kNullDepthDb = 25;

/// Direction from the AP to a floor point, in the antenna's own frame.
typedef FloorDirection = ({double thetaDeg, int phiDeg});

/// Geometry only: where a floor point sits relative to the AP.
abstract final class FloorGeometry {
  /// Vertical drop from the AP to the client's antenna, m (never below a
  /// centimetre, so a 1 m mount still has a direction).
  static double dropM(double heightM) =>
      math.max(0.01, heightM - kClientHeightM);

  /// Slant distance from the AP to a client [xM] along the floor, m.
  static double slantM(double xM, double heightM) {
    final double d = dropM(heightM);
    return math.sqrt(xM * xM + d * d);
  }

  /// Degrees below the horizon at which the AP sees a client [xM] away.
  static double depressionDeg(double xM, double heightM) =>
      math.atan2(dropM(heightM), xM.abs()) * 180 / math.pi;

  /// The direction toward a client [xM] along the floor (negative = behind),
  /// in the antenna's own frame. [turned] is the 90 degree mounting turn the
  /// 3D view makes (AntennaPatternLab.rotatedForMount).
  static FloorDirection direction(
    double xM,
    double heightM, {
    required bool turned,
  }) {
    final double d = dropM(heightM);
    if (turned) {
      return (thetaDeg: 90 + math.atan2(xM, d) * 180 / math.pi, phiDeg: 0);
    }
    return (
      thetaDeg: 90 + math.atan2(d, xM.abs()) * 180 / math.pi,
      phiDeg: xM < 0 ? 180 : 0,
    );
  }
}

/// Gain of [grid] toward zenith [thetaDeg], linear in dB between its 1 degree
/// rows, at azimuth [phiDeg].
double gainTowardDbi(GainGrid grid, double thetaDeg, int phiDeg) {
  final double t = thetaDeg.clamp(0, 180).toDouble();
  final int i = t.floor();
  if (i >= 180) return grid.at(180, phiDeg);
  final double f = t - i;
  return grid.at(i, phiDeg) * (1 - f) + grid.at(i + 1, phiDeg) * f;
}

/// One point on the floor.
typedef FloorPoint = ({
  double xM,
  double slantM,
  double thetaDeg,
  int phiDeg,

  /// The AP antenna's gain toward this point, dBi.
  double gainDbi,

  /// How far that gain sits under the antenna's peak, dB (>= 0).
  double belowPeakDb,
  double pathLossDb,

  /// What the client receives from the AP, dBm.
  double downlinkDbm,

  /// What the AP receives from the client, dBm.
  double uplinkDbm,
});

/// The stretch of floor (x >= 0) at or above a downlink level.
class FloorCell {
  const FloorCell({
    required this.thresholdDbm,
    required this.segments,
    required this.reachesSearchEdge,
  });

  final double thresholdDbm;

  /// Covered stretches, near to far, each (from, to) in m.
  final List<({double fromM, double toM})> segments;

  /// True when the last stretch runs to [kFloorSearchM] or beyond.
  final bool reachesSearchEdge;

  bool get isEmpty => segments.isEmpty;

  /// The outer edge of the cell, m, or null when no floor reaches the level.
  double? get radiusM => segments.isEmpty ? null : segments.last.toM;

  /// The hole under the AP: the floor from 0 out to here is under the level.
  /// Null when the floor directly below reaches it (or none of it does).
  double? get holeM => segments.isEmpty || segments.first.fromM <= 0
      ? null
      : segments.first.fromM;

  /// Gaps between covered stretches beyond the first (a lobe's null landing
  /// on the floor).
  int get gaps => math.max(0, segments.length - 1);
}

/// The whole link between a mounted AP and clients on the floor. Immutable.
class FloorLink {
  const FloorLink({
    required this.grid,
    required this.turned,
    required this.heightM,
    this.band = WifiBand.band5,
    this.apTxDbm = UdConfig.defaultApTxDbm,
    this.clientTxDbm = UdConfig.defaultClientTxDbm,
    this.clientGainDbi = UdConfig.defaultClientGainDbi,
    this.exponent = UdConfig.defaultExponent,
  });

  /// The AP antenna's gain in every direction, dBi.
  final GainGrid grid;

  /// Whether the antenna is turned 90 degrees from its own frame.
  final bool turned;
  final double heightM;
  final WifiBand band;

  /// AP transmit power before its antenna, dBm (= peak EIRP - peak gain).
  final double apTxDbm;
  final double clientTxDbm;
  final double clientGainDbi;

  /// Path-loss exponent n.
  final double exponent;

  /// Centre of the band's 20 MHz channel, MHz (the Uplink vs Downlink
  /// channels).
  double get freqMHz =>
      channelToFrequency(band, kUdChannels[band]!)!.toDouble();

  double get peakEirpDbm => apTxDbm + grid.peakDbi;
  double get clientEirpDbm => clientTxDbm + clientGainDbi;

  FloorPoint at(double xM) {
    final double r = FloorGeometry.slantM(xM, heightM);
    final FloorDirection dir = FloorGeometry.direction(
      xM,
      heightM,
      turned: turned,
    );
    final double g = gainTowardDbi(grid, dir.thetaDeg, dir.phiDeg);
    final double pl = RateVsRangeMath.pathLossDb(r, freqMHz, exponent);
    return (
      xM: xM,
      slantM: r,
      thetaDeg: dir.thetaDeg,
      phiDeg: dir.phiDeg,
      gainDbi: g,
      belowPeakDb: math.max(0, grid.peakDbi - g),
      pathLossDb: pl,
      downlinkDbm: apTxDbm + g - pl + clientGainDbi,
      uplinkDbm: clientEirpDbm + g - pl,
    );
  }

  double downlinkDbmAt(double xM) => at(xM).downlinkDbm;

  /// Whether the floor directly below is deep in the pattern's null.
  bool get nullBelow => at(0).belowPeakDb >= kNullDepthDb;

  /// Every stretch of floor from x = 0 out to [kFloorSearchM] where the
  /// downlink reaches [thresholdDbm].
  FloorCell cell({double thresholdDbm = kFloorTargetDbm}) {
    bool ok(double x) => downlinkDbmAt(x) >= thresholdDbm;
    double edge(double lo, double hi) {
      // ok(lo) != ok(hi); bisect to a millimetre.
      final bool loOk = ok(lo);
      double a = lo, b = hi;
      while (b - a > 0.001) {
        final double m = (a + b) / 2;
        if (ok(m) == loOk) {
          a = m;
        } else {
          b = m;
        }
      }
      return (a + b) / 2;
    }

    final List<({double fromM, double toM})> segs =
        <({double fromM, double toM})>[];
    final int steps = (kFloorSearchM / kFloorSearchStepM).round();
    bool inside = ok(0);
    double start = 0;
    double prev = 0;
    for (int k = 1; k <= steps; k++) {
      final double x = k * kFloorSearchStepM;
      final bool now = ok(x);
      if (now != inside) {
        final double e = edge(prev, x);
        if (inside) {
          segs.add((fromM: start, toM: e));
        } else {
          start = e;
        }
        inside = now;
      }
      prev = x;
    }
    if (inside) segs.add((fromM: start, toM: kFloorSearchM));
    return FloorCell(
      thresholdDbm: thresholdDbm,
      segments: segs,
      reachesSearchEdge: inside,
    );
  }
}
