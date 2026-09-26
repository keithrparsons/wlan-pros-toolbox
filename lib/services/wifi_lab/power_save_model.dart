// Power Save: the pure model behind the Wi-Fi Classroom tool (power-save).
//
// CLEAN-ROOM BUILD (2026-09-25) from the Wi-Fi Classroom wave 3 research brief §9
// and the wave 5 brief §9, per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/24-power-save.md. What those briefs pin, and what this file
// takes from them:
//   * 1 TU = 1024 µs; a 100 TU beacon interval (102.4 ms) is the common
//     default, not a mandated value.
//   * DTIM period = beacon intervals between DTIM beacons; buffered group
//     frames follow a DTIM beacon; the TIM tells a dozing client that the AP
//     holds unicast frames for it.
//   * Legacy PS: the client wakes for beacons and sends one PS-Poll per
//     buffered frame.
//   * U-APSD: a trigger frame opens a service period on trigger-enabled ACs.
//     QoS Info (non-AP STA): B0 AC_VO, B1 AC_VI, B2 AC_BK, B3 AC_BE, B5-B6
//     Max SP Length (0 = all, 1 = 2, 2 = 4, 3 = 6).
//   * TWT: wake interval = mantissa x 2^exponent µs, mantissa 16 bits,
//     exponent 5 bits; nominal minimum wake duration is one octet in units
//     of 256 µs or 1 TU; individual (per client) or broadcast (scheduled by
//     the AP in beacons).
//
// Everything else here is a TEACHING MODEL and is labeled so on screen: the
// frame-exchange durations (kWakeRampUs and friends), the traffic
// generator, the rule that a PS client wakes on every listen-interval beacon
// AND every DTIM beacon, that broadcast TWT service periods start at a
// beacon, and the currents (parameters the student sets). No battery figure
// from the research is used in the arithmetic; the one vendor example is
// shown separately and labeled as such.
//
// The whole run is computed at once, in microseconds, over a fixed horizon.
// Nothing here touches Flutter, so every rule is unit-testable.

import 'dart:math' as math;

// ── Units ───────────────────────────────────────────────────────────────────

/// One time unit (TU) in microseconds.
const int kTuUs = 1024;

/// [tu] time units in microseconds.
int tuToUs(int tu) => tu * kTuUs;

/// [tu] time units in milliseconds (100 TU = 102.4 ms).
double tuToMs(num tu) => tu * kTuUs / 1000;

// ── TWT fields ──────────────────────────────────────────────────────────────

/// The TWT Wake Interval Mantissa field is 16 bits.
const int kTwtMantissaBits = 16;
const int kTwtMantissaMax = (1 << kTwtMantissaBits) - 1; // 65535

/// The TWT Wake Interval Exponent field is 5 bits.
const int kTwtExponentBits = 5;
const int kTwtExponentMax = (1 << kTwtExponentBits) - 1; // 31

/// The Nominal Minimum TWT Wake Duration field is one octet.
const int kTwtDurationMax = 255;

/// TWT wake interval in µs: mantissa x 2^exponent. Null when either value
/// does not fit its field. Uses pow, not a shift, so it is exact on the web
/// too (a JS shift is 32-bit).
int? twtWakeIntervalUs(int mantissa, int exponent) {
  if (mantissa < 0 || mantissa > kTwtMantissaMax) return null;
  if (exponent < 0 || exponent > kTwtExponentMax) return null;
  return mantissa * math.pow(2, exponent).toInt();
}

/// The unit of the Nominal Minimum TWT Wake Duration (the Wake Duration
/// Unit bit: 0 = 256 µs, 1 = 1 TU).
enum TwtDurationUnit {
  us256(256, '256 µs'),
  tu(kTuUs, '1 TU (1024 µs)');

  const TwtDurationUnit(this.us, this.label);

  final int us;
  final String label;
}

/// Minimum wake duration in µs. Null when [value] does not fit one octet.
int? twtWakeDurationUs(int value, TwtDurationUnit unit) {
  if (value < 0 || value > kTwtDurationMax) return null;
  return value * unit.us;
}

// ── U-APSD fields ───────────────────────────────────────────────────────────

/// The four access categories with their U-APSD flag bit in a non-AP STA's
/// QoS Info field.
enum AccessCategory {
  vo('Voice', 'AC_VO', 0),
  vi('Video', 'AC_VI', 1),
  be('Best effort', 'AC_BE', 3),
  bk('Background', 'AC_BK', 2);

  const AccessCategory(this.label, this.code, this.qosInfoBit);

  final String label;
  final String code;

  /// Bit position in QoS Info: VO B0, VI B1, BK B2, BE B3.
  final int qosInfoBit;
}

/// Max SP Length (QoS Info B5-B6): how many buffered frames the AP may send
/// in one U-APSD service period.
enum MaxSpLength {
  all(0, null, 'All buffered'),
  two(1, 2, '2 frames'),
  four(2, 4, '4 frames'),
  six(3, 6, '6 frames');

  const MaxSpLength(this.code, this.frames, this.label);

  /// The two-bit field value.
  final int code;

  /// Frames per service period; null means all buffered frames.
  final int? frames;
  final String label;
}

/// The Max SP Length for a field [code] (0 to 3).
MaxSpLength maxSpFromCode(int code) =>
    MaxSpLength.values.firstWhere((MaxSpLength m) => m.code == code);

/// The QoS Info byte a non-AP STA sends for [acs] and [maxSp] (Q-Ack and
/// More Data Ack left 0).
int qosInfoByte(Set<AccessCategory> acs, MaxSpLength maxSp) {
  int v = 0;
  for (final AccessCategory ac in acs) {
    v |= 1 << ac.qosInfoBit;
  }
  return v | (maxSp.code << 5);
}

// ── Teaching-model timings (illustrative, labeled on screen) ────────────────

/// Radio ramp from doze to ready, before any wake.
const double kWakeRampUs = 500;

/// Receiving one beacon.
const double kBeaconRxUs = 1000;

/// One legacy PS-Poll exchange: poll, data, ACK.
const double kPsPollUs = 600;

/// One frame delivered inside a service period (or to an awake client):
/// data and ACK.
const double kSpFrameUs = 400;

/// A U-APSD trigger (QoS Null) and its ACK.
const double kTriggerUs = 300;

/// One uplink frame and its ACK.
const double kUplinkUs = 400;

/// One group-addressed frame after a DTIM beacon.
const double kGroupFrameUs = 300;

/// Where the first individual TWT service period starts: 25 ms in, so it
/// does not sit on beacon 0.
const double kTwtFirstSpUs = 25000;

/// The longest TWT wake interval the simulator accepts: 5 minutes, so four
/// cycles fit in the longest run.
const int kTwtMaxIntervalUs = 300 * 1000000;

/// Run length: at least 60 s, at least four TWT cycles, at most 20 minutes.
const int kMinHorizonUs = 60 * 1000000;
const int kMaxHorizonUs = 1200 * 1000000;

// ── Configuration ───────────────────────────────────────────────────────────

enum PsMode {
  awake('Always awake', 'Awake'),
  legacy('Legacy PS (PS-Poll)', 'Legacy PS'),
  uapsd('U-APSD', 'U-APSD'),
  twt('Target Wake Time (TWT)', 'TWT');

  const PsMode(this.label, this.short);

  final String label;
  final String short;
}

enum TwtKind {
  individual('Individual'),
  broadcast('Broadcast');

  const TwtKind(this.label);

  final String label;
}

class UapsdSettings {
  const UapsdSettings({
    this.acs = const <AccessCategory>{
      AccessCategory.vo,
      AccessCategory.vi,
      AccessCategory.be,
      AccessCategory.bk,
    },
    this.maxSp = MaxSpLength.all,
  });

  /// Trigger- and delivery-enabled ACs.
  final Set<AccessCategory> acs;
  final MaxSpLength maxSp;

  UapsdSettings copyWith({Set<AccessCategory>? acs, MaxSpLength? maxSp}) =>
      UapsdSettings(acs: acs ?? this.acs, maxSp: maxSp ?? this.maxSp);

  @override
  bool operator ==(Object other) =>
      other is UapsdSettings &&
      other.maxSp == maxSp &&
      other.acs.length == acs.length &&
      other.acs.containsAll(acs);

  @override
  int get hashCode =>
      Object.hash(maxSp, Object.hashAllUnordered(acs.map((a) => a.index)));
}

class TwtSettings {
  const TwtSettings({
    this.mantissa = 62500,
    this.exponent = 4,
    this.duration = 16,
    this.durationUnit = TwtDurationUnit.us256,
    this.kind = TwtKind.individual,
    this.wakeForDtim = false,
  });

  final int mantissa;
  final int exponent;

  /// Nominal minimum wake duration, in [durationUnit]s.
  final int duration;
  final TwtDurationUnit durationUnit;
  final TwtKind kind;

  /// Also wake for DTIM beacons to hear group traffic.
  final bool wakeForDtim;

  int? get intervalUs => twtWakeIntervalUs(mantissa, exponent);
  int? get durationUs => twtWakeDurationUs(duration, durationUnit);

  /// Why these values cannot run, in words, or null when they can.
  String? get error {
    final int? i = intervalUs;
    if (i == null) {
      return 'The mantissa must be 0 to $kTwtMantissaMax (16 bits) and the '
          'exponent 0 to $kTwtExponentMax (5 bits).';
    }
    if (i == 0) return 'A mantissa of 0 gives no wake interval.';
    if (i > kTwtMaxIntervalUs) {
      return 'This simulator runs wake intervals up to 5 minutes; this one '
          'is ${(i / 1e6).toStringAsFixed(0)} s.';
    }
    final int? d = durationUs;
    if (d == null || d == 0) return 'The wake duration must be 1 to 255.';
    if (d >= i) {
      return 'The wake duration is as long as the interval, so the client '
          'would never doze.';
    }
    return null;
  }

  TwtSettings copyWith({
    int? mantissa,
    int? exponent,
    int? duration,
    TwtDurationUnit? durationUnit,
    TwtKind? kind,
    bool? wakeForDtim,
  }) => TwtSettings(
    mantissa: mantissa ?? this.mantissa,
    exponent: exponent ?? this.exponent,
    duration: duration ?? this.duration,
    durationUnit: durationUnit ?? this.durationUnit,
    kind: kind ?? this.kind,
    wakeForDtim: wakeForDtim ?? this.wakeForDtim,
  );

  @override
  bool operator ==(Object other) =>
      other is TwtSettings &&
      other.mantissa == mantissa &&
      other.exponent == exponent &&
      other.duration == duration &&
      other.durationUnit == durationUnit &&
      other.kind == kind &&
      other.wakeForDtim == wakeForDtim;

  @override
  int get hashCode => Object.hash(
    mantissa,
    exponent,
    duration,
    durationUnit,
    kind,
    wakeForDtim,
  );
}

class TrafficSettings {
  const TrafficSettings({
    this.dlBurstsPerS = 0.5,
    this.dlBurstSize = 1,
    this.ulPerS = 0.5,
    this.groupPerS = 2,
    this.ac = AccessCategory.be,
    this.regular = false,
    this.seed = 1,
  });

  /// Downlink bursts arriving at the AP per second.
  final double dlBurstsPerS;

  /// Frames in each downlink burst.
  final int dlBurstSize;

  /// Uplink frames the client sends per second.
  final double ulPerS;

  /// Group-addressed (broadcast and multicast) frames per second.
  final double groupPerS;

  /// The access category of the client's unicast traffic, both ways.
  final AccessCategory ac;

  /// Evenly spaced arrivals (true) or random ones (false).
  final bool regular;
  final int seed;

  TrafficSettings copyWith({
    double? dlBurstsPerS,
    int? dlBurstSize,
    double? ulPerS,
    double? groupPerS,
    AccessCategory? ac,
    bool? regular,
    int? seed,
  }) => TrafficSettings(
    dlBurstsPerS: dlBurstsPerS ?? this.dlBurstsPerS,
    dlBurstSize: dlBurstSize ?? this.dlBurstSize,
    ulPerS: ulPerS ?? this.ulPerS,
    groupPerS: groupPerS ?? this.groupPerS,
    ac: ac ?? this.ac,
    regular: regular ?? this.regular,
    seed: seed ?? this.seed,
  );

  @override
  bool operator ==(Object other) =>
      other is TrafficSettings &&
      other.dlBurstsPerS == dlBurstsPerS &&
      other.dlBurstSize == dlBurstSize &&
      other.ulPerS == ulPerS &&
      other.groupPerS == groupPerS &&
      other.ac == ac &&
      other.regular == regular &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(
    dlBurstsPerS,
    dlBurstSize,
    ulPerS,
    groupPerS,
    ac,
    regular,
    seed,
  );
}

class PsConfig {
  const PsConfig({
    this.beaconTu = 100,
    this.dtimPeriod = 3,
    this.listenInterval = 3,
    this.mode = PsMode.legacy,
    this.uapsd = const UapsdSettings(),
    this.twt = const TwtSettings(),
    this.traffic = const TrafficSettings(),
    this.awakeMa = 50,
    this.dozeMa = 0.02,
    this.batteryMah = 1000,
  });

  final int beaconTu;
  final int dtimPeriod;

  /// A PS client reads the TIM on every Nth beacon.
  final int listenInterval;
  final PsMode mode;
  final UapsdSettings uapsd;
  final TwtSettings twt;
  final TrafficSettings traffic;

  /// Current while the radio is awake, mA (a parameter, not a measurement).
  final double awakeMa;

  /// Current while dozing, mA.
  final double dozeMa;

  /// Battery capacity for the life estimate, mAh.
  final double batteryMah;

  int get beaconUs => tuToUs(beaconTu);

  /// The run length: at least 60 s, and four TWT cycles when the TWT values
  /// are valid, capped at 20 minutes. The same for every mode, so two modes
  /// compare over the same traffic.
  int get horizonUs {
    final int? i = twt.error == null ? twt.intervalUs : null;
    if (i == null) return kMinHorizonUs;
    return (4 * i).clamp(kMinHorizonUs, kMaxHorizonUs);
  }

  PsConfig copyWith({
    int? beaconTu,
    int? dtimPeriod,
    int? listenInterval,
    PsMode? mode,
    UapsdSettings? uapsd,
    TwtSettings? twt,
    TrafficSettings? traffic,
    double? awakeMa,
    double? dozeMa,
    double? batteryMah,
  }) => PsConfig(
    beaconTu: beaconTu ?? this.beaconTu,
    dtimPeriod: dtimPeriod ?? this.dtimPeriod,
    listenInterval: listenInterval ?? this.listenInterval,
    mode: mode ?? this.mode,
    uapsd: uapsd ?? this.uapsd,
    twt: twt ?? this.twt,
    traffic: traffic ?? this.traffic,
    awakeMa: awakeMa ?? this.awakeMa,
    dozeMa: dozeMa ?? this.dozeMa,
    batteryMah: batteryMah ?? this.batteryMah,
  );

  @override
  bool operator ==(Object other) =>
      other is PsConfig &&
      other.beaconTu == beaconTu &&
      other.dtimPeriod == dtimPeriod &&
      other.listenInterval == listenInterval &&
      other.mode == mode &&
      other.uapsd == uapsd &&
      other.twt == twt &&
      other.traffic == traffic &&
      other.awakeMa == awakeMa &&
      other.dozeMa == dozeMa &&
      other.batteryMah == batteryMah;

  @override
  int get hashCode => Object.hash(
    beaconTu,
    dtimPeriod,
    listenInterval,
    mode,
    uapsd,
    twt,
    traffic,
    awakeMa,
    dozeMa,
    batteryMah,
  );
}

// ── Energy arithmetic ───────────────────────────────────────────────────────

/// Average current: awake share at [awakeMa], the rest at [dozeMa].
double averageCurrentMa(double awakeFraction, double awakeMa, double dozeMa) =>
    awakeFraction * awakeMa + (1 - awakeFraction) * dozeMa;

/// Battery life in hours: capacity over average current.
double batteryHours(double capacityMah, double averageMa) =>
    averageMa <= 0 ? double.infinity : capacityMah / averageMa;

/// The longest a group frame can wait: it arrives just after a DTIM beacon,
/// waits a whole DTIM period, then goes first after the next DTIM beacon.
double groupLatencyBoundUs(int beaconTu, int dtimPeriod) =>
    dtimPeriod * tuToUs(beaconTu) + kBeaconRxUs + kGroupFrameUs;

// ── Run output ──────────────────────────────────────────────────────────────

/// What the client's radio is doing while awake.
enum AwakeKind {
  /// Ramping up, receiving a beacon, or simply listening.
  listen,

  /// Receiving frames (PS-Poll exchanges, service-period deliveries, group
  /// frames).
  frames,

  /// Sending an uplink frame or a trigger.
  send,

  /// Inside a TWT service period with nothing to receive.
  twtSp,
}

class AwakeSpan {
  const AwakeSpan(this.startUs, this.endUs, this.kind);

  final double startUs;
  final double endUs;
  final AwakeKind kind;
}

class BeaconMark {
  const BeaconMark({
    required this.index,
    required this.tUs,
    required this.dtim,
    required this.listened,
    required this.tim,
    required this.groupFrames,
  });

  final int index;
  final double tUs;
  final bool dtim;

  /// The client was awake for this beacon.
  final bool listened;

  /// The TIM bit for this client was set (frames held at TBTT).
  final bool tim;

  /// Group frames sent after this beacon (DTIM only).
  final int groupFrames;
}

enum FrameKind { downlink, group, uplink }

class FrameRecord {
  FrameRecord(this.kind, this.arrivalUs);

  final FrameKind kind;
  final double arrivalUs;

  /// When delivery (or, uplink, the send) finished; null if still waiting.
  double? doneUs;

  /// A group frame sent while the client was dozing.
  bool missed = false;

  double? get latencyUs => doneUs == null ? null : doneUs! - arrivalUs;
}

/// Frames held at the AP for this client, from [tUs] on.
class QueueStep {
  const QueueStep(this.tUs, this.depth);

  final double tUs;
  final int depth;
}

class LatencyStats {
  const LatencyStats({
    required this.count,
    required this.meanUs,
    required this.worstUs,
  });

  final int count;
  final double? meanUs;
  final double? worstUs;

  static LatencyStats of(Iterable<double> xs) {
    int n = 0;
    double sum = 0;
    double worst = 0;
    for (final double x in xs) {
      n++;
      sum += x;
      if (x > worst) worst = x;
    }
    return LatencyStats(
      count: n,
      meanUs: n == 0 ? null : sum / n,
      worstUs: n == 0 ? null : worst,
    );
  }
}

class PsRun {
  PsRun._({
    required this.config,
    required this.mode,
    required this.horizonUs,
    required this.spans,
    required this.beacons,
    required this.frames,
    required this.queue,
    required this.serviceStarts,
  }) {
    // Awake time: the union of spans, clipped to the run.
    final List<AwakeSpan> sorted = List<AwakeSpan>.of(spans)
      ..sort((AwakeSpan a, AwakeSpan b) => a.startUs.compareTo(b.startUs));
    double? s;
    double? e;
    for (final AwakeSpan sp in sorted) {
      final double a = sp.startUs.clamp(0, horizonUs.toDouble());
      final double b = sp.endUs.clamp(0, horizonUs.toDouble());
      if (b <= a) continue;
      if (e == null || a > e) {
        if (e != null) _merged.add((s!, e));
        s = a;
        e = b;
      } else if (b > e) {
        e = b;
      }
    }
    if (e != null) _merged.add((s!, e));
    awakeUs = awakeUsBetween(0, horizonUs.toDouble());
    wakeCount = _merged.length;
  }

  /// The awake intervals, merged and in order.
  final List<(double, double)> _merged = <(double, double)>[];

  /// Awake time inside [fromUs, toUs).
  double awakeUsBetween(double fromUs, double toUs) {
    double t = 0;
    for (final (double a, double b) in _merged) {
      if (b <= fromUs) continue;
      if (a >= toUs) break;
      t += math.min(b, toUs) - math.max(a, fromUs);
    }
    return t;
  }

  /// Wakes that start inside [fromUs, toUs).
  int wakesBetween(double fromUs, double toUs) => _merged
      .where(((double, double) w) => w.$1 >= fromUs && w.$1 < toUs)
      .length;

  final PsConfig config;
  final PsMode mode;
  final int horizonUs;
  final List<AwakeSpan> spans;
  final List<BeaconMark> beacons;
  final List<FrameRecord> frames;
  final List<QueueStep> queue;

  /// TWT service-period starts (TWT mode only).
  final List<double> serviceStarts;

  late final double awakeUs;
  late final int wakeCount;

  double get awakeFraction => awakeUs / horizonUs;

  double get averageMa =>
      averageCurrentMa(awakeFraction, config.awakeMa, config.dozeMa);

  double get batteryLifeHours => batteryHours(config.batteryMah, averageMa);

  Iterable<FrameRecord> _done(FrameKind k) => frames.where(
    (FrameRecord f) =>
        f.kind == k && !f.missed && f.doneUs != null && f.doneUs! <= horizonUs,
  );

  LatencyStats get downlink =>
      LatencyStats.of(_done(FrameKind.downlink).map((f) => f.latencyUs!));

  LatencyStats get group =>
      LatencyStats.of(_done(FrameKind.group).map((f) => f.latencyUs!));

  LatencyStats get uplink =>
      LatencyStats.of(_done(FrameKind.uplink).map((f) => f.latencyUs!));

  int get groupMissed => frames
      .where(
        (FrameRecord f) =>
            f.kind == FrameKind.group &&
            f.missed &&
            f.doneUs != null &&
            f.doneUs! <= horizonUs,
      )
      .length;

  /// Downlink frames that arrived in the run and were not delivered in it.
  int get downlinkWaiting => frames
      .where(
        (FrameRecord f) =>
            f.kind == FrameKind.downlink &&
            (f.doneUs == null || f.doneUs! > horizonUs),
      )
      .length;

  /// Beacons the client woke for.
  int get beaconsHeard => beacons.where((BeaconMark b) => b.listened).length;
}

// ── Traffic ─────────────────────────────────────────────────────────────────

List<double> _arrivals(
  double perS,
  int horizonUs,
  bool regular,
  int seed,
  double phase,
) {
  if (perS <= 0) return const <double>[];
  final double period = 1e6 / perS;
  final List<double> out = <double>[];
  if (regular) {
    for (double t = period * phase; t < horizonUs; t += period) {
      out.add(t);
    }
  } else {
    final math.Random rng = math.Random(seed);
    double t = 0;
    while (true) {
      t += -math.log(1 - rng.nextDouble()) * period;
      if (t >= horizonUs) break;
      out.add(t);
    }
  }
  return out;
}

class _Traffic {
  _Traffic(PsConfig c) {
    final TrafficSettings t = c.traffic;
    final int h = c.horizonUs;
    for (final double a in _arrivals(
      t.dlBurstsPerS,
      h,
      t.regular,
      t.seed * 7919 + 1,
      0.37,
    )) {
      for (int i = 0; i < t.dlBurstSize; i++) {
        downlink.add(FrameRecord(FrameKind.downlink, a));
      }
    }
    for (final double a in _arrivals(
      t.ulPerS,
      h,
      t.regular,
      t.seed * 7919 + 2,
      0.61,
    )) {
      uplink.add(FrameRecord(FrameKind.uplink, a));
    }
    for (final double a in _arrivals(
      t.groupPerS,
      h,
      t.regular,
      t.seed * 7919 + 3,
      0.13,
    )) {
      group.add(FrameRecord(FrameKind.group, a));
    }
  }

  final List<FrameRecord> downlink = <FrameRecord>[];
  final List<FrameRecord> uplink = <FrameRecord>[];
  final List<FrameRecord> group = <FrameRecord>[];
}

// ── The client's radio ──────────────────────────────────────────────────────

class _Radio {
  final List<AwakeSpan> spans = <AwakeSpan>[];

  /// The radio is busy until this time.
  double cursor = double.negativeInfinity;

  /// Do [kind] for [durUs], not before [t]. A radio that has been idle for
  /// longer than the ramp dozed, so it ramps first; a shorter gap is spent
  /// awake. Returns the start of the activity itself.
  double act(double t, double durUs, AwakeKind kind) {
    double s = math.max(t, cursor);
    if (s - cursor > kWakeRampUs) {
      spans.add(AwakeSpan(s - kWakeRampUs, s, AwakeKind.listen));
    } else if (s > cursor) {
      spans.add(AwakeSpan(cursor, s, AwakeKind.listen));
    }
    spans.add(AwakeSpan(s, s + durUs, kind));
    cursor = s + durUs;
    return s;
  }
}

/// Unicast frames held at the AP, admitted as they arrive.
class _ApBuffer {
  _ApBuffer(this.frames);

  final List<FrameRecord> frames;
  int _next = 0;
  final List<FrameRecord> held = <FrameRecord>[];

  /// Admit every frame that has arrived by [t] (strictly before, so a frame
  /// arriving at a TBTT just misses that beacon's TIM).
  void admit(double t) {
    while (_next < frames.length && frames[_next].arrivalUs < t) {
      held.add(frames[_next++]);
    }
  }

  bool get isEmpty => held.isEmpty;

  FrameRecord take() => held.removeAt(0);

  /// The arrival time of the next frame not yet admitted.
  double? get nextArrival =>
      _next < frames.length ? frames[_next].arrivalUs : null;
}

// ── Simulation ──────────────────────────────────────────────────────────────

/// Runs [config] with [mode] (defaults to the config's own mode).
PsRun simulatePowerSave(PsConfig config, {PsMode? mode}) {
  final PsMode m = mode ?? config.mode;
  final _Traffic tr = _Traffic(config);
  final int h = config.horizonUs;
  final int bi = config.beaconUs;
  final int dtim = config.dtimPeriod;
  final _Radio radio = _Radio();
  final _ApBuffer ap = _ApBuffer(tr.downlink);
  final List<BeaconMark> beacons = <BeaconMark>[];
  final List<double> spStarts = <double>[];

  final TwtSettings twt = config.twt;
  final bool twtOk = twt.error == null;
  final int twtI = twtOk ? twt.intervalUs! : 0;
  final int twtD = twtOk ? twt.durationUs! : 0;
  final int bcastEvery = twtOk ? math.max(1, (twtI / bi).ceil()) : 1;

  final bool uapsdAc = config.uapsd.acs.contains(config.traffic.ac);
  final int? spMax = config.uapsd.maxSp.frames;

  int groupNext = 0;

  void deliverOne(double durUs) {
    final FrameRecord f = ap.take();
    radio.act(radio.cursor, durUs, AwakeKind.frames);
    f.doneUs = radio.cursor;
  }

  void psPollAll() {
    while (true) {
      ap.admit(radio.cursor);
      if (ap.isEmpty) break;
      deliverOne(kPsPollUs);
    }
  }

  /// U-APSD service periods, the first already triggered.
  void uapsdSps({required bool triggered}) {
    bool first = triggered;
    while (true) {
      ap.admit(radio.cursor);
      if (ap.isEmpty) break;
      if (!first) radio.act(radio.cursor, kTriggerUs, AwakeKind.send);
      first = false;
      ap.admit(radio.cursor);
      int n = 0;
      while (!ap.isEmpty && (spMax == null || n < spMax)) {
        deliverOne(kSpFrameUs);
        n++;
      }
    }
  }

  void retrieve() {
    if (m == PsMode.uapsd && uapsdAc) {
      uapsdSps(triggered: false);
    } else {
      psPollAll();
    }
  }

  // Group frames go right after every DTIM beacon, whoever listens.
  int sendGroup(double tbtt, double? clientBeaconStart) {
    int n = 0;
    final double base = (clientBeaconStart ?? tbtt) + kBeaconRxUs;
    while (groupNext < tr.group.length &&
        tr.group[groupNext].arrivalUs < tbtt) {
      final FrameRecord f = tr.group[groupNext++];
      n++;
      f.doneUs = base + n * kGroupFrameUs;
      f.missed = clientBeaconStart == null;
    }
    if (n > 0 && clientBeaconStart != null) {
      radio.act(radio.cursor, n * kGroupFrameUs, AwakeKind.frames);
    }
    return n;
  }

  if (m == PsMode.awake) {
    // Always awake: every beacon heard, unicast delivered on arrival, group
    // frames still wait for the DTIM (other clients in the cell doze).
    radio.spans.add(AwakeSpan(0, h.toDouble(), AwakeKind.listen));
    double medium = 0;
    for (final FrameRecord f in tr.downlink) {
      final double s = math.max(f.arrivalUs, medium);
      f.doneUs = s + kSpFrameUs;
      medium = f.doneUs!;
      radio.spans.add(AwakeSpan(s, f.doneUs!, AwakeKind.frames));
    }
    double up = 0;
    for (final FrameRecord f in tr.uplink) {
      final double s = math.max(f.arrivalUs, up);
      f.doneUs = s + kUplinkUs;
      up = f.doneUs!;
      radio.spans.add(AwakeSpan(s, f.doneUs!, AwakeKind.send));
    }
    for (int k = 0; k * bi < h; k++) {
      final double tbtt = (k * bi).toDouble();
      final bool isDtim = k % dtim == 0;
      int n = 0;
      if (isDtim) {
        while (groupNext < tr.group.length &&
            tr.group[groupNext].arrivalUs < tbtt) {
          final FrameRecord f = tr.group[groupNext++];
          n++;
          f.doneUs = tbtt + kBeaconRxUs + n * kGroupFrameUs;
        }
        if (n > 0) {
          radio.spans.add(
            AwakeSpan(
              tbtt + kBeaconRxUs,
              tbtt + kBeaconRxUs + n * kGroupFrameUs,
              AwakeKind.frames,
            ),
          );
        }
      }
      beacons.add(
        BeaconMark(
          index: k,
          tUs: tbtt,
          dtim: isDtim,
          listened: true,
          tim: false,
          groupFrames: n,
        ),
      );
    }
  } else {
    // Events in time order: beacons, uplink frames, TWT service periods.
    final List<_Event> events = <_Event>[
      for (int k = 0; k * bi < h; k++)
        _Event((k * bi).toDouble(), _EventKind.beacon, k),
      for (int i = 0; i < tr.uplink.length; i++)
        _Event(tr.uplink[i].arrivalUs, _EventKind.uplink, i),
      if (m == PsMode.twt && twtOk && twt.kind == TwtKind.individual)
        for (double t = kTwtFirstSpUs; t < h; t += twtI)
          _Event(t, _EventKind.sp, 0),
    ]..sort(_Event.compare);

    for (final _Event ev in events) {
      switch (ev.kind) {
        case _EventKind.uplink:
          final FrameRecord f = tr.uplink[ev.index];
          radio.act(f.arrivalUs, kUplinkUs, AwakeKind.send);
          f.doneUs = radio.cursor;
          // An uplink frame on a trigger-enabled AC is itself the trigger.
          if (m == PsMode.uapsd && uapsdAc) uapsdSps(triggered: true);
        case _EventKind.beacon:
          final int k = ev.index;
          final double tbtt = ev.tUs;
          final bool isDtim = k % dtim == 0;
          ap.admit(tbtt);
          final bool tim = !ap.isEmpty;
          final bool bcastSp =
              m == PsMode.twt &&
              twtOk &&
              twt.kind == TwtKind.broadcast &&
              k % bcastEvery == 0;
          final bool listen = switch (m) {
            PsMode.legacy ||
            PsMode.uapsd => k % config.listenInterval == 0 || isDtim,
            PsMode.twt => bcastSp || (twt.wakeForDtim && isDtim),
            PsMode.awake => true,
          };
          double? start;
          if (listen) start = radio.act(tbtt, kBeaconRxUs, AwakeKind.listen);
          final int n = isDtim ? sendGroup(tbtt, start) : 0;
          beacons.add(
            BeaconMark(
              index: k,
              tUs: tbtt,
              dtim: isDtim,
              listened: listen,
              tim: tim,
              groupFrames: n,
            ),
          );
          if (listen && tim && m != PsMode.twt) retrieve();
          if (bcastSp) _serviceWindow(radio, ap, radio.cursor, twtD, spStarts);
        case _EventKind.sp:
          _serviceWindow(radio, ap, ev.tUs, twtD, spStarts);
      }
    }
  }

  // Queue depth over time: +1 per arrival, -1 per delivery.
  final List<(double, int)> deltas = <(double, int)>[
    for (final FrameRecord f in tr.downlink) (f.arrivalUs, 1),
    for (final FrameRecord f in tr.downlink)
      if (f.doneUs != null) (f.doneUs!, -1),
  ]..sort(((double, int) a, (double, int) b) => a.$1.compareTo(b.$1));
  final List<QueueStep> queue = <QueueStep>[const QueueStep(0, 0)];
  int depth = 0;
  for (final (double t, int d) in deltas) {
    depth += d;
    if (queue.last.tUs == t) {
      queue[queue.length - 1] = QueueStep(t, depth);
    } else {
      queue.add(QueueStep(t, depth));
    }
  }

  return PsRun._(
    config: config,
    mode: m,
    horizonUs: h,
    spans: radio.spans,
    beacons: beacons,
    frames: <FrameRecord>[...tr.downlink, ...tr.group, ...tr.uplink],
    queue: queue,
    serviceStarts: spStarts,
  );
}

/// One TWT service period from [t]: the client is awake for [durUs] and the
/// AP delivers held frames (and frames that arrive) while they fit.
void _serviceWindow(
  _Radio radio,
  _ApBuffer ap,
  double t,
  int durUs,
  List<double> starts,
) {
  final double s = radio.act(t, durUs.toDouble(), AwakeKind.twtSp);
  starts.add(s);
  final double end = s + durUs;
  double d = s;
  while (true) {
    ap.admit(d);
    if (ap.isEmpty) {
      final double? next = ap.nextArrival;
      if (next == null || next >= end - kSpFrameUs) break;
      d = next + 1e-6;
      continue;
    }
    if (d + kSpFrameUs > end) break;
    final FrameRecord f = ap.take();
    radio.spans.add(AwakeSpan(d, d + kSpFrameUs, AwakeKind.frames));
    d += kSpFrameUs;
    f.doneUs = d;
  }
}

enum _EventKind { beacon, uplink, sp }

class _Event {
  const _Event(this.tUs, this.kind, this.index);

  final double tUs;
  final _EventKind kind;
  final int index;

  /// By time; at a tie, a beacon first.
  static int compare(_Event a, _Event b) {
    final int c = a.tUs.compareTo(b.tUs);
    if (c != 0) return c;
    return a.kind.index.compareTo(b.kind.index);
  }
}

// ── Formatting ──────────────────────────────────────────────────────────────

/// A duration in µs as ms or s, for readouts.
String fmtUs(double us) {
  final double ms = us / 1000;
  if (ms < 10) return '${ms.toStringAsFixed(2)} ms';
  if (ms < 1000) return '${ms.toStringAsFixed(1)} ms';
  final double s = ms / 1000;
  return s < 100 ? '${s.toStringAsFixed(2)} s' : '${s.toStringAsFixed(0)} s';
}

/// A current in mA, shown in µA below 1 mA.
String fmtCurrent(double ma) {
  if (ma < 1) {
    final double ua = ma * 1000;
    return ua < 10
        ? '${ua.toStringAsFixed(1)} µA'
        : '${ua.toStringAsFixed(0)} µA';
  }
  return ma < 10
      ? '${ma.toStringAsFixed(2)} mA'
      : '${ma.toStringAsFixed(1)} mA';
}

/// A battery life in hours, as hours, days or years.
String fmtLife(double hours) {
  if (hours.isInfinite) return 'unlimited';
  if (hours < 48) return '${hours.toStringAsFixed(1)} hours';
  final double days = hours / 24;
  if (days < 365) return '${days.toStringAsFixed(0)} days';
  return '${(days / 365).toStringAsFixed(1)} years';
}

/// A percentage with enough places to show small shares.
String fmtPct(double fraction) {
  final double p = fraction * 100;
  if (p >= 10) return '${p.toStringAsFixed(1)}%';
  if (p >= 1) return '${p.toStringAsFixed(2)}%';
  return '${p.toStringAsFixed(3)}%';
}
