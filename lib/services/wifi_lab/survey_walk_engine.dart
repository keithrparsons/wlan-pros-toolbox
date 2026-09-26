// Survey Walk engine (Wi-Fi Classroom, 2026-09-26).
//
// Pure Dart, no Flutter imports. Built clean-room from the Wi-Fi Classroom
// wave 4 research brief §3 (survey types, capture methods) and §5 (walking
// speed), per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 26-survey-walk.md. Same config and seed, same walk.
//
// THE LESSON IN ONE LINE. The radio wave does not care how fast you walk, but
// the scanner does: each channel is visited once per revisit, so a channel's
// samples land (walking speed x revisit time) apart.
//
// THE SCANNER. Each radio (network interface card, NIC) spends one slot of
// (dwell + switch) on a channel, then moves on. A visit is stamped at the end
// of its slot. How the channels are shared among the radios is the hopping
// algorithm:
//   * sequential, shared: one list; the radios take the next channel in turn
//     and work in parallel, so revisit = ceil(channels / radios) x slot;
//   * band per radio: each radio owns whole bands (extra radios split the
//     band that is slowest), so each band has its own revisit time;
//   * priority channels: every k-th slot goes to the next priority channel,
//     the other slots go round the rest.
// The device presets are generic (Keith, 2026-09-26: no product names): 1 to
// 4 NICs on the channel set and dwell the student chose, so only the radio
// count changes.
//
// THE WALKER. Continuous: clicks at the start, every turn and the stop, and
// the samples between two clicks are spread evenly in time (constant speed
// is assumed). Line: a click at the start and end of every straight segment,
// with a pause between segments that is not recorded. Stop and go: the
// walker stops at points along the path and the scanner completes two full
// cycles there. A pause at a door stops the walker mid-segment with no click,
// so continuous and line placement slides the samples; the true position is
// kept for the ghost.
//
// TIMESTAMPS. Per channel: each sample is stamped when its channel is
// visited. Per cycle: every sample in a cycle carries the time the cycle
// completes, so an early channel is placed up to one revisit later. Which
// one real products use is not published.
//
// SIGNAL. Mean level per AP from the log-distance model of spec 15
// (RoamBand.fspl1mDb, exponent 3.0), plus small-scale fading from spec 07's
// Rayleigh engine (ManyPathScene) evaluated at the sample's true position
// along the path. A stationary scanner therefore repeats one fade; a moving
// one draws a new fade at every sample.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'multipath_model.dart'
    show ManyPathScene, MultipathBand, ScatterEnvironment;
import 'roaming_walk_engine.dart' show FloorPoint, RoamBand, pointAlong;

export 'roaming_walk_engine.dart'
    show
        FloorPoint,
        RoamBand,
        kFloorDepthM,
        kFloorWidthM,
        pathLengthM,
        pointAlong;

// ── Constants ───────────────────────────────────────────────────────────────

/// Walking pace range and default, m/s. 1.4 is a normal walk (comfortable
/// gait is 1.27 to 1.46 m/s, Bohannon 1997).
const double kSurveyPaceMin = 0.5;
const double kSurveyPaceMax = 2.0;
const double kSurveyPaceDefault = 1.4;

/// Interpolation distance (guess range), meters. Keith's indoor default 5 m.
const double kGuessRangeMin = 1;
const double kGuessRangeMax = 20;
const double kGuessRangeDefault = 5;

/// Dwell per channel, ms. 250 ms is a common survey default.
const double kDwellMin = 20;
const double kDwellMax = 500;
const double kDwellDefault = 250;

/// Channel-switch overhead per hop, ms. Illustrative.
const double kSwitchMax = 50;

/// Radios (NICs).
const int kMinRadios = 1;
const int kMaxRadios = 4;

/// Priority channels get every k-th slot.
const int kPriorityEveryMin = 2;
const int kPriorityEveryMax = 6;
const int kPriorityEveryDefault = 3;

/// Pause at a door, seconds.
const double kDoorPauseMin = 1;
const double kDoorPauseMax = 10;
const double kDoorPauseDefault = 3;

/// Stop-and-go point spacing, meters.
const double kStopSpacingMin = 2;
const double kStopSpacingMax = 20;
const double kStopSpacingDefault = 5;

/// One active test result per this many seconds. Illustrative.
const double kActiveTestIntervalS = 1.0;

/// Pause between line segments (not recorded), seconds. Illustrative.
const double kLinePauseS = 2.0;

/// Signal model (the spec 15 teaching model).
const double kSurveyEirpDbm = 14;
const double kSurveyPathLossExponent = 3.0;

/// Scatterers per AP for the fading layer.
const int _kScatterers = 24;

const double _eps = 1e-9;

// ── Channels ────────────────────────────────────────────────────────────────

/// One 20 MHz channel a scanner visits.
class SurveyChannel {
  const SurveyChannel(this.band, this.number);

  final RoamBand band;
  final int number;

  /// "1", "36", "37": the number alone, for places that already show the band.
  String get shortLabel => '$number';

  /// "Ch 36 (5 GHz)".
  String get label => 'Ch $number (${band.label})';

  @override
  bool operator ==(Object other) =>
      other is SurveyChannel && other.band == band && other.number == number;

  @override
  int get hashCode => Object.hash(band, number);

  @override
  String toString() => label;
}

/// 2.4 GHz channels 1 to 11 (US).
final List<SurveyChannel> k24AllChannels = <SurveyChannel>[
  for (int n = 1; n <= 11; n++) SurveyChannel(RoamBand.b24, n),
];

/// 2.4 GHz 1, 6, 11.
const List<SurveyChannel> k24ThreeChannels = <SurveyChannel>[
  SurveyChannel(RoamBand.b24, 1),
  SurveyChannel(RoamBand.b24, 6),
  SurveyChannel(RoamBand.b24, 11),
];

/// US 5 GHz 20 MHz channels, U-NII-1 to U-NII-3 (25).
final List<SurveyChannel> k5UsChannels = <SurveyChannel>[
  for (final int n in const <int>[
    36, 40, 44, 48, 52, 56, 60, 64, //
    100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, //
    149, 153, 157, 161, 165,
  ])
    SurveyChannel(RoamBand.b5, n),
];

/// Every US 6 GHz 20 MHz channel, 1 to 233 (59).
final List<SurveyChannel> k6AllChannels = <SurveyChannel>[
  for (int k = 0; k < 59; k++) SurveyChannel(RoamBand.b6, 1 + 4 * k),
];

/// 6 GHz Preferred Scanning Channels, 5 to 229 every 16 (15).
final List<SurveyChannel> k6PscChannels = <SurveyChannel>[
  for (int k = 0; k < 15; k++) SurveyChannel(RoamBand.b6, 5 + 16 * k),
];

/// Every 20 MHz channel in 2.4 + 5 + 6 GHz, US (11 + 25 + 59 = 95).
final List<SurveyChannel> kAllUsChannels = <SurveyChannel>[
  ...k24AllChannels,
  ...k5UsChannels,
  ...k6AllChannels,
];

/// The channel-set choices.
enum ChannelSetPreset {
  g24('2.4 GHz 1, 6, 11 (3)'),
  g24g5('2.4 GHz 1, 6, 11 + US 5 GHz (28)'),
  g24g5psc('+ 6 GHz Preferred Scanning Channels (PSCs), 43'),
  all('Every 20 MHz channel, US (95)'),
  g6('6 GHz only (59)'),
  custom('Custom count');

  const ChannelSetPreset(this.label);

  final String label;
}

/// The channels in [preset]. [customCount] (1 to 95) takes the first
/// channels of the full US list, 2.4 GHz first.
List<SurveyChannel> channelsFor(
  ChannelSetPreset preset, {
  int customCount = 28,
}) {
  switch (preset) {
    case ChannelSetPreset.g24:
      return k24ThreeChannels;
    case ChannelSetPreset.g24g5:
      return <SurveyChannel>[...k24ThreeChannels, ...k5UsChannels];
    case ChannelSetPreset.g24g5psc:
      return <SurveyChannel>[
        ...k24ThreeChannels,
        ...k5UsChannels,
        ...k6PscChannels,
      ];
    case ChannelSetPreset.all:
      return kAllUsChannels;
    case ChannelSetPreset.g6:
      return k6AllChannels;
    case ChannelSetPreset.custom:
      return kAllUsChannels.sublist(
        0,
        customCount.clamp(1, kAllUsChannels.length),
      );
  }
}

/// The spec's default "channels in use": 1, 6, 11, 36, 149.
const List<SurveyChannel> kDefaultPriorityChannels = <SurveyChannel>[
  SurveyChannel(RoamBand.b24, 1),
  SurveyChannel(RoamBand.b24, 6),
  SurveyChannel(RoamBand.b24, 11),
  SurveyChannel(RoamBand.b5, 36),
  SurveyChannel(RoamBand.b5, 149),
];

// ── Scanner ─────────────────────────────────────────────────────────────────

enum HoppingAlgorithm {
  sequentialShared('Sequential, shared'),
  bandPerRadio('Band per radio'),
  priority('Priority channels');

  const HoppingAlgorithm(this.label);

  final String label;
}

/// The generic data-collection device presets: 1 to 4 NICs. Label for [n].
String nicPresetLabel(int n) =>
    n == 1 ? "1 NIC (a laptop's built-in radio)" : '$n NICs';

/// Everything about the scanner.
class ScannerConfig {
  const ScannerConfig({
    this.channelSet = ChannelSetPreset.g24g5,
    this.customCount = 28,
    this.dwellMs = kDwellDefault,
    this.switchMs = 0,
    this.radios = 1,
    this.algorithm = HoppingAlgorithm.sequentialShared,
    this.priority = kDefaultPriorityChannels,
    this.priorityEvery = kPriorityEveryDefault,
  });

  final ChannelSetPreset channelSet;
  final int customCount;
  final double dwellMs;
  final double switchMs;

  /// Radios (NICs), 1 to 4.
  final int radios;
  final HoppingAlgorithm algorithm;

  /// Channels marked in use (order does not matter).
  final List<SurveyChannel> priority;
  final int priorityEvery;

  /// A device preset: [radios] NICs on the channel set and dwell of [base].
  factory ScannerConfig.nics(
    int radios, {
    ScannerConfig base = const ScannerConfig(),
  }) => base.copyWith(radios: radios);

  List<SurveyChannel> get channels =>
      channelsFor(channelSet, customCount: customCount);

  /// Slot time per channel visit, seconds (explicit model only).
  double get slotS => (dwellMs + switchMs) / 1000;

  ScannerConfig copyWith({
    ChannelSetPreset? channelSet,
    int? customCount,
    double? dwellMs,
    double? switchMs,
    int? radios,
    HoppingAlgorithm? algorithm,
    List<SurveyChannel>? priority,
    int? priorityEvery,
  }) => ScannerConfig(
    channelSet: channelSet ?? this.channelSet,
    customCount: customCount ?? this.customCount,
    dwellMs: dwellMs ?? this.dwellMs,
    switchMs: switchMs ?? this.switchMs,
    radios: radios ?? this.radios,
    algorithm: algorithm ?? this.algorithm,
    priority: priority ?? this.priority,
    priorityEvery: priorityEvery ?? this.priorityEvery,
  );

  @override
  bool operator ==(Object other) =>
      other is ScannerConfig &&
      other.channelSet == channelSet &&
      other.customCount == customCount &&
      other.dwellMs == dwellMs &&
      other.switchMs == switchMs &&
      other.radios == radios &&
      other.algorithm == algorithm &&
      other.priority.length == priority.length &&
      other.priority.every(priority.contains) &&
      other.priorityEvery == priorityEvery;

  @override
  int get hashCode => Object.hash(
    channelSet,
    customCount,
    dwellMs,
    switchMs,
    radios,
    algorithm,
    Object.hashAllUnordered(priority),
    priorityEvery,
  );
}

/// One channel visit by one radio.
class ScanVisit {
  const ScanVisit(this.timeS, this.radio, this.channel);

  /// When the visit completes (end of its slot), seconds.
  final double timeS;
  final int radio;

  /// Index into the schedule's channel list.
  final int channel;
}

/// Revisit statistics for one channel.
class RevisitStats {
  const RevisitStats({required this.meanS, required this.maxS});

  /// Mean time between visits, seconds.
  final double meanS;

  /// Longest time between visits, seconds.
  final double maxS;
}

/// Spacing between one channel's samples: pace x revisit time.
double sampleSpacingM(double paceMps, double revisitS) => paceMps * revisitS;

/// Keith's Rule 4: the longest revisit time the interpolation distance
/// allows at this pace.
double maxAllowedRevisitS(double guessRangeM, double paceMps) =>
    guessRangeM / paceMps;

/// A scanner's channel schedule, for [radios] scanning radios.
class ScanSchedule {
  ScanSchedule._({
    required this.channels,
    required this.radios,
    required this.slotS,
    required List<List<int>>? lists,
    required List<int> priority,
    required List<int> rest,
    required this.every,
  }) : radioLists = lists,
       priorityIdx = priority,
       restIdx = rest {
    revisit = List<RevisitStats>.unmodifiable(_computeRevisit());
  }

  /// Builds the schedule of [scanner] run on [radios] radios (the scanner's
  /// own count, less one for hybrid).
  factory ScanSchedule.build(ScannerConfig scanner, {int? radios}) {
    final List<SurveyChannel> ch = scanner.channels;
    final int r = math.max(1, radios ?? scanner.radios);
    switch (scanner.algorithm) {
      case HoppingAlgorithm.sequentialShared:
        return ScanSchedule._(
          channels: ch,
          radios: r,
          slotS: scanner.slotS,
          lists: _splitShared(<int>[for (int i = 0; i < ch.length; i++) i], r),
          priority: const <int>[],
          rest: const <int>[],
          every: 0,
        );
      case HoppingAlgorithm.bandPerRadio:
        return ScanSchedule._(
          channels: ch,
          radios: r,
          slotS: scanner.slotS,
          lists: _bandLists(ch, r),
          priority: const <int>[],
          rest: const <int>[],
          every: 0,
        );
      case HoppingAlgorithm.priority:
        final List<int> pri = <int>[
          for (int i = 0; i < ch.length; i++)
            if (scanner.priority.contains(ch[i])) i,
        ];
        final List<int> rest = <int>[
          for (int i = 0; i < ch.length; i++)
            if (!scanner.priority.contains(ch[i])) i,
        ];
        if (pri.isEmpty || rest.isEmpty) {
          // Nothing to prioritize over: plain sequential.
          return ScanSchedule._(
            channels: ch,
            radios: r,
            slotS: scanner.slotS,
            lists: _splitShared(<int>[
              for (int i = 0; i < ch.length; i++) i,
            ], r),
            priority: const <int>[],
            rest: const <int>[],
            every: 0,
          );
        }
        return ScanSchedule._(
          channels: ch,
          radios: r,
          slotS: scanner.slotS,
          lists: null,
          priority: pri,
          rest: rest,
          every: scanner.priorityEvery.clamp(
            kPriorityEveryMin,
            kPriorityEveryMax,
          ),
        );
    }
  }

  final List<SurveyChannel> channels;

  /// Radios that scan.
  final int radios;

  /// Time per visit (dwell + switch), seconds.
  final double slotS;

  /// Per-radio looping channel lists (-1 = idle slot); null for priority.
  final List<List<int>>? radioLists;
  final List<int> priorityIdx;
  final List<int> restIdx;
  final int every;

  /// Revisit statistics per channel index.
  late final List<RevisitStats> revisit;

  bool get isPriority => radioLists == null;

  /// True when channel [i] is a priority channel in this schedule.
  bool isPriorityChannel(int i) => priorityIdx.contains(i);

  /// The channel radio [radio] is on during step [step], or null (idle).
  /// A step is one slot; all radios step together.
  int? channelAt(int radio, int step) {
    if (radio < 0 || radio >= radios || step < 0) return null;
    final List<List<int>>? lists = radioLists;
    if (lists != null) {
      final List<int> l = lists[radio];
      if (l.isEmpty) return null;
      final int c = l[step % l.length];
      return c < 0 ? null : c;
    }
    final int n = step * radios + radio;
    if ((n + 1) % every == 0) {
      return priorityIdx[((n + 1) ~/ every - 1) % priorityIdx.length];
    }
    final int j = n - n ~/ every;
    return restIdx[j % restIdx.length];
  }

  /// Every visit that completes at or before [untilS], in time order.
  List<ScanVisit> visitsUntil(double untilS) {
    final List<ScanVisit> out = <ScanVisit>[];
    for (int m = 0; (m + 1) * slotS <= untilS + _eps; m++) {
      for (int r = 0; r < radios; r++) {
        final int? c = channelAt(r, m);
        if (c != null) out.add(ScanVisit((m + 1) * slotS, r, c));
      }
    }
    return out;
  }

  /// Time from a fresh start until every channel has been visited twice
  /// (stop and go: "two full cycles").
  double get twoCyclesS {
    final List<int> seen = List<int>.filled(channels.length, 0);
    int done = 0;
    for (int m = 0; m < 1000000; m++) {
      for (int r = 0; r < radios; r++) {
        final int? c = channelAt(r, m);
        if (c == null) continue;
        seen[c]++;
        if (seen[c] == 2) done++;
      }
      if (done == channels.length) return (m + 1) * slotS;
    }
    return double.infinity;
  }

  /// Revisit time per band: the longest mean revisit of the band's channels.
  Map<RoamBand, double> get bandRevisitS {
    final Map<RoamBand, double> out = <RoamBand, double>{};
    for (int i = 0; i < channels.length; i++) {
      final RoamBand b = channels[i].band;
      out[b] = math.max(out[b] ?? 0, revisit[i].meanS);
    }
    return out;
  }

  /// The longest revisit of any channel (the Rule 4 number).
  double get worstRevisitS {
    double w = 0;
    for (final RevisitStats s in revisit) {
      w = math.max(w, s.maxS);
    }
    return w;
  }

  List<RevisitStats> _computeRevisit() {
    final int n = channels.length;
    final List<List<int>>? lists = radioLists;
    if (lists != null) {
      // Each list loops exactly, so every channel on a list of length L is
      // revisited every L slots.
      final List<double> per = List<double>.filled(n, double.infinity);
      for (final List<int> l in lists) {
        for (final int c in l) {
          if (c >= 0) per[c] = l.length * slotS;
        }
      }
      return <RevisitStats>[
        for (int i = 0; i < n; i++) RevisitStats(meanS: per[i], maxS: per[i]),
      ];
    }
    // Priority: measure over a long run until every channel has 40 gaps.
    final List<double?> last = List<double?>.filled(n, null);
    final List<double> sum = List<double>.filled(n, 0);
    final List<double> mx = List<double>.filled(n, 0);
    final List<int> gaps = List<int>.filled(n, 0);
    int ready = 0;
    for (int m = 0; m < 2000000 && ready < n; m++) {
      final double t = (m + 1) * slotS;
      for (int r = 0; r < radios; r++) {
        final int? c = channelAt(r, m);
        if (c == null) continue;
        final double? prev = last[c];
        if (prev != null) {
          final double g = t - prev;
          sum[c] += g;
          mx[c] = math.max(mx[c], g);
          gaps[c]++;
          if (gaps[c] == 40) ready++;
        }
        last[c] = t;
      }
    }
    return <RevisitStats>[
      for (int i = 0; i < n; i++)
        RevisitStats(
          meanS: gaps[i] == 0 ? double.infinity : sum[i] / gaps[i],
          maxS: gaps[i] == 0 ? double.infinity : mx[i],
        ),
    ];
  }
}

/// Splits [items] among [radios] radios in turn, each list padded with idle
/// slots (-1) to ceil(items / radios) so every radio loops in step.
List<List<int>> _splitShared(List<int> items, int radios) {
  final int len = (items.length / radios).ceil();
  return <List<int>>[
    for (int r = 0; r < radios; r++)
      <int>[
        for (int k = 0; k < len; k++)
          k * radios + r < items.length ? items[k * radios + r] : -1,
      ],
  ];
}

/// Band per radio. With at least one radio per band, each band gets one and
/// each extra radio joins the band with the longest per-radio list. With fewer
/// radios than bands, bands go (largest first) to the least-loaded radio.
List<List<int>> _bandLists(List<SurveyChannel> ch, int radios) {
  final Map<RoamBand, List<int>> byBand = <RoamBand, List<int>>{};
  for (int i = 0; i < ch.length; i++) {
    (byBand[ch[i].band] ??= <int>[]).add(i);
  }
  final List<List<int>> bands = byBand.values.toList();
  if (radios >= bands.length) {
    final List<int> share = List<int>.filled(bands.length, 1);
    for (int extra = radios - bands.length; extra > 0; extra--) {
      int worst = 0;
      for (int b = 1; b < bands.length; b++) {
        if ((bands[b].length / share[b]).ceil() >
            (bands[worst].length / share[worst]).ceil()) {
          worst = b;
        }
      }
      share[worst]++;
    }
    return <List<int>>[
      for (int b = 0; b < bands.length; b++)
        ..._splitShared(bands[b], share[b]),
    ];
  }
  final List<List<int>> out = <List<int>>[
    for (int r = 0; r < radios; r++) <int>[],
  ];
  final List<List<int>> sorted = List<List<int>>.of(bands)
    ..sort((List<int> a, List<int> b) => b.length.compareTo(a.length));
  for (final List<int> band in sorted) {
    int least = 0;
    for (int r = 1; r < radios; r++) {
      if (out[r].length < out[least].length) least = r;
    }
    out[least].addAll(band);
  }
  return out;
}

// ── Survey type ─────────────────────────────────────────────────────────────

enum SurveyType {
  passive('Passive'),
  active('Active'),
  hybrid('Hybrid');

  const SurveyType(this.label);

  final String label;
}

/// Whether a hybrid survey is possible, and why not.
({bool available, String? reason}) hybridAvailability(ScannerConfig s) {
  if (s.radios < 2) {
    return (
      available: false,
      reason:
          'A hybrid survey needs one radio for the active connection and '
          'at least one more to scan. Add a second radio (NIC).',
    );
  }
  return (available: true, reason: null);
}

// ── Walker ──────────────────────────────────────────────────────────────────

enum CaptureMethod {
  continuous('Continuous'),
  line('Line'),
  stopAndGo('Stop and go');

  const CaptureMethod(this.label);

  final String label;
}

enum TimestampMode {
  perChannel('Per channel'),
  perCycle('Per cycle');

  const TimestampMode(this.label);

  final String label;
}

/// A corridor down the middle and rooms either side (drawn, not modeled).
const double kCorridorTopM = 8;
const double kCorridorBottomM = 12;

/// Built-in paths on the 60 m x 20 m floor.
const List<FloorPoint> kSurveyCorridorPath = <FloorPoint>[
  (x: 1, y: 10),
  (x: 59, y: 10),
];
const List<FloorPoint> kSurveyLoopPath = <FloorPoint>[
  (x: 1, y: 10),
  (x: 59, y: 10),
  (x: 59, y: 4),
  (x: 1, y: 4),
  (x: 1, y: 10),
];
const List<FloorPoint> kSurveyPerimeterPath = <FloorPoint>[
  (x: 1, y: 1),
  (x: 59, y: 1),
  (x: 59, y: 19),
  (x: 1, y: 19),
  (x: 1, y: 1),
];

enum SurveyPathPreset {
  corridor('Straight corridor', kSurveyCorridorPath),
  loop('Loop', kSurveyLoopPath),
  perimeter('Perimeter', kSurveyPerimeterPath),
  custom('Drawn by you', null);

  const SurveyPathPreset(this.label, this.points);

  final String label;
  final List<FloorPoint>? points;

  static SurveyPathPreset matching(List<FloorPoint> path) {
    for (final SurveyPathPreset p in values) {
      final List<FloorPoint>? pts = p.points;
      if (pts != null && _pointsEq(pts, path)) return p;
    }
    return custom;
  }
}

/// An AP on the floor.
class SurveyAp {
  const SurveyAp({
    required this.name,
    required this.position,
    required this.channel,
    this.neighbor = false,
  });

  final String name;
  final FloorPoint position;
  final SurveyChannel channel;

  /// Someone else's AP: a passive survey hears it, an active one does not.
  final bool neighbor;

  String get label => '$name, ch ${channel.shortLabel}';
}

/// Five of our APs on the spec's channels in use, and one neighbor.
const List<SurveyAp> kSurveyAps = <SurveyAp>[
  SurveyAp(
    name: 'AP 1',
    position: (x: 10, y: 4),
    channel: SurveyChannel(RoamBand.b24, 1),
  ),
  SurveyAp(
    name: 'AP 2',
    position: (x: 20, y: 16),
    channel: SurveyChannel(RoamBand.b5, 36),
  ),
  SurveyAp(
    name: 'AP 3',
    position: (x: 30, y: 4),
    channel: SurveyChannel(RoamBand.b24, 6),
  ),
  SurveyAp(
    name: 'AP 4',
    position: (x: 40, y: 16),
    channel: SurveyChannel(RoamBand.b5, 149),
  ),
  SurveyAp(
    name: 'AP 5',
    position: (x: 50, y: 4),
    channel: SurveyChannel(RoamBand.b24, 11),
  ),
  SurveyAp(
    name: 'Neighbor',
    position: (x: 56, y: 18),
    channel: SurveyChannel(RoamBand.b5, 44),
    neighbor: true,
  ),
];

/// Everything the walk depends on.
class SurveyWalkConfig {
  SurveyWalkConfig({
    this.scanner = const ScannerConfig(),
    this.surveyType = SurveyType.passive,
    this.capture = CaptureMethod.continuous,
    this.timestamp = TimestampMode.perChannel,
    List<FloorPoint>? path,
    this.paceMps = kSurveyPaceDefault,
    this.guessRangeM = kGuessRangeDefault,
    this.doorPause = false,
    this.doorPauseS = kDoorPauseDefault,
    this.stopSpacingM = kStopSpacingDefault,
    this.seed = 1,
    this.aps = kSurveyAps,
  }) : path = List<FloorPoint>.unmodifiable(path ?? kSurveyCorridorPath) {
    assert(this.path.length >= 2);
  }

  final ScannerConfig scanner;
  final SurveyType surveyType;
  final CaptureMethod capture;
  final TimestampMode timestamp;
  final List<FloorPoint> path;
  final double paceMps;
  final double guessRangeM;

  /// The walker stops mid-segment (at a door) with no click.
  final bool doorPause;
  final double doorPauseS;
  final double stopSpacingM;
  final int seed;
  final List<SurveyAp> aps;

  /// The type actually run: hybrid falls back to passive when unavailable.
  SurveyType get effectiveType =>
      surveyType == SurveyType.hybrid && !hybridAvailability(scanner).available
      ? SurveyType.passive
      : surveyType;

  /// Radios that scan: all for passive, all but one for hybrid, none active.
  int get scanningRadios {
    switch (effectiveType) {
      case SurveyType.passive:
        return scanner.radios;
      case SurveyType.hybrid:
        return scanner.radios - 1;
      case SurveyType.active:
        return 0;
    }
  }

  /// Where the door is: the middle of the first segment of the path.
  double get doorS {
    final double dx = path[1].x - path[0].x;
    final double dy = path[1].y - path[0].y;
    return math.sqrt(dx * dx + dy * dy) / 2;
  }

  SurveyWalkConfig copyWith({
    ScannerConfig? scanner,
    SurveyType? surveyType,
    CaptureMethod? capture,
    TimestampMode? timestamp,
    List<FloorPoint>? path,
    double? paceMps,
    double? guessRangeM,
    bool? doorPause,
    double? doorPauseS,
    double? stopSpacingM,
    int? seed,
  }) => SurveyWalkConfig(
    scanner: scanner ?? this.scanner,
    surveyType: surveyType ?? this.surveyType,
    capture: capture ?? this.capture,
    timestamp: timestamp ?? this.timestamp,
    path: path ?? this.path,
    paceMps: paceMps ?? this.paceMps,
    guessRangeM: guessRangeM ?? this.guessRangeM,
    doorPause: doorPause ?? this.doorPause,
    doorPauseS: doorPauseS ?? this.doorPauseS,
    stopSpacingM: stopSpacingM ?? this.stopSpacingM,
    seed: seed ?? this.seed,
    aps: aps,
  );

  @override
  bool operator ==(Object other) =>
      other is SurveyWalkConfig &&
      other.scanner == scanner &&
      other.surveyType == surveyType &&
      other.capture == capture &&
      other.timestamp == timestamp &&
      _pointsEq(other.path, path) &&
      other.paceMps == paceMps &&
      other.guessRangeM == guessRangeM &&
      other.doorPause == doorPause &&
      other.doorPauseS == doorPauseS &&
      other.stopSpacingM == stopSpacingM &&
      other.seed == seed &&
      identical(other.aps, aps);

  @override
  int get hashCode => Object.hash(
    scanner,
    surveyType,
    capture,
    timestamp,
    Object.hashAll(path),
    paceMps,
    guessRangeM,
    doorPause,
    doorPauseS,
    stopSpacingM,
    seed,
  );
}

bool _pointsEq(List<FloorPoint> a, List<FloorPoint> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What the walker is doing during a phase.
enum WalkPhaseKind { walk, door, linePause, stop }

/// One stretch of the walk: moving from [s0] to [s1] (or standing still).
class WalkPhase {
  const WalkPhase({
    required this.t0,
    required this.t1,
    required this.s0,
    required this.s1,
    required this.kind,
    required this.recording,
  });

  final double t0;
  final double t1;

  /// Distance along the path, meters.
  final double s0;
  final double s1;
  final WalkPhaseKind kind;

  /// The survey app is recording samples.
  final bool recording;

  double sAt(double t) {
    if (t1 - t0 <= _eps) return s1;
    return s0 + (s1 - s0) * ((t - t0) / (t1 - t0)).clamp(0.0, 1.0);
  }
}

/// A click: the surveyor tells the app where they are.
class WalkClick {
  const WalkClick(this.timeS, this.s);

  final double timeS;
  final double s;
}

/// The whole walk, before any sample is taken.
class WalkPlan {
  WalkPlan._(this.phases, this.clicks, this.lengthM);

  /// Builds the walker's timeline. [stopDurationS] is how long each stop
  /// lasts in stop and go.
  factory WalkPlan.build(SurveyWalkConfig c, {required double stopDurationS}) {
    final List<FloorPoint> path = c.path;
    final List<double> cum = <double>[0];
    for (int i = 1; i < path.length; i++) {
      final double dx = path[i].x - path[i - 1].x;
      final double dy = path[i].y - path[i - 1].y;
      cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
    }
    final double length = cum.last;
    final double pace = c.paceMps;
    final double? door = c.doorPause ? c.doorS : null;
    final List<WalkPhase> phases = <WalkPhase>[];
    final List<WalkClick> clicks = <WalkClick>[];
    double t = 0;

    // Moves from a to b, stopping at the door on the way if it lies inside.
    void move(double a, double b, {required bool recording}) {
      if (door != null && door > a + _eps && door < b - _eps) {
        final double t1 = t + (door - a) / pace;
        phases.add(
          WalkPhase(
            t0: t,
            t1: t1,
            s0: a,
            s1: door,
            kind: WalkPhaseKind.walk,
            recording: recording,
          ),
        );
        t = t1;
        phases.add(
          WalkPhase(
            t0: t,
            t1: t + c.doorPauseS,
            s0: door,
            s1: door,
            kind: WalkPhaseKind.door,
            recording: recording,
          ),
        );
        t += c.doorPauseS;
        a = door;
      }
      final double t1 = t + (b - a) / pace;
      phases.add(
        WalkPhase(
          t0: t,
          t1: t1,
          s0: a,
          s1: b,
          kind: WalkPhaseKind.walk,
          recording: recording,
        ),
      );
      t = t1;
    }

    switch (c.capture) {
      case CaptureMethod.continuous:
        clicks.add(const WalkClick(0, 0));
        for (int i = 0; i + 1 < cum.length; i++) {
          if (cum[i + 1] - cum[i] <= _eps) continue;
          move(cum[i], cum[i + 1], recording: true);
          clicks.add(WalkClick(t, cum[i + 1]));
        }
      case CaptureMethod.line:
        for (int i = 0; i + 1 < cum.length; i++) {
          if (cum[i + 1] - cum[i] <= _eps) continue;
          if (clicks.isNotEmpty) {
            phases.add(
              WalkPhase(
                t0: t,
                t1: t + kLinePauseS,
                s0: cum[i],
                s1: cum[i],
                kind: WalkPhaseKind.linePause,
                recording: false,
              ),
            );
            t += kLinePauseS;
          }
          clicks.add(WalkClick(t, cum[i]));
          move(cum[i], cum[i + 1], recording: true);
          clicks.add(WalkClick(t, cum[i + 1]));
        }
      case CaptureMethod.stopAndGo:
        final double d = c.stopSpacingM;
        final List<double> stops = <double>[];
        for (double s = 0; s < length - 0.01; s += d) {
          stops.add(s);
        }
        stops.add(length);
        for (int j = 0; j < stops.length; j++) {
          clicks.add(WalkClick(t, stops[j]));
          phases.add(
            WalkPhase(
              t0: t,
              t1: t + stopDurationS,
              s0: stops[j],
              s1: stops[j],
              kind: WalkPhaseKind.stop,
              recording: true,
            ),
          );
          t += stopDurationS;
          if (j + 1 < stops.length) {
            move(stops[j], stops[j + 1], recording: false);
          }
        }
    }
    return WalkPlan._(
      List<WalkPhase>.unmodifiable(phases),
      List<WalkClick>.unmodifiable(clicks),
      length,
    );
  }

  final List<WalkPhase> phases;
  final List<WalkClick> clicks;
  final double lengthM;

  double get durationS => phases.isEmpty ? 0 : phases.last.t1;

  /// The phase at time [t]. Phases are end-inclusive: a visit completes at
  /// its stamp, so one that ends exactly as a stop ends belongs to the stop.
  WalkPhase phaseAt(double t) {
    for (final WalkPhase p in phases) {
      if (t <= p.t1 + _eps) return p;
    }
    return phases.last;
  }

  /// Distance along the path at time [t].
  double sAt(double t) {
    if (t <= 0) return 0;
    return phaseAt(t).sAt(t);
  }

  bool recordingAt(double t) => phaseAt(t).recording;
}

// ── Samples ─────────────────────────────────────────────────────────────────

/// One AP heard in a sample.
class HeardAp {
  const HeardAp({
    required this.ap,
    required this.meanDbm,
    required this.fadeDb,
  });

  /// Index into the config's AP list.
  final int ap;

  /// Log-distance mean at the true position, dBm.
  final double meanDbm;

  /// Small-scale fading at the true position, dB (Rayleigh, spec 07).
  final double fadeDb;

  double get rssiDbm => meanDbm + fadeDb;
}

/// One measurement on one channel.
class SurveySample {
  const SurveySample({
    required this.channel,
    required this.active,
    required this.radio,
    required this.measuredAtS,
    required this.stampS,
    required this.placedAtS,
    required this.trueS,
    required this.placedS,
    required this.truePoint,
    required this.placedPoint,
    required this.heard,
  });

  /// Index into the result's channel list.
  final int channel;

  /// An active-survey test result rather than a passive scan.
  final bool active;
  final int radio;

  /// When the channel was really measured, seconds.
  final double measuredAtS;

  /// The time the sample is stamped with.
  final double stampS;

  /// When the app puts it on the map (the next click, or at once).
  final double placedAtS;

  /// True and placed distance along the path, meters.
  final double trueS;
  final double placedS;
  final FloorPoint truePoint;
  final FloorPoint placedPoint;
  final List<HeardAp> heard;

  /// Distance between where it was taken and where the map puts it, meters.
  double get errorM {
    final double dx = placedPoint.x - truePoint.x;
    final double dy = placedPoint.y - truePoint.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// Per-channel analysis over the whole walk.
class ChannelStats {
  const ChannelStats({
    required this.channel,
    required this.samples,
    required this.revisit,
    required this.spacingM,
    required this.largestGapM,
    required this.noData,
    required this.maxErrorM,
  });

  final SurveyChannel channel;
  final int samples;
  final RevisitStats revisit;

  /// Pace x mean revisit time, meters.
  final double spacingM;

  /// Largest distance along the path between two consecutive placed
  /// samples, or null with fewer than two.
  final double? largestGapM;

  /// Stretches of the path (start, end meters) with no sample within half
  /// the guess range: drawn white, "no data".
  final List<(double, double)> noData;
  final double maxErrorM;
}

/// The whole survey walk, computed once per config.
class SurveyWalkResult {
  SurveyWalkResult._({
    required this.config,
    required this.plan,
    required this.schedule,
    required this.channels,
    required this.samples,
    required this.stats,
    required this.activeChannels,
    required this.stopDurationS,
  });

  final SurveyWalkConfig config;
  final WalkPlan plan;

  /// The scanning radios' schedule, or null for an active-only survey.
  final ScanSchedule? schedule;

  /// Channels that can carry samples: the scan set, plus (active and hybrid)
  /// any serving channel outside it.
  final List<SurveyChannel> channels;
  final List<SurveySample> samples;

  /// Stats per channel index (passive samples; active samples for a channel
  /// only the active radio visits).
  final List<ChannelStats> stats;

  /// Channel indices the active radio used.
  final Set<int> activeChannels;
  final double stopDurationS;

  double get durationS => plan.durationS;

  /// Rule 4: the longest revisit allowed at this pace and guess range.
  double get maxAllowedRevisit =>
      maxAllowedRevisitS(config.guessRangeM, config.paceMps);

  /// The revisit time Rule 4 is checked against: the scanning radios'
  /// longest revisit, or the active test interval for an active survey.
  double get ruleRevisitS => schedule?.worstRevisitS ?? kActiveTestIntervalS;

  bool get rule4Pass => ruleRevisitS <= maxAllowedRevisit + 1e-9;

  /// Largest gap between consecutive samples of any channel, meters.
  double? get largestGapM {
    double? g;
    for (final ChannelStats s in stats) {
      final double? x = s.largestGapM;
      if (x != null && (g == null || x > g)) g = x;
    }
    return g;
  }

  /// Largest position error of any sample, meters.
  double get maxErrorM {
    double e = 0;
    for (final SurveySample s in samples) {
      e = math.max(e, s.errorM);
    }
    return e;
  }

  /// Mean position error over all samples, meters.
  double get meanErrorM {
    if (samples.isEmpty) return 0;
    double e = 0;
    for (final SurveySample s in samples) {
      e += s.errorM;
    }
    return e / samples.length;
  }

  int indexOf(SurveyChannel c) => channels.indexOf(c);

  /// Samples of channel [i].
  Iterable<SurveySample> samplesOf(int i) =>
      samples.where((SurveySample s) => s.channel == i);

  /// What each radio is doing at time [t]: a channel index, or null.
  List<RadioNow> radiosAt(double t) {
    final List<RadioNow> out = <RadioNow>[];
    final WalkPhase phase = plan.phaseAt(t);
    final bool rec = phase.recording;
    final ScanSchedule? sch = schedule;
    final SurveyType type = config.effectiveType;
    int radio = 0;
    if (type != SurveyType.passive) {
      out.add(
        RadioNow(
          radio: radio++,
          active: true,
          channel: _channelOfAp(servingApAt(t)),
          recording: rec,
        ),
      );
    }
    if (sch != null) {
      // Stop and go runs the schedule from each stop's start and leaves the
      // scanner idle while walking.
      double local = t;
      bool running = true;
      if (config.capture == CaptureMethod.stopAndGo) {
        running = phase.kind == WalkPhaseKind.stop;
        local = t - phase.t0;
      }
      final int step = (local / sch.slotS + _eps).floor();
      for (int r = 0; r < sch.radios; r++) {
        int? ch;
        if (running) {
          ch = sch.channelAt(r, step);
          if (ch != null) ch = channels.indexOf(sch.channels[ch]);
        }
        out.add(
          RadioNow(
            radio: radio++,
            active: false,
            channel: ch,
            recording: rec && running,
          ),
        );
      }
    }
    return out;
  }

  /// The AP the active radio is associated with at time [t]: the strongest
  /// of our APs (never the neighbor), or null for a passive survey.
  int? servingApAt(double t) {
    if (config.effectiveType == SurveyType.passive) return null;
    return strongestOwnAp(config, pointAlong(config.path, plan.sAt(t)));
  }

  int? _channelOfAp(int? a) =>
      a == null ? null : channels.indexOf(config.aps[a].channel);
}

/// The strongest of our APs at [p] by mean level (the active client's pick,
/// kept simple: no roam hysteresis).
int? strongestOwnAp(SurveyWalkConfig config, FloorPoint p) {
  int? best;
  double bestDbm = -double.infinity;
  for (int a = 0; a < config.aps.length; a++) {
    final SurveyAp ap = config.aps[a];
    if (ap.neighbor) continue;
    final double m = meanDbm(ap, p);
    if (m > bestDbm) {
      bestDbm = m;
      best = a;
    }
  }
  return best;
}

/// A radio's state right now.
class RadioNow {
  const RadioNow({
    required this.radio,
    required this.active,
    required this.channel,
    required this.recording,
  });

  final int radio;

  /// The radio holding the active connection.
  final bool active;

  /// Index into the result's channels, or null (idle).
  final int? channel;
  final bool recording;
}

/// Log-distance mean level from [ap] at [p], dBm (spec 15's model).
double meanDbm(SurveyAp ap, FloorPoint p) {
  final double dx = ap.position.x - p.x;
  final double dy = ap.position.y - p.y;
  final double d = math.max(1.0, math.sqrt(dx * dx + dy * dy));
  return kSurveyEirpDbm -
      ap.channel.band.fspl1mDb -
      10 * kSurveyPathLossExponent * math.log(d) / math.ln10;
}

MultipathBand _fadeBand(RoamBand b) {
  switch (b) {
    case RoamBand.b24:
      return MultipathBand.b24;
    case RoamBand.b5:
      return MultipathBand.b55;
    case RoamBand.b6:
      return MultipathBand.b65;
  }
}

/// Uncovered stretches of [0, length] given samples at [positions] each
/// covering half the guess range either side.
List<(double, double)> noDataIntervals(
  List<double> positions,
  double guessRangeM,
  double lengthM,
) {
  final List<double> s = List<double>.of(positions)..sort();
  final double h = guessRangeM / 2;
  final List<(double, double)> out = <(double, double)>[];
  double covered = 0;
  for (final double x in s) {
    final double a = x - h;
    if (a > covered + 1e-6) out.add((covered, math.min(a, lengthM)));
    covered = math.max(covered, x + h);
    if (covered >= lengthM) break;
  }
  if (covered < lengthM - 1e-6) out.add((covered, lengthM));
  return out;
}

/// Runs the walk. Deterministic for a given [config] (including its seed).
SurveyWalkResult simulateSurveyWalk(SurveyWalkConfig config) {
  final SurveyType type = config.effectiveType;
  final ScannerConfig sc = config.scanner;
  final ScanSchedule? schedule = type == SurveyType.active
      ? null
      : ScanSchedule.build(sc, radios: config.scanningRadios);

  final double stopDur = schedule != null
      ? schedule.twoCyclesS
      : 2 * kActiveTestIntervalS;
  final WalkPlan plan = WalkPlan.build(config, stopDurationS: stopDur);
  final double length = plan.lengthM;
  final double dur = plan.durationS;

  final List<SurveyChannel> channels = <SurveyChannel>[...?schedule?.channels];
  int channelIndex(SurveyChannel c) {
    final int i = channels.indexOf(c);
    if (i >= 0) return i;
    channels.add(c);
    return channels.length - 1;
  }

  // Fading: one seeded scatter scene per AP, centered on the path.
  final List<ManyPathScene> scenes = <ManyPathScene>[
    for (int a = 0; a < config.aps.length; a++)
      ManyPathScene.generate(
        seed: config.seed * 101 + a,
        count: _kScatterers,
        environment: ScatterEnvironment.outdoors,
        trackLength: math.max(length, 1),
      ),
  ];

  List<HeardAp> hear(SurveyChannel ch, double trueS, {int? only}) {
    final FloorPoint p = pointAlong(config.path, trueS);
    return <HeardAp>[
      for (int a = 0; a < config.aps.length; a++)
        if (config.aps[a].channel == ch && (only == null || only == a))
          HeardAp(
            ap: a,
            meanDbm: meanDbm(config.aps[a], p),
            fadeDb: scenes[a].normalizedPowerDb(
              trueS,
              _fadeBand(config.aps[a].channel.band),
            ),
          ),
    ];
  }

  // Placement: where the app puts a sample stamped at [stamp], measured in
  // the phase at [trueT].
  (double, double) place(double trueT, double stamp) {
    final List<WalkClick> clicks = plan.clicks;
    switch (config.capture) {
      case CaptureMethod.stopAndGo:
        final WalkPhase ph = plan.phaseAt(trueT);
        return (ph.s0, trueT);
      case CaptureMethod.line:
        // The segment whose two clicks enclose the measurement.
        for (int i = 0; i + 1 < clicks.length; i += 2) {
          final WalkClick a = clicks[i];
          final WalkClick b = clicks[i + 1];
          if (trueT <= b.timeS + _eps) {
            final double st = stamp.clamp(a.timeS, b.timeS);
            final double f = b.timeS - a.timeS <= _eps
                ? 1
                : (st - a.timeS) / (b.timeS - a.timeS);
            return (a.s + (b.s - a.s) * f, b.timeS);
          }
        }
        return (clicks.last.s, clicks.last.timeS);
      case CaptureMethod.continuous:
        final double st = stamp.clamp(0.0, clicks.last.timeS);
        for (int i = 0; i + 1 < clicks.length; i++) {
          final WalkClick a = clicks[i];
          final WalkClick b = clicks[i + 1];
          if (st <= b.timeS + _eps) {
            final double f = b.timeS - a.timeS <= _eps
                ? 1
                : (st - a.timeS) / (b.timeS - a.timeS);
            return (a.s + (b.s - a.s) * f, math.max(b.timeS, trueT));
          }
        }
        return (clicks.last.s, math.max(clicks.last.timeS, trueT));
    }
  }

  final List<SurveySample> samples = <SurveySample>[];

  SurveySample make({
    required int channel,
    required bool active,
    required int radio,
    required double trueT,
    required double stamp,
    required List<HeardAp> heard,
  }) {
    final double trueS = plan.sAt(trueT);
    final (double placedS, double placedAt) = place(trueT, stamp);
    return SurveySample(
      channel: channel,
      active: active,
      radio: radio,
      measuredAtS: trueT,
      stampS: stamp,
      placedAtS: placedAt,
      trueS: trueS,
      placedS: placedS,
      truePoint: pointAlong(config.path, trueS),
      placedPoint: pointAlong(config.path, placedS),
      heard: heard,
    );
  }

  final int radioOffset = type == SurveyType.passive ? 0 : 1;

  // Passive scanning.
  if (schedule != null) {
    final List<(ScanVisit, double)> visits = <(ScanVisit, double)>[];
    if (config.capture == CaptureMethod.stopAndGo) {
      for (final WalkPhase ph in plan.phases) {
        if (ph.kind != WalkPhaseKind.stop) continue;
        for (final ScanVisit v in schedule.visitsUntil(stopDur)) {
          final double t = ph.t0 + v.timeS;
          visits.add((ScanVisit(t, v.radio, v.channel), t));
        }
      }
    } else {
      final List<ScanVisit> all = schedule.visitsUntil(dur);
      final List<double> stamps = List<double>.generate(
        all.length,
        (int i) => all[i].timeS,
      );
      if (config.timestamp == TimestampMode.perCycle) {
        // One stamp per cycle: the time the last channel of the cycle is
        // visited. Samples left at the end carry the end of the walk.
        final Set<int> seen = <int>{};
        final List<int> pending = <int>[];
        for (int i = 0; i < all.length; i++) {
          seen.add(all[i].channel);
          pending.add(i);
          if (seen.length == schedule.channels.length) {
            for (final int j in pending) {
              stamps[j] = all[i].timeS;
            }
            pending.clear();
            seen.clear();
          }
        }
        for (final int j in pending) {
          stamps[j] = dur;
        }
      }
      for (int i = 0; i < all.length; i++) {
        visits.add((all[i], stamps[i]));
      }
    }
    for (final (ScanVisit v, double stamp) in visits) {
      if (!plan.recordingAt(v.timeS)) continue;
      final SurveyChannel ch = schedule.channels[v.channel];
      final double trueS = plan.sAt(v.timeS);
      samples.add(
        make(
          channel: channelIndex(ch),
          active: false,
          radio: v.radio + radioOffset,
          trueT: v.timeS,
          stamp: stamp,
          heard: hear(ch, trueS),
        ),
      );
    }
  }

  // Active testing on the serving AP's channel.
  final Set<int> activeChannels = <int>{};
  if (type != SurveyType.passive) {
    final List<double> times = <double>[];
    if (config.capture == CaptureMethod.stopAndGo) {
      for (final WalkPhase ph in plan.phases) {
        if (ph.kind != WalkPhaseKind.stop) continue;
        for (
          double t = kActiveTestIntervalS;
          t <= ph.t1 - ph.t0 + _eps;
          t += kActiveTestIntervalS
        ) {
          times.add(ph.t0 + t);
        }
      }
    } else {
      for (
        double t = kActiveTestIntervalS;
        t <= dur + _eps;
        t += kActiveTestIntervalS
      ) {
        if (plan.recordingAt(t)) times.add(t);
      }
    }
    for (final double t in times) {
      final double trueS = plan.sAt(t);
      final int? best = strongestOwnAp(config, pointAlong(config.path, trueS));
      if (best == null) continue;
      final SurveyChannel ch = config.aps[best].channel;
      final int ci = channelIndex(ch);
      activeChannels.add(ci);
      samples.add(
        make(
          channel: ci,
          active: true,
          radio: 0,
          trueT: t,
          stamp: t,
          heard: hear(ch, trueS, only: best),
        ),
      );
    }
  }

  samples.sort(
    (SurveySample a, SurveySample b) => a.measuredAtS.compareTo(b.measuredAtS),
  );

  // Per-channel stats.
  final List<ChannelStats> stats = <ChannelStats>[];
  for (int i = 0; i < channels.length; i++) {
    final List<SurveySample> own = <SurveySample>[
      for (final SurveySample s in samples)
        if (s.channel == i) s,
    ];
    // Passive samples decide a scanned channel's map; a channel only the
    // active radio used is mapped from its active samples.
    final List<SurveySample> mapped = own.any((SurveySample s) => !s.active)
        ? own.where((SurveySample s) => !s.active).toList()
        : own;
    final List<double> pos = <double>[
      for (final SurveySample s in mapped) s.placedS,
    ]..sort();
    double? gap;
    for (int k = 1; k < pos.length; k++) {
      final double g = pos[k] - pos[k - 1];
      if (gap == null || g > gap) gap = g;
    }
    final int? schedIdx = schedule?.channels.indexOf(channels[i]);
    final RevisitStats rv =
        schedule != null && schedIdx != null && schedIdx >= 0
        ? schedule.revisit[schedIdx]
        : const RevisitStats(
            meanS: kActiveTestIntervalS,
            maxS: kActiveTestIntervalS,
          );
    double maxErr = 0;
    for (final SurveySample s in mapped) {
      maxErr = math.max(maxErr, s.errorM);
    }
    stats.add(
      ChannelStats(
        channel: channels[i],
        samples: mapped.length,
        revisit: rv,
        spacingM: sampleSpacingM(config.paceMps, rv.meanS),
        largestGapM: gap,
        noData: noDataIntervals(pos, config.guessRangeM, length),
        maxErrorM: maxErr,
      ),
    );
  }

  return SurveyWalkResult._(
    config: config,
    plan: plan,
    schedule: schedule,
    channels: List<SurveyChannel>.unmodifiable(channels),
    samples: List<SurveySample>.unmodifiable(samples),
    stats: List<ChannelStats>.unmodifiable(stats),
    activeChannels: activeChannels,
    stopDurationS: stopDur,
  );
}

/// Walking-pace physics for the reveal (brief §5 (a)): coherence time
/// 0.423 / f_d with f_d = v / lambda, milliseconds.
double coherenceTimeMs(RoamBand band, double paceMps) {
  const double c = 299792458.0;
  final double lambda = c / (band.freqMHz * 1e6);
  final double fd = paceMps / lambda;
  return 0.423 / fd * 1000;
}

/// The longest HT/VHT/HE PPDU, ms (aPPDUMaxTime).
const double kLongestPpduMs = 5.484;
