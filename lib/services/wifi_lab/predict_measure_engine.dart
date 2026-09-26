// Predict, Then Measure engine (Wi-Fi Classroom, spec 32, 2026-09-26).
//
// Pure Dart, no Flutter imports. CLEAN-ROOM BUILD from myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/32-predict-then-measure.md, from the
// wave 4 research brief row E and Keith's Rule 5 (capture on both sides of
// what you care about). No primary source was read for multi-wall model
// coefficients, so every wall loss here is an illustrative, adjustable value.
// No product is named or implied.
//
// Same scenario, same seed, same walk: same numbers.
//
// THE MODEL. One AP (the AP on a stick) on a floor with 6 to 12 walls. Each
// wall has a PREDICTED loss (what the designer typed) and a TRUE loss (the
// building, hidden until revealed). The signal at a point p is
//     S(p) = EIRP - PL(d) - sum of the losses of the walls the straight line
//            from the AP to p crosses
//     PL(d) = FSPL(1 m) + 10 n log10(d),  d = max(|p - AP|, 1 m)
// This is Heat Map Builder's floor (HmFloor, HmWall.crosses), which uses the
// FSPL Simulator's log-distance code (FsplMath.logDistanceDb). Room
// Propagation's own crossing code is private to its full-wave engine, so the
// straight-line model is reused from Heat Map Builder instead.
//
// THREE MAPS from the same AP position:
//   Predicted: the floor with the predicted losses, every cell.
//   Truth:     the floor with the true losses, every cell (shown after the
//              reveal).
//   Measured:  samples along the student's walk read the truth plus optional
//              noise and are interpolated with Heat Map Builder's IDW
//              (buildHmMap), white beyond the guess range.
// And the DIFFERENCE map: each sample minus what the design predicted at that
// exact spot, spread with the same IDW. Comparing at the samples (not
// interpolated map minus model) keeps interpolation error out of it, so a
// design that matches the building shows zero everywhere it was measured.
//
// A WALL IS TESTED when two neighboring samples on one walk leg sit on
// opposite sides of it: the leg crosses the wall, and the line from the AP
// crosses it for one sample and not the other, with every other wall the same
// for both. Then
//     estimate = S(near) - S(far) - (PL(d_far) - PL(d_near))
// because every other wall cancels. The estimate is the mean over every such
// pair. The distance correction uses the design's path-loss exponent. A wall
// no leg crosses stays untested, however many samples sit on one side of it.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;
import 'dart:typed_data';

import 'heat_map_builder_engine.dart';

/// AP transmit EIRP, dBm. Illustrative.
const double kPmEirpDbm = 20;

/// Channel frequency for FSPL(1 m), MHz (a 5 GHz channel).
const double kPmFreqMHz = 5500;

/// Map cell size, meters.
const double kPmCellM = 0.5;

/// Distance between samples along the walk, meters.
const double kPmSampleSpacingM = 1;

/// The measured map's guess range, meters (Heat Map Builder's default).
const double kPmGuessRangeM = 5;

/// A cell "differs" when |measured - predicted| is above this, dB (spec).
const double kPmDiffThresholdDb = 5;

/// The design target, dBm. Illustrative.
const double kPmDesignTargetDbm = -67;

/// Noise limit, dB (standard deviation of one reading). Illustrative.
const double kPmMaxSigmaDb = 8;

/// Predicted and true wall loss limits, dB.
const double kPmMinLossDb = 0;
const double kPmMaxLossDb = 45;

/// Most samples one walk may hold.
const int kPmMaxSamples = 600;

/// The IDW settings every measured and difference map uses: Heat Map
/// Builder's defaults (IDW, p = 2, averaged in dB, extrapolation off).
const HmSettings kPmMapSettings = HmSettings(guessRangeM: kPmGuessRangeM);

double _dist(HmPoint a, HmPoint b) {
  final double dx = a.x - b.x;
  final double dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

// ── Walls ───────────────────────────────────────────────────────────────────

/// Wall materials with their illustrative default losses, dB (spec).
enum PmMaterial {
  drywall('Drywall', 3),
  glass('Glass', 4),
  brick('Brick', 10),
  concrete('Concrete', 15),
  elevatorShaft('Elevator shaft', 25);

  const PmMaterial(this.label, this.defaultLossDb);

  final String label;

  /// Illustrative: what a designer might type. Not a measured value.
  final double defaultLossDb;
}

/// A wall with the loss the design assumed and the loss the building has.
class PmWall {
  const PmWall({
    required this.a,
    required this.b,
    required this.material,
    required this.predictedLossDb,
    required this.trueLossDb,
  });

  final HmPoint a;
  final HmPoint b;
  final PmMaterial material;

  /// What the design says, dB.
  final double predictedLossDb;

  /// What the building does, dB. Hidden until the reveal.
  final double trueLossDb;

  HmPoint get mid => (x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);

  double get lengthM => _dist(a, b);

  HmWall get predictedHm => HmWall(a: a, b: b, lossDb: predictedLossDb);
  HmWall get trueHm => HmWall(a: a, b: b, lossDb: trueLossDb);

  /// True when the straight segment p-q crosses this wall (Heat Map
  /// Builder's test: touching an end does not count).
  bool crosses(HmPoint p, HmPoint q) => predictedHm.crosses(p, q);

  PmWall copyWith({double? predictedLossDb, double? trueLossDb}) => PmWall(
    a: a,
    b: b,
    material: material,
    predictedLossDb: predictedLossDb ?? this.predictedLossDb,
    trueLossDb: trueLossDb ?? this.trueLossDb,
  );

  @override
  bool operator ==(Object other) =>
      other is PmWall &&
      other.a == a &&
      other.b == b &&
      other.material == material &&
      other.predictedLossDb == predictedLossDb &&
      other.trueLossDb == trueLossDb;

  @override
  int get hashCode => Object.hash(a, b, material, predictedLossDb, trueLossDb);
}

// ── Scenarios ───────────────────────────────────────────────────────────────

/// The scenario presets (spec: office, school, warehouse; illustrative).
enum PmPreset {
  office('Office'),
  school('School'),
  warehouse('Warehouse');

  const PmPreset(this.label);

  final String label;
}

/// One wall of a scenario, before any loss is assigned.
typedef PmWallSpec = ({HmPoint a, HmPoint b, PmMaterial material});

/// A floor plan: size, where the design puts the AP, the walls, and a walk
/// that stays on the AP's side of every wall.
class PmScenario {
  const PmScenario({
    required this.preset,
    required this.widthM,
    required this.depthM,
    required this.ap,
    required this.pathLossExponent,
    required this.walls,
    required this.oneSideWalk,
    this.defaultSeed = 1,
  });

  final PmPreset preset;
  final double widthM;
  final double depthM;

  /// Where the design places the AP.
  final HmPoint ap;

  /// n in the log-distance model. Illustrative.
  final double pathLossExponent;
  final List<PmWallSpec> walls;

  /// A walk that crosses no wall, so it tests none.
  final List<HmPoint> oneSideWalk;

  /// The seed the scenario opens with, picked so the hidden truth puts a
  /// visible hole in a design that looks fine.
  final int defaultSeed;
}

/// The three illustrative floors. Each wall is a straight run; doors are not
/// modeled, so a walk that crosses a wall went through its door.
const PmScenario kPmOffice = PmScenario(
  preset: PmPreset.office,
  widthM: 30,
  depthM: 20,
  ap: (x: 15, y: 10),
  pathLossExponent: 2.8,
  defaultSeed: 2,
  walls: <PmWallSpec>[
    (a: (x: 0, y: 7), b: (x: 9, y: 7), material: PmMaterial.glass),
    (a: (x: 9, y: 0), b: (x: 9, y: 7), material: PmMaterial.glass),
    (a: (x: 21, y: 0), b: (x: 21, y: 7), material: PmMaterial.drywall),
    (a: (x: 21, y: 7), b: (x: 30, y: 7), material: PmMaterial.drywall),
    (a: (x: 25.5, y: 0), b: (x: 25.5, y: 7), material: PmMaterial.drywall),
    (a: (x: 0, y: 15.5), b: (x: 4, y: 15.5), material: PmMaterial.elevatorShaft),
    (a: (x: 4, y: 15.5), b: (x: 4, y: 20), material: PmMaterial.elevatorShaft),
    (a: (x: 9, y: 14), b: (x: 9, y: 20), material: PmMaterial.drywall),
    (a: (x: 20, y: 14), b: (x: 20, y: 20), material: PmMaterial.drywall),
    (a: (x: 26, y: 16), b: (x: 30, y: 16), material: PmMaterial.brick),
    (a: (x: 26, y: 16), b: (x: 26, y: 20), material: PmMaterial.brick),
  ],
  oneSideWalk: <HmPoint>[(x: 3, y: 10.5), (x: 27, y: 10.5)],
);

const PmScenario kPmSchool = PmScenario(
  preset: PmPreset.school,
  widthM: 32,
  depthM: 20,
  ap: (x: 16, y: 10),
  pathLossExponent: 2.6,
  defaultSeed: 3,
  walls: <PmWallSpec>[
    (a: (x: 0, y: 7), b: (x: 16, y: 7), material: PmMaterial.drywall),
    (a: (x: 16, y: 7), b: (x: 32, y: 7), material: PmMaterial.drywall),
    (a: (x: 8, y: 0), b: (x: 8, y: 7), material: PmMaterial.drywall),
    (a: (x: 24, y: 0), b: (x: 24, y: 7), material: PmMaterial.drywall),
    (a: (x: 0, y: 13), b: (x: 16, y: 13), material: PmMaterial.glass),
    (a: (x: 16, y: 13), b: (x: 32, y: 13), material: PmMaterial.drywall),
    (a: (x: 10, y: 13), b: (x: 10, y: 20), material: PmMaterial.drywall),
    (a: (x: 27, y: 16), b: (x: 32, y: 16), material: PmMaterial.concrete),
    (a: (x: 27, y: 16), b: (x: 27, y: 20), material: PmMaterial.concrete),
    (a: (x: 0, y: 3), b: (x: 3, y: 3), material: PmMaterial.brick),
    (a: (x: 3, y: 0), b: (x: 3, y: 3), material: PmMaterial.brick),
  ],
  oneSideWalk: <HmPoint>[(x: 2, y: 10), (x: 30, y: 10)],
);

const PmScenario kPmWarehouse = PmScenario(
  preset: PmPreset.warehouse,
  widthM: 40,
  depthM: 26,
  ap: (x: 20, y: 13),
  pathLossExponent: 2.2,
  defaultSeed: 2,
  walls: <PmWallSpec>[
    (a: (x: 0, y: 8), b: (x: 12, y: 8), material: PmMaterial.drywall),
    (a: (x: 12, y: 0), b: (x: 12, y: 8), material: PmMaterial.drywall),
    (a: (x: 6, y: 0), b: (x: 6, y: 8), material: PmMaterial.glass),
    (a: (x: 32, y: 0), b: (x: 32, y: 6), material: PmMaterial.concrete),
    (a: (x: 32, y: 6), b: (x: 40, y: 6), material: PmMaterial.concrete),
    (a: (x: 0, y: 21), b: (x: 10, y: 21), material: PmMaterial.brick),
    (a: (x: 35, y: 21), b: (x: 40, y: 21), material: PmMaterial.elevatorShaft),
    (a: (x: 35, y: 21), b: (x: 35, y: 26), material: PmMaterial.elevatorShaft),
  ],
  oneSideWalk: <HmPoint>[
    (x: 4, y: 13),
    (x: 30, y: 13),
    (x: 30, y: 18),
    (x: 16, y: 18),
  ],
);

PmScenario pmScenario(PmPreset p) => switch (p) {
  PmPreset.office => kPmOffice,
  PmPreset.school => kPmSchool,
  PmPreset.warehouse => kPmWarehouse,
};

/// The hidden truth for [s] under [seed] (spec default: two walls much worse
/// than predicted, one better; the rest as designed). Worse: 8 to 14 dB
/// more than the material default. Better: 4 to 8 dB less, on a wall of 8 dB
/// or more if there is one, never below 1 dB. Losses, in wall order.
List<double> pmHiddenTruth(PmScenario s, int seed) {
  final math.Random r = math.Random(seed * 7919 + s.preset.index * 104729);
  final List<double> base = <double>[
    for (final PmWallSpec w in s.walls) w.material.defaultLossDb,
  ];
  final List<double> out = List<double>.of(base);
  final List<int> order = List<int>.generate(base.length, (int i) => i)
    ..shuffle(r);
  final int worse1 = order[0];
  final int worse2 = order[1];
  out[worse1] = base[worse1] + 8 + r.nextInt(7);
  out[worse2] = base[worse2] + 8 + r.nextInt(7);
  final List<int> rest = order.sublist(2);
  final List<int> heavy = <int>[
    for (final int i in rest)
      if (base[i] >= 8) i,
  ];
  final int better = heavy.isNotEmpty ? heavy.first : rest.first;
  final double drop = (4 + r.nextInt(5)).toDouble();
  out[better] = math.max(1, base[better] - drop);
  return out;
}

/// The walls of [s] as the design first has them: predicted losses at the
/// material defaults, true losses from [trueLosses].
List<PmWall> pmWalls(PmScenario s, List<double> trueLosses) => <PmWall>[
  for (int i = 0; i < s.walls.length; i++)
    PmWall(
      a: s.walls[i].a,
      b: s.walls[i].b,
      material: s.walls[i].material,
      predictedLossDb: s.walls[i].material.defaultLossDb,
      trueLossDb: trueLosses[i],
    ),
];

// ── The model ───────────────────────────────────────────────────────────────

/// A floor, the AP on a stick and the walls: the physics of one moment.
class PmModel {
  PmModel({
    required this.widthM,
    required this.depthM,
    required this.ap,
    required List<PmWall> walls,
    required this.pathLossExponent,
    this.eirpDbm = kPmEirpDbm,
    this.freqMHz = kPmFreqMHz,
  }) : walls = List<PmWall>.unmodifiable(walls);

  factory PmModel.fromScenario(PmScenario s, {int? seed}) => PmModel(
    widthM: s.widthM,
    depthM: s.depthM,
    ap: s.ap,
    walls: pmWalls(s, pmHiddenTruth(s, seed ?? s.defaultSeed)),
    pathLossExponent: s.pathLossExponent,
  );

  final double widthM;
  final double depthM;
  final HmPoint ap;
  final List<PmWall> walls;
  final double pathLossExponent;
  final double eirpDbm;
  final double freqMHz;

  /// The design: the floor with the predicted losses.
  HmFloor get predictedFloor => _floor(<HmWall>[
    for (final PmWall w in walls) w.predictedHm,
  ]);

  /// The building: the floor with the true losses.
  HmFloor get trueFloor => _floor(<HmWall>[
    for (final PmWall w in walls) w.trueHm,
  ]);

  HmFloor _floor(List<HmWall> w) => HmFloor(
    widthM: widthM,
    depthM: depthM,
    aps: <HmPoint>[ap],
    walls: w,
    pathLossExponent: pathLossExponent,
    eirpDbm: eirpDbm,
    freqMHz: freqMHz,
  );

  bool contains(HmPoint p) =>
      p.x >= 0 && p.x <= widthM && p.y >= 0 && p.y <= depthM;

  PmModel copyWith({HmPoint? ap, List<PmWall>? walls}) => PmModel(
    widthM: widthM,
    depthM: depthM,
    ap: ap ?? this.ap,
    walls: walls ?? this.walls,
    pathLossExponent: pathLossExponent,
    eirpDbm: eirpDbm,
    freqMHz: freqMHz,
  );
}

// ── The walk ────────────────────────────────────────────────────────────────

/// Points every [spacingM] along a polyline, starting at its first point.
/// The last point is kept when it lies more than a quarter spacing past the
/// previous sample.
List<HmPoint> pmResample(List<HmPoint> leg, [double spacingM = kPmSampleSpacingM]) {
  if (leg.isEmpty) return const <HmPoint>[];
  final List<HmPoint> out = <HmPoint>[leg.first];
  double carry = 0; // distance walked since the last sample
  for (int i = 1; i < leg.length; i++) {
    final HmPoint a = leg[i - 1];
    final HmPoint b = leg[i];
    final double len = _dist(a, b);
    if (len <= 0) continue;
    double s = spacingM - carry;
    while (s <= len + 1e-9) {
      final double t = s / len;
      out.add((x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t));
      s += spacingM;
    }
    carry = len - (s - spacingM);
  }
  final HmPoint last = leg.last;
  if (leg.length > 1 && _dist(out.last, last) > spacingM / 4) out.add(last);
  return out;
}

/// A short leg across the middle of every wall, 1.5 m each side: the walk
/// that captures on both sides of every wall. Where the middle is not
/// usable (the AP sits on the wall's line), a quarter point is tried.
List<List<HmPoint>> pmBothSidesWalk(PmModel m) {
  final List<List<HmPoint>> legs = <List<HmPoint>>[];
  for (int wi = 0; wi < m.walls.length; wi++) {
    final PmWall w = m.walls[wi];
    final double len = w.lengthM;
    final HmPoint n = (x: -(w.b.y - w.a.y) / len, y: (w.b.x - w.a.x) / len);
    for (final double t in const <double>[0.5, 0.3, 0.7]) {
      final HmPoint c = (
        x: w.a.x + (w.b.x - w.a.x) * t,
        y: w.a.y + (w.b.y - w.a.y) * t,
      );
      HmPoint at(double k) => (
        x: (c.x + n.x * k).clamp(0.0, m.widthM),
        y: (c.y + n.y * k).clamp(0.0, m.depthM),
      );
      final List<HmPoint> leg = <HmPoint>[at(-1.5), at(1.5)];
      final List<HmPoint> pts = pmResample(leg);
      if (_testPairs(m, pts).any(((int, int, int) p) => p.$3 == wi)) {
        legs.add(leg);
        break;
      }
    }
  }
  return legs;
}

/// For neighboring samples of one leg: (i, j, wall) for every pair that sits
/// on opposite sides of exactly one wall, the one the leg crosses between
/// them. A sample exactly on a wall has no side, so it is skipped and its
/// neighbors are paired instead.
List<(int, int, int)> _testPairs(PmModel m, List<HmPoint> pts) {
  final List<(int, int, int)> out = <(int, int, int)>[];
  List<bool> status(HmPoint p) => <bool>[
    for (final PmWall w in m.walls) w.crosses(m.ap, p),
  ];
  bool onWall(HmPoint p) {
    for (final PmWall w in m.walls) {
      if (_distToSegment(p, w.a, w.b) < 1e-6) return true;
    }
    return false;
  }

  int? prevIndex;
  List<bool>? prev;
  for (int i = 0; i < pts.length; i++) {
    if (onWall(pts[i])) continue;
    final List<bool> cur = status(pts[i]);
    if (prev != null && prevIndex != null) {
      int differing = -1;
      int count = 0;
      for (int w = 0; w < cur.length; w++) {
        if (cur[w] != prev[w]) {
          differing = w;
          count++;
        }
      }
      if (count == 1 && m.walls[differing].crosses(pts[prevIndex], pts[i])) {
        out.add((prevIndex, i, differing));
      }
    }
    prev = cur;
    prevIndex = i;
  }
  return out;
}

double _distToSegment(HmPoint p, HmPoint a, HmPoint b) {
  final double dx = b.x - a.x;
  final double dy = b.y - a.y;
  final double l2 = dx * dx + dy * dy;
  final double t = l2 == 0
      ? 0
      : (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
  return _dist(p, (x: a.x + dx * t, y: a.y + dy * t));
}

/// What a walk found out about one wall.
class PmWallTest {
  const PmWallTest({
    required this.wallIndex,
    required this.estimateDb,
    required this.pairs,
  });

  final int wallIndex;

  /// The measured loss estimate, dB: the mean over [pairs].
  final double estimateDb;

  /// How many sample pairs straddled the wall.
  final int pairs;
}

/// The samples of a walk and what they tested.
class PmSurvey {
  const PmSurvey({
    required this.samples,
    required this.legStarts,
    required this.tests,
    required this.pairs,
  });

  static const PmSurvey empty = PmSurvey(
    samples: <HmSample>[],
    legStarts: <int>[],
    tests: <int, PmWallTest>{},
    pairs: <(int, int, int)>[],
  );

  /// Every sample, in walk order.
  final List<HmSample> samples;

  /// The index in [samples] where each leg starts.
  final List<int> legStarts;

  /// Tested walls by wall index. A wall that is not here is untested.
  final Map<int, PmWallTest> tests;

  /// Every straddling pair as (sample, next sample, wall).
  final List<(int, int, int)> pairs;

  bool isTested(int wall) => tests.containsKey(wall);
}

/// Walks [legs] on [m]'s building: samples every [spacingM] read the truth
/// plus [noise], and each wall with samples on both sides gets an estimate.
PmSurvey runPmSurvey(
  PmModel m,
  List<List<HmPoint>> legs, {
  HmNoise noise = const HmNoise(),
  double spacingM = kPmSampleSpacingM,
}) {
  final List<HmPoint> points = <HmPoint>[];
  final List<int> starts = <int>[];
  final List<(int, int, int)> pairs = <(int, int, int)>[];
  for (final List<HmPoint> leg in legs) {
    final List<HmPoint> pts = pmResample(leg, spacingM);
    if (pts.isEmpty) continue;
    final int base = points.length;
    starts.add(base);
    for (final (int i, int j, int w) in _testPairs(m, pts)) {
      pairs.add((base + i, base + j, w));
    }
    points.addAll(pts);
  }
  if (points.isEmpty) return PmSurvey.empty;
  final List<HmSample> samples = takeHmSamples(m.trueFloor, points, noise);
  final HmFloor design = m.predictedFloor;
  final Map<int, double> sum = <int, double>{};
  final Map<int, int> count = <int, int>{};
  for (final (int i, int j, int w) in pairs) {
    final bool iFar = m.walls[w].crosses(m.ap, points[i]);
    final HmSample near = iFar ? samples[j] : samples[i];
    final HmSample far = iFar ? samples[i] : samples[j];
    final double est =
        near.dbm -
        far.dbm -
        (design.pathLossDb(_dist(m.ap, far.p)) -
            design.pathLossDb(_dist(m.ap, near.p)));
    sum[w] = (sum[w] ?? 0) + est;
    count[w] = (count[w] ?? 0) + 1;
  }
  return PmSurvey(
    samples: List<HmSample>.unmodifiable(samples),
    legStarts: List<int>.unmodifiable(starts),
    tests: Map<int, PmWallTest>.unmodifiable(<int, PmWallTest>{
      for (final int w in sum.keys)
        w: PmWallTest(
          wallIndex: w,
          estimateDb: sum[w]! / count[w]!,
          pairs: count[w]!,
        ),
    }),
    pairs: List<(int, int, int)>.unmodifiable(pairs),
  );
}

/// "Update model": every tested wall's predicted loss becomes its measured
/// estimate. Untested walls keep what the design said.
List<PmWall> pmUpdateModel(List<PmWall> walls, PmSurvey survey) => <PmWall>[
  for (int i = 0; i < walls.length; i++)
    survey.isTested(i)
        ? walls[i].copyWith(predictedLossDb: survey.tests[i]!.estimateDb)
        : walls[i],
];

// ── The maps ────────────────────────────────────────────────────────────────

/// The four grids and the readouts, for one model and one walk.
class PmMaps {
  PmMaps._({
    required this.cols,
    required this.rows,
    required this.cellM,
    required this.predicted,
    required this.truth,
    required this.measured,
    required this.difference,
    required this.largestDiffDb,
    required this.largestDiffAt,
    required this.diffOverShare,
    required this.diffOverShareOfMeasured,
    required this.measuredShare,
    required this.predictedBelowTarget,
    required this.measuredBelowTarget,
    required this.truthBelowTarget,
  });

  final int cols;
  final int rows;
  final double cellM;

  /// dBm per cell, row-major. [measured] and [difference] are NaN where the
  /// walk gave no data.
  final Float64List predicted;
  final Float64List truth;
  final Float64List measured;

  /// Measured minus predicted, dB (see the header).
  final Float64List difference;

  /// The largest difference by size (signed), dB, or null with no data.
  final double? largestDiffDb;
  final HmPoint? largestDiffAt;

  /// Share of the whole floor where |difference| > [kPmDiffThresholdDb].
  final double diffOverShare;

  /// The same share over the measured cells only, or null with no data.
  final double? diffOverShareOfMeasured;

  /// Share of the floor the walk measured (the rest is white).
  final double measuredShare;

  /// Share of the floor below [kPmDesignTargetDbm]: predicted, measured
  /// (of the measured cells, or null), truth.
  final double predictedBelowTarget;
  final double? measuredBelowTarget;
  final double truthBelowTarget;

  int get cellCount => cols * rows;

  HmPoint center(int col, int row) =>
      (x: (col + 0.5) * cellM, y: (row + 0.5) * cellM);

  (int, int) cellOf(HmPoint p) => (
    (p.x / cellM).floor().clamp(0, cols - 1),
    (p.y / cellM).floor().clamp(0, rows - 1),
  );
}

/// Builds the maps. Pass [predicted] and [truth] from [hmTruthGrid] to reuse
/// them when only the walk changed.
PmMaps buildPmMaps(
  PmModel m,
  PmSurvey survey, {
  Float64List? predicted,
  Float64List? truth,
  double cellM = kPmCellM,
}) {
  final HmFloor design = m.predictedFloor;
  final HmFloor building = m.trueFloor;
  final int cols = (m.widthM / cellM).round();
  final int rows = (m.depthM / cellM).round();
  final int n = cols * rows;
  final Float64List pred = predicted ?? hmTruthGrid(design, cellM);
  final Float64List tru = truth ?? hmTruthGrid(building, cellM);
  assert(pred.length == n && tru.length == n);

  final Float64List measured;
  final Float64List diff = Float64List(n)..fillRange(0, n, double.nan);
  if (survey.samples.isEmpty) {
    measured = Float64List(n)..fillRange(0, n, double.nan);
  } else {
    measured = buildHmMap(
      building,
      survey.samples,
      kPmMapSettings,
      truth: tru,
      cellM: cellM,
    ).estimate;
    // Residuals at the samples, spread with the same IDW.
    final List<HmSample> residuals = <HmSample>[
      for (final HmSample s in survey.samples)
        HmSample(
          p: s.p,
          apDbm: <double>[s.dbm - design.truthDbm(s.p)],
          dbm: s.dbm - design.truthDbm(s.p),
          truthDbm: 0,
        ),
    ];
    final HmInterpolator idw = documentedHmInterpolator(
      design,
      residuals,
      kPmMapSettings,
    );
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final double? v = idw
            .estimateAt((x: (c + 0.5) * cellM, y: (r + 0.5) * cellM))
            .dbm;
        diff[r * cols + c] = v ?? double.nan;
      }
    }
  }

  double? worst;
  HmPoint? worstAt;
  int over = 0;
  int data = 0;
  int predBelow = 0;
  int measBelow = 0;
  int truthBelow = 0;
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      final int i = r * cols + c;
      if (pred[i] < kPmDesignTargetDbm) predBelow++;
      if (tru[i] < kPmDesignTargetDbm) truthBelow++;
      final double d = diff[i];
      if (d.isNaN) continue;
      data++;
      if (measured[i] < kPmDesignTargetDbm) measBelow++;
      if (d.abs() > kPmDiffThresholdDb) over++;
      if (worst == null || d.abs() > worst.abs()) {
        worst = d;
        worstAt = (x: (c + 0.5) * cellM, y: (r + 0.5) * cellM);
      }
    }
  }
  return PmMaps._(
    cols: cols,
    rows: rows,
    cellM: cellM,
    predicted: pred,
    truth: tru,
    measured: measured,
    difference: diff,
    largestDiffDb: worst,
    largestDiffAt: worstAt,
    diffOverShare: over / n,
    diffOverShareOfMeasured: data == 0 ? null : over / data,
    measuredShare: data / n,
    predictedBelowTarget: predBelow / n,
    measuredBelowTarget: data == 0 ? null : measBelow / data,
    truthBelowTarget: truthBelow / n,
  );
}
