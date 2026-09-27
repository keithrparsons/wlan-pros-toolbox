// Body Loss: the pure model for the Wi-Fi Classroom tool (body-loss).
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/34-body-loss.md.
//
// EVERY LOSS VALUE HERE IS ILLUSTRATIVE. No primary source was read for any
// body-loss figure (the spec's only source is the abstract of a 2018 journal
// paper on 2.4 GHz body shadowing, tagged S1). So each loss is an adjustable
// setting with an illustrative default, and every UI string that names one
// says "illustrative" ([BlLabels], pinned by
// test/services/wifi_lab/body_loss_model_test.dart):
//   - holder body loss at 2.4 GHz: 0 to 20 dB, default 8 dB
//   - per-band multipliers: 1.0 at 2.4 GHz (the reference), 5 GHz 1.2 and
//     6 GHz 1.3 by default, each adjustable 1.0 to 2.0
//   - loss per person on the line at 2.4 GHz: 0 to 10 dB, default 4 dB
//   - the turn ramp: a raised-cosine ramp over 60 degrees either side of
//     "back to the AP"
//
// THE SCENE. A top-down auditorium floor, 20 m by 12 m, x to the right and y
// down. One AP on the front wall. One person (the holder) holding a device
// 0.3 m in front of their body, facing a compass bearing (0 = up, clockwise).
// Up to 50 other people, scattered from a seed or dragged into place.
//
// THE HOLDER. The body blocks the path when the holder's back is toward the
// AP. With beta = the angle between the holder's back and the bearing to the
// AP (0 = back square to the AP, 180 = facing it), the share of the holder
// loss applied is (1 + cos(pi * beta / 60)) / 2 for beta under 60 degrees and
// 0 beyond. Facing the AP applies none; back to the AP applies all of it.
//
// THE CROWD. A person crosses the line when the straight line from the AP to
// the device passes through their body, taken as a 0.5 m wide circle seen
// from above. Crowd loss = loss per person at this band x people crossing,
// and only while the building is occupied. Empty vs occupied changes the
// crowd loss and nothing else.
//
// THE BAND. Both body losses scale by the band's multiplier: higher bands
// generally lose more to the body. An illustrative trend, not a measured
// table.
//
// REUSED, NOT RE-DERIVED:
//   - path loss and received level: RateVsRangeMath.pathLossDb and
//     receivedDbm (rate_vs_range_math.dart), over FsplMath.logDistanceDb,
//     PL(d) = FSPL(1 m) + 10 n log10(d), the log-distance model Roaming Walk
//     uses, at Roaming Walk's default exponent n = 3.
//   - MCS from the received level: RateVsRangeMath.mcsFor, the Rate vs
//     Range table, at 20 MHz.
//
// Pure Dart, no Flutter imports. Deterministic: the crowd comes from
// math.Random(seed), so the same config gives the same scene.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import '../../data/channel_frequency_data.dart';
import 'rate_vs_range_math.dart';
import '../../units/length_format.dart';
import '../../units/unit_system.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kBodyLossToolId = 'body-loss';

/// The 20 MHz channel path loss is taken at, per band: the same channels the
/// FSPL Simulator, Rate vs Range and Uplink vs Downlink use (2.4 GHz ch 6,
/// 5 GHz ch 100, 6 GHz ch 37).
const Map<WifiBand, int> kBlChannels = <WifiBand, int>{
  WifiBand.band24: 6,
  WifiBand.band5: 100,
  WifiBand.band6: 37,
};

/// Every UI label that names a loss value. Each one says "illustrative"; a
/// test holds them to it and the controls read them from here.
abstract final class BlLabels {
  static const String holderLoss = 'Holder body loss at 2.4 GHz (illustrative)';
  static const String perPersonLoss =
      'Loss per person on the line at 2.4 GHz (illustrative)';
  static const String multiplier5 = '5 GHz body-loss multiplier (illustrative)';
  static const String multiplier6 = '6 GHz body-loss multiplier (illustrative)';
  static const String lossesSection = 'Body losses (illustrative values)';
  static const String bandTrend =
      'Holder body loss by band (illustrative trend, not measured)';
  static const String turnRamp =
      'The holder loss ramps in over 60 degrees either side of back-to-the-AP '
      '(illustrative).';

  static const List<String> all = <String>[
    holderLoss,
    perPersonLoss,
    multiplier5,
    multiplier6,
    lossesSection,
    bandTrend,
    turnRamp,
  ];
}

/// A point on the floor, meters. x to the right, y down.
class BlPoint {
  const BlPoint(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(BlPoint o) => math.sqrt(_sq(x - o.x) + _sq(y - o.y));

  static double _sq(double v) => v * v;

  @override
  bool operator ==(Object other) =>
      other is BlPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'BlPoint($x, $y)';
}

/// The whole scene, immutable. Every operation returns a new config.
class BlConfig {
  BlConfig({
    this.band = WifiBand.band5,
    this.holderLossDb = defaultHolderLossDb,
    this.perPersonLossDb = defaultPerPersonLossDb,
    this.multiplier5 = defaultMultiplier5,
    this.multiplier6 = defaultMultiplier6,
    this.crowdSize = defaultCrowdSize,
    this.occupied = true,
    this.seed = defaultSeed,
    this.holder = defaultHolder,
    this.facingDeg = defaultFacingDeg,
    List<BlPoint>? people,
  }) : people = List<BlPoint>.unmodifiable(
         people ?? scatterPeople(seed, avoid: holder),
       );

  // ── The floor (geometry, not a loss) ──────────────────────────────────

  static const double floorWidthM = 20;
  static const double floorDepthM = 12;

  /// The AP, on the front wall.
  static const BlPoint ap = BlPoint(1.5, 6);

  static const BlPoint defaultHolder = BlPoint(16, 6.6);

  /// Facing the AP (bearing 270 is to the left).
  static const double defaultFacingDeg = 270;

  /// How far in front of the body the device is held.
  static const double deviceOffsetM = 0.3;

  /// A body seen from above, as a circle this wide.
  static const double bodyWidthM = 0.5;

  /// People keep this far apart when scattered.
  static const double minSpacingM = 0.7;

  /// Nobody is scattered closer than this to the AP or the holder.
  static const double clearanceM = 1.2;

  // ── The link (fixed, stated in the explainer and help) ────────────────

  static const double apEirpDbm = 20;
  static const double clientGainDbi = 0;

  /// Roaming Walk's default path-loss exponent.
  static const double exponent = 3;
  static const int widthMHz = 20;

  // ── Loss settings. Every default is ILLUSTRATIVE. ─────────────────────

  static const double holderLossMin = 0;
  static const double holderLossMax = 20;

  /// Illustrative.
  static const double defaultHolderLossDb = 8;

  static const double perPersonLossMin = 0;
  static const double perPersonLossMax = 10;

  /// Illustrative.
  static const double defaultPerPersonLossDb = 4;

  static const double multiplierMin = 1;
  static const double multiplierMax = 2;

  /// Illustrative.
  static const double defaultMultiplier5 = 1.2;

  /// Illustrative.
  static const double defaultMultiplier6 = 1.3;

  /// Half-width of the turn ramp, degrees either side of back-to-the-AP.
  /// Illustrative.
  static const double rampHalfWidthDeg = 60;

  static const int maxCrowd = 50;
  static const int defaultCrowdSize = 30;

  /// The default scatter. Chosen, and pinned by a test, so the default scene
  /// has people on the line to the AP (2 of 30, 3 of 50); any other seed is
  /// equally valid.
  static const int defaultSeed = 2;

  final WifiBand band;

  /// Holder body loss at 2.4 GHz when the body is square on the line, dB.
  final double holderLossDb;

  /// Loss per person crossing the line at 2.4 GHz, dB.
  final double perPersonLossDb;

  final double multiplier5;
  final double multiplier6;

  /// How many of [people] are in the room (the first [crowdSize]).
  final int crowdSize;

  /// Occupied (Monday) or empty (the Saturday survey).
  final bool occupied;
  final int seed;
  final BlPoint holder;

  /// Compass bearing the holder faces, degrees: 0 up, 90 right, clockwise.
  final double facingDeg;

  /// All [maxCrowd] places, in order. Only the first [crowdSize] are used.
  final List<BlPoint> people;

  // ── Geometry ──────────────────────────────────────────────────────────

  /// Compass bearing from [from] to [to], degrees in [0, 360).
  static double bearingDeg(BlPoint from, BlPoint to) {
    final double d =
        math.atan2(to.x - from.x, -(to.y - from.y)) * 180 / math.pi;
    return _norm(d);
  }

  static double _norm(double deg) {
    final double r = deg % 360;
    return r < 0 ? r + 360 : r;
  }

  /// The unit step on the floor for a compass bearing.
  static BlPoint _unit(double deg) {
    final double a = deg * math.pi / 180;
    return BlPoint(math.sin(a), -math.cos(a));
  }

  /// Where the device is: [deviceOffsetM] in front of the holder.
  BlPoint get device {
    final BlPoint u = _unit(facingDeg);
    return BlPoint(
      holder.x + u.x * deviceOffsetM,
      holder.y + u.y * deviceOffsetM,
    );
  }

  /// Bearing from the holder to the AP.
  double get apBearingDeg => bearingDeg(holder, ap);

  /// How far the holder faces away from the AP, degrees in [0, 180]:
  /// 0 = facing it, 180 = back to it.
  double get offAxisDeg {
    final double d = (_norm(facingDeg) - apBearingDeg).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  /// Share of the holder loss applied, 0 to 1: the raised-cosine turn ramp.
  double get holderShare {
    final double beta = 180 - offAxisDeg;
    if (beta >= rampHalfWidthDeg) return 0;
    return 0.5 * (1 + math.cos(math.pi * beta / rampHalfWidthDeg));
  }

  // ── The band ──────────────────────────────────────────────────────────

  int get channel => kBlChannels[band]!;

  double get freqMHz => channelToFrequency(band, channel)!.toDouble();

  /// The body-loss multiplier of [b] (1 at 2.4 GHz).
  double multiplierFor(WifiBand b) => switch (b) {
    WifiBand.band24 => 1,
    WifiBand.band5 => multiplier5,
    WifiBand.band6 => multiplier6,
  };

  double get multiplier => multiplierFor(band);

  /// Holder loss with the body square on the line, at [b], dB.
  double fullHolderLossAt(WifiBand b) => holderLossDb * multiplierFor(b);

  /// Loss per person at this band, dB.
  double get perPersonAtBandDb => perPersonLossDb * multiplier;

  // ── Losses ────────────────────────────────────────────────────────────

  /// Holder loss applied now, dB.
  double get holderLossAppliedDb => fullHolderLossAt(band) * holderShare;

  /// Distance from [p] to the straight line from the AP to the device.
  double _toLine(BlPoint p) {
    final BlPoint a = ap;
    final BlPoint b = device;
    final double dx = b.x - a.x;
    final double dy = b.y - a.y;
    final double len2 = dx * dx + dy * dy;
    double t = len2 == 0 ? 0 : ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    return p.distanceTo(BlPoint(a.x + t * dx, a.y + t * dy));
  }

  /// Indexes (into [people]) of the people in the room whose bodies the line
  /// passes through, whether or not the room is [occupied].
  List<int> get crossingIndexes => <int>[
    for (int i = 0; i < crowdSize; i++)
      if (_toLine(people[i]) < bodyWidthM / 2) i,
  ];

  /// People on the line, counted whether or not the room is occupied.
  int get crossingCount => crossingIndexes.length;

  /// Crowd loss if the room is occupied, dB.
  double get occupiedCrowdLossDb => perPersonAtBandDb * crossingCount;

  /// Crowd loss applied now, dB: zero in the empty building.
  double get crowdLossDb => occupied ? occupiedCrowdLossDb : 0;

  // ── The link ──────────────────────────────────────────────────────────

  double get distanceM => ap.distanceTo(device);

  double get pathLossDb =>
      RateVsRangeMath.pathLossDb(distanceM, freqMHz, exponent);

  /// Received level with no bodies at all, dBm.
  double get clearDbm => RateVsRangeMath.receivedDbm(
    eirpDbm: apEirpDbm,
    clientGainDbi: clientGainDbi,
    distanceM: distanceM,
    freqMHz: freqMHz,
    exponent: exponent,
  );

  /// Received level now, dBm.
  double get receivedDbm => clearDbm - holderLossAppliedDb - crowdLossDb;

  /// Received level in the empty building, dBm.
  double get emptyDbm => clearDbm - holderLossAppliedDb;

  /// Received level in the occupied building, dBm.
  double get occupiedDbm => emptyDbm - occupiedCrowdLossDb;

  /// Empty minus occupied, dB.
  double get emptyVsOccupiedDb => emptyDbm - occupiedDbm;

  /// Highest MCS at [dbm] and 20 MHz, or null below MCS 0.
  static int? mcsAt(double dbm) => RateVsRangeMath.mcsFor(dbm, widthMHz);

  int? get mcs => mcsAt(receivedDbm);
  int? get mcsEmpty => mcsAt(emptyDbm);
  int? get mcsOccupied => mcsAt(occupiedDbm);

  // ── Operations: each returns a new config ─────────────────────────────

  BlConfig _copy({
    WifiBand? band,
    double? holderLossDb,
    double? perPersonLossDb,
    double? multiplier5,
    double? multiplier6,
    int? crowdSize,
    bool? occupied,
    int? seed,
    BlPoint? holder,
    double? facingDeg,
    List<BlPoint>? people,
  }) => BlConfig(
    band: band ?? this.band,
    holderLossDb: holderLossDb ?? this.holderLossDb,
    perPersonLossDb: perPersonLossDb ?? this.perPersonLossDb,
    multiplier5: multiplier5 ?? this.multiplier5,
    multiplier6: multiplier6 ?? this.multiplier6,
    crowdSize: crowdSize ?? this.crowdSize,
    occupied: occupied ?? this.occupied,
    seed: seed ?? this.seed,
    holder: holder ?? this.holder,
    facingDeg: facingDeg ?? this.facingDeg,
    people: people ?? this.people,
  );

  static double _fin(double v, double fallback) => v.isFinite ? v : fallback;

  BlConfig withBand(WifiBand b) => _copy(band: b);

  BlConfig withHolderLoss(double v) => _copy(
    holderLossDb: _fin(v, holderLossDb).clamp(holderLossMin, holderLossMax),
  );

  BlConfig withPerPersonLoss(double v) => _copy(
    perPersonLossDb: _fin(
      v,
      perPersonLossDb,
    ).clamp(perPersonLossMin, perPersonLossMax),
  );

  BlConfig withMultiplier5(double v) => _copy(
    multiplier5: _fin(v, multiplier5).clamp(multiplierMin, multiplierMax),
  );

  BlConfig withMultiplier6(double v) => _copy(
    multiplier6: _fin(v, multiplier6).clamp(multiplierMin, multiplierMax),
  );

  BlConfig withCrowdSize(int n) => _copy(crowdSize: n.clamp(0, maxCrowd));

  BlConfig withOccupied(bool v) => _copy(occupied: v);

  /// The one crowd control: empty the room, or fill it again.
  BlConfig toggleOccupied() => _copy(occupied: !occupied);

  /// A fresh scatter from the next seed, keeping clear of the holder.
  BlConfig scatter() {
    final int next = seed + 1;
    return _copy(
      seed: next,
      people: scatterPeople(next, avoid: holder),
    );
  }

  static BlPoint _clampToFloor(BlPoint p) => BlPoint(
    _fin(p.x, defaultHolder.x).clamp(0.3, floorWidthM - 0.3),
    _fin(p.y, defaultHolder.y).clamp(0.3, floorDepthM - 0.3),
  );

  BlConfig withHolder(BlPoint p) => _copy(holder: _clampToFloor(p));

  /// Moves the holder along the room's length (the x axis), keeping y.
  BlConfig withHolderX(double x) => withHolder(BlPoint(x, holder.y));

  BlConfig withFacing(double deg) =>
      _copy(facingDeg: _norm(_fin(deg, facingDeg)));

  /// Turns the holder by [deg], clockwise when positive.
  BlConfig rotatedBy(double deg) => withFacing(facingDeg + deg);

  /// Turns the holder to face [p] (no change when [p] is on the holder).
  BlConfig facing(BlPoint p) =>
      p.distanceTo(holder) < 1e-6 ? this : withFacing(bearingDeg(holder, p));

  /// Turns the holder square to the AP.
  BlConfig facingAp() => withFacing(apBearingDeg);

  /// Turns the holder's back square to the AP.
  BlConfig backToAp() => withFacing(apBearingDeg + 180);

  /// Moves person [i] to [p].
  BlConfig withPerson(int i, BlPoint p) {
    if (i < 0 || i >= people.length) return this;
    final List<BlPoint> next = List<BlPoint>.of(people);
    next[i] = _clampToFloor(p);
    return _copy(people: next);
  }

  /// Back to the defaults.
  BlConfig reset() => BlConfig();

  // ── The crowd ─────────────────────────────────────────────────────────

  /// [maxCrowd] places from [seed]: uniform over the seating area (the floor
  /// behind the front 2.5 m), at least [minSpacingM] apart and at least
  /// [clearanceM] from the AP and from [avoid]. Deterministic.
  static List<BlPoint> scatterPeople(
    int seed, {
    BlPoint avoid = defaultHolder,
  }) {
    final math.Random rng = math.Random(seed);
    final List<BlPoint> out = <BlPoint>[];
    const double x0 = 2.5;
    const double x1 = floorWidthM - 0.5;
    const double y0 = 0.5;
    const double y1 = floorDepthM - 0.5;
    while (out.length < maxCrowd) {
      BlPoint p = BlPoint(
        x0 + rng.nextDouble() * (x1 - x0),
        y0 + rng.nextDouble() * (y1 - y0),
      );
      // Rejection sampling with a bounded number of tries; the floor holds
      // far more than 50 people at this spacing, so the fallback (accept the
      // last try) is never reached in practice but keeps this total.
      for (int tries = 0; tries < 500; tries++) {
        final bool ok =
            p.distanceTo(ap) >= clearanceM &&
            p.distanceTo(avoid) >= clearanceM &&
            out.every((BlPoint q) => q.distanceTo(p) >= minSpacingM);
        if (ok) break;
        p = BlPoint(
          x0 + rng.nextDouble() * (x1 - x0),
          y0 + rng.nextDouble() * (y1 - y0),
        );
      }
      out.add(p);
    }
    return out;
  }
}

/// Number formatting shared by stage, controls and copy.
abstract final class BlFormat {
  static String n(double v, [int decimals = 1]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String dbm(double v) => '${n(v)} dBm';

  static String db(double v) => '${n(v)} dB';

  static String mcs(int? m) => m == null ? 'below MCS 0' : 'MCS $m';

  static String deg(double v) => '${v.round() % 360}°';

  /// A distance in metres, in [u]: tenths under 10, whole above.
  static String dist(double m, [UnitSystem u = UnitSystem.metric]) {
    final LengthFormat f = LengthFormat(u);
    final double v = f.distValue(m);
    return v < 10
        ? '${v.toStringAsFixed(1)} ${f.distUnit}'
        : '${v.round()} ${f.distUnit}';
  }

  static String people(int k) => k == 1 ? '1 person' : '$k people';
}
