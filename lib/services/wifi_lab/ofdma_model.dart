// OFDMA Resource Units (Wi-Fi Classroom, 2026-09-25): the pure-Dart model.
//
// Two parts:
//   1. The HE tone plan: which resource units (RUs) exist at each channel
//      width, how many, and where they sit, so a placement can be checked.
//   2. An airtime comparison for N clients that each have one frame of L
//      bytes: N single-user TXOPs, one DL OFDMA TXOP, and one UL OFDMA TXOP.
//
// Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/19-ofdma.md.
// Values: the wave-3 research brief, §6 (myPKA Deliverables/2026-09-25-wifi-
// lab-wave3-research/brief.md). HE SU timing is NOT recomputed here: it comes
// from computeAirtime() in airtime_anatomy.dart, so the two tools agree.
//
// THE RU TABLE is the brief's §6 table, verbatim ([OfdmaTonePlan.countTable]).
// THE POSITIONS are derived from that table plus the tone-plan nesting: a
// 20 MHz channel is nine 26-tone slots; 52-tone RUs pair slots 1-2, 3-4, 6-7,
// 8-9; 106-tone RUs cover 1-4 and 6-9; the center slot 5 is only ever a
// 26-tone RU; 40 MHz is two 20s; 80 MHz is two 40s with one more center
// 26-tone RU between them; 160 MHz is two 80s. Every count this produces
// matches the brief's table, which the tests assert. Positions are logical
// (in tone-plan order), not exact subcarrier indices: guard, DC and leftover
// tones are not modeled.
//
// ESTIMATES. The brief marks the worked example, the trigger frame size, the
// HE-SIG-B symbol count and the Multi-STA BlockAck size as INF (its own
// arithmetic or estimate). Every such value here carries `estimate: true` on
// its segment and is listed in [OfdmaAssumption], so the screen can label it.
//
// ARITHMETIC. Whole tenths of a microsecond throughout, as in
// airtime_anatomy.dart; every ceiling is taken on integers.

import 'dart:math' as math;

import 'airtime_anatomy.dart';

/// HE resource-unit sizes, with the brief's data + pilot split. [slots] is how
/// many 26-tone slots of the tone plan the RU covers.
enum RuSize {
  ru26('26', 26, 24, 2, 1),
  ru52('52', 52, 48, 4, 2),
  ru106('106', 106, 102, 4, 4),
  ru242('242', 242, 234, 8, 9),
  ru484('484', 484, 468, 16, 18),
  ru996('996', 996, 980, 16, 37),
  ru2x996('2x996', 1992, 1960, 32, 74);

  const RuSize(
    this.label,
    this.tones,
    this.dataTones,
    this.pilotTones,
    this.slots,
  );

  /// "26", "2x996".
  final String label;
  final int tones;
  final int dataTones;
  final int pilotTones;

  /// 26-tone slots covered in the logical tone plan.
  final int slots;

  /// "52-tone".
  String get toneLabel => '$label-tone';
}

/// A contiguous run of 26-tone slots: where one RU sits.
class RuSpan {
  const RuSpan(this.start, this.length);

  final int start;
  final int length;

  int get end => start + length;

  bool overlaps(RuSpan o) => start < o.end && o.start < end;

  bool contains(int slot) => slot >= start && slot < end;

  @override
  bool operator ==(Object other) =>
      other is RuSpan && other.start == start && other.length == length;

  @override
  int get hashCode => Object.hash(start, length);

  @override
  String toString() => 'RuSpan($start, $length)';
}

/// The HE tone plan at 20, 40, 80 and 160 MHz.
class OfdmaTonePlan {
  OfdmaTonePlan._();

  static const List<int> widthsMhz = <int>[20, 40, 80, 160];

  /// RUs per channel width, the brief's §6 table verbatim. A missing width is
  /// "n/a" (the RU is wider than the channel).
  static const Map<RuSize, Map<int, int>> countTable = <RuSize, Map<int, int>>{
    RuSize.ru26: <int, int>{20: 9, 40: 18, 80: 37, 160: 74},
    RuSize.ru52: <int, int>{20: 4, 40: 8, 80: 16, 160: 32},
    RuSize.ru106: <int, int>{20: 2, 40: 4, 80: 8, 160: 16},
    RuSize.ru242: <int, int>{20: 1, 40: 2, 80: 4, 160: 8},
    RuSize.ru484: <int, int>{40: 1, 80: 2, 160: 4},
    RuSize.ru996: <int, int>{80: 1, 160: 2},
    RuSize.ru2x996: <int, int>{160: 1},
  };

  /// RUs of [size] in a [widthMhz] channel, or null for n/a.
  static int? count(RuSize size, int widthMhz) => countTable[size]![widthMhz];

  /// 26-tone slots across the channel: 9, 18, 37 or 74.
  static int slots(int widthMhz) => count(RuSize.ru26, widthMhz)!;

  /// RU sizes that exist at [widthMhz], smallest first.
  static List<RuSize> sizesFor(int widthMhz) => <RuSize>[
    for (final RuSize s in RuSize.values)
      if (count(s, widthMhz) != null) s,
  ];

  /// The full-channel RU at [widthMhz].
  static RuSize fullChannel(int widthMhz) => sizesFor(widthMhz).last;

  /// Every position of [size] at [widthMhz], in tone-plan order.
  static List<RuSpan> positions(int widthMhz, RuSize size) {
    final List<RuSpan> out;
    switch (widthMhz) {
      case 20:
        out = _in20(0, size);
      case 40:
        out = _in40(0, size);
      case 80:
        out = _in80(0, size);
      case 160:
        out = size == RuSize.ru2x996
            ? <RuSpan>[const RuSpan(0, 74)]
            : <RuSpan>[..._in80(0, size), ..._in80(37, size)];
      default:
        throw ArgumentError.value(widthMhz, 'widthMhz', 'not 20/40/80/160');
    }
    return List<RuSpan>.unmodifiable(out);
  }

  static List<RuSpan> _in20(int o, RuSize s) {
    switch (s) {
      case RuSize.ru26:
        return <RuSpan>[for (int i = 0; i < 9; i++) RuSpan(o + i, 1)];
      case RuSize.ru52:
        return <RuSpan>[
          RuSpan(o, 2),
          RuSpan(o + 2, 2),
          RuSpan(o + 5, 2),
          RuSpan(o + 7, 2),
        ];
      case RuSize.ru106:
        return <RuSpan>[RuSpan(o, 4), RuSpan(o + 5, 4)];
      case RuSize.ru242:
        return <RuSpan>[RuSpan(o, 9)];
      case RuSize.ru484:
      case RuSize.ru996:
      case RuSize.ru2x996:
        return const <RuSpan>[];
    }
  }

  static List<RuSpan> _in40(int o, RuSize s) => s == RuSize.ru484
      ? <RuSpan>[RuSpan(o, 18)]
      : <RuSpan>[..._in20(o, s), ..._in20(o + 9, s)];

  static List<RuSpan> _in80(int o, RuSize s) {
    if (s == RuSize.ru996) return <RuSpan>[RuSpan(o, 37)];
    if (s == RuSize.ru2x996) return const <RuSpan>[];
    return <RuSpan>[
      ..._in40(o, s),
      // The center 26-tone RU between the two 40 MHz halves.
      if (s == RuSize.ru26) RuSpan(o + 18, 1),
      ..._in40(o + 19, s),
    ];
  }

  /// The position of [size] that covers [slot], or null if none does (the
  /// center 26-tone slot is only ever a 26-tone RU).
  static RuSpan? positionAt(int widthMhz, RuSize size, int slot) {
    for (final RuSpan p in positions(widthMhz, size)) {
      if (p.contains(slot)) return p;
    }
    return null;
  }

  /// Places every client, largest RU first, each in the first free position.
  /// Returns one span per client, null where it did not fit. Because the tone
  /// plan nests like a buddy allocator, largest-first first-fit places a set
  /// whenever any placement of that set exists.
  static List<RuSpan?> autoPlace(int widthMhz, List<RuSize> sizes) {
    final List<RuSpan?> out = List<RuSpan?>.filled(sizes.length, null);
    final List<int> order = List<int>.generate(sizes.length, (int i) => i)
      ..sort((int a, int b) {
        final int c = sizes[b].slots.compareTo(sizes[a].slots);
        return c != 0 ? c : a.compareTo(b);
      });
    for (final int i in order) {
      out[i] = firstFree(widthMhz, sizes[i], <RuSpan>[
        for (final RuSpan? s in out) ?s,
      ]);
    }
    return out;
  }

  /// The first position of [size] that overlaps none of [taken].
  static RuSpan? firstFree(int widthMhz, RuSize size, List<RuSpan> taken) {
    for (final RuSpan p in positions(widthMhz, size)) {
      if (!taken.any((RuSpan t) => t.overlaps(p))) return p;
    }
    return null;
  }

  /// True when the clients' RUs can all be placed at once.
  static bool fits(int widthMhz, List<RuSize> sizes) =>
      sizes.every((RuSize s) => count(s, widthMhz) != null) &&
      !autoPlace(widthMhz, sizes).contains(null);

  /// The largest RU size of which [clients] equal RUs fit at [widthMhz].
  static RuSize largestEqualFit(int widthMhz, int clients) {
    RuSize best = RuSize.ru26;
    for (final RuSize s in sizesFor(widthMhz)) {
      if (count(s, widthMhz)! >= clients) best = s;
    }
    return best;
  }
}

/// The labeled assumptions and estimates. Each one is shown on screen.
enum OfdmaAssumption {
  example(
    'Teaching estimate',
    'One frame per client, no collisions or retries, the average backoff, '
        'best-effort access, one spatial stream, control frames at 24 Mbps. '
        'The research brief built its worked example on these same '
        'assumptions; it is not a figure from the standard.',
  ),
  suBlockAck(
    'Block Ack after each SU frame',
    'Each single-user frame is answered with a 32-byte Block Ack (a Block '
        'Ack agreement is assumed), as in the research example. Airtime '
        'Anatomy answers a lone frame with a 14-byte ACK, 4 µs shorter.',
  ),
  sigB(
    'HE-SIG-B length',
    'Computed from assumed field sizes: per content channel an 8-bit RU '
        'allocation per 20 MHz (plus 1 center-RU bit at 80 and 160 MHz), '
        '4 CRC and 6 tail bits; 21 bits per user, users paired with 10 bits '
        'of CRC and tail per pair; sent at MCS 0, 26 bits per 4 µs symbol. '
        'Users are split evenly across the two content channels above '
        '20 MHz.',
  ),
  dlAck(
    'Downlink block acks',
    'After DL OFDMA each client answers at once in its own RU, inside one '
        'HE TB PPDU, with a 32-byte Block Ack. The rate is assumed: MCS 4, '
        'or the data MCS if lower. The brief estimated about 91 µs for this '
        'response and did not show its working.',
  ),
  trigger(
    'Trigger frame size',
    '16 bytes of header, 8 of Common Info, 6 per user (5 of User Info plus '
        '1 for a Basic trigger) and a 4-byte FCS, no padding. Inferred in '
        'the brief and checked against one published example.',
  ),
  multiStaBa(
    'Multi-STA BlockAck size',
    '16 bytes of header, 2 of BA control, 12 per client (AID/TID, sequence '
        'and a 64-bit bitmap) and a 4-byte FCS, sent at 24 Mbps. An '
        'estimate: no primary source was found for its size.',
  ),
  tbFormat(
    'HE TB PPDU format',
    'Uplink HE TB PPDUs use an 8 µs HE-STF, a 2x HE-LTF and a 1.6 µs guard '
        'interval (one of the three allowed pairings). Downlink uses a '
        '0.8 µs guard interval, like the single-user frames.',
  );

  const OfdmaAssumption(this.title, this.detail);

  final String title;
  final String detail;
}

/// The three ways to deliver the frames.
enum OfdmaMode {
  su('SU', 'Single user, one TXOP per client'),
  dl('DL OFDMA', 'Downlink OFDMA, one TXOP'),
  ul('UL OFDMA', 'Uplink OFDMA, one TXOP');

  const OfdmaMode(this.shortLabel, this.label);

  final String shortLabel;
  final String label;
}

/// What a segment of airtime is.
enum OfdmaSegmentKind {
  aifs,
  backoff,
  preamble,
  data,
  sifs,
  trigger,
  ack;

  /// The savings category the segment counts toward.
  OfdmaPart get part {
    switch (this) {
      case OfdmaSegmentKind.aifs:
      case OfdmaSegmentKind.backoff:
        return OfdmaPart.contention;
      case OfdmaSegmentKind.preamble:
        return OfdmaPart.preamble;
      case OfdmaSegmentKind.data:
        return OfdmaPart.data;
      case OfdmaSegmentKind.sifs:
      case OfdmaSegmentKind.trigger:
      case OfdmaSegmentKind.ack:
        return OfdmaPart.acks;
    }
  }
}

/// The categories the savings line names.
enum OfdmaPart {
  contention('contention'),
  preamble('preambles'),
  data('data'),
  acks('triggers, acks and SIFS');

  const OfdmaPart(this.label);

  final String label;
}

/// One segment of a timeline.
class OfdmaSegment {
  const OfdmaSegment({
    required this.kind,
    required this.label,
    required this.shortLabel,
    required this.tenths,
    required this.startTenths,
    required this.formula,
    this.estimate,
    this.client,
    this.lanes,
  });

  final OfdmaSegmentKind kind;

  /// "Block Ack (A)", "HE MU preamble".
  final String label;

  /// Fits inside a block: "BA", "Data".
  final String shortLabel;

  final int tenths;
  final int startTenths;

  /// The working, with this scenario's numbers.
  final String formula;

  /// The assumption this value rests on, when it is an estimate.
  final OfdmaAssumption? estimate;

  /// The client this segment belongs to (single-user timeline only).
  final int? client;

  /// OFDMA data only: each client's own data time, tenths. The segment's
  /// length is the longest; shorter RUs are padded to it.
  final List<int>? lanes;

  int get endTenths => startTenths + tenths;
  double get us => tenths / 10;
  double get startUs => startTenths / 10;
  double get endUs => endTenths / 10;
  String get durationLabel => '${formatTenthsUs(tenths)} µs';
}

/// One mode's timeline.
class OfdmaTimeline {
  OfdmaTimeline({required this.mode, required List<OfdmaSegment> segments})
    : segments = List<OfdmaSegment>.unmodifiable(segments);

  final OfdmaMode mode;
  final List<OfdmaSegment> segments;

  int get totalTenths =>
      segments.fold<int>(0, (int a, OfdmaSegment s) => a + s.tenths);
  double get totalUs => totalTenths / 10;

  /// Tenths spent on [part].
  int partTenths(OfdmaPart part) => segments
      .where((OfdmaSegment s) => s.kind.part == part)
      .fold<int>(0, (int a, OfdmaSegment s) => a + s.tenths);

  /// The longest single PPDU (preamble plus data), tenths.
  int get longestPpduTenths {
    int best = 0;
    for (int i = 0; i < segments.length; i++) {
      if (segments[i].kind != OfdmaSegmentKind.data) continue;
      final int pre = i > 0 && segments[i - 1].kind == OfdmaSegmentKind.preamble
          ? segments[i - 1].tenths
          : 0;
      best = math.max(best, pre + segments[i].tenths);
    }
    return best;
  }

  bool get ppduTooLong => longestPpduTenths > AirtimeConstants.maxPpduUs * 10;
}

/// Why OFDMA timelines cannot be computed.
enum OfdmaCheck {
  ok('OK'),
  ruTooWide('An RU is wider than the channel'),
  doesNotFit('These RUs do not fit in the channel'),
  mcsNeedsFullRu(
    'MCS 10 and 11 (1024-QAM) need a 242-tone RU or larger; smaller RUs stop '
    'at MCS 9',
  );

  const OfdmaCheck(this.message);

  final String message;

  bool get isOk => this == OfdmaCheck.ok;
}

/// The inputs.
class OfdmaScenario {
  OfdmaScenario({
    required this.widthMhz,
    required List<RuSize> ruSizes,
    this.payloadBytes = 200,
    this.mcs = 7,
  }) : ruSizes = List<RuSize>.unmodifiable(ruSizes),
       assert(ruSizes.isNotEmpty),
       assert(mcs >= 0 && mcs <= 11),
       assert(payloadBytes > 0);

  final int widthMhz;

  /// One RU size per client; the client count is its length.
  final List<RuSize> ruSizes;

  /// The MSDU each client's frame carries.
  final int payloadBytes;

  /// HE MCS for every client's data, 0-11.
  final int mcs;

  int get clients => ruSizes.length;
}

/// HE-SIG-B size, per [OfdmaAssumption.sigB].
class SigBLength {
  const SigBLength({
    required this.contentChannels,
    required this.commonBits,
    required this.userBits,
    required this.symbols,
  });

  final int contentChannels;

  /// Common field bits per content channel.
  final int commonBits;

  /// User-specific bits on the busier content channel.
  final int userBits;

  final int symbols;

  int get bitsPerChannel => commonBits + userBits;
  int get tenths => symbols * 40;
}

/// Constants the OFDMA timelines use (all assumptions are in
/// [OfdmaAssumption]).
class OfdmaConstants {
  OfdmaConstants._();

  static const int controlRateMbps = 24;
  static const int encryptionBytes = 16;
  static const AirtimeAccessCategory accessCategory = AirtimeAccessCategory.be;

  /// L-STF 8 + L-LTF 8 + L-SIG 4 + RL-SIG 4 + HE-SIG-A 8, µs.
  static const int legacyAndSigAUs = 32;

  /// HE-STF in an HE MU PPDU, µs; an HE TB PPDU uses 8.
  static const int heStfMuUs = 4;
  static const int heStfTbUs = 8;

  /// One 2x HE-LTF at 0.8 µs GI (DL) and 1.6 µs GI (UL TB), tenths.
  static const int heLtfDlTenths = 72;
  static const int heLtfTbTenths = 80;

  /// Data symbol, 12.8 µs + GI, tenths.
  static const int symbolDlTenths = 136;
  static const int symbolTbTenths = 144;

  // HE-SIG-B field sizes (assumed).
  static const int sigBAllocationBits = 8;
  static const int sigBCenterRuBits = 1;
  static const int sigBCrcTailBits = 10;
  static const int sigBUserBits = 21;
  static const int sigBBitsPerSymbol = 26;

  /// The DL block-ack response is sent at MCS min(data MCS, this).
  static const int dlAckMcsCap = 4;

  // Trigger frame (Basic), bytes.
  static const int triggerFixedBytes = 16 + 8 + 4;
  static const int triggerPerUserBytes = 6;

  // Multi-STA BlockAck, bytes.
  static const int multiStaBaFixedBytes = 16 + 2 + 4;
  static const int multiStaBaPerUserBytes = 12;
}

/// Everything the screen shows for one scenario.
class OfdmaResult {
  const OfdmaResult._({
    required this.scenario,
    required this.su,
    required this.dl,
    required this.ul,
    required this.check,
    required this.suTxopTenths,
    required this.sigB,
    required this.dataSymbolsDl,
    required this.dataSymbolsUl,
  });

  final OfdmaScenario scenario;
  final OfdmaTimeline su;

  /// Null unless [check] is OK.
  final OfdmaTimeline? dl;
  final OfdmaTimeline? ul;

  final OfdmaCheck check;

  /// One single-user TXOP, tenths.
  final int suTxopTenths;

  final SigBLength sigB;

  /// Per client, data symbols in the DL MU PPDU and UL TB PPDU.
  final List<int> dataSymbolsDl;
  final List<int> dataSymbolsUl;

  OfdmaTimeline? timeline(OfdmaMode m) => switch (m) {
    OfdmaMode.su => su,
    OfdmaMode.dl => dl,
    OfdmaMode.ul => ul,
  };

  /// SU airtime over [mode]'s airtime; null when [mode] is not drawable.
  double? ratio(OfdmaMode mode) {
    final OfdmaTimeline? t = timeline(mode);
    if (t == null || t.ppduTooLong || t.totalTenths == 0) return null;
    return su.totalTenths / t.totalTenths;
  }

  /// SU minus [mode], per category, tenths (negative = OFDMA spends more).
  Map<OfdmaPart, int>? savings(OfdmaMode mode) {
    final OfdmaTimeline? t = timeline(mode);
    if (t == null) return null;
    return <OfdmaPart, int>{
      for (final OfdmaPart p in OfdmaPart.values)
        p: su.partTenths(p) - t.partTenths(p),
    };
  }
}

/// Data bits per symbol for one RU at one stream, rounded down as the HE MCS
/// tables do.
int ruBitsPerSymbol(RuSize ru, int mcs) {
  final McsRow row = AirtimeConstants.mcsRow(mcs);
  return ru.dataTones * row.bitsPerSubcarrier * row.rateNum ~/ row.rateDen;
}

/// HE-SIG-B length for [users] users at [widthMhz], per the assumption.
SigBLength sigBLength(int widthMhz, int users) {
  final int ccs = widthMhz == 20 ? 1 : 2;
  final int allocPerCc = switch (widthMhz) {
    20 => 1,
    40 => 1,
    80 => 2,
    _ => 4,
  };
  final int common =
      allocPerCc * OfdmaConstants.sigBAllocationBits +
      (widthMhz >= 80 ? OfdmaConstants.sigBCenterRuBits : 0) +
      OfdmaConstants.sigBCrcTailBits;
  final int perCc = (users + ccs - 1) ~/ ccs;
  final int pairs = perCc ~/ 2;
  final int single = perCc % 2;
  final int userBits =
      pairs *
          (2 * OfdmaConstants.sigBUserBits + OfdmaConstants.sigBCrcTailBits) +
      single * (OfdmaConstants.sigBUserBits + OfdmaConstants.sigBCrcTailBits);
  final int symbols = _ceilDiv(
    common + userBits,
    OfdmaConstants.sigBBitsPerSymbol,
  );
  return SigBLength(
    contentChannels: ccs,
    commonBits: common,
    userBits: userBits,
    symbols: symbols,
  );
}

/// Runs all three timelines.
OfdmaResult computeOfdma(OfdmaScenario s) {
  final int n = s.clients;
  final String Function(int) t = formatTenthsUs;

  // ── Single user, from the Airtime Anatomy service ─────────────────────────
  final AirtimeResult one = computeAirtime(
    AirtimeScenario(
      band: AirtimeBand.ghz5,
      phy: AirtimePhy.he,
      widthMhz: s.widthMhz,
      mcs: s.mcs,
      streams: 1,
      guardInterval: GuardInterval.gi08,
      payloadBytes: s.payloadBytes,
      framesAggregated: 1,
      encryptionBytes: OfdmaConstants.encryptionBytes,
      accessCategory: OfdmaConstants.accessCategory,
      controlRateMbps: OfdmaConstants.controlRateMbps,
    ),
  );
  final int sifs = one.sifsUs * 10;
  final int aifs = one.segment(TxopSegmentKind.aifs).tenths;
  final int backoff = one.segment(TxopSegmentKind.backoff).tenths;
  final int suPre = one.preambleTenths;
  final int suData = one.dataTenths;
  final int ba = one.blockAckTenths;
  final int sub = one.subframeBytes;
  final int suTxop = aifs + backoff + suPre + suData + sifs + ba;

  final _Builder suB = _Builder();
  for (int c = 0; c < n; c++) {
    final String who = clientLetter(c);
    suB
      ..add(
        OfdmaSegmentKind.aifs,
        'AIFS ($who)',
        'AIFS',
        aifs,
        one.segment(TxopSegmentKind.aifs).formula,
        client: c,
      )
      ..add(
        OfdmaSegmentKind.backoff,
        'Backoff ($who)',
        'Backoff',
        backoff,
        one.segment(TxopSegmentKind.backoff).formula,
        client: c,
      )
      ..add(
        OfdmaSegmentKind.preamble,
        'HE SU preamble ($who)',
        'Pre',
        suPre,
        one.segment(TxopSegmentKind.preamble).formula,
        client: c,
      )
      ..add(
        OfdmaSegmentKind.data,
        'Data ($who)',
        'Data',
        suData,
        '${one.segment(TxopSegmentKind.data).formula} The whole '
            '${s.widthMhz} MHz channel (${one.dataSubcarriers} data '
            'subcarriers) carries this one client.',
        client: c,
      )
      ..add(
        OfdmaSegmentKind.sifs,
        'SIFS ($who)',
        'SIFS',
        sifs,
        'SIFS = '
            '${one.sifsUs} µs.',
        client: c,
      )
      ..add(
        OfdmaSegmentKind.ack,
        'Block Ack ($who)',
        'BA',
        ba,
        '20 + 4 x ceil((16 + 8 x ${AirtimeConstants.blockAckBytes} bytes + 6) '
            '/ ${OfdmaConstants.controlRateMbps * 4}) = ${t(ba)} µs at '
            '${OfdmaConstants.controlRateMbps} Mbps.',
        client: c,
        estimate: OfdmaAssumption.suBlockAck,
      );
  }
  final OfdmaTimeline su = OfdmaTimeline(
    mode: OfdmaMode.su,
    segments: suB.segments,
  );

  final SigBLength sigB = sigBLength(s.widthMhz, n);

  // ── Checks ────────────────────────────────────────────────────────────────
  final OfdmaCheck check;
  if (s.ruSizes.any((RuSize r) => OfdmaTonePlan.count(r, s.widthMhz) == null)) {
    check = OfdmaCheck.ruTooWide;
  } else if (!OfdmaTonePlan.fits(s.widthMhz, s.ruSizes)) {
    check = OfdmaCheck.doesNotFit;
  } else if (s.mcs >= 10 &&
      s.ruSizes.any((RuSize r) => r.tones < RuSize.ru242.tones)) {
    check = OfdmaCheck.mcsNeedsFullRu;
  } else {
    check = OfdmaCheck.ok;
  }
  if (!check.isOk) {
    return OfdmaResult._(
      scenario: s,
      su: su,
      dl: null,
      ul: null,
      check: check,
      suTxopTenths: suTxop,
      sigB: sigB,
      dataSymbolsDl: const <int>[],
      dataSymbolsUl: const <int>[],
    );
  }

  final int dataBits = 16 + 8 * sub;
  final List<int> symbols = <int>[
    for (final RuSize r in s.ruSizes)
      _ceilDiv(dataBits, ruBitsPerSymbol(r, s.mcs)),
  ];
  final int maxSym = symbols.reduce(math.max);
  final int slowest = symbols.indexOf(maxSym);
  final RuSize slowRu = s.ruSizes[slowest];
  final String slowWhy =
      'ceil((16 + 8 x $sub bytes) / ${ruBitsPerSymbol(slowRu, s.mcs)} bits '
      'per symbol on ${clientLetter(slowest)}\'s ${slowRu.toneLabel} RU) '
      '= $maxSym symbols';
  final String waitF =
      'One contention for everyone: AIFS ${t(aifs)} + average backoff '
      '${t(backoff)} µs.';

  // ── DL OFDMA ──────────────────────────────────────────────────────────────
  final int muPre =
      (OfdmaConstants.legacyAndSigAUs + OfdmaConstants.heStfMuUs) * 10 +
      sigB.tenths +
      OfdmaConstants.heLtfDlTenths;
  final int tbPre =
      (OfdmaConstants.legacyAndSigAUs + OfdmaConstants.heStfTbUs) * 10 +
      OfdmaConstants.heLtfTbTenths;
  final int ackMcs = math.min(s.mcs, OfdmaConstants.dlAckMcsCap);
  const int baBits =
      16 +
      8 *
          (AirtimeConstants.blockAckBytes +
              AirtimeConstants.ampduDelimiterBytes);
  final List<int> ackSyms = <int>[
    for (final RuSize r in s.ruSizes)
      _ceilDiv(baBits, ruBitsPerSymbol(r, ackMcs)),
  ];
  final int ackSym = ackSyms.reduce(math.max);
  final int dlAck = tbPre + ackSym * OfdmaConstants.symbolTbTenths;

  final _Builder dlB = _Builder()
    ..add(OfdmaSegmentKind.aifs, 'AIFS', 'AIFS', aifs, waitF)
    ..add(OfdmaSegmentKind.backoff, 'Backoff', 'Backoff', backoff, waitF)
    ..add(
      OfdmaSegmentKind.preamble,
      'HE MU preamble',
      'Preamble',
      muPre,
      'L-STF 8 + L-LTF 8 + L-SIG 4 + RL-SIG 4 + HE-SIG-A 8 + HE-SIG-B '
          '${sigB.symbols} x 4 + HE-STF 4 + 1 HE-LTF 7.2 = ${t(muPre)} µs. '
          'HE-SIG-B: ${sigB.commonBits} common + ${sigB.userBits} user bits = '
          '${sigB.bitsPerChannel} bits per content channel / '
          '${OfdmaConstants.sigBBitsPerSymbol} = ${sigB.symbols} symbols.',
      estimate: OfdmaAssumption.sigB,
    )
    ..add(
      OfdmaSegmentKind.data,
      'Data, all RUs at once',
      'Data',
      maxSym * OfdmaConstants.symbolDlTenths,
      'Set by the slowest RU: $slowWhy x 13.6 µs = '
          '${t(maxSym * OfdmaConstants.symbolDlTenths)} µs. Faster RUs pad '
          'to the same end.',
      lanes: <int>[
        for (final int k in symbols) k * OfdmaConstants.symbolDlTenths,
      ],
    )
    ..add(
      OfdmaSegmentKind.sifs,
      'SIFS',
      'SIFS',
      sifs,
      'SIFS = ${one.sifsUs} '
          'µs.',
    )
    ..add(
      OfdmaSegmentKind.ack,
      'Block acks (HE TB PPDU)',
      'BAs',
      dlAck,
      'All clients answer together in their own RUs: HE TB preamble '
          '${t(tbPre)} (legacy 20 + RL-SIG 4 + HE-SIG-A 8 + HE-STF 8 + HE-LTF '
          '8) + $ackSym symbols x 14.4 = ${t(dlAck)} µs. Each 36-byte Block '
          'Ack (32 + 4 delimiter) at MCS $ackMcs.',
      estimate: OfdmaAssumption.dlAck,
    );
  final OfdmaTimeline dl = OfdmaTimeline(
    mode: OfdmaMode.dl,
    segments: dlB.segments,
  );

  // ── UL OFDMA ──────────────────────────────────────────────────────────────
  final int trigBytes =
      OfdmaConstants.triggerFixedBytes + OfdmaConstants.triggerPerUserBytes * n;
  final int trig = controlFrameTenths(
    trigBytes,
    OfdmaConstants.controlRateMbps,
    0,
  );
  final int msbaBytes =
      OfdmaConstants.multiStaBaFixedBytes +
      OfdmaConstants.multiStaBaPerUserBytes * n;
  final int msba = controlFrameTenths(
    msbaBytes,
    OfdmaConstants.controlRateMbps,
    0,
  );
  final _Builder ulB = _Builder()
    ..add(OfdmaSegmentKind.aifs, 'AIFS', 'AIFS', aifs, waitF)
    ..add(OfdmaSegmentKind.backoff, 'Backoff', 'Backoff', backoff, waitF)
    ..add(
      OfdmaSegmentKind.trigger,
      'Trigger frame',
      'Trigger',
      trig,
      'Basic trigger 16 + 8 + 6 x $n users + 4 = $trigBytes bytes at '
          '${OfdmaConstants.controlRateMbps} Mbps: 20 + 4 x ceil((16 + 8 x '
          '$trigBytes + 6) / ${OfdmaConstants.controlRateMbps * 4}) = '
          '${t(trig)} µs.',
      estimate: OfdmaAssumption.trigger,
    )
    ..add(
      OfdmaSegmentKind.sifs,
      'SIFS',
      'SIFS',
      sifs,
      'SIFS = ${one.sifsUs} '
          'µs.',
    )
    ..add(
      OfdmaSegmentKind.preamble,
      'HE TB preamble',
      'Preamble',
      tbPre,
      'Legacy 20 + RL-SIG 4 + HE-SIG-A 8 + HE-STF 8 + 1 HE-LTF 8 (2x at '
          '1.6 µs GI) = ${t(tbPre)} µs. No HE-SIG-B: the trigger already told '
          'each client its RU.',
      estimate: OfdmaAssumption.tbFormat,
    )
    ..add(
      OfdmaSegmentKind.data,
      'Data, all clients at once',
      'Data',
      maxSym * OfdmaConstants.symbolTbTenths,
      'Set by the slowest RU: $slowWhy x 14.4 µs = '
          '${t(maxSym * OfdmaConstants.symbolTbTenths)} µs.',
      lanes: <int>[
        for (final int k in symbols) k * OfdmaConstants.symbolTbTenths,
      ],
    )
    ..add(
      OfdmaSegmentKind.sifs,
      'SIFS',
      'SIFS',
      sifs,
      'SIFS = ${one.sifsUs} '
          'µs.',
    )
    ..add(
      OfdmaSegmentKind.ack,
      'Multi-STA BlockAck',
      'M-BA',
      msba,
      'One frame acknowledges everyone: 16 + 2 + 12 x $n + 4 = $msbaBytes '
          'bytes at ${OfdmaConstants.controlRateMbps} Mbps = ${t(msba)} µs.',
      estimate: OfdmaAssumption.multiStaBa,
    );
  final OfdmaTimeline ul = OfdmaTimeline(
    mode: OfdmaMode.ul,
    segments: ulB.segments,
  );

  return OfdmaResult._(
    scenario: s,
    su: su,
    dl: dl,
    ul: ul,
    check: check,
    suTxopTenths: suTxop,
    sigB: sigB,
    dataSymbolsDl: List<int>.unmodifiable(symbols),
    dataSymbolsUl: List<int>.unmodifiable(symbols),
  );
}

/// "A" for client 0.
String clientLetter(int i) => String.fromCharCode(0x41 + i);

class _Builder {
  final List<OfdmaSegment> segments = <OfdmaSegment>[];
  int _at = 0;

  void add(
    OfdmaSegmentKind kind,
    String label,
    String shortLabel,
    int tenths,
    String formula, {
    OfdmaAssumption? estimate,
    int? client,
    List<int>? lanes,
  }) {
    segments.add(
      OfdmaSegment(
        kind: kind,
        label: label,
        shortLabel: shortLabel,
        tenths: tenths,
        startTenths: _at,
        formula: formula,
        estimate: estimate,
        client: client,
        lanes: lanes == null ? null : List<int>.unmodifiable(lanes),
      ),
    );
    _at += tenths;
  }
}

int _ceilDiv(int a, int b) {
  assert(b > 0 && a >= 0);
  return (a + b - 1) ~/ b;
}
