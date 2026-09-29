// Rate set builder: the pure model behind the Rate set card in the Wi-Fi
// Classroom's Rate vs Range tool (rate-vs-range).
//
// CLEAN-ROOM BUILD (2026-09-29) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/44-rate-set.md, with facts from Deliverables/2026-09-25-
// wifi-lab-cleanroom/evidence/2026-09-29-facts-security-compat-and-rate-set.md
// section C (IEEE Std 802.11-2024, read by Pax), plus Table 10-9 and 10.6.11
// read directly by Felix the same day. No other teaching simulator was
// studied.
//
// WHAT IT COMPUTES
//   - A rate set: each of the 12 legacy rates off, supported or basic, for one
//     PHY (ERP at 2.4 GHz, OFDM at 5 and 6 GHz). The lowest basic rate is the
//     derived minimum basic rate. The Supported Rates element octets: a basic
//     rate has bit 7 set, the rate in units of 500 kb/s in bits 6 to 0
//     (9.4.2.3, p.935); up to eight octets, the rest in Extended Supported
//     Rates (9.4.2.11).
//   - canJoin: whether a client can associate. A client that lacks any basic
//     rate is refused with status 18, REFUSED_BASIC_RATES_MISMATCH (Table
//     9-80). The code name keeps "join"; the UI says associate (Keith,
//     2026-09-29).
//   - beaconRate: one of the basic rates (10.6.5.1, p.1938). The standard
//     does not say which; the LOWEST is vendor behavior, not pinned, and the
//     UI labels it so. An empty basic set falls back to a mandatory rate.
//   - controlResponseRate: the ACK or CTS rate (10.6.6.5.2, p.1944): the
//     highest basic rate not faster than the frame being answered, else the
//     highest mandatory rate of the PHY not faster than it, in the same
//     modulation class (p.1945). HT, VHT and HE frames convert to a non-HT
//     reference rate first (10.6.11, Table 10-10, pp.1961-1962).
//
// MODULATION CLASSES (Table 10-9, p.1959). "DSSS and HR/DSSS" is one class,
// so 1, 2, 5.5 and 11 share it. ERP-OFDM (2.4 GHz) and OFDM (5 and 6 GHz) are
// separate classes, but only one of them exists in a band, so the model has
// two families: dsss and ofdm.
//
// THE MODEL'S READINGS (the standard is silent; every one is labelled):
//   1. When the rate rule picks a basic rate of the other class, the class
//      filter is applied first (RsControlResponse.classFilterDecided).
//   2. HE frames are answered in a non-HT OFDM PPDU: 10.6.10's class rule
//      names HT and VHT; 10.6.11 converts HE-MCS for this purpose.
//   3. A Clause 15 or 16 device has no OFDM receiver, so it cannot decode a
//      beacon sent at an OFDM rate (an inference).
//   4. Mandatory rates are marked, not locked: the facts pin what a DEVICE
//      must support, not what an AP must keep in its rate set.
//   5. A client without a required PHY (membership selector 127 HT or 122 HE,
//      Table 9-131) cannot associate; no status code is pinned for it.
//
// ASCII only, no em dashes (GL-004). No Flutter imports.

/// The two modulation families of Table 10-9 that legacy rates fall in.
enum RsModClass {
  /// "DSSS and HR/DSSS": 1, 2, 5.5 and 11 Mb/s.
  dsss('DSSS/CCK'),

  /// ERP-OFDM at 2.4 GHz, OFDM at 5 and 6 GHz: 6 to 54 Mb/s.
  ofdm('OFDM');

  const RsModClass(this.label);
  final String label;
}

/// The 12 legacy rates, in units of 500 kb/s as the element carries them.
enum RsRate {
  r1(2, RsModClass.dsss),
  r2(4, RsModClass.dsss),
  r5_5(11, RsModClass.dsss),
  r11(22, RsModClass.dsss),
  r6(12, RsModClass.ofdm),
  r9(18, RsModClass.ofdm),
  r12(24, RsModClass.ofdm),
  r18(36, RsModClass.ofdm),
  r24(48, RsModClass.ofdm),
  r36(72, RsModClass.ofdm),
  r48(96, RsModClass.ofdm),
  r54(108, RsModClass.ofdm);

  const RsRate(this.halfMbps, this.modClass);

  /// The rate in units of 500 kb/s (bits 6 to 0 of its octet).
  final int halfMbps;
  final RsModClass modClass;

  double get mbps => halfMbps / 2;

  /// "5.5" or "24".
  String get label =>
      halfMbps.isEven ? '${halfMbps ~/ 2}' : (halfMbps / 2).toStringAsFixed(1);

  /// "24 Mbps" (the Rate vs Range tool's unit style).
  String get mbpsLabel => '$label Mbps';

  /// The octet in a Beacon's Supported Rates field: bit 7 set when basic.
  int octet({required bool basic}) => basic ? 0x80 | halfMbps : halfMbps;

  /// The rate for [mbps], or null when it is not one of the 12.
  static RsRate? ofMbps(double mbps) {
    for (final RsRate r in RsRate.values) {
      if (r.mbps == mbps) return r;
    }
    return null;
  }

  /// The rates of [cls], slowest first.
  static List<RsRate> ofClass(RsModClass cls) => <RsRate>[
    for (final RsRate r in byRate)
      if (r.modClass == cls) r,
  ];

  /// All 12, slowest first (5.5 before 6, 9 before 11).
  static final List<RsRate> byRate = List<RsRate>.of(RsRate.values)
    ..sort((RsRate a, RsRate b) => a.halfMbps.compareTo(b.halfMbps));
}

/// The PHY the access point runs.
enum RsPhy {
  /// 2.4 GHz ERP (Clause 18): DSSS/CCK and ERP-OFDM, all 12 rates.
  erp('2.4 GHz ERP'),

  /// 5 and 6 GHz OFDM (Clause 17): the eight OFDM rates.
  ofdm('OFDM (5 and 6 GHz)');

  const RsPhy(this.label);
  final String label;

  /// The rates this PHY has, slowest first.
  List<RsRate> get rates =>
      this == RsPhy.erp ? RsRate.byRate : RsRate.ofClass(RsModClass.ofdm);

  /// The rates every device of this PHY must support. OFDM: 6, 12, 24
  /// (17.1.1, p.3338). ERP: 1, 2, 5.5, 6, 11, 12, 24 (18.1.2, p.3387).
  List<RsRate> get mandatory => this == RsPhy.erp
      ? const <RsRate>[
          RsRate.r1,
          RsRate.r2,
          RsRate.r5_5,
          RsRate.r6,
          RsRate.r11,
          RsRate.r12,
          RsRate.r24,
        ]
      : const <RsRate>[RsRate.r6, RsRate.r12, RsRate.r24];

  bool isMandatory(RsRate r) => mandatory.contains(r);

  bool has(RsRate r) => rates.contains(r);
}

/// One rate's state in the AP's rate set.
enum RsState {
  off('off'),
  supported('supported'),
  basic('basic');

  const RsState(this.label);
  final String label;

  /// Tap order: off, supported, basic, off.
  RsState get next => RsState.values[(index + 1) % RsState.values.length];
}

/// A PHY a network can require through a BSS membership selector (Table
/// 9-131, p.936).
enum RsRequiredPhy {
  none('Nothing more', null),
  ht('HT (Wi-Fi 4)', 127),
  he('HE (Wi-Fi 6)', 122);

  const RsRequiredPhy(this.label, this.selector);
  final String label;

  /// The selector value, or null for none.
  final int? selector;
}

/// The client types the picker offers.
enum RsClient {
  dot11b('802.11b only'),
  erpClass2('802.11g, least it must support'),
  dot11g('802.11g'),
  wifi6('Wi-Fi 6');

  const RsClient(this.label);
  final String label;

  /// 802.11b, 802.11g and a Class 2 ERP device are 2.4 GHz only.
  bool on(RsPhy phy) => this == RsClient.wifi6 || phy == RsPhy.erp;

  /// The legacy rates it supports on [phy]. A Class 2 ERP device must
  /// support only 1, 2 and 6 (18.1.2); this one does no more.
  List<RsRate> rates(RsPhy phy) {
    if (!on(phy)) return const <RsRate>[];
    switch (this) {
      case RsClient.dot11b:
        return RsRate.ofClass(RsModClass.dsss);
      case RsClient.erpClass2:
        return const <RsRate>[RsRate.r1, RsRate.r2, RsRate.r6];
      case RsClient.dot11g:
      case RsClient.wifi6:
        return phy.rates;
    }
  }

  bool supports(RsRate r, RsPhy phy) => rates(phy).contains(r);

  /// Whether it has the PHY a membership selector requires.
  bool hasPhy(RsRequiredPhy p) => p == RsRequiredPhy.none || this == wifi6;
}

/// The outcome of [canJoin].
enum RsVerdict {
  /// It can associate.
  associates,

  /// It lacks a basic rate: the AP refuses it with status 18.
  refusedBasicRates,

  /// The network requires a PHY it lacks (membership selector). No status
  /// code is pinned for this case.
  lacksRequiredPhy,

  /// It has no radio for this band, so it never hears the network.
  otherBand,

  /// Every rate is off: the AP has nothing to send with.
  noRates,
}

/// Status 18 in Table 9-80.
const int kStatusRefusedBasicRates = 18;
const String kStatusRefusedBasicRatesName = 'REFUSED_BASIC_RATES_MISMATCH';

/// Whether one client can associate, and why.
class RsAssociation {
  const RsAssociation({
    required this.client,
    required this.verdict,
    this.missingBasic = const <RsRate>[],
    this.decodesBeacons = true,
    this.requiredPhy = RsRequiredPhy.none,
  });

  final RsClient client;
  final RsVerdict verdict;

  /// The basic rates it lacks, slowest first.
  final List<RsRate> missingBasic;

  /// False when the beacon rate is one it cannot receive (an 802.11b device
  /// and an OFDM beacon: the model's reading 3).
  final bool decodesBeacons;

  final RsRequiredPhy requiredPhy;

  bool get associates => verdict == RsVerdict.associates;

  /// 18 when refused for a basic rate, else null.
  int? get statusCode =>
      verdict == RsVerdict.refusedBasicRates ? kStatusRefusedBasicRates : null;
}

/// A frame whose ACK or CTS rate is asked for.
class RsEliciting {
  const RsEliciting.legacy(RsRate this.rate)
    : mcs = null,
      modulation = null,
      codeRate = null;

  const RsEliciting.he({
    required int this.mcs,
    required String this.modulation,
    required String this.codeRate,
  }) : rate = null;

  /// A legacy frame's rate, or null for an HE frame.
  final RsRate? rate;

  /// An HE frame's MCS and its modulation and coding.
  final int? mcs;
  final String? modulation;
  final String? codeRate;

  bool get isHe => mcs != null;

  /// The rate the rule compares against: the frame's own rate, or the
  /// non-HT reference rate of its modulation and coding (10.6.11).
  double get compareMbps =>
      rate?.mbps ?? nonHtReferenceRate(modulation!, codeRate!);

  /// The class the answer must keep: the frame's own for a legacy frame;
  /// OFDM for HE (the model's reading 2).
  RsModClass get responseClass => rate?.modClass ?? RsModClass.ofdm;

  String get label => isHe ? 'HE MCS $mcs' : rate!.mbpsLabel;
}

/// The HE MCS rows the ACK table shows (MCS 0 to 11, with modulation and
/// coding from the 802.11ax MCS table).
const List<RsEliciting> kRsHeRows = <RsEliciting>[
  RsEliciting.he(mcs: 0, modulation: 'BPSK', codeRate: '1/2'),
  RsEliciting.he(mcs: 1, modulation: 'QPSK', codeRate: '1/2'),
  RsEliciting.he(mcs: 2, modulation: 'QPSK', codeRate: '3/4'),
  RsEliciting.he(mcs: 3, modulation: '16-QAM', codeRate: '1/2'),
  RsEliciting.he(mcs: 4, modulation: '16-QAM', codeRate: '3/4'),
  RsEliciting.he(mcs: 5, modulation: '64-QAM', codeRate: '2/3'),
  RsEliciting.he(mcs: 6, modulation: '64-QAM', codeRate: '3/4'),
  RsEliciting.he(mcs: 7, modulation: '64-QAM', codeRate: '5/6'),
  RsEliciting.he(mcs: 8, modulation: '256-QAM', codeRate: '3/4'),
  RsEliciting.he(mcs: 9, modulation: '256-QAM', codeRate: '5/6'),
  RsEliciting.he(mcs: 10, modulation: '1024-QAM', codeRate: '3/4'),
  RsEliciting.he(mcs: 11, modulation: '1024-QAM', codeRate: '5/6'),
];

/// Table 10-10 (p.1962): the non-HT reference rate, Mb/s, for a modulation
/// and coding rate. Throws on a pair the table does not carry.
double nonHtReferenceRate(String modulation, String codeRate) {
  const Map<String, double> table = <String, double>{
    'BPSK 1/2': 6,
    'BPSK 3/4': 9,
    'QPSK 1/2': 12,
    'QPSK 3/4': 18,
    '16-QAM 1/2': 24,
    '16-QAM 3/4': 36,
    '64-QAM 1/2': 48,
    '64-QAM 2/3': 48,
    '64-QAM 3/4': 54,
    '64-QAM 5/6': 54,
    '256-QAM 3/4': 54,
    '256-QAM 5/6': 54,
    '1024-QAM 3/4': 54,
    '1024-QAM 5/6': 54,
  };
  final double? r = table['$modulation $codeRate'];
  if (r == null) {
    throw ArgumentError.value('$modulation $codeRate', 'modulation and coding');
  }
  return r;
}

/// The ACK or CTS rate for one eliciting frame.
class RsControlResponse {
  const RsControlResponse({
    required this.eliciting,
    required this.rate,
    required this.fromBasic,
    required this.classFilterDecided,
  });

  final RsEliciting eliciting;

  /// The rate the ACK goes at.
  final RsRate rate;

  /// True when a basic rate fits; false when the mandatory fallback answers.
  final bool fromBasic;

  /// True when the rate rule alone would have picked a basic rate of the
  /// other class, so the class filter decided (the model's reading 1).
  final bool classFilterDecided;
}

/// Where the beacon rate came from.
class RsBeacon {
  const RsBeacon(this.rate, {required this.fromBasic});

  /// The rate beacons go at in this model.
  final RsRate rate;

  /// True when it is the lowest basic rate (vendor behavior); false when the
  /// basic set is empty and the lowest mandatory rate stands in.
  final bool fromBasic;
}

/// An access point's rate set on one PHY.
class RateSet {
  RateSet(this.phy, Map<RsRate, RsState> states)
    : _states = Map<RsRate, RsState>.unmodifiable(<RsRate, RsState>{
        for (final RsRate r in RsRate.values) r: states[r] ?? RsState.off,
      });

  /// The default: 6, 12 and 24 basic; the other OFDM rates and, at 2.4 GHz,
  /// the four DSSS/CCK rates supported. Its minimum basic rate is 6 Mb/s,
  /// which keeps every Rate vs Range number the tool had before.
  factory RateSet.defaults(RsPhy phy) => RateSet(phy, <RsRate, RsState>{
    for (final RsRate r in RsRate.values)
      r: const <RsRate>[RsRate.r6, RsRate.r12, RsRate.r24].contains(r)
          ? RsState.basic
          : RsState.supported,
  });

  /// Built from basic and supported lists (tests and presets).
  factory RateSet.of(
    RsPhy phy, {
    required List<RsRate> basic,
    List<RsRate> supported = const <RsRate>[],
  }) => RateSet(phy, <RsRate, RsState>{
    for (final RsRate r in supported) r: RsState.supported,
    for (final RsRate r in basic) r: RsState.basic,
  });

  final RsPhy phy;
  final Map<RsRate, RsState> _states;

  /// The state of [r]. A rate this PHY does not have reads off.
  RsState stateOf(RsRate r) => phy.has(r) ? _states[r]! : RsState.off;

  /// The same states on another PHY (switching band keeps the choices; DSSS
  /// states return when the band is 2.4 GHz again).
  RateSet onPhy(RsPhy p) => RateSet(p, _states);

  RateSet withState(RsRate r, RsState s) =>
      RateSet(phy, <RsRate, RsState>{..._states, r: s});

  /// The next state in tap order.
  RateSet cycle(RsRate r) => withState(r, stateOf(r).next);

  /// Makes [r] the minimum basic rate: every slower rate of the PHY off,
  /// [r] basic, and any faster rate that was off now supported.
  RateSet withMinimumBasic(RsRate r) => RateSet(phy, <RsRate, RsState>{
    for (final RsRate x in RsRate.values)
      x: !phy.has(x)
          ? _states[x]!
          : x.halfMbps < r.halfMbps
          ? RsState.off
          : x == r
          ? RsState.basic
          : _states[x] == RsState.off
          ? RsState.supported
          : _states[x]!,
  });

  /// Basic rates, slowest first.
  List<RsRate> get basic => <RsRate>[
    for (final RsRate r in phy.rates)
      if (stateOf(r) == RsState.basic) r,
  ];

  /// Every rate that is on (basic or supported), slowest first.
  List<RsRate> get operational => <RsRate>[
    for (final RsRate r in phy.rates)
      if (stateOf(r) != RsState.off) r,
  ];

  bool get isEmpty => operational.isEmpty;

  /// The derived minimum basic rate: the lowest basic rate, or null when
  /// the basic set is empty.
  RsRate? get minimumBasic => basic.isEmpty ? null : basic.first;

  /// The Supported Rates element's octets (at most eight), then the
  /// Extended Supported Rates element's, as a Beacon carries them.
  ({List<int> supported, List<int> extended}) get elementOctets {
    final List<int> all = <int>[
      for (final RsRate r in operational)
        r.octet(basic: stateOf(r) == RsState.basic),
    ];
    return (supported: all.take(8).toList(), extended: all.skip(8).toList());
  }

  /// The beacon rate (see [RsBeacon]), or null when every rate is off.
  RsBeacon? get beacon {
    if (isEmpty) return null;
    final RsRate? low = minimumBasic;
    if (low != null) return RsBeacon(low, fromBasic: true);
    return RsBeacon(phy.mandatory.first, fromBasic: false);
  }

  /// The ACK or CTS rate for [e] (10.6.6.5.2 with the class rule).
  RsControlResponse controlResponse(RsEliciting e) {
    final double at = e.compareMbps;
    final RsModClass cls = e.responseClass;
    RsRate? inClass;
    RsRate? anyClass;
    for (final RsRate r in basic) {
      if (r.mbps > at) continue;
      if (anyClass == null || r.mbps > anyClass.mbps) anyClass = r;
      if (r.modClass == cls && (inClass == null || r.mbps > inClass.mbps)) {
        inClass = r;
      }
    }
    RsRate? fallback;
    for (final RsRate r in phy.mandatory) {
      if (r.modClass != cls || r.mbps > at) continue;
      if (fallback == null || r.mbps > fallback.mbps) fallback = r;
    }
    final RsRate answer = inClass ?? fallback ?? phy.mandatory.first;
    return RsControlResponse(
      eliciting: e,
      rate: answer,
      fromBasic: inClass != null,
      classFilterDecided: anyClass != null && anyClass != inClass,
    );
  }

  /// One row per rate that is on, then (when [withHe]) HE MCS 0 to 11.
  List<RsControlResponse> ackTable({
    bool withHe = false,
  }) => <RsControlResponse>[
    for (final RsRate r in operational) controlResponse(RsEliciting.legacy(r)),
    // Every rate off: nothing is sent, so nothing is answered.
    if (withHe && !isEmpty)
      for (final RsEliciting e in kRsHeRows) controlResponse(e),
  ];

  @override
  bool operator ==(Object other) =>
      other is RateSet &&
      other.phy == phy &&
      RsRate.values.every((RsRate r) => other._states[r] == _states[r]);

  @override
  int get hashCode => Object.hash(
    phy,
    Object.hashAll(<RsState>[
      for (final RsRate r in RsRate.values) _states[r]!,
    ]),
  );
}

/// Whether [client] can associate to an AP with [set] (and, when set, a
/// required PHY). Order: no rates; wrong band; a missing basic rate
/// (status 18); a missing required PHY.
RsAssociation canJoin(
  RateSet set,
  RsClient client, {
  RsRequiredPhy requirePhy = RsRequiredPhy.none,
}) {
  if (set.isEmpty) {
    return RsAssociation(client: client, verdict: RsVerdict.noRates);
  }
  if (!client.on(set.phy)) {
    return RsAssociation(client: client, verdict: RsVerdict.otherBand);
  }
  final RsBeacon beacon = set.beacon!;
  final bool decodes = client.supports(beacon.rate, set.phy);
  final List<RsRate> missing = <RsRate>[
    for (final RsRate r in set.basic)
      if (!client.supports(r, set.phy)) r,
  ];
  if (missing.isNotEmpty) {
    return RsAssociation(
      client: client,
      verdict: RsVerdict.refusedBasicRates,
      missingBasic: missing,
      decodesBeacons: decodes,
    );
  }
  if (!client.hasPhy(requirePhy)) {
    return RsAssociation(
      client: client,
      verdict: RsVerdict.lacksRequiredPhy,
      decodesBeacons: decodes,
      requiredPhy: requirePhy,
    );
  }
  return RsAssociation(
    client: client,
    verdict: RsVerdict.associates,
    decodesBeacons: decodes,
  );
}

/// "6, 12 and 24 Mbps".
String rsRateList(List<RsRate> rates) {
  if (rates.isEmpty) return 'none';
  final List<String> l = <String>[for (final RsRate r in rates) r.label];
  final String head = l.length == 1
      ? l.first
      : '${l.sublist(0, l.length - 1).join(', ')} and ${l.last}';
  return '$head Mbps';
}

/// The verdict in a few words, for a badge ("Refused: status 18").
String rsVerdictHeadline(RsAssociation a) {
  switch (a.verdict) {
    case RsVerdict.associates:
      return 'Associates';
    case RsVerdict.refusedBasicRates:
      return a.decodesBeacons ? 'Refused: status 18' : 'Cannot associate';
    case RsVerdict.lacksRequiredPhy:
      return 'Cannot associate';
    case RsVerdict.otherBand:
      return 'Never hears this network';
    case RsVerdict.noRates:
      return 'No rates on';
  }
}

/// The verdict in a sentence or two. UI text says associate, never join
/// (Keith, 2026-09-29).
String rsVerdictLine(RsAssociation a) {
  final String status =
      'status $kStatusRefusedBasicRates ($kStatusRefusedBasicRatesName)';
  switch (a.verdict) {
    case RsVerdict.associates:
      return 'Associates: it supports every basic rate.';
    case RsVerdict.refusedBasicRates:
      final String lacks = 'it lacks ${rsRateList(a.missingBasic)}';
      return a.decodesBeacons
          ? 'Refused with $status: $lacks.'
          : 'Cannot associate: it cannot decode the OFDM beacons, so it '
                'never sees this network. If it tried, the AP would refuse '
                'it with $status: $lacks.';
    case RsVerdict.lacksRequiredPhy:
      return 'Cannot associate: the network requires '
          '${a.requiredPhy.label} (BSS membership selector '
          '${a.requiredPhy.selector}), which it lacks.';
    case RsVerdict.otherBand:
      return 'Never hears this network: it is a 2.4 GHz-only device.';
    case RsVerdict.noRates:
      return 'No rates are on: the AP has nothing to send with.';
  }
}
