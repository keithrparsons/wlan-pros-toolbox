// Multicast at the Basic Rate: the pure model behind the Wi-Fi Classroom tool
// (multicast-basic-rate).
//
// CLEAN-ROOM BUILD (2026-09-26) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/30-multicast-basic-rate.md. The problem statement is RFC
// 9119 (IETF, 2021), which the research brief read from summaries only
// (wave 4 brief, row C). No number in this file comes from the RFC: every
// airtime is computed.
//
// WHAT IT COMPUTES
//   - One multicast packet's airtime at a basic rate: DIFS + average backoff
//     + preamble + data, and NO acknowledgment (group frames are not
//     acknowledged or retried).
//   - The same packet converted to unicast: one copy per listening client at
//     that client's MCS, each with its own wait, SIFS and ACK.
//   - Airtime share per second for each, the break-even listener count, and
//     a one-second timeline with beacons, DTIM buffering and the frames.
//
// REUSE (spec: "reuses Airtime Anatomy's timing functions"). The 802.11a/g
// rates (6, 12, 24 Mb/s) and every unicast copy go through computeAirtime()
// in airtime_anatomy.dart, unchanged: its preamble, symbol, SIFS, slot,
// signal-extension and ACK math. The spec pinned that math to
// airtime_anatomy_model.dart; it actually lives in the service file, and the
// model file is the screen's ChangeNotifier.
//
// WHAT AIRTIME ANATOMY DOES NOT COVER, ADDED HERE. The 802.11b rates (1, 2,
// 5.5 and 11 Mb/s, DSSS and CCK) have no path in computeAirtime(), which is
// OFDM only. They use the 802.11b long-preamble TXTIME:
//     192 us (144 us preamble + 48 us PLCP header) + ceil(8 x bytes / rate)
// with the 802.11b 20 us slot, 10 us SIFS and CWmin 31. The long preamble is
// the one every 802.11b receiver decodes, which is the point of a basic rate.
// These are the standard's well-known values, from the team's knowledge of
// IEEE 802.11 (not re-read; the standard is paywalled).
//
// SIMPLIFICATIONS (stated in the help):
//   1. Frame sizes follow Airtime Anatomy: payload + 26-byte QoS header +
//      4-byte FCS + 16 bytes of CCMP, for group and unicast frames alike.
//   2. Multicast waits DIFS (SIFS + 2 slots) plus the average backoff,
//      CWmin / 2 slots; OFDM rates use the 9 us slot and CWmin 15.
//   3. Unicast copies are Wi-Fi 6 single-user frames, 20 MHz, 2 spatial
//      streams, 0.8 us guard interval, one frame per copy with an ACK at
//      24 Mb/s, video access category (illustrative).
//   4. One AP, no other traffic, no collisions, no retries. Beacons are drawn
//      as markers; their own airtime is what SSID Airtime shows.
//   5. Unicast copies to a dozing client wait for that client to wake, which
//      this model does not draw: the DTIM switch holds multicast only.
//
// ARITHMETIC. Per-packet airtimes are whole tenths of a microsecond, as in
// Airtime Anatomy. The timeline is in microseconds as doubles.
//
// ASCII only, no em dashes (GL-004). No Flutter imports.

import 'airtime_anatomy.dart';

/// Beacon interval: 100 TU = 102.4 ms, in microseconds.
const double kMcBeaconIntervalUs = 102400;

/// The timeline window: one second, in microseconds.
const double kMcWindowUs = 1000000;

/// Tenths of a microsecond in one second.
const int kTenthsPerSecond = 10000000;

const int kMcMinListeners = 1;
const int kMcMaxListeners = 30;
const int kMcMinDtim = 1;
const int kMcMaxDtim = 10;

/// Stream bit rates the slider steps through, Mb/s (spec: 0.064 to 20).
const List<double> kMcStreamRatesMbps = <double>[
  0.064,
  0.1,
  0.25,
  0.5,
  1,
  2,
  3,
  4,
  6,
  8,
  10,
  15,
  20,
];

/// Packet sizes offered, bytes (the IP packet the stream sends).
const List<int> kMcPacketSizes = <int>[200, 400, 576, 1000, 1316, 1500];

/// The 802.11b timing the long-preamble basic rates use.
class DsssTiming {
  DsssTiming._();

  static const int slotUs = 20;
  static const int sifsUs = 10;
  static const int cwMin = 31;

  /// 144 us long preamble + 48 us PLCP header.
  static const int longPreambleUs = 192;
}

/// OFDM contention window minimum for the multicast wait.
const int kOfdmCwMin = 15;

/// The unicast copies' fixed, illustrative radio settings.
class UnicastAssumptions {
  UnicastAssumptions._();

  static const int widthMhz = 20;
  static const int streams = 2;
  static const GuardInterval guardInterval = GuardInterval.gi08;
  static const AirtimeAccessCategory accessCategory = AirtimeAccessCategory.vi;
  static const int controlRateMbps = 24;
  static const int encryptionBytes = 16;
}

/// Band. 802.11b rates exist on 2.4 GHz only.
enum McBand {
  ghz24('2.4 GHz', AirtimeBand.ghz24),
  ghz5('5 GHz', AirtimeBand.ghz5);

  const McBand(this.label, this.airtime);

  final String label;
  final AirtimeBand airtime;
}

/// A basic (mandatory) rate, slowest first.
enum BasicRate {
  r1(10, dsss: true),
  r2(20, dsss: true),
  r5_5(55, dsss: true),
  r6(60, dsss: false),
  r11(110, dsss: true),
  r12(120, dsss: false),
  r24(240, dsss: false);

  const BasicRate(this.tenthsMbps, {required this.dsss});

  /// The rate in tenths of a Mb/s, so 5.5 stays exact.
  final int tenthsMbps;

  /// True for the 802.11b rates (DSSS and CCK); false for 802.11a/g OFDM.
  final bool dsss;

  double get mbps => tenthsMbps / 10;

  /// "5.5 Mb/s".
  String get label =>
      '${tenthsMbps % 10 == 0 ? '${tenthsMbps ~/ 10}' : mbps.toString()} Mb/s';

  /// "802.11b" or "802.11a/g".
  String get phyLabel => dsss ? '802.11b' : '802.11a/g';

  bool availableOn(McBand band) => band == McBand.ghz24 || !dsss;

  /// The rates offered on [band], slowest first.
  static List<BasicRate> on(McBand band) => <BasicRate>[
    for (final BasicRate r in BasicRate.values)
      if (r.availableOn(band)) r,
  ];
}

/// How the listening clients' rates are spread. All illustrative.
enum ListenerRates {
  spread('Spread, MCS 1 to 11'),
  near('All close, MCS 9'),
  far('All far, MCS 1');

  const ListenerRates(this.label);

  final String label;

  /// Listener k's MCS. The spread cycles through a fixed order, so adding a
  /// listener never changes anyone else's rate.
  int mcsOf(int k) => switch (this) {
    ListenerRates.spread => kSpreadMcs[k % kSpreadMcs.length],
    ListenerRates.near => 9,
    ListenerRates.far => 1,
  };
}

/// The spread's cycle (illustrative): each group of six covers the range.
const List<int> kSpreadMcs = <int>[9, 5, 7, 3, 11, 1];

/// A named starting point for the stream. All illustrative.
enum StreamPreset {
  voicePaging('Voice paging', 0.064, 200),
  video('Video', 4, 1316),
  discovery('Service discovery chatter', 0.1, 400);

  const StreamPreset(this.label, this.mbps, this.packetBytes);

  final String label;
  final double mbps;
  final int packetBytes;
}

/// Every input.
class McConfig {
  const McConfig({
    this.streamMbps = 4,
    this.packetBytes = 1316,
    this.band = McBand.ghz5,
    this.basicRate = BasicRate.r6,
    this.listeners = 5,
    this.rates = ListenerRates.spread,
    this.dtimPeriod = 3,
    this.powerSave = false,
  }) : assert(streamMbps > 0),
       assert(packetBytes > 0),
       assert(listeners >= kMcMinListeners && listeners <= kMcMaxListeners),
       assert(dtimPeriod >= kMcMinDtim && dtimPeriod <= kMcMaxDtim);

  final double streamMbps;
  final int packetBytes;
  final McBand band;
  final BasicRate basicRate;
  final int listeners;
  final ListenerRates rates;
  final int dtimPeriod;

  /// "A client is in power save": multicast is held for the DTIM beacon.
  final bool powerSave;

  McConfig copyWith({
    double? streamMbps,
    int? packetBytes,
    McBand? band,
    BasicRate? basicRate,
    int? listeners,
    ListenerRates? rates,
    int? dtimPeriod,
    bool? powerSave,
  }) {
    final McBand b = band ?? this.band;
    BasicRate r = basicRate ?? this.basicRate;
    // 5 GHz has no 802.11b rates: snap to the slowest OFDM one.
    if (!r.availableOn(b)) r = BasicRate.r6;
    return McConfig(
      streamMbps: streamMbps ?? this.streamMbps,
      packetBytes: packetBytes ?? this.packetBytes,
      band: b,
      basicRate: r,
      listeners: listeners ?? this.listeners,
      rates: rates ?? this.rates,
      dtimPeriod: dtimPeriod ?? this.dtimPeriod,
      powerSave: powerSave ?? this.powerSave,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is McConfig &&
      other.streamMbps == streamMbps &&
      other.packetBytes == packetBytes &&
      other.band == band &&
      other.basicRate == basicRate &&
      other.listeners == listeners &&
      other.rates == rates &&
      other.dtimPeriod == dtimPeriod &&
      other.powerSave == powerSave;

  @override
  int get hashCode => Object.hash(
    streamMbps,
    packetBytes,
    band,
    basicRate,
    listeners,
    rates,
    dtimPeriod,
    powerSave,
  );
}

/// One multicast packet's airtime, tenths of a microsecond.
class MulticastTiming {
  const MulticastTiming({
    required this.difsTenths,
    required this.backoffTenths,
    required this.preambleTenths,
    required this.dataTenths,
    required this.mpduBytes,
  });

  final int difsTenths;
  final int backoffTenths;
  final int preambleTenths;
  final int dataTenths;
  final int mpduBytes;

  /// Always zero: nobody acknowledges a group frame.
  int get ackTenths => 0;

  int get frameTenths => preambleTenths + dataTenths;

  int get totalTenths =>
      difsTenths + backoffTenths + preambleTenths + dataTenths + ackTenths;

  double get totalUs => totalTenths / 10;
}

/// One unicast copy for one listener.
class UnicastCopy {
  const UnicastCopy({
    required this.listener,
    required this.mcs,
    required this.result,
  });

  /// Zero-based listener index.
  final int listener;
  final int mcs;

  /// Airtime Anatomy's full TXOP for this copy.
  final AirtimeResult result;

  int get waitTenths =>
      result.segment(TxopSegmentKind.aifs).tenths +
      result.segment(TxopSegmentKind.backoff).tenths;
  int get preambleTenths => result.preambleTenths;
  int get dataTenths => result.dataTenths;
  int get sifsTenths => result.segment(TxopSegmentKind.sifs).tenths;
  int get ackTenths => result.segment(TxopSegmentKind.ack).tenths;
  int get totalTenths => result.totalTenths;
  double get phyRateMbps => result.phyRateMbps;
}

/// A beacon on the one-second timeline.
class McBeacon {
  const McBeacon({required this.atUs, required this.dtim});

  final double atUs;
  final bool dtim;
}

/// One transmission on the timeline: a multicast frame, or one packet's
/// unicast copies back to back.
class McBlock {
  const McBlock({
    required this.arrivalUs,
    required this.releaseUs,
    required this.startUs,
    required this.endUs,
  });

  /// When the packet reached the AP. Negative for packets held from before
  /// the window.
  final double arrivalUs;

  /// When the AP let it go: the arrival, or the next DTIM beacon when a
  /// client is in power save.
  final double releaseUs;

  /// When it went on air (after any queue ahead of it).
  final double startUs;
  final double endUs;

  /// The DTIM hold: release minus arrival.
  double get holdUs => releaseUs - arrivalUs;
}

/// Everything the screen shows.
class McResult {
  const McResult({
    required this.config,
    required this.packetsPerSecond,
    required this.multicast,
    required this.copies,
    required this.breakEven,
    required this.beacons,
    required this.multicastBlocks,
    required this.unicastBlocks,
  });

  final McConfig config;
  final double packetsPerSecond;
  final MulticastTiming multicast;

  /// One copy per listener, in listener order.
  final List<UnicastCopy> copies;

  /// The smallest listener count at which unicast copies take at least as
  /// much airtime as the one multicast frame; null when unicast stays cheaper
  /// all the way to [kMcMaxListeners].
  final int? breakEven;

  final List<McBeacon> beacons;
  final List<McBlock> multicastBlocks;
  final List<McBlock> unicastBlocks;

  /// All copies of one packet, tenths of a microsecond.
  int get unicastPerPacketTenths =>
      copies.fold<int>(0, (int a, UnicastCopy c) => a + c.totalTenths);

  /// Airtime per second / 1 s. Above 1 the stream does not fit.
  double get multicastShare =>
      multicast.totalTenths * packetsPerSecond / kTenthsPerSecond;
  double get unicastShare =>
      unicastPerPacketTenths * packetsPerSecond / kTenthsPerSecond;

  /// The DTIM period in microseconds.
  double get dtimIntervalUs => config.dtimPeriod * kMcBeaconIntervalUs;

  /// Worst added delay from DTIM buffering: zero with nobody in power save,
  /// else just under one DTIM interval.
  double get maxDtimDelayUs => config.powerSave ? dtimIntervalUs : 0;

  /// Average added delay: half a DTIM interval for evenly spaced packets.
  double get meanDtimDelayUs => config.powerSave ? dtimIntervalUs / 2 : 0;
}

/// Packets per second for a stream of [mbps] in packets of [bytes].
double packetsPerSecond(double mbps, int bytes) => mbps * 1e6 / (8 * bytes);

/// One multicast packet of [payloadBytes] at [rate] on [band].
MulticastTiming multicastTiming(BasicRate rate, McBand band, int payloadBytes) {
  if (!rate.availableOn(band)) {
    throw ArgumentError.value(rate, 'rate', 'not offered on ${band.label}');
  }
  if (rate.dsss) {
    // Frame size from Airtime Anatomy, so both paths count the same bytes.
    final int mpdu = computeAirtime(
      _legacyScenario(band, 6, payloadBytes),
    ).mpduBytes;
    const int difs = DsssTiming.sifsUs + 2 * DsssTiming.slotUs;
    // CWmin / 2 x slot, in tenths: 31 x 20 x 5 = 3100.
    const int backoff = DsssTiming.cwMin * DsssTiming.slotUs * 5;
    // ceil(8 x bytes / rate) us, with the rate in tenths of a Mb/s.
    final int dataUs = _ceilDiv(80 * mpdu, rate.tenthsMbps);
    return MulticastTiming(
      difsTenths: difs * 10,
      backoffTenths: backoff,
      preambleTenths: DsssTiming.longPreambleUs * 10,
      dataTenths: dataUs * 10,
      mpduBytes: mpdu,
    );
  }
  final AirtimeResult r = computeAirtime(
    _legacyScenario(band, rate.tenthsMbps ~/ 10, payloadBytes),
  );
  final int difs = r.sifsUs + 2 * r.slotUs;
  return MulticastTiming(
    difsTenths: difs * 10,
    backoffTenths: kOfdmCwMin * r.slotUs * 5,
    preambleTenths: r.preambleTenths,
    dataTenths: r.dataTenths,
    mpduBytes: r.mpduBytes,
  );
}

/// One unicast copy for a listener at [mcs].
AirtimeResult unicastCopyAirtime(McBand band, int mcs, int payloadBytes) =>
    computeAirtime(
      AirtimeScenario(
        band: band.airtime,
        phy: AirtimePhy.he,
        widthMhz: UnicastAssumptions.widthMhz,
        mcs: mcs,
        streams: UnicastAssumptions.streams,
        guardInterval: UnicastAssumptions.guardInterval,
        payloadBytes: payloadBytes,
        framesAggregated: 1,
        encryptionBytes: UnicastAssumptions.encryptionBytes,
        accessCategory: UnicastAssumptions.accessCategory,
        controlRateMbps: UnicastAssumptions.controlRateMbps,
      ),
    );

/// The copies for the first [n] listeners.
List<UnicastCopy> unicastCopies(McConfig c, [int? n]) => <UnicastCopy>[
  for (int k = 0; k < (n ?? c.listeners); k++)
    UnicastCopy(
      listener: k,
      mcs: c.rates.mcsOf(k),
      result: unicastCopyAirtime(c.band, c.rates.mcsOf(k), c.packetBytes),
    ),
];

/// When a packet that reached the AP at [arrivalUs] is released: at once, or
/// at the first DTIM beacon at or after it. DTIM beacons fall on multiples
/// of [dtimIntervalUs], counting from the beacon at 0.
double releaseAt(double arrivalUs, {required double dtimIntervalUs}) {
  final double k = arrivalUs / dtimIntervalUs;
  // A hair of tolerance so an arrival exactly on a beacon is not pushed a
  // whole interval by floating-point residue.
  final double n = (k - 1e-9).ceilToDouble();
  return n * dtimIntervalUs;
}

/// Runs the model.
McResult computeMulticast(McConfig c) {
  final double pps = packetsPerSecond(c.streamMbps, c.packetBytes);
  final MulticastTiming mc = multicastTiming(
    c.basicRate,
    c.band,
    c.packetBytes,
  );
  final List<UnicastCopy> copies = unicastCopies(c);

  // Break-even: walk the listener count up with the same rate profile.
  int? breakEven;
  int sum = 0;
  for (int n = 1; n <= kMcMaxListeners; n++) {
    final int mcs = c.rates.mcsOf(n - 1);
    sum += unicastCopyAirtime(c.band, mcs, c.packetBytes).totalTenths;
    if (sum >= mc.totalTenths) {
      breakEven = n;
      break;
    }
  }

  final double dtimUs = c.dtimPeriod * kMcBeaconIntervalUs;
  final List<McBeacon> beacons = <McBeacon>[
    for (int k = 0; k * kMcBeaconIntervalUs < kMcWindowUs; k++)
      McBeacon(atUs: k * kMcBeaconIntervalUs, dtim: k % c.dtimPeriod == 0),
  ];

  final double gapUs = 1e6 / pps;
  final double mcUs = mc.totalUs;
  final double ucUs =
      copies.fold<int>(0, (int a, UnicastCopy u) => a + u.totalTenths) / 10;

  // Multicast lane. With power save on, the steady state includes the packets
  // that arrived during the DTIM interval before the window and go out at the
  // DTIM beacon at 0.
  final List<McBlock> mcBlocks = <McBlock>[];
  {
    int i = c.powerSave ? -(dtimUs / gapUs).floor() : 0;
    // An arrival exactly one interval back went out at the previous DTIM.
    if (c.powerSave && i * gapUs <= -dtimUs) i++;
    double busyUntil = double.negativeInfinity;
    while (true) {
      final double arrival = i * gapUs;
      final double release = c.powerSave
          ? releaseAt(arrival, dtimIntervalUs: dtimUs)
          : arrival;
      if (release >= kMcWindowUs) break;
      final double start = release > busyUntil ? release : busyUntil;
      if (start >= kMcWindowUs) break;
      final double end = start + mcUs;
      mcBlocks.add(
        McBlock(
          arrivalUs: arrival,
          releaseUs: release,
          startUs: start,
          endUs: end,
        ),
      );
      busyUntil = end;
      i++;
    }
  }

  // Unicast lane: each packet's copies back to back, sent on arrival.
  final List<McBlock> ucBlocks = <McBlock>[];
  {
    double busyUntil = 0;
    for (int i = 0; ; i++) {
      final double arrival = i * gapUs;
      if (arrival >= kMcWindowUs) break;
      final double start = arrival > busyUntil ? arrival : busyUntil;
      if (start >= kMcWindowUs) break;
      final double end = start + ucUs;
      ucBlocks.add(
        McBlock(
          arrivalUs: arrival,
          releaseUs: arrival,
          startUs: start,
          endUs: end,
        ),
      );
      busyUntil = end;
    }
  }

  return McResult(
    config: c,
    packetsPerSecond: pps,
    multicast: mc,
    copies: List<UnicastCopy>.unmodifiable(copies),
    breakEven: breakEven,
    beacons: List<McBeacon>.unmodifiable(beacons),
    multicastBlocks: List<McBlock>.unmodifiable(mcBlocks),
    unicastBlocks: List<McBlock>.unmodifiable(ucBlocks),
  );
}

AirtimeScenario _legacyScenario(McBand band, int rateMbps, int payload) =>
    AirtimeScenario(
      band: band.airtime,
      phy: AirtimePhy.legacy,
      widthMhz: 20,
      mcs: 0,
      legacyRateMbps: rateMbps,
      streams: 1,
      guardInterval: GuardInterval.gi08,
      payloadBytes: payload,
      framesAggregated: 1,
      encryptionBytes: UnicastAssumptions.encryptionBytes,
    );

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;
