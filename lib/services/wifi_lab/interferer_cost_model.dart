// What an Interferer Costs (and how a NIC hears the air): the pure-Dart model
// behind the Wi-Fi Classroom tool `interferer-cost`. No Flutter imports.
//
// THE LESSON (Keith, 2026-09-27): the real cost of an interferer is usually
// not lost frames. It is how readily your radio holds off. A Wi-Fi radio
// waits for another Wi-Fi transmitter it can decode at -82 dBm (preamble
// detect), but for energy it cannot decode only at -62 dBm (energy detect).
// That 20 dB gap is 100x in power, so a Wi-Fi neighbor on your channel makes
// you wait from much farther away than a microwave oven of the same power.
// The counterexample (Pax's brief, 1.6) is a continuous analog video sender:
// it stays under energy detect, so nobody waits, and it ruins frames anyway.
//
// CLEAN-ROOM BUILD (2026-09-27) from myPKA Deliverables/2026-09-27-classroom-
// interferer-and-ds-sources/RESEARCH-BRIEF.md Part 1. Pinned vs illustrative:
//   PINNED  -82 dBm preamble detect and -62 dBm energy detect per 20 MHz
//           (802.11-2020 17.3.10.6, two sources); the primary-channel PD
//           scaling -82/-79/-76/-73 for 20/40/80/160 MHz PPDUs (one source
//           past 20 MHz, said so in help; 320 MHz omitted, it is arithmetic
//           only); the 20 dB gap and the distance ratio 10^(20/10n) (calc);
//           microwave duty 0.5 per mains cycle, 16.67 ms at 60 Hz (measured)
//           and 20 ms at 50 Hz (calc); oven peak 2.45 to 2.47 GHz; Bluetooth
//           Classic 79 x 1 MHz hops, so about 20/79 of hops land in a 20 MHz
//           channel (calc); FSPL at 1 m (calc).
//   ILLUS   the -95 dBm noise floor; every default level; the Wi-Fi
//           neighbor's 30% airtime; the Bluetooth link's active-slot share;
//           the oven's level on channels 6 and 1 relative to its peak; the
//           20 dBm reference transmitter for the distances; and the whole
//           corruption curve (Pax found no per-MCS SINR or retry curve). The
//           curve's midpoints are chosen to agree with what Airshark (IMC
//           2011) measured on a good link: the oven costs almost nothing
//           below about -60 dBm, Bluetooth never costs more than about 10%,
//           and a video camera costs 80% or more at -70 dBm.
//
// ONE PLACE, TWO DECISIONS. Waiting is decided at the transmitter; whether a
// frame survives is decided at its receiver. This model puts both at your
// radio, so one level per source drives both. The help says so.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'fspl_math.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kInterfererCostToolId = 'interferer-cost';

// ── Thresholds (pinned) ─────────────────────────────────────────────────────

/// Preamble detect for a 20 MHz PPDU: the standard's minimum requirement.
const double kIcPreambleDetect20Dbm = -82;

/// Energy detect on the primary 20 MHz, whatever sent the energy.
const double kIcEnergyDetectDbm = -62;

/// Primary-channel preamble detect by PPDU width. 20 MHz is two sources; the
/// 40/80/160 values are one source (Bejarano, Knightly, Park 2013). 320 MHz
/// is omitted: -70 would be arithmetic from the pattern, pinned nowhere.
const Map<int, double> kIcPreambleDetectByWidth = <int, double>{
  20: -82,
  40: -79,
  80: -76,
  160: -73,
};

/// Widths offered, 5 GHz only. 2.4 GHz is held to 20 MHz.
const List<int> kIcWidthsMHz = <int>[20, 40, 80, 160];

/// Noise floor in 20 MHz, illustrative: thermal -101 dBm plus a 6 dB noise
/// figure (Pax 1.5).
const double kIcNoiseFloorDbm = -95;

/// A real chip's preamble detect, about 4 dB above a -95 dBm noise floor
/// (one vendor source, 2017). Help only; the model uses the standard's -82.
const double kIcRealChipPreambleDbm = -91;

/// The same-power transmitter the distances assume, EIRP, illustrative.
const double kIcReferenceEirpDbm = 20;

/// The path-loss exponents Pax's table works (free space, typical indoor,
/// dense walls).
const List<double> kIcExponents = <double>[2.0, 3.0, 3.5];

// ── Sources ─────────────────────────────────────────────────────────────────

enum IcSource {
  wifiNeighbor(
    label: 'Neighbor\'s AP on your channel',
    short: 'Wi-Fi AP',
    isWifi: true,
  ),
  microwave(label: 'Microwave oven', short: 'Microwave', isWifi: false),
  bluetooth(label: 'Bluetooth', short: 'Bluetooth', isWifi: false),
  videoSender(label: 'Analog video sender', short: 'Video', isWifi: false);

  const IcSource({
    required this.label,
    required this.short,
    required this.isWifi,
  });

  final String label;

  /// For a segmented toggle.
  final String short;

  /// True when your radio can decode its preamble, so -82 applies.
  final bool isWifi;
}

/// Your radio's channel. The 2.4 GHz channels decide how much of the oven
/// lands in yours; 5 GHz has no oven and no Bluetooth.
enum IcChannel {
  ch1(label: 'Ch 1', centerMHz: 2412, is24: true),
  ch6(label: 'Ch 6', centerMHz: 2437, is24: true),
  ch11(label: 'Ch 11', centerMHz: 2462, is24: true),
  ch36(label: '5 GHz', centerMHz: 5180, is24: false);

  const IcChannel({
    required this.label,
    required this.centerMHz,
    required this.is24,
  });

  final String label;
  final double centerMHz;
  final bool is24;

  /// "channel 11" / "5 GHz channel 36", for prose.
  String get prose => switch (this) {
    IcChannel.ch1 => 'channel 1',
    IcChannel.ch6 => 'channel 6',
    IcChannel.ch11 => 'channel 11',
    IcChannel.ch36 => '5 GHz channel 36',
  };
}

enum IcMains {
  hz60(label: '60 Hz', hz: 60),
  hz50(label: '50 Hz', hz: 50);

  const IcMains({required this.label, required this.hz});

  final String label;
  final int hz;
}

// ── Microwave (pinned timing, illustrative roll-off) ────────────────────────

/// One ON burst per mains cycle, about half of it (Airshark D = 0.5; a
/// 2007 vendor paper; Kamerman and Erkocevic 1997).
const double kIcMicrowaveDuty = 0.5;

/// The oven's mains cycle in ms: 16.67 at 60 Hz (Airshark measured 16.66),
/// 20 at 50 Hz (calc).
double icMicrowavePeriodMs(IcMains m) => 1000 / m.hz;

/// ON time per cycle, ms.
double icMicrowaveOnMs(IcMains m) => icMicrowavePeriodMs(m) * kIcMicrowaveDuty;

/// The oven's peak, MHz (Airshark, six ovens: mostly 2450 to 2470).
const double kIcMicrowavePeakLowMHz = 2450;
const double kIcMicrowavePeakHighMHz = 2470;

/// How far below its peak the oven sits in your channel, dB. Channel 11
/// (2452 to 2472 MHz) holds the peak (calc). Channel 1 is 30 dB down and
/// channel 6 15 dB down: ILLUSTRATIVE (Pax found no roll-off data; 30 is the
/// gap between his illustrative -50 on 11 and -80 on 1, and 15 splits it).
/// Null: no oven on that band.
double? icMicrowaveOffsetDb(IcChannel c) => switch (c) {
  IcChannel.ch11 => 0,
  IcChannel.ch6 => 15,
  IcChannel.ch1 => 30,
  IcChannel.ch36 => null,
};

/// True when the offset for [c] is illustrative rather than calculated.
bool icMicrowaveOffsetIsIllustrative(IcChannel c) =>
    c == IcChannel.ch6 || c == IcChannel.ch1;

// ── Bluetooth (pinned hop math, illustrative activity) ──────────────────────

/// Bluetooth Classic hop channels, 1 MHz each, 2402 to 2480 MHz.
const int kIcBtChannels = 79;

/// Hops that land inside one 20 MHz Wi-Fi channel (calc, no adaptive
/// hopping): 20 of 79.
const double kIcBtInChannelShare = 20 / kIcBtChannels;

/// Slot length, microseconds (1,600 hops per second).
const double kIcBtSlotUs = 625;

/// Share of slots the link transmits in: 2 of every 6, ILLUSTRATIVE.
const double kIcBtActiveShare = 2 / 6;

// ── Wi-Fi neighbor ──────────────────────────────────────────────────────────

/// The neighbor's share of airtime, ILLUSTRATIVE default (Pax 1.5).
const double kIcNeighborAirtimeDefault = 0.30;
const double kIcNeighborAirtimeMin = 0.10;
const double kIcNeighborAirtimeMax = 0.80;

/// One neighbor transmission in the timeline, ms, ILLUSTRATIVE.
const double kIcNeighborBurstMs = 1.5;

// ── Levels ──────────────────────────────────────────────────────────────────

const double kIcLevelMinDbm = -100;
const double kIcLevelMaxDbm = -30;

/// Default levels, all ILLUSTRATIVE except where noted (Pax 1.5).
/// Wi-Fi -78 (above -82, so it defers every time). Oven -50 at its peak, 3 m
/// away. Bluetooth -42: a 4 dBm Class 2 radio 2 m away in free space (calc).
/// Video -70: Airshark's level for 80% or more loss, below energy detect.
double icDefaultLevelDbm(IcSource s) => switch (s) {
  IcSource.wifiNeighbor => -78,
  IcSource.microwave => -50,
  IcSource.bluetooth => -42,
  IcSource.videoSender => -70,
};

// ── Corruption (ILLUSTRATIVE) ───────────────────────────────────────────────

/// The chance a frame that overlaps the source fails, as a logistic in the
/// source's level: 1 / (1 + e^-((level - midpoint) / spread)). ILLUSTRATIVE:
/// no per-MCS SINR or retry curve exists in the sources. Midpoints agree with
/// Airshark's good-link measurements (oven near no loss below about -60 dBm;
/// Bluetooth never much worse than 0.9 of throughput; a video camera 80% or
/// more lost at -70 dBm). The Wi-Fi midpoint is a pure illustration of a
/// neighbor too weak to hear still landing on your frames.
({double midpointDbm, double spreadDb}) icCorruptionCurve(IcSource s) =>
    switch (s) {
      IcSource.wifiNeighbor => (midpointDbm: -86, spreadDb: 2.5),
      IcSource.microwave => (midpointDbm: -55, spreadDb: 2.5),
      IcSource.bluetooth => (midpointDbm: -70, spreadDb: 3),
      IcSource.videoSender => (midpointDbm: -75, spreadDb: 2.5),
    };

double icFailProbability(IcSource s, double levelDbm) {
  final ({double midpointDbm, double spreadDb}) c = icCorruptionCurve(s);
  return 1 / (1 + math.exp(-(levelDbm - c.midpointDbm) / c.spreadDb));
}

// ── Configuration ───────────────────────────────────────────────────────────

class IcConfig {
  const IcConfig({
    this.source = IcSource.wifiNeighbor,
    this.channel = IcChannel.ch11,
    this.widthMHz = 20,
    this.mains = IcMains.hz60,
    this.exponent = 3.0,
    this.neighborAirtime = kIcNeighborAirtimeDefault,
    this.wifiLevelDbm = -78,
    this.microwavePeakDbm = -50,
    this.bluetoothLevelDbm = -42,
    this.videoLevelDbm = -70,
  });

  /// The source the stage shows.
  final IcSource source;
  final IcChannel channel;

  /// Your channel width, and the neighbor's PPDU width. 20 in 2.4 GHz.
  final int widthMHz;
  final IcMains mains;

  /// Path-loss exponent for the distances only.
  final double exponent;

  /// The Wi-Fi neighbor's share of airtime.
  final double neighborAirtime;

  /// The Wi-Fi neighbor's whole PPDU at your radio, dBm.
  final double wifiLevelDbm;

  /// The oven at its strongest frequency, dBm; your channel gets less.
  final double microwavePeakDbm;
  final double bluetoothLevelDbm;
  final double videoLevelDbm;

  /// The level the source's slider sets.
  double levelFor(IcSource s) => switch (s) {
    IcSource.wifiNeighbor => wifiLevelDbm,
    IcSource.microwave => microwavePeakDbm,
    IcSource.bluetooth => bluetoothLevelDbm,
    IcSource.videoSender => videoLevelDbm,
  };

  IcConfig withLevel(IcSource s, double v) {
    final double c = v.clamp(kIcLevelMinDbm, kIcLevelMaxDbm);
    return switch (s) {
      IcSource.wifiNeighbor => copyWith(wifiLevelDbm: c),
      IcSource.microwave => copyWith(microwavePeakDbm: c),
      IcSource.bluetooth => copyWith(bluetoothLevelDbm: c),
      IcSource.videoSender => copyWith(videoLevelDbm: c),
    };
  }

  IcConfig copyWith({
    IcSource? source,
    IcChannel? channel,
    int? widthMHz,
    IcMains? mains,
    double? exponent,
    double? neighborAirtime,
    double? wifiLevelDbm,
    double? microwavePeakDbm,
    double? bluetoothLevelDbm,
    double? videoLevelDbm,
  }) => IcConfig(
    source: source ?? this.source,
    channel: channel ?? this.channel,
    widthMHz: widthMHz ?? this.widthMHz,
    mains: mains ?? this.mains,
    exponent: exponent ?? this.exponent,
    neighborAirtime: neighborAirtime ?? this.neighborAirtime,
    wifiLevelDbm: wifiLevelDbm ?? this.wifiLevelDbm,
    microwavePeakDbm: microwavePeakDbm ?? this.microwavePeakDbm,
    bluetoothLevelDbm: bluetoothLevelDbm ?? this.bluetoothLevelDbm,
    videoLevelDbm: videoLevelDbm ?? this.videoLevelDbm,
  );

  @override
  bool operator ==(Object other) =>
      other is IcConfig &&
      other.source == source &&
      other.channel == channel &&
      other.widthMHz == widthMHz &&
      other.mains == mains &&
      other.exponent == exponent &&
      other.neighborAirtime == neighborAirtime &&
      other.wifiLevelDbm == wifiLevelDbm &&
      other.microwavePeakDbm == microwavePeakDbm &&
      other.bluetoothLevelDbm == bluetoothLevelDbm &&
      other.videoLevelDbm == videoLevelDbm;

  @override
  int get hashCode => Object.hash(
    source,
    channel,
    widthMHz,
    mains,
    exponent,
    neighborAirtime,
    wifiLevelDbm,
    microwavePeakDbm,
    bluetoothLevelDbm,
    videoLevelDbm,
  );
}

// ── Results ─────────────────────────────────────────────────────────────────

/// How your radio's clear channel assessment (CCA) treats the source.
enum IcHeard {
  /// A Wi-Fi preamble at or above preamble detect: your radio waits.
  preamble,

  /// Energy at or above energy detect: your radio waits.
  energy,

  /// Below both: your radio transmits into it.
  notHeard,

  /// The source has no energy on this band.
  absent;

  bool get waits => this == preamble || this == energy;
}

class IcSourceResult {
  const IcSourceResult({
    required this.source,
    required this.levelInChannelDbm,
    required this.onAirShare,
    required this.heard,
    required this.thresholdDbm,
    required this.failProbability,
  });

  final IcSource source;

  /// The source in your channel, dBm; null when [heard] is absent.
  final double? levelInChannelDbm;

  /// Share of time the source is on the air in your channel.
  final double onAirShare;
  final IcHeard heard;

  /// The threshold that applies to it: preamble detect for Wi-Fi at this
  /// width, energy detect for anything else.
  final double thresholdDbm;

  /// Chance a frame that overlaps it fails (ILLUSTRATIVE).
  final double failProbability;

  /// Share of your airtime spent waiting for it.
  double get deferralShare => heard.waits ? onAirShare : 0;

  /// Share of your airtime your frames spend overlapping it.
  double get overlapShare => heard == IcHeard.notHeard ? onAirShare : 0;

  /// Share of your airtime spent on frames that fail (ILLUSTRATIVE).
  double get corruptionShare => overlapShare * failProbability;

  double get totalShare => deferralShare + corruptionShare;

  /// dB above (+) or below (-) the threshold that applies.
  double? get marginDb =>
      levelInChannelDbm == null ? null : levelInChannelDbm! - thresholdDbm;
}

class IcResult {
  const IcResult({
    required this.config,
    required this.preambleDetectDbm,
    required this.sources,
    required this.wifiHeardAtM,
    required this.energyHeardAtM,
  });

  final IcConfig config;

  /// Preamble detect for a PPDU of the configured width.
  final double preambleDetectDbm;
  final Map<IcSource, IcSourceResult> sources;

  /// How far a 20 dBm Wi-Fi transmitter still makes you wait.
  final double wifiHeardAtM;

  /// How far a 20 dBm non-Wi-Fi transmitter still makes you wait.
  final double energyHeardAtM;

  double get energyDetectDbm => kIcEnergyDetectDbm;

  /// Energy detect minus preamble detect: 20 dB at 20 MHz.
  double get gapDb => kIcEnergyDetectDbm - preambleDetectDbm;

  /// The gap as a power ratio: 100 at 20 MHz.
  double get gapPowerRatio => math.pow(10, gapDb / 10).toDouble();

  /// 10^(gap / 10n): 10 in free space, 4.6 at n = 3, 3.7 at n = 3.5.
  double get distanceRatio => wifiHeardAtM / energyHeardAtM;

  double get areaRatio => distanceRatio * distanceRatio;

  IcSourceResult get selected => sources[config.source]!;
}

/// Preamble detect for a PPDU [widthMHz] wide.
double icPreambleDetectDbm(int widthMHz) =>
    kIcPreambleDetectByWidth[widthMHz] ??
    (throw ArgumentError.value(widthMHz, 'widthMHz', 'no pinned threshold'));

/// Distance in metres at which [eirpDbm] falls to [thresholdDbm] under the
/// log-distance model PL = FSPL(1 m) + 10 n log10(d).
double icHeardDistanceM({
  required double thresholdDbm,
  required double freqMHz,
  required double exponent,
  double eirpDbm = kIcReferenceEirpDbm,
}) {
  final double budget = eirpDbm - thresholdDbm - FsplMath.fsplDb(1, freqMHz);
  return math.pow(10, budget / (10 * exponent)).toDouble();
}

/// The source's level in your channel, or null when it has no energy there.
double? icLevelInChannel(IcConfig c, IcSource s) {
  switch (s) {
    case IcSource.wifiNeighbor:
    case IcSource.videoSender:
      return c.levelFor(s);
    case IcSource.bluetooth:
      return c.channel.is24 ? c.bluetoothLevelDbm : null;
    case IcSource.microwave:
      final double? off = icMicrowaveOffsetDb(c.channel);
      return off == null ? null : c.microwavePeakDbm - off;
  }
}

/// Share of time [s] is on the air inside your channel.
double icOnAirShare(IcConfig c, IcSource s) => switch (s) {
  IcSource.wifiNeighbor => c.neighborAirtime,
  IcSource.microwave => kIcMicrowaveDuty,
  IcSource.bluetooth => kIcBtActiveShare * kIcBtInChannelShare,
  IcSource.videoSender => 1,
};

IcSourceResult icEvaluate(IcConfig c, IcSource s) {
  final double pd = icPreambleDetectDbm(c.widthMHz);
  final double threshold = s.isWifi ? pd : kIcEnergyDetectDbm;
  final double? level = icLevelInChannel(c, s);
  if (level == null) {
    return IcSourceResult(
      source: s,
      levelInChannelDbm: null,
      onAirShare: 0,
      heard: IcHeard.absent,
      thresholdDbm: threshold,
      failProbability: 0,
    );
  }
  // A Wi-Fi signal below preamble detect is far below energy detect too, so
  // one comparison decides each kind.
  final IcHeard heard = level >= threshold
      ? (s.isWifi ? IcHeard.preamble : IcHeard.energy)
      : IcHeard.notHeard;
  return IcSourceResult(
    source: s,
    levelInChannelDbm: level,
    onAirShare: icOnAirShare(c, s),
    heard: heard,
    thresholdDbm: threshold,
    failProbability: icFailProbability(s, level),
  );
}

IcResult computeInterfererCost(IcConfig c) {
  final double pd = icPreambleDetectDbm(c.widthMHz);
  return IcResult(
    config: c,
    preambleDetectDbm: pd,
    sources: <IcSource, IcSourceResult>{
      for (final IcSource s in IcSource.values) s: icEvaluate(c, s),
    },
    wifiHeardAtM: icHeardDistanceM(
      thresholdDbm: pd,
      freqMHz: c.channel.centerMHz,
      exponent: c.exponent,
    ),
    energyHeardAtM: icHeardDistanceM(
      thresholdDbm: kIcEnergyDetectDbm,
      freqMHz: c.channel.centerMHz,
      exponent: c.exponent,
    ),
  );
}

// ── Timeline: one 60 ms sample of your channel ──────────────────────────────

/// The timeline's length, ms: three 50 Hz cycles, 3.6 at 60 Hz, so switching
/// mains changes the pattern and never the axis.
const double kIcTimelineMs = 60;

/// One stretch of time the source is on the air in your channel.
typedef IcSpan = ({double startMs, double endMs});

/// Deterministic generator so the sample never changes between frames.
class _Lcg {
  _Lcg(this._s);
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }
}

/// Bluetooth hop channel k sits at 2402 + k MHz; it lands in your channel
/// when that is inside your 20 MHz.
bool icBtHopInChannel(int k, IcChannel c) {
  if (!c.is24) return false;
  final double f = 2402.0 + k;
  return f >= c.centerMHz - 10 && f < c.centerMHz + 10;
}

/// When [s] is on the air in your channel during the sample. Empty when it
/// is absent from the band.
List<IcSpan> icTimeline(IcConfig c, IcSource s) {
  if (icLevelInChannel(c, s) == null) return const <IcSpan>[];
  switch (s) {
    case IcSource.videoSender:
      return const <IcSpan>[(startMs: 0, endMs: kIcTimelineMs)];
    case IcSource.microwave:
      final double t = icMicrowavePeriodMs(c.mains);
      final double on = icMicrowaveOnMs(c.mains);
      return <IcSpan>[
        for (double k = 0; k * t < kIcTimelineMs; k++)
          (startMs: k * t, endMs: math.min(k * t + on, kIcTimelineMs)),
      ];
    case IcSource.bluetooth:
      final _Lcg r = _Lcg(7);
      final double slot = kIcBtSlotUs / 1000;
      final int slots = (kIcTimelineMs / slot).floor();
      final List<IcSpan> out = <IcSpan>[];
      for (int i = 0; i < slots; i++) {
        final int hop = (r.next() * kIcBtChannels).floor() % kIcBtChannels;
        // Two active slots in every six (illustrative).
        if (i % 6 >= 2) continue;
        if (!icBtHopInChannel(hop, c.channel)) continue;
        out.add((startMs: i * slot, endMs: (i + 1) * slot));
      }
      return out;
    case IcSource.wifiNeighbor:
      final _Lcg r = _Lcg(11);
      final double period = kIcNeighborBurstMs / c.neighborAirtime;
      final List<IcSpan> out = <IcSpan>[];
      for (double p = 0; p < kIcTimelineMs; p += period) {
        final double start = p + r.next() * (period - kIcNeighborBurstMs);
        if (start >= kIcTimelineMs) break;
        out.add((
          startMs: start,
          endMs: math.min(start + kIcNeighborBurstMs, kIcTimelineMs),
        ));
      }
      return out;
  }
}

/// Share of the sample covered by [spans].
double icSpanShare(List<IcSpan> spans) =>
    spans.fold<double>(0, (double a, IcSpan s) => a + s.endMs - s.startMs) /
    kIcTimelineMs;

// ── Predict, then reveal ────────────────────────────────────────────────────

/// "A microwave oven and a neighbor's AP on your channel, both at the same
/// received level of -70 dBm. Which one costs your Wi-Fi more airtime?"
/// The oven is on channel 11, where its peak lands, so -70 is its level in
/// your channel too.
const IcConfig kIcQuestionScene = IcConfig(
  wifiLevelDbm: -70,
  microwavePeakDbm: -70,
);

/// Which of the two costs more in [c].
IcSource icCostlier(IcConfig c) {
  final IcResult r = computeInterfererCost(c);
  return r.sources[IcSource.wifiNeighbor]!.totalShare >=
          r.sources[IcSource.microwave]!.totalShare
      ? IcSource.wifiNeighbor
      : IcSource.microwave;
}
