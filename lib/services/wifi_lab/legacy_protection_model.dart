// Legacy Protection Cost: the pure model behind the Wi-Fi Classroom tool
// (legacy-protection).
//
// CLEAN-ROOM BUILD (2026-09-27) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/39-legacy-protection.md, with values and sources from the
// wave 4 research brief (Deliverables/2026-09-26-wifi-classroom-wave4-
// research/brief-GKL.md, section L).
//
// WHAT IT COMPUTES
//   - The ERP Information element's three bits (NonERP_Present,
//     Use_Protection, Barker_Preamble_Mode) and the HT Protection value, from
//     whether an 802.11b device is associated or an 802.11b network is heard.
//   - One 54 Mb/s sender's send cycle: DIFS + average backoff + protection
//     frame(s) + data + SIFS + ACK, and its payload rate. With an 802.11b
//     device associated the slot is 20 us instead of 9 and a protection frame
//     goes before every data frame; with one only heard, protection only.
//   - The six-row ceiling table of the spec, as computed cases.
//
// REUSE (spec: "reusing the Airtime Anatomy engine"; brief: "don't write new
// timing math"). The data frame and the ACK come from computeAirtime() in
// airtime_anatomy.dart: 802.11g OFDM at 2.4 GHz (20 us preamble, 4 us
// symbols, 6 us signal extension, SIFS 10 us, ACK at 24 Mb/s). The 802.11b
// protection frames come from dsss_timing.dart (shared with Multicast at the
// Basic Rate). The OFDM contrast CTS uses Airtime Anatomy's
// controlFrameTenths(). The wait is DIFS (SIFS + 2 slots) plus the mean
// backoff, CWmin / 2 slots, as Multicast at the Basic Rate computes it.
//
// ONE INTERPRETATION, stated in the help. The brief's worked example counts a
// 1536-octet data frame (57 OFDM symbols, 254 us). Airtime Anatomy builds the
// frame as payload + 26-byte QoS header + 4-byte FCS + encryption bytes; with
// 16 bytes of encryption that is 1546 octets, 58 symbols, 258 us, and the
// ceiling table would miss by 4 us. With encryption 0 it is 1530 octets and
// the same 57 symbols, 254 us. This tool therefore models an open network
// (encryption 0), so every row of the spec's table holds.
//
// ARITHMETIC. Durations are whole tenths of a microsecond, as in Airtime
// Anatomy (the mean backoff can end in .5 us).
//
// ASCII only, no em dashes (GL-004). No Flutter imports.

import 'airtime_anatomy.dart';
import 'dsss_timing.dart';

/// The ERP short slot, 9 us (Airtime Anatomy's slot).
const int kLpShortSlotUs = AirtimeConstants.slotUs;

/// The 802.11b slot an associated 802.11b station forces, 20 us.
const int kLpLongSlotUs = DsssTiming.slotUs;

/// SIFS at 2.4 GHz, 10 us (the same for 802.11b and 802.11g).
const int kLpSifsUs = AirtimeConstants.sifs24GhzUs;

/// The OFDM minimum contention window, 15 (Airtime Anatomy's best-effort
/// CWmin).
final int kLpOfdmCwMin = AirtimeAccessCategory.be.cwMin;

/// Bytes of encryption on the data frame: 0, an open network. See the header.
const int kLpEncryptionBytes = 0;

/// The ACK's rate, Mb/s (Airtime Anatomy's default control rate).
const int kLpAckRateMbps = 24;

/// The OFDM rate of the contrast CTS, Mb/s.
const int kLpOfdmContrastRateMbps = 6;

/// Payload sizes offered, bytes.
const List<int> kLpPayloadSizes = <int>[64, 256, 512, 1000, 1500];

/// The sender's data rates: the 802.11g OFDM rates, Mb/s.
const List<int> kLpDataRatesMbps = AirtimeConstants.legacyRatesMbps;

/// The shortest timeline window, microseconds.
const int kLpMinWindowUs = 3000;

/// The two ways to protect a frame.
enum ProtectionKind {
  ctsToSelf('CTS-to-self'),
  rtsCts('RTS/CTS');

  const ProtectionKind(this.label);

  final String label;
}

/// The rate of a protection frame: one of the four 802.11b rates, or 6 Mb/s
/// OFDM for contrast (an 802.11b device cannot decode it).
enum ProtectionRate {
  r1(DsssRate.r1),
  r2(DsssRate.r2),
  r5_5(DsssRate.r5_5),
  r11(DsssRate.r11),
  ofdm6(null);

  const ProtectionRate(this.dsss);

  /// The 802.11b rate, or null for the OFDM contrast.
  final DsssRate? dsss;

  bool get isDsss => dsss != null;

  /// "5.5 Mb/s" or "6 Mb/s OFDM".
  String get label => dsss?.label ?? '$kLpOfdmContrastRateMbps Mb/s OFDM';

  /// The 802.11b rates, slowest first.
  static const List<ProtectionRate> dsssRates = <ProtectionRate>[
    ProtectionRate.r1,
    ProtectionRate.r2,
    ProtectionRate.r5_5,
    ProtectionRate.r11,
  ];
}

/// One protection frame choice. The preamble matters only at 802.11b rates.
class ProtectionChoice {
  const ProtectionChoice({
    this.kind = ProtectionKind.ctsToSelf,
    this.rate = ProtectionRate.r1,
    this.preamble = DsssPreamble.long,
  });

  final ProtectionKind kind;
  final ProtectionRate rate;
  final DsssPreamble preamble;

  /// False only for 1 Mb/s with short preamble, which 802.11b does not define.
  bool get isAvailable => rate.dsss?.allows(preamble) ?? true;

  /// Why this choice is unavailable, or null when it is available.
  String? get unavailableReason => isAvailable ? null : kDsssNoShortAt1Reason;

  /// "1 Mb/s, long preamble" or "6 Mb/s OFDM".
  String get rateLabel => rate.isDsss
      ? '${rate.label}, ${preamble.label.toLowerCase()} preamble'
      : rate.label;

  /// "CTS-to-self at 1 Mb/s, long preamble".
  String get label => '${kind.label} at $rateLabel';

  ProtectionChoice copyWith({
    ProtectionKind? kind,
    ProtectionRate? rate,
    DsssPreamble? preamble,
  }) => ProtectionChoice(
    kind: kind ?? this.kind,
    rate: rate ?? this.rate,
    preamble: preamble ?? this.preamble,
  );

  @override
  bool operator ==(Object other) =>
      other is ProtectionChoice &&
      other.kind == kind &&
      other.rate == rate &&
      other.preamble == preamble;

  @override
  int get hashCode => Object.hash(kind, rate, preamble);
}

/// The seven 802.11b rate and preamble pairs that exist, longest CTS first
/// (the order Up and Down step through): 1 long, 2 long, 5.5 long, 11 long,
/// 2 short, 5.5 short, 11 short.
List<(ProtectionRate, DsssPreamble)> dsssStepOrder() {
  final List<(ProtectionRate, DsssPreamble)> all =
      <(ProtectionRate, DsssPreamble)>[
        for (final DsssPreamble p in DsssPreamble.values)
          for (final ProtectionRate r in ProtectionRate.dsssRates)
            if (r.dsss!.allows(p)) (r, p),
      ];
  all.sort((
    (ProtectionRate, DsssPreamble) a,
    (ProtectionRate, DsssPreamble) b,
  ) {
    final int ta = dsssTxTimeUs(
      AirtimeConstants.ctsBytes,
      a.$1.dsss!,
      preamble: a.$2,
    );
    final int tb = dsssTxTimeUs(
      AirtimeConstants.ctsBytes,
      b.$1.dsss!,
      preamble: b.$2,
    );
    return tb.compareTo(ta);
  });
  return all;
}

/// The airtime one protection exchange adds before a data frame, tenths of a
/// microsecond.
class ProtectionTiming {
  const ProtectionTiming({
    required this.choice,
    required this.rtsTenths,
    required this.ctsTenths,
    required this.sifsTenths,
  });

  final ProtectionChoice choice;

  /// The RTS, or 0 for CTS-to-self.
  final int rtsTenths;
  final int ctsTenths;

  /// One SIFS.
  final int sifsTenths;

  /// CTS-to-self: CTS + SIFS. RTS/CTS: RTS + SIFS + CTS + SIFS.
  int get totalTenths => choice.kind == ProtectionKind.ctsToSelf
      ? ctsTenths + sifsTenths
      : rtsTenths + sifsTenths + ctsTenths + sifsTenths;

  /// The frames alone, without the SIFS gaps.
  int get framesTenths => rtsTenths + ctsTenths;

  double get totalUs => totalTenths / 10;
  double get ctsUs => ctsTenths / 10;
  double get rtsUs => rtsTenths / 10;
}

/// One protection exchange. Throws for 1 Mb/s short preamble.
ProtectionTiming protectionTiming(ProtectionChoice c) {
  final int cts;
  final int rts;
  final DsssRate? d = c.rate.dsss;
  if (d != null) {
    cts = dsssTxTimeUs(AirtimeConstants.ctsBytes, d, preamble: c.preamble) * 10;
    rts = c.kind == ProtectionKind.rtsCts
        ? dsssTxTimeUs(AirtimeConstants.rtsBytes, d, preamble: c.preamble) * 10
        : 0;
  } else {
    cts = controlFrameTenths(
      AirtimeConstants.ctsBytes,
      kLpOfdmContrastRateMbps,
      AirtimeConstants.signalExtension24GhzUs,
    );
    rts = c.kind == ProtectionKind.rtsCts
        ? controlFrameTenths(
            AirtimeConstants.rtsBytes,
            kLpOfdmContrastRateMbps,
            AirtimeConstants.signalExtension24GhzUs,
          )
        : 0;
  }
  return ProtectionTiming(
    choice: c,
    rtsTenths: rts,
    ctsTenths: cts,
    sifsTenths: kLpSifsUs * 10,
  );
}

/// What makes up one send cycle.
class LpCycleSpec {
  const LpCycleSpec({
    required this.slotUs,
    required this.cwMin,
    this.protection,
    this.payloadBytes = 1500,
    this.rateMbps = 54,
  });

  final int slotUs;
  final int cwMin;

  /// Null: no protection frame.
  final ProtectionChoice? protection;
  final int payloadBytes;
  final int rateMbps;
}

/// The parts of a send cycle, in order.
enum LpSegmentKind {
  difs('DIFS'),
  backoff('Backoff'),
  protection('Protection'),
  preamble('Preamble'),
  data('Data'),
  sifs('SIFS'),
  ack('ACK');

  const LpSegmentKind(this.label);

  final String label;
}

/// One part of a send cycle.
class LpSegment {
  const LpSegment({
    required this.kind,
    required this.label,
    required this.tenths,
    required this.startTenths,
    this.baseTenths,
  });

  final LpSegmentKind kind;
  final String label;
  final int tenths;
  final int startTenths;

  /// For the waits (DIFS, backoff): what the same wait takes with the short
  /// slot and CWmin 15. The rest of [tenths] is the added wait an 802.11b
  /// device causes. Null for every other part.
  final int? baseTenths;

  /// The added wait, tenths of a us (0 when not a wait).
  int get addedTenths => baseTenths == null ? 0 : tenths - baseTenths!;

  double get us => tenths / 10;
  int get endTenths => startTenths + tenths;
}

/// One send cycle, computed.
class LpCycle {
  const LpCycle({
    required this.spec,
    required this.data,
    required this.protection,
    required this.segments,
  });

  final LpCycleSpec spec;

  /// Airtime Anatomy's result for the data frame and its ACK.
  final AirtimeResult data;

  /// Null when no protection frame is sent.
  final ProtectionTiming? protection;

  final List<LpSegment> segments;

  int get totalTenths =>
      segments.fold<int>(0, (int a, LpSegment s) => a + s.tenths);
  double get cycleUs => totalTenths / 10;

  int get payloadBits => spec.payloadBytes * 8;

  /// Payload bits over the cycle, Mb/s.
  double get payloadRateMbps => payloadBits / cycleUs;

  int get protectionTenths => protection?.totalTenths ?? 0;

  /// The added wait in DIFS and backoff, tenths of a us.
  int get addedWaitTenths =>
      segments.fold<int>(0, (int a, LpSegment s) => a + s.addedTenths);

  LpSegment segment(LpSegmentKind k) =>
      segments.firstWhere((LpSegment s) => s.kind == k);
}

AirtimeScenario _dataScenario(int payloadBytes, int rateMbps) =>
    AirtimeScenario(
      band: AirtimeBand.ghz24,
      phy: AirtimePhy.legacy,
      widthMhz: 20,
      mcs: 0,
      legacyRateMbps: rateMbps,
      streams: 1,
      guardInterval: GuardInterval.gi08,
      payloadBytes: payloadBytes,
      framesAggregated: 1,
      encryptionBytes: kLpEncryptionBytes,
      controlRateMbps: kLpAckRateMbps,
    );

/// DIFS (SIFS + 2 slots) in tenths.
int _difsTenths(int slotUs) => (kLpSifsUs + 2 * slotUs) * 10;

/// Mean backoff (CWmin / 2 slots) in tenths.
int _backoffTenths(int cwMin, int slotUs) => cwMin * slotUs * 5;

/// Runs one send cycle.
LpCycle computeCycle(LpCycleSpec s) {
  final AirtimeResult d = computeAirtime(
    _dataScenario(s.payloadBytes, s.rateMbps),
  );
  final ProtectionTiming? p = s.protection == null
      ? null
      : protectionTiming(s.protection!);
  final List<(LpSegmentKind, String, int, int?)> rows =
      <(LpSegmentKind, String, int, int?)>[
        (
          LpSegmentKind.difs,
          'DIFS',
          _difsTenths(s.slotUs),
          _difsTenths(kLpShortSlotUs),
        ),
        (
          LpSegmentKind.backoff,
          'Backoff',
          _backoffTenths(s.cwMin, s.slotUs),
          _backoffTenths(kLpOfdmCwMin, kLpShortSlotUs),
        ),
        if (p != null)
          (LpSegmentKind.protection, p.choice.kind.label, p.totalTenths, null),
        (LpSegmentKind.preamble, 'Preamble', d.preambleTenths, null),
        (LpSegmentKind.data, 'Data', d.dataTenths, null),
        (LpSegmentKind.sifs, 'SIFS', d.sifsUs * 10, null),
        (LpSegmentKind.ack, 'ACK', d.ackTenths, null),
      ];
  final List<LpSegment> segs = <LpSegment>[];
  int at = 0;
  for (final (LpSegmentKind k, String l, int t, int? base) in rows) {
    segs.add(
      LpSegment(
        kind: k,
        label: l,
        tenths: t,
        startTenths: at,
        baseTenths: base,
      ),
    );
    at += t;
  }
  return LpCycle(
    spec: s,
    data: d,
    protection: p,
    segments: List<LpSegment>.unmodifiable(segs),
  );
}

/// Where the heard 802.11b network is.
enum NeighborChannel {
  same('On our channel'),
  other('On another channel');

  const NeighborChannel(this.label);

  final String label;
}

/// Which heard networks this AP reacts to. Sources disagree; the standard
/// allows both (spec 39).
enum NeighborPolicy {
  ownOnly('Own channel only'),
  adjacentToo('Adjacent channels too');

  const NeighborPolicy(this.label);

  final String label;
}

/// CWmin while an 802.11b device is associated: 15, or 31 (one unverified
/// source).
enum LpCwMin {
  cw15(15),
  cw31(31);

  const LpCwMin(this.value);

  final int value;
}

/// The four HT Protection values (802.11-2020 clause 9.4.2.56).
enum HtProtection {
  none(0, 'No protection', 'every station is 802.11n and matches the width'),
  nonMember(1, 'Nonmember', 'an older network is heard'),
  twentyMhz(
    2,
    '20 MHz',
    'only 802.11n stations, at least one 20 MHz-only, in a 20/40 MHz network',
  ),
  nonHtMixed(3, 'Non-HT mixed', 'an older station is associated');

  const HtProtection(this.value, this.name, this.meaning);

  final int value;
  final String name;
  final String meaning;
}

/// The ERP Information element's three bits.
class ErpBits {
  const ErpBits({
    required this.nonErpPresent,
    required this.useProtection,
    required this.barkerPreambleMode,
  });

  final bool nonErpPresent;
  final bool useProtection;
  final bool barkerPreambleMode;

  @override
  bool operator ==(Object other) =>
      other is ErpBits &&
      other.nonErpPresent == nonErpPresent &&
      other.useProtection == useProtection &&
      other.barkerPreambleMode == barkerPreambleMode;

  @override
  int get hashCode =>
      Object.hash(nonErpPresent, useProtection, barkerPreambleMode);
}

/// Every input.
class LpConfig {
  const LpConfig({
    this.associated = true,
    this.heard = false,
    this.neighborChannel = NeighborChannel.same,
    this.policy = NeighborPolicy.ownOnly,
    this.oldDeviceShortPreamble = false,
    this.protection = const ProtectionChoice(),
    this.cwMin = LpCwMin.cw15,
    this.payloadBytes = 1500,
    this.rateMbps = 54,
  }) : assert(payloadBytes > 0),
       assert(rateMbps > 0);

  /// "802.11b device associated".
  final bool associated;

  /// "802.11b network heard nearby".
  final bool heard;
  final NeighborChannel neighborChannel;
  final NeighborPolicy policy;

  /// Whether the associated 802.11b device can use short preamble. Sets
  /// Barker_Preamble_Mode when it cannot.
  final bool oldDeviceShortPreamble;

  /// The protection frame. Default: CTS-to-self at 1 Mb/s long preamble
  /// (default chosen by Larry pending Keith).
  final ProtectionChoice protection;

  /// CWmin while an 802.11b device is associated.
  final LpCwMin cwMin;

  final int payloadBytes;
  final int rateMbps;

  LpConfig copyWith({
    bool? associated,
    bool? heard,
    NeighborChannel? neighborChannel,
    NeighborPolicy? policy,
    bool? oldDeviceShortPreamble,
    ProtectionChoice? protection,
    LpCwMin? cwMin,
    int? payloadBytes,
    int? rateMbps,
  }) {
    ProtectionChoice p = protection ?? this.protection;
    // 1 Mb/s short preamble does not exist: keep the rate, use long.
    if (!p.isAvailable) p = p.copyWith(preamble: DsssPreamble.long);
    return LpConfig(
      associated: associated ?? this.associated,
      heard: heard ?? this.heard,
      neighborChannel: neighborChannel ?? this.neighborChannel,
      policy: policy ?? this.policy,
      oldDeviceShortPreamble:
          oldDeviceShortPreamble ?? this.oldDeviceShortPreamble,
      protection: p,
      cwMin: cwMin ?? this.cwMin,
      payloadBytes: payloadBytes ?? this.payloadBytes,
      rateMbps: rateMbps ?? this.rateMbps,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LpConfig &&
      other.associated == associated &&
      other.heard == heard &&
      other.neighborChannel == neighborChannel &&
      other.policy == policy &&
      other.oldDeviceShortPreamble == oldDeviceShortPreamble &&
      other.protection == protection &&
      other.cwMin == cwMin &&
      other.payloadBytes == payloadBytes &&
      other.rateMbps == rateMbps;

  @override
  int get hashCode => Object.hash(
    associated,
    heard,
    neighborChannel,
    policy,
    oldDeviceShortPreamble,
    protection,
    cwMin,
    payloadBytes,
    rateMbps,
  );
}

/// Whether a heard 802.11b network makes this AP protect: always on its own
/// channel; on another channel only when the AP reacts to adjacent channels.
bool heardTriggers(LpConfig c) =>
    c.heard &&
    (c.neighborChannel == NeighborChannel.same ||
        c.policy == NeighborPolicy.adjacentToo);

/// The ERP bits for [c]. Associated sets NonERP_Present and Use_Protection;
/// heard sets Use_Protection only; Barker_Preamble_Mode is set when the
/// associated device cannot use short preamble.
ErpBits erpBits(LpConfig c) => ErpBits(
  nonErpPresent: c.associated,
  useProtection: c.associated || heardTriggers(c),
  barkerPreambleMode: c.associated && !c.oldDeviceShortPreamble,
);

/// The HT Protection value for [c]: 3 with an older station associated, 1
/// with an older network heard, else 0. Value 2 needs a 20 MHz-only 802.11n
/// station, which this tool does not model.
HtProtection htProtection(LpConfig c) {
  if (c.associated) return HtProtection.nonHtMixed;
  if (heardTriggers(c)) return HtProtection.nonMember;
  return HtProtection.none;
}

/// Everything the screen shows.
class LpResult {
  const LpResult({
    required this.config,
    required this.erp,
    required this.ht,
    required this.cycle,
    required this.baseline,
    required this.slotAddedTenths,
    required this.cwAddedTenths,
  });

  final LpConfig config;
  final ErpBits erp;
  final HtProtection ht;

  /// This network's send cycle.
  final LpCycle cycle;

  /// The same frames with modern devices only: short slot, CWmin 15, no
  /// protection.
  final LpCycle baseline;

  /// Time the long slot adds per cycle, at CWmin 15, tenths of a us.
  final int slotAddedTenths;

  /// Time CWmin 31 adds per cycle at this slot, tenths of a us (0 at 15).
  final int cwAddedTenths;

  bool get longSlot => config.associated;
  bool get protecting => erp.useProtection;
  int get protectionTenths => cycle.protectionTenths;

  /// Share of the modern-only payload rate lost, 0..1.
  double get lostShare => 1 - cycle.payloadRateMbps / baseline.payloadRateMbps;

  /// The timeline window: at least [kLpMinWindowUs], and long enough for
  /// three of this network's cycles, rounded up to a whole millisecond.
  int get windowUs {
    final int need = (3 * cycle.totalTenths / 10).ceil();
    final int w = need < kLpMinWindowUs ? kLpMinWindowUs : need;
    return ((w + 999) ~/ 1000) * 1000;
  }
}

/// Runs the model.
LpResult computeLegacyProtection(LpConfig c) {
  final ErpBits erp = erpBits(c);
  final int slot = c.associated ? kLpLongSlotUs : kLpShortSlotUs;
  final int cw = c.associated ? c.cwMin.value : kLpOfdmCwMin;
  LpCycle run(int slotUs, int cwMin, ProtectionChoice? p) => computeCycle(
    LpCycleSpec(
      slotUs: slotUs,
      cwMin: cwMin,
      protection: p,
      payloadBytes: c.payloadBytes,
      rateMbps: c.rateMbps,
    ),
  );
  final LpCycle baseline = run(kLpShortSlotUs, kLpOfdmCwMin, null);
  final LpCycle cycle = run(slot, cw, erp.useProtection ? c.protection : null);
  final int slotAdded =
      run(slot, kLpOfdmCwMin, null).totalTenths - baseline.totalTenths;
  final int cwAdded =
      run(slot, cw, null).totalTenths -
      run(slot, kLpOfdmCwMin, null).totalTenths;
  return LpResult(
    config: c,
    erp: erp,
    ht: htProtection(c),
    cycle: cycle,
    baseline: baseline,
    slotAddedTenths: slotAdded,
    cwAddedTenths: cwAdded,
  );
}

/// One row of the spec's ceiling table.
class LpCeilingCase {
  const LpCeilingCase(this.label, this.spec);

  final String label;
  final LpCycleSpec spec;
}

/// The spec's six ceiling cases (1500 bytes at 54 Mb/s), in order.
final List<LpCeilingCase> kLpCeilingCases = <LpCeilingCase>[
  LpCeilingCase(
    'Modern devices only, short slot',
    LpCycleSpec(slotUs: kLpShortSlotUs, cwMin: kLpOfdmCwMin),
  ),
  LpCeilingCase(
    'Long slot forced, no protection frame',
    LpCycleSpec(slotUs: kLpLongSlotUs, cwMin: kLpOfdmCwMin),
  ),
  LpCeilingCase(
    'Long slot + CTS-to-self at 11 Mb/s short',
    LpCycleSpec(
      slotUs: kLpLongSlotUs,
      cwMin: kLpOfdmCwMin,
      protection: const ProtectionChoice(
        rate: ProtectionRate.r11,
        preamble: DsssPreamble.short,
      ),
    ),
  ),
  LpCeilingCase(
    'Long slot + CTS-to-self at 11 Mb/s long',
    LpCycleSpec(
      slotUs: kLpLongSlotUs,
      cwMin: kLpOfdmCwMin,
      protection: const ProtectionChoice(rate: ProtectionRate.r11),
    ),
  ),
  LpCeilingCase(
    'Long slot + CTS-to-self at 1 Mb/s long',
    LpCycleSpec(
      slotUs: kLpLongSlotUs,
      cwMin: kLpOfdmCwMin,
      protection: const ProtectionChoice(),
    ),
  ),
  LpCeilingCase(
    'Same, CWmin 31',
    LpCycleSpec(
      slotUs: kLpLongSlotUs,
      cwMin: LpCwMin.cw31.value,
      protection: const ProtectionChoice(),
    ),
  ),
];

/// The index of the ceiling row [r] is on, or null when it is on none (a
/// different frame, rate, protection or heard-only case).
int? ceilingRowOf(LpResult r) {
  final LpConfig c = r.config;
  if (c.payloadBytes != 1500 || c.rateMbps != 54) return null;
  final LpCycleSpec s = r.cycle.spec;
  for (int i = 0; i < kLpCeilingCases.length; i++) {
    final LpCycleSpec k = kLpCeilingCases[i].spec;
    if (k.slotUs == s.slotUs &&
        k.cwMin == s.cwMin &&
        k.protection == s.protection) {
      return i;
    }
  }
  return null;
}
