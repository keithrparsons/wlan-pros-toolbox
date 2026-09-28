// Airtime Anatomy calculator (Wi-Fi Classroom, 2026-09-25).
//
// One transmit opportunity (TXOP), microsecond by microsecond: AIFS, average
// backoff, optional RTS/CTS, preamble, data, SIFS, ACK or Block Ack. A pure
// Dart port of the WLAN Pros Airtime Calculator's "Calculator" sheet (myPKA
// Deliverables/2026-09-25-wlanpros-airtime-calculator/build.py), which Larry
// built from the IEEE 802.11 TXTIME equations (clauses 17, 19, 21, 27) and the
// default EDCA parameters. Spec: myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/05-airtime-anatomy.md. No Flutter imports.
//
// PORTED EXACTLY, row by row, from "Timing and PHY" through "Results",
// including the Check row and the Constants tables. The sheet's
// simplifications are kept on purpose (and stated in the help entry):
//   1. One station, no contention, no retries; backoff is CWmin / 2 slots.
//   2. HT/VHT use one BCC encoder (6 tail bits).
//   3. HE uses LDPC with pre-FEC padding ignored; HE-LTFs are 2x (6.4 us +
//      GI) at 0.8/1.6 us GI and 4x (16 us) at 3.2 us GI.
//   4. HE is the SU PPDU; no OFDMA resource units.
//   5. Control frames at the chosen legacy rate; short slot (9 us).
//   6. The Check does not catch every VHT MCS exclusion.
//
// ARITHMETIC. Every duration is a whole number of TENTHS of a microsecond
// (all inputs are multiples of 0.1 us), and every ceiling is taken on
// integers: the coding rate is kept as a fraction, so N_DBPS is exact and a
// ceiling can never tip over on a floating-point residue. Where the sheet
// writes CEILING(3.6 x N_SYM / 4) this computes ceil(9 x N_SYM / 10), the
// same number. Results are exposed as doubles in microseconds.

/// Frequency band. Sets SIFS and the 2.4 GHz signal extension.
enum AirtimeBand {
  ghz24('2.4 GHz'),
  ghz5('5 GHz'),
  ghz6('6 GHz');

  const AirtimeBand(this.label);

  final String label;
}

/// PHY. Legacy = 802.11a/g OFDM, HT = 802.11n, VHT = 802.11ac, HE = 802.11ax
/// (SU PPDU).
enum AirtimePhy {
  legacy('Legacy', 'Legacy (802.11a/g)'),
  ht('HT', 'HT (802.11n)'),
  vht('VHT', 'VHT (802.11ac)'),
  he('HE', 'HE (802.11ax)');

  const AirtimePhy(this.shortLabel, this.label);

  final String shortLabel;
  final String label;
}

/// Guard interval. Stored in tenths of a microsecond so sums stay exact.
enum GuardInterval {
  gi04(4),
  gi08(8),
  gi16(16),
  gi32(32);

  const GuardInterval(this.tenths);

  final int tenths;

  double get us => tenths / 10;

  String get label => '${_fmtTenths(tenths)} µs';
}

/// The EDCA access categories with the default parameter set for a non-AP
/// STA (802.11-2020 9.4.2.28, Table 9-155). The "EDCA" Constants table.
enum AirtimeAccessCategory {
  vo('VO', 'Voice', 2, 3, 7),
  vi('VI', 'Video', 2, 7, 15),
  be('BE', 'Best effort', 3, 15, 1023),
  bk('BK', 'Background', 7, 15, 1023);

  const AirtimeAccessCategory(
    this.shortLabel,
    this.label,
    this.aifsn,
    this.cwMin,
    this.cwMax,
  );

  final String shortLabel;
  final String label;
  final int aifsn;
  final int cwMin;
  final int cwMax;
}

/// One row of the MCS Constants table.
class McsRow {
  const McsRow(
    this.mcs,
    this.modulation,
    this.bitsPerSubcarrier,
    this.rateNum,
    this.rateDen,
  );

  final int mcs;
  final String modulation;
  final int bitsPerSubcarrier;

  /// Coding rate as a fraction, rateNum / rateDen.
  final int rateNum;
  final int rateDen;

  double get codingRate => rateNum / rateDen;

  String get codingRateLabel => '$rateNum/$rateDen';
}

/// The Constants sheet, verbatim.
class AirtimeConstants {
  AirtimeConstants._();

  /// Per-stream MCS 0-11 (HT uses 0-7, VHT 0-9, HE 0-11).
  static const List<McsRow> mcs = <McsRow>[
    McsRow(0, 'BPSK', 1, 1, 2),
    McsRow(1, 'QPSK', 2, 1, 2),
    McsRow(2, 'QPSK', 2, 3, 4),
    McsRow(3, '16-QAM', 4, 1, 2),
    McsRow(4, '16-QAM', 4, 3, 4),
    McsRow(5, '64-QAM', 6, 2, 3),
    McsRow(6, '64-QAM', 6, 3, 4),
    McsRow(7, '64-QAM', 6, 5, 6),
    McsRow(8, '256-QAM', 8, 3, 4),
    McsRow(9, '256-QAM', 8, 5, 6),
    McsRow(10, '1024-QAM', 10, 3, 4),
    McsRow(11, '1024-QAM', 10, 5, 6),
  ];

  /// Channel widths the sheet accepts, MHz.
  static const List<int> widthsMhz = <int>[20, 40, 80, 160];

  /// Data subcarriers, HT/VHT, by width.
  static const Map<int, int> dataSubcarriersHtVht = <int, int>{
    20: 52,
    40: 108,
    80: 234,
    160: 468,
  };

  /// Data subcarriers, HE, by width.
  static const Map<int, int> dataSubcarriersHe = <int, int>{
    20: 234,
    40: 468,
    80: 980,
    160: 1960,
  };

  /// Legacy OFDM 20 MHz data subcarriers.
  static const int dataSubcarriersLegacy = 48;

  /// HT-LTFs by stream count (null = not allowed for HT, max 4 streams).
  static const Map<int, int?> ltfHt = <int, int?>{
    1: 1,
    2: 2,
    3: 4,
    4: 4,
    5: null,
    6: null,
    7: null,
    8: null,
  };

  /// VHT/HE-LTFs by stream count.
  static const Map<int, int> ltfVhtHe = <int, int>{
    1: 1,
    2: 2,
    3: 4,
    4: 4,
    5: 6,
    6: 6,
    7: 8,
    8: 8,
  };

  static const int slotUs = 9;
  static const int sifs5And6GhzUs = 16;
  static const int sifs24GhzUs = 10;
  static const int signalExtension24GhzUs = 6;
  static const int qosDataHeaderBytes = 26;
  static const int fcsBytes = 4;
  static const int ampduDelimiterBytes = 4;
  static const int ackBytes = 14;
  static const int blockAckBytes = 32;
  static const int rtsBytes = 20;
  static const int ctsBytes = 14;
  static const int maxPpduUs = 5484;

  /// The legacy OFDM data rates, Mbps.
  static const List<int> legacyRatesMbps = <int>[6, 9, 12, 18, 24, 36, 48, 54];

  /// Control-frame rates the sheet offers, Mbps.
  static const List<int> controlRatesMbps = <int>[6, 12, 24];

  /// HE packet extension choices, us.
  static const List<int> hePacketExtensionsUs = <int>[0, 4, 8, 12, 16];

  /// Spatial streams the LTF table covers.
  static const int maxStreams = 8;

  static McsRow mcsRow(int mcs) =>
      AirtimeConstants.mcs.firstWhere((McsRow r) => r.mcs == mcs);
}

/// Every input on the sheet's "Inputs" block for one scenario.
class AirtimeScenario {
  const AirtimeScenario({
    this.band = AirtimeBand.ghz5,
    this.phy = AirtimePhy.vht,
    this.widthMhz = 80,
    this.mcs = 9,
    this.legacyRateMbps = 6,
    this.streams = 2,
    this.guardInterval = GuardInterval.gi04,
    this.payloadBytes = 1500,
    this.framesAggregated = 1,
    this.encryptionBytes = 16,
    this.accessCategory = AirtimeAccessCategory.be,
    this.rtsCts = false,
    this.controlRateMbps = 24,
    this.hePacketExtensionUs = 0,
  }) : assert(streams >= 1 && streams <= AirtimeConstants.maxStreams),
       assert(mcs >= 0 && mcs <= 11),
       assert(payloadBytes >= 0),
       assert(framesAggregated >= 1),
       assert(controlRateMbps > 0),
       assert(legacyRateMbps > 0);

  final AirtimeBand band;
  final AirtimePhy phy;

  /// 20, 40, 80 or 160. Legacy is always 20 (the Check flags anything else).
  final int widthMhz;

  /// Per-stream MCS, 0-11. Ignored for Legacy.
  final int mcs;

  /// Used only when [phy] is Legacy: 6, 9, 12, 18, 24, 36, 48, 54.
  final int legacyRateMbps;

  /// Spatial streams, 1-8.
  final int streams;

  /// HT/VHT: 0.4 or 0.8. HE: 0.8, 1.6 or 3.2. Ignored for Legacy.
  final GuardInterval guardInterval;

  /// The MSDU the user cares about.
  final int payloadBytes;

  /// A-MPDU subframes. Legacy always sends 1.
  final int framesAggregated;

  /// CCMP/GCMP = 16, open = 0.
  final int encryptionBytes;

  final AirtimeAccessCategory accessCategory;
  final bool rtsCts;

  /// Legacy rate for RTS, CTS, ACK and Block Ack.
  final int controlRateMbps;

  /// HE only: 0, 4, 8, 12 or 16.
  final int hePacketExtensionUs;

  AirtimeScenario copyWith({
    AirtimeBand? band,
    AirtimePhy? phy,
    int? widthMhz,
    int? mcs,
    int? legacyRateMbps,
    int? streams,
    GuardInterval? guardInterval,
    int? payloadBytes,
    int? framesAggregated,
    int? encryptionBytes,
    AirtimeAccessCategory? accessCategory,
    bool? rtsCts,
    int? controlRateMbps,
    int? hePacketExtensionUs,
  }) => AirtimeScenario(
    band: band ?? this.band,
    phy: phy ?? this.phy,
    widthMhz: widthMhz ?? this.widthMhz,
    mcs: mcs ?? this.mcs,
    legacyRateMbps: legacyRateMbps ?? this.legacyRateMbps,
    streams: streams ?? this.streams,
    guardInterval: guardInterval ?? this.guardInterval,
    payloadBytes: payloadBytes ?? this.payloadBytes,
    framesAggregated: framesAggregated ?? this.framesAggregated,
    encryptionBytes: encryptionBytes ?? this.encryptionBytes,
    accessCategory: accessCategory ?? this.accessCategory,
    rtsCts: rtsCts ?? this.rtsCts,
    controlRateMbps: controlRateMbps ?? this.controlRateMbps,
    hePacketExtensionUs: hePacketExtensionUs ?? this.hePacketExtensionUs,
  );

  @override
  bool operator ==(Object other) =>
      other is AirtimeScenario &&
      other.band == band &&
      other.phy == phy &&
      other.widthMhz == widthMhz &&
      other.mcs == mcs &&
      other.legacyRateMbps == legacyRateMbps &&
      other.streams == streams &&
      other.guardInterval == guardInterval &&
      other.payloadBytes == payloadBytes &&
      other.framesAggregated == framesAggregated &&
      other.encryptionBytes == encryptionBytes &&
      other.accessCategory == accessCategory &&
      other.rtsCts == rtsCts &&
      other.controlRateMbps == controlRateMbps &&
      other.hePacketExtensionUs == hePacketExtensionUs;

  @override
  int get hashCode => Object.hash(
    band,
    phy,
    widthMhz,
    mcs,
    legacyRateMbps,
    streams,
    guardInterval,
    payloadBytes,
    framesAggregated,
    encryptionBytes,
    accessCategory,
    rtsCts,
    controlRateMbps,
    hePacketExtensionUs,
  );
}

/// The sheet's four default scenarios, as named presets.
enum AirtimePreset {
  legacy6(
    'Legacy 6 Mbps',
    AirtimeScenario(
      band: AirtimeBand.ghz5,
      phy: AirtimePhy.legacy,
      widthMhz: 20,
      mcs: 0,
      legacyRateMbps: 6,
      streams: 1,
      guardInterval: GuardInterval.gi08,
      framesAggregated: 1,
    ),
  ),
  vhtOne(
    'VHT one frame',
    AirtimeScenario(
      band: AirtimeBand.ghz5,
      phy: AirtimePhy.vht,
      widthMhz: 80,
      mcs: 9,
      streams: 2,
      guardInterval: GuardInterval.gi04,
      framesAggregated: 1,
    ),
  ),
  vht32(
    'VHT 32 aggregated',
    AirtimeScenario(
      band: AirtimeBand.ghz5,
      phy: AirtimePhy.vht,
      widthMhz: 80,
      mcs: 9,
      streams: 2,
      guardInterval: GuardInterval.gi04,
      framesAggregated: 32,
    ),
  ),
  he32(
    'HE 32 aggregated',
    AirtimeScenario(
      band: AirtimeBand.ghz6,
      phy: AirtimePhy.he,
      widthMhz: 80,
      mcs: 11,
      streams: 2,
      guardInterval: GuardInterval.gi08,
      framesAggregated: 32,
    ),
  );

  const AirtimePreset(this.label, this.scenario);

  final String label;
  final AirtimeScenario scenario;
}

/// The Check row's verdicts, in the order the sheet tests them.
enum AirtimeCheck {
  ok('OK'),
  sixGhzRequiresHe('6 GHz requires HE'),
  vhtIs5GhzOnly('VHT is 5 GHz only'),
  legacyIs20MhzOnly('Legacy is 20 MHz only'),
  htLimits('HT: MCS 0-7, up to 4 streams, 20/40 MHz'),
  vhtMcsLimit('VHT: MCS 0-9'),
  invalidCombination('Not a valid MCS/width/stream combination'),
  ppduTooLong('PPDU exceeds 5.484 ms: send fewer frames');

  const AirtimeCheck(this.message);

  final String message;

  bool get isOk => this == AirtimeCheck.ok;
}

/// The seven rows of "The TXOP, in order", which the timeline draws.
enum TxopSegmentKind {
  aifs('AIFS'),
  backoff('Backoff'),
  rtsCts('RTS/CTS'),
  preamble('Preamble'),
  data('Data'),
  sifs('SIFS'),
  ack('ACK');

  const TxopSegmentKind(this.label);

  final String label;
}

/// One segment of the TXOP with the working that produced it.
class TxopSegment {
  const TxopSegment({
    required this.kind,
    required this.label,
    required this.tenths,
    required this.startTenths,
    required this.formula,
  });

  final TxopSegmentKind kind;

  /// Display label ("ACK" or "Block Ack" for the last segment).
  final String label;

  /// Duration, tenths of a microsecond.
  final int tenths;

  /// Start offset from the beginning of the TXOP, tenths of a microsecond.
  final int startTenths;

  /// The formula with the scenario's numbers substituted.
  final String formula;

  double get us => tenths / 10;
  double get startUs => startTenths / 10;
  double get endUs => (startTenths + tenths) / 10;

  String get durationLabel => '${_fmtTenths(tenths)} µs';
}

/// Every calculated row of the sheet for one scenario.
class AirtimeResult {
  const AirtimeResult._({
    required this.scenario,
    required this.sifsUs,
    required this.slotUs,
    required this.signalExtensionUs,
    required this.aifsn,
    required this.cwMin,
    required this.mcsRow,
    required this.dataSubcarriers,
    required this.ndbpsNum,
    required this.ndbpsDen,
    required this.symbolTenths,
    required this.ltfCount,
    required this.mpduBytes,
    required this.subframeBytes,
    required this.framesSent,
    required this.psduBytes,
    required this.dataSymbols,
    required this.preambleTenths,
    required this.dataTenths,
    required this.ackTenths,
    required this.blockAckTenths,
    required this.rtsTenths,
    required this.ctsTenths,
    required this.usesBlockAck,
    required this.segments,
    required this.check,
  });

  final AirtimeScenario scenario;

  // ── Timing and PHY ────────────────────────────────────────────────────────
  final int sifsUs;
  final int slotUs;
  final int signalExtensionUs;
  final int aifsn;
  final int cwMin;

  /// The MCS row, or null for Legacy (the sheet shows "n/a").
  final McsRow? mcsRow;

  final int dataSubcarriers;

  /// N_DBPS as an exact fraction ndbpsNum / ndbpsDen. HE is already rounded
  /// down, so its denominator is 1.
  final int ndbpsNum;
  final int ndbpsDen;

  /// Symbol time, tenths of a microsecond.
  final int symbolTenths;

  final int ltfCount;

  // ── Frame sizes ───────────────────────────────────────────────────────────
  final int mpduBytes;
  final int subframeBytes;
  final int framesSent;
  final int psduBytes;

  // ── Durations (tenths of a us) ────────────────────────────────────────────
  final int dataSymbols;
  final int preambleTenths;

  /// Data portion: symbols, plus HE packet extension and 2.4 GHz signal
  /// extension.
  final int dataTenths;
  final int ackTenths;
  final int blockAckTenths;
  final int rtsTenths;
  final int ctsTenths;

  /// True when the response is a Block Ack (two or more frames aggregated).
  final bool usesBlockAck;

  /// The TXOP in order. RTS/CTS is present with zero length when off, so the
  /// list always has seven rows, like the sheet.
  final List<TxopSegment> segments;

  final AirtimeCheck check;

  // ── Derived rows ──────────────────────────────────────────────────────────

  double get bitsPerSymbol => ndbpsNum / ndbpsDen;
  double get symbolUs => symbolTenths / 10;
  double get phyRateMbps => ndbpsNum / ndbpsDen / symbolUs;
  double get preambleUs => preambleTenths / 10;
  double get dataUs => dataTenths / 10;
  int get ppduTenths => preambleTenths + dataTenths;
  double get ppduUs => ppduTenths / 10;
  double get ackUs => ackTenths / 10;
  double get blockAckUs => blockAckTenths / 10;
  double get rtsUs => rtsTenths / 10;
  double get ctsUs => ctsTenths / 10;

  int get totalTenths =>
      segments.fold<int>(0, (int a, TxopSegment s) => a + s.tenths);
  double get totalUs => totalTenths / 10;

  /// Payload delivered, bits.
  int get payloadBits => framesSent * scenario.payloadBytes * 8;

  /// Payload bits over total airtime, Mbps.
  double get throughputMbps => payloadBits / totalUs;

  /// Throughput / PHY rate, 0..1.
  double get efficiency => throughputMbps / phyRateMbps;

  /// (Data portion - signal extension - HE packet extension) / total, 0..1:
  /// both extensions are padding, not data symbols.
  double get dataShare =>
      (dataTenths -
          signalExtensionUs * 10 -
          (scenario.phy == AirtimePhy.he
              ? scenario.hePacketExtensionUs * 10
              : 0)) /
      totalTenths;

  TxopSegment segment(TxopSegmentKind kind) =>
      segments.firstWhere((TxopSegment s) => s.kind == kind);
}

/// Legacy OFDM control-frame duration at [rateMbps], plus signal extension:
/// 20 + 4 x ceil((16 + 8 x bytes + 6) / (rate x 4)) + SE. Tenths of a us.
int controlFrameTenths(int bytes, int rateMbps, int signalExtensionUs) {
  final int ndbps = rateMbps * 4;
  final int symbols = _ceilDiv(16 + 8 * bytes + 6, ndbps);
  return (20 + 4 * symbols + signalExtensionUs) * 10;
}

/// Runs the Calculator sheet for one scenario.
AirtimeResult computeAirtime(AirtimeScenario s) {
  final bool legacy = s.phy == AirtimePhy.legacy;
  final bool he = s.phy == AirtimePhy.he;
  final bool is24 = s.band == AirtimeBand.ghz24;

  // Timing and PHY.
  final int sifs = is24
      ? AirtimeConstants.sifs24GhzUs
      : AirtimeConstants.sifs5And6GhzUs;
  const int slot = AirtimeConstants.slotUs;
  final int se = is24 ? AirtimeConstants.signalExtension24GhzUs : 0;
  final int aifsn = s.accessCategory.aifsn;
  final int cwMin = s.accessCategory.cwMin;
  final McsRow? row = legacy ? null : AirtimeConstants.mcsRow(s.mcs);

  final int nsd;
  if (legacy) {
    nsd = AirtimeConstants.dataSubcarriersLegacy;
  } else {
    final Map<int, int> table = he
        ? AirtimeConstants.dataSubcarriersHe
        : AirtimeConstants.dataSubcarriersHtVht;
    final int? v = table[s.widthMhz];
    if (v == null) {
      throw ArgumentError.value(s.widthMhz, 'widthMhz', 'not 20/40/80/160');
    }
    nsd = v;
  }

  int ndbpsNum;
  int ndbpsDen;
  if (legacy) {
    ndbpsNum = s.legacyRateMbps * 4;
    ndbpsDen = 1;
  } else {
    ndbpsNum = nsd * row!.bitsPerSubcarrier * row.rateNum * s.streams;
    ndbpsDen = row.rateDen;
    if (he) {
      // ROUNDDOWN(..., 0), as the 802.11ax MCS tables do.
      ndbpsNum = ndbpsNum ~/ ndbpsDen;
      ndbpsDen = 1;
    }
  }

  final int gi = s.guardInterval.tenths;
  final int tsym = legacy ? 40 : (he ? 128 + gi : 32 + gi);

  final int nltf;
  if (legacy) {
    nltf = 0;
  } else if (s.phy == AirtimePhy.ht) {
    // A blank cell (HT above 4 streams) reads as 0 in the sheet's arithmetic.
    nltf = AirtimeConstants.ltfHt[s.streams] ?? 0;
  } else {
    nltf = AirtimeConstants.ltfVhtHe[s.streams]!;
  }

  // Frame sizes.
  final int mpdu =
      s.payloadBytes +
      AirtimeConstants.qosDataHeaderBytes +
      AirtimeConstants.fcsBytes +
      s.encryptionBytes;
  final int sub = 4 * _ceilDiv(AirtimeConstants.ampduDelimiterBytes + mpdu, 4);
  final int nn = legacy ? 1 : s.framesAggregated;
  final bool singleMpdu = legacy || (s.phy == AirtimePhy.ht && nn == 1);
  final int psdu = singleMpdu ? mpdu : nn * sub;

  // Durations.
  final int nsym = _dataSymbols(he, psdu, ndbpsNum, ndbpsDen);

  final int pre;
  switch (s.phy) {
    case AirtimePhy.legacy:
      pre = 200;
    case AirtimePhy.ht:
      pre = (20 + 8 + 4 + 4 * nltf) * 10;
    case AirtimePhy.vht:
      pre = (20 + 8 + 4 + 4 * nltf + 4) * 10;
    case AirtimePhy.he:
      // 2x HE-LTF (6.4 + GI) at 0.8/1.6 us GI; 4x HE-LTF (16 us) at 3.2.
      pre = (20 + 4 + 8 + 4) * 10 + nltf * _heLtfTenths(gi);
  }

  final bool shortGi = !legacy && s.guardInterval == GuardInterval.gi04;
  final int data = _dataTenths(s, nsym, tsym, se);
  final int ppdu = pre + data;

  final int ack = controlFrameTenths(
    AirtimeConstants.ackBytes,
    s.controlRateMbps,
    se,
  );
  final int ba = controlFrameTenths(
    AirtimeConstants.blockAckBytes,
    s.controlRateMbps,
    se,
  );
  final int rts = controlFrameTenths(
    AirtimeConstants.rtsBytes,
    s.controlRateMbps,
    se,
  );
  final int cts = controlFrameTenths(
    AirtimeConstants.ctsBytes,
    s.controlRateMbps,
    se,
  );

  // The TXOP, in order.
  final int tAifs = (sifs + aifsn * slot) * 10;
  final int tBackoff = cwMin * slot * 5; // CWmin / 2 x slot, in tenths.
  final int tRts = s.rtsCts ? rts + sifs * 10 + cts + sifs * 10 : 0;
  final int tSifs = sifs * 10;
  // One frame gets a normal ACK, for every PHY (a VHT/HE single-MPDU
  // A-MPDU included); only an aggregate of 2 or more gets a Block Ack.
  final bool blockAck = nn > 1;
  final int tAck = blockAck ? ba : ack;

  const String Function(int) t = _fmtTenths;
  final String seNote = se > 0 ? ' + signal extension $se' : '';
  final String ctlRate = '${s.controlRateMbps} Mbps';
  final String sifsWhy = is24 ? 'SIFS at 2.4 GHz' : 'SIFS at 5 and 6 GHz';

  String dataFormula() {
    final StringBuffer b = StringBuffer();
    if (he) {
      b.write(
        '$nsym symbols x ${t(tsym)} µs (12.8 + GI ${t(gi)})'
        '${s.hePacketExtensionUs > 0 ? ' + packet extension ${s.hePacketExtensionUs}' : ''}',
      );
    } else if (shortGi) {
      b.write('4 x ceil(3.6 x $nsym symbols / 4)');
    } else {
      b.write('$nsym symbols x 4 µs');
    }
    b.write('$seNote = ${t(data)} µs. ');
    b.write(
      he
          ? 'Symbols = ceil((16 + 8 x $psdu bytes) / $ndbpsNum bits per symbol).'
          : 'Symbols = ceil((16 + 8 x $psdu bytes + 6) / '
                '${_fmtRational(ndbpsNum, ndbpsDen)} bits per symbol).',
    );
    return b.toString();
  }

  String preambleFormula() {
    switch (s.phy) {
      case AirtimePhy.legacy:
        return 'L-STF 8 + L-LTF 8 + L-SIG 4 = 20 µs.';
      case AirtimePhy.ht:
        return 'Legacy 20 + HT-SIG 8 + HT-STF 4 + $nltf HT-LTF x 4 '
            '= ${t(pre)} µs.';
      case AirtimePhy.vht:
        return 'Legacy 20 + VHT-SIG-A 8 + VHT-STF 4 + $nltf VHT-LTF x 4 '
            '+ VHT-SIG-B 4 = ${t(pre)} µs.';
      case AirtimePhy.he:
        return 'Legacy 20 + RL-SIG 4 + HE-SIG-A 8 + HE-STF 4 + $nltf HE-LTF '
            '${gi == 32 ? 'x 16 (4x HE-LTF at 3.2 GI)' : 'x (6.4 + GI ${t(gi)}) (2x HE-LTF)'}'
            ' = ${t(pre)} µs.';
    }
  }

  final List<(TxopSegmentKind, String, int, String)>
  rows = <(TxopSegmentKind, String, int, String)>[
    (
      TxopSegmentKind.aifs,
      'AIFS',
      tAifs,
      'SIFS $sifs + AIFSN $aifsn (${s.accessCategory.shortLabel}) x slot '
          '$slot = ${t(tAifs)} µs.',
    ),
    (
      TxopSegmentKind.backoff,
      'Backoff',
      tBackoff,
      'Average backoff = CWmin $cwMin / 2 x slot $slot = ${t(tBackoff)} µs. '
          'The mean of a draw from 0 to CWmin, with no one else '
          'contending.',
    ),
    (
      TxopSegmentKind.rtsCts,
      'RTS/CTS',
      tRts,
      s.rtsCts
          ? 'RTS ${t(rts)} + SIFS $sifs + CTS ${t(cts)} + SIFS $sifs '
                '= ${t(tRts)} µs, control frames at $ctlRate.'
          : 'Off. Turn on RTS/CTS protection to add RTS + SIFS + CTS '
                '+ SIFS.',
    ),
    (TxopSegmentKind.preamble, 'Preamble', pre, preambleFormula()),
    (TxopSegmentKind.data, 'Data', data, dataFormula()),
    (TxopSegmentKind.sifs, 'SIFS', tSifs, '$sifsWhy = $sifs µs.'),
    (
      TxopSegmentKind.ack,
      blockAck ? 'Block Ack' : 'ACK',
      tAck,
      '20 + 4 x ceil((16 + 8 x '
          '${blockAck ? AirtimeConstants.blockAckBytes : AirtimeConstants.ackBytes}'
          ' bytes + 6) / ${s.controlRateMbps * 4})$seNote = ${t(tAck)} µs, '
          '${blockAck ? 'a 32-byte compressed Block Ack' : 'a 14-byte ACK'} '
          'at $ctlRate.',
    ),
  ];

  final List<TxopSegment> segments = <TxopSegment>[];
  int start = 0;
  for (final (TxopSegmentKind kind, String label, int d, String f) in rows) {
    segments.add(
      TxopSegment(
        kind: kind,
        label: label,
        tenths: d,
        startTenths: start,
        formula: f,
      ),
    );
    start += d;
  }

  // Check, in the sheet's order.
  final AirtimeCheck check;
  if (s.band == AirtimeBand.ghz6 && !he) {
    check = AirtimeCheck.sixGhzRequiresHe;
  } else if (is24 && s.phy == AirtimePhy.vht) {
    check = AirtimeCheck.vhtIs5GhzOnly;
  } else if (legacy && s.widthMhz != 20) {
    check = AirtimeCheck.legacyIs20MhzOnly;
  } else if (s.phy == AirtimePhy.ht &&
      (s.mcs > 7 || s.streams > 4 || s.widthMhz > 40)) {
    check = AirtimeCheck.htLimits;
  } else if (s.phy == AirtimePhy.vht && s.mcs > 9) {
    check = AirtimeCheck.vhtMcsLimit;
  } else if (!he && ndbpsNum % ndbpsDen != 0) {
    check = AirtimeCheck.invalidCombination;
  } else if (ppdu > AirtimeConstants.maxPpduUs * 10) {
    check = AirtimeCheck.ppduTooLong;
  } else {
    check = AirtimeCheck.ok;
  }

  return AirtimeResult._(
    scenario: s,
    sifsUs: sifs,
    slotUs: slot,
    signalExtensionUs: se,
    aifsn: aifsn,
    cwMin: cwMin,
    mcsRow: row,
    dataSubcarriers: nsd,
    ndbpsNum: ndbpsNum,
    ndbpsDen: ndbpsDen,
    symbolTenths: tsym,
    ltfCount: nltf,
    mpduBytes: mpdu,
    subframeBytes: sub,
    framesSent: nn,
    psduBytes: psdu,
    dataSymbols: nsym,
    preambleTenths: pre,
    dataTenths: data,
    ackTenths: ack,
    blockAckTenths: ba,
    rtsTenths: rts,
    ctsTenths: cts,
    usesBlockAck: blockAck,
    segments: List<TxopSegment>.unmodifiable(segments),
    check: check,
  );
}

/// Preamble plus data, tenths of a microsecond, for a PSDU of [psduBytes]
/// sent with [r]'s PHY settings. The same arithmetic [computeAirtime] uses
/// for its own PSDU, so `ppduTenthsForPsdu(r, r.psduBytes) == r.ppduTenths`.
/// The frame-structure view (aggregation_structure.dart) uses it to put a
/// time on an arrangement the sheet does not draw, and on a retry.
int ppduTenthsForPsdu(AirtimeResult r, int psduBytes) {
  assert(psduBytes >= 0);
  final bool he = r.scenario.phy == AirtimePhy.he;
  final int nsym = _dataSymbols(he, psduBytes, r.ndbpsNum, r.ndbpsDen);
  return r.preambleTenths +
      _dataTenths(r.scenario, nsym, r.symbolTenths, r.signalExtensionUs);
}

/// Data symbols for a PSDU: HE ceil((16 + 8 x PSDU) / N_DBPS) (LDPC, no
/// tail); the others ceil((16 + 8 x PSDU + 6) / N_DBPS) with N_DBPS kept as
/// the exact fraction num / den.
int _dataSymbols(bool he, int psdu, int ndbpsNum, int ndbpsDen) => he
    ? _ceilDiv(16 + 8 * psdu, ndbpsNum)
    : _ceilDiv((16 + 8 * psdu + 6) * ndbpsDen, ndbpsNum);

/// The data portion, tenths of a us: symbols, plus the HE packet extension
/// and the 2.4 GHz signal extension.
int _dataTenths(AirtimeScenario s, int nsym, int tsym, int se) {
  final int core;
  if (s.phy == AirtimePhy.he) {
    core = nsym * tsym + s.hePacketExtensionUs * 10;
  } else if (s.phy != AirtimePhy.legacy &&
      s.guardInterval == GuardInterval.gi04) {
    // 4 x CEILING(3.6 x N_SYM / 4) = 4 x ceil(9 x N_SYM / 10).
    core = 4 * _ceilDiv(9 * nsym, 10) * 10;
  } else {
    core = 4 * nsym * 10;
  }
  return core + se * 10;
}

/// Formats a tenths-of-a-microsecond count: 430 -> "43", 675 -> "67.5".
String formatTenthsUs(int tenths) => _fmtTenths(tenths);

String _fmtTenths(int tenths) {
  if (tenths % 10 == 0) return '${tenths ~/ 10}';
  final String sign = tenths < 0 ? '-' : '';
  final int a = tenths.abs();
  return '$sign${a ~/ 10}.${a % 10}';
}

String _fmtRational(int num, int den) {
  if (num % den == 0) return '${num ~/ den}';
  return (num / den).toStringAsFixed(2);
}

/// One HE-LTF, tenths of a us: 4x (16 us) at a 3.2 us GI, else 2x
/// (6.4 us + GI).
int _heLtfTenths(int giTenths) => giTenths == 32 ? 160 : 64 + giTenths;

int _ceilDiv(int a, int b) {
  assert(b > 0);
  return a >= 0 ? (a + b - 1) ~/ b : -((-a) ~/ b);
}
