// PHY Preamble Reference (Wi-Fi Lab, 2026-09-25): the model.
//
// Every Wi-Fi PPDU since 802.11a opens with the same 20 us legacy preamble
// (L-STF, L-LTF, L-SIG). This file lays out what each later PHY adds after
// it, to scale in microseconds, what is inside every SIG field bit by bit,
// how a receiver tells the PHYs apart from the first symbols after L-SIG, and
// how L-SIG LENGTH is set so a legacy radio defers for the whole PPDU.
//
// CLEAN-ROOM BUILD. Every duration, bit position, width and evidence tag is
// taken from Pax's wave-5 brief (myPKA Deliverables/2026-09-25-wifi-lab-
// wave5-research/brief.md, sections 1 to 8). Spec: myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/13-phy-preamble.md. No cheat sheet, and
// nothing from any mirror folder, was opened.
//
// EVIDENCE. Each field carries the tag the brief gives it, verbatim (`P`,
// `S2`, `S2+`, `P/S2`, `S1`, `INF`, `P, single vendor`, `not verified`).
// [EvidenceLevel] sorts those into settled and not settled so the screen can
// never show a single-source or inferred field as settled. Two places where
// the brief gives no tag at all carry [EvidenceLevel.untagged], which is
// also not settled.
//
// DURATIONS agree with lib/services/wifi_lab/airtime_anatomy.dart for every
// setting both cover (a test pins it). Where this model covers more (HE MU,
// HE TB, ER SU, EHT, 4x HE-LTF with a 0.8 us GI), the extra rows come from the
// brief and are tagged there. Durations are integer tenths of a microsecond,
// as in the airtime service, so sums are exact. No Flutter imports.

/// How far a field's evidence goes.
enum EvidenceLevel {
  /// Two independent sources, or code from two unrelated code bases.
  settled('settled'),

  /// One source, or code from one vendor only.
  singleSource('one source'),

  /// The researcher's own derivation.
  inferred('inferred'),

  /// Given from memory in the brief and marked not verified.
  unverified('not verified'),

  /// The brief gives this field no tag.
  untagged('no tag in the brief');

  const EvidenceLevel(this.words);

  /// What the screen says beside the tag when the field is not settled.
  final String words;

  bool get isSettled => this == EvidenceLevel.settled;
}

/// One evidence tag, exactly as the brief writes it.
class Evidence {
  const Evidence(this.tag, this.level, {this.scope});

  /// The brief's tag, verbatim.
  final String tag;

  final EvidenceLevel level;

  /// What the tag covers when a field carries more than one ("MU split").
  final String? scope;

  bool get isSettled => level.isSettled;

  /// "S1 (MU split), one source" for the screen reader.
  String get spoken {
    final String s = scope == null ? '' : ' ($scope)';
    return isSettled
        ? 'evidence $tag$s'
        : 'evidence $tag$s, ${level.words}, not settled';
  }

  @override
  bool operator ==(Object other) =>
      other is Evidence &&
      other.tag == tag &&
      other.level == level &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(tag, level, scope);
}

// The tags the brief uses. Scoped variants are built inline.
const Evidence _p = Evidence('P', EvidenceLevel.settled);
const Evidence _s2 = Evidence('S2', EvidenceLevel.settled);
const Evidence _s2plus = Evidence('S2+', EvidenceLevel.settled);
const Evidence _pS2 = Evidence('P/S2', EvidenceLevel.settled);
const Evidence _s1 = Evidence('S1', EvidenceLevel.singleSource);
const Evidence _inf = Evidence('INF', EvidenceLevel.inferred);
const Evidence _pOneVendor = Evidence(
  'P',
  EvidenceLevel.singleSource,
  scope: 'one vendor',
);
const Evidence _pSingleVendor = Evidence(
  'P, single vendor',
  EvidenceLevel.singleSource,
);
const Evidence _notVerified = Evidence(
  'not verified',
  EvidenceLevel.unverified,
);
const Evidence _untagged = Evidence('none', EvidenceLevel.untagged);

// ── Bit tables ──────────────────────────────────────────────────────────────

/// One field of a SIG table.
class BitField {
  const BitField(this.start, this.end, this.name, this.meaning, this.evidence)
    : _width = null;

  /// Field-level only: the brief gives the width but no bit positions.
  const BitField.unplaced(this._width, this.name, this.meaning, this.evidence)
    : start = null,
      end = null;

  /// First bit, `B0` = first transmitted in its symbol. Null when unplaced.
  final int? start;

  /// Last bit, inclusive. Null when unplaced.
  final int? end;

  final String name;
  final String meaning;

  /// One tag, or several with scopes.
  final List<Evidence> evidence;

  final int? _width;

  int get width => _width ?? (end! - start! + 1);

  bool get isPlaced => start != null;

  /// True only when every tag on the field is settled.
  bool get isSettled => evidence.every((Evidence e) => e.isSettled);

  /// "B8-B13", "B4", or "-" when the brief gives no position.
  String get bitsLabel {
    if (start == null) return '-';
    return start == end ? 'B$start' : 'B$start-B$end';
  }
}

/// A run of fields: one symbol of a SIG field, or one variant of it.
class BitGroup {
  const BitGroup({
    required this.title,
    required this.bits,
    required this.fields,
    this.modulation,
  });

  /// "HE-SIG-A1", "SU, 20 MHz", "Common field".
  final String title;

  /// Declared size of this group, or null when the brief does not total it.
  final int? bits;

  /// "BPSK", "QBPSK", or null.
  final String? modulation;

  final List<BitField> fields;

  int get fieldWidthSum =>
      fields.fold<int>(0, (int a, BitField f) => a + f.width);
}

/// A note under a table, with its own tag.
class TableNote {
  const TableNote(this.text, this.evidence);

  final String text;
  final Evidence evidence;
}

/// A SIG (or SERVICE) field's bit table.
class SigTable {
  const SigTable({
    required this.title,
    required this.groups,
    this.totalBits,
    this.groupsAreAlternatives = false,
    this.notes = const <TableNote>[],
  });

  final String title;

  /// The field's size when its groups are consecutive symbols. Null for
  /// tables made of alternatives or of field-level summaries.
  final int? totalBits;

  /// True when each group is an alternative layout (SU or MU, per width), so
  /// the groups do not add up; each one totals on its own.
  final bool groupsAreAlternatives;

  final List<BitGroup> groups;
  final List<TableNote> notes;

  Iterable<BitField> get allFields => groups.expand((BitGroup g) => g.fields);

  /// Sum of every field's width when the groups are consecutive.
  int get fieldWidthSum =>
      groups.fold<int>(0, (int a, BitGroup g) => a + g.fieldWidthSum);

  /// The first field named [name], with its group, or null.
  ({BitGroup group, BitField field})? find(String name) {
    for (final BitGroup g in groups) {
      for (final BitField f in g.fields) {
        if (f.name == name) return (group: g, field: f);
      }
    }
    return null;
  }
}

// ── L-SIG and SERVICE (brief section 2) ─────────────────────────────────────

const SigTable kLsigTable = SigTable(
  title: 'L-SIG',
  totalBits: 24,
  groups: <BitGroup>[
    BitGroup(
      title: 'L-SIG',
      bits: 24,
      modulation: 'BPSK',
      fields: <BitField>[
        BitField(
          0,
          3,
          'RATE',
          'Rate code, R1 to R4 in transmit order. 6 Mb/s = 1101, 9 = 1111, '
              '12 = 0101, 18 = 0111, 24 = 1001, 36 = 1011, 48 = 0001, '
              '54 = 0011. Always 1101 (6 Mb/s) in HT, VHT, HE and EHT PPDUs',
          <Evidence>[
            _s2plus,
            Evidence('S2', EvidenceLevel.settled, scope: 'rate codes'),
          ],
        ),
        BitField(4, 4, 'Reserved', '0', <Evidence>[_s2plus]),
        BitField(
          5,
          16,
          'LENGTH',
          'Octets in non-HT. In HT and later, a spoofed length that sets how '
              'long a legacy radio defers',
          <Evidence>[_s2plus],
        ),
        BitField(17, 17, 'Parity', 'Even parity over B0-B16', <Evidence>[
          _s2plus,
        ]),
        BitField(18, 23, 'Tail', 'All zero', <Evidence>[_s2plus]),
      ],
    ),
  ],
);

/// The 16-bit SERVICE field at the start of the Data field. [vht] swaps in
/// the VHT-SIG-B CRC at B8-B15.
SigTable serviceTable({required bool vht}) => SigTable(
  title: vht ? 'SERVICE (VHT)' : 'SERVICE',
  totalBits: 16,
  groups: <BitGroup>[
    BitGroup(
      title: 'SERVICE, first 16 bits of the Data field',
      bits: 16,
      fields: vht
          ? const <BitField>[
              BitField(
                0,
                6,
                'Scrambler initialization',
                'Transmitted as zeros',
                <Evidence>[_s2],
              ),
              BitField(7, 7, 'Reserved', 'Zero', <Evidence>[_s2]),
              BitField(
                8,
                15,
                'VHT-SIG-B CRC',
                '8-bit CRC that protects VHT-SIG-B',
                <Evidence>[_s2],
              ),
            ]
          : const <BitField>[
              BitField(
                0,
                6,
                'Scrambler initialization',
                'Transmitted as zeros',
                <Evidence>[_s2],
              ),
              BitField(7, 15, 'Reserved', 'Zero in non-HT and HT', <Evidence>[
                Evidence('S1', EvidenceLevel.singleSource, scope: 'non-HT'),
              ]),
            ],
    ),
  ],
);

// ── HT-SIG (brief section 3) ────────────────────────────────────────────────

const SigTable kHtSigTable = SigTable(
  title: 'HT-SIG',
  totalBits: 48,
  groups: <BitGroup>[
    BitGroup(
      title: 'HT-SIG1',
      bits: 24,
      modulation: 'QBPSK',
      fields: <BitField>[
        BitField(0, 6, 'MCS', '0-76', <Evidence>[_s2plus]),
        BitField(7, 7, 'CBW 20/40', '0 = 20 MHz, 1 = 40 MHz', <Evidence>[
          _s2plus,
        ]),
        BitField(8, 23, 'HT Length', 'PSDU octets', <Evidence>[_s2plus]),
      ],
    ),
    BitGroup(
      title: 'HT-SIG2',
      bits: 24,
      modulation: 'QBPSK',
      fields: <BitField>[
        BitField(0, 0, 'Smoothing', '1 = smoothing recommended', <Evidence>[
          _s2plus,
        ]),
        BitField(1, 1, 'Not Sounding', '0 = sounding PPDU', <Evidence>[
          _s2plus,
        ]),
        BitField(2, 2, 'Reserved', 'Set to 1', <Evidence>[_s2plus]),
        BitField(3, 3, 'Aggregation', '1 = A-MPDU', <Evidence>[_s2plus]),
        BitField(4, 5, 'STBC', 'N_STS minus N_SS', <Evidence>[_s2plus]),
        BitField(6, 6, 'FEC Coding', '0 = BCC, 1 = LDPC', <Evidence>[_s2plus]),
        BitField(7, 7, 'Short GI', '1 = 400 ns GI', <Evidence>[_s2plus]),
        BitField(8, 9, 'Number of Extension Spatial Streams', '0-3', <Evidence>[
          _s2plus,
        ]),
        BitField(
          10,
          17,
          'CRC',
          'Over HT-SIG1 B0-B23 and HT-SIG2 B0-B9 (34 bits)',
          <Evidence>[_s2plus],
        ),
        BitField(18, 23, 'Tail', 'Zero', <Evidence>[_s2plus]),
      ],
    ),
  ],
);

// ── VHT-SIG-A and VHT-SIG-B (brief section 4) ──────────────────────────────

const SigTable kVhtSigATable = SigTable(
  title: 'VHT-SIG-A',
  totalBits: 48,
  groups: <BitGroup>[
    BitGroup(
      title: 'VHT-SIG-A1',
      bits: 24,
      modulation: 'BPSK',
      fields: <BitField>[
        BitField(0, 1, 'BW', '0/1/2/3 = 20/40/80/160 or 80+80 MHz', <Evidence>[
          _s2,
        ]),
        BitField(2, 2, 'Reserved', 'Set to 1', <Evidence>[_s2]),
        BitField(3, 3, 'STBC', 'Space-time block coding', <Evidence>[_s2]),
        BitField(4, 9, 'Group ID', '0 or 63 = SU; otherwise MU', <Evidence>[
          _s2,
        ]),
        BitField(
          10,
          21,
          'N_STS and Partial AID',
          'SU: N_STS (B10-B12, 3 bits) + Partial AID (B13-B21, 9 bits). MU: '
              'four 3-bit N_STS fields',
          <Evidence>[_s2],
        ),
        BitField(
          22,
          22,
          'TXOP_PS_NOT_ALLOWED',
          'TXOP power save not allowed',
          <Evidence>[_s2],
        ),
        BitField(23, 23, 'Reserved', 'Set to 1', <Evidence>[_s2]),
      ],
    ),
    BitGroup(
      title: 'VHT-SIG-A2',
      bits: 24,
      modulation: 'QBPSK',
      fields: <BitField>[
        BitField(0, 0, 'Short GI', 'Short guard interval', <Evidence>[_s2]),
        BitField(
          1,
          1,
          'Short GI N_SYM Disambiguation',
          '1 when short GI and N_SYM mod 10 = 9',
          <Evidence>[
            Evidence('S2', EvidenceLevel.settled, scope: 'position'),
            Evidence('S1', EvidenceLevel.singleSource, scope: 'meaning'),
          ],
        ),
        BitField(2, 2, 'SU/MU[0] Coding', '0 = BCC, 1 = LDPC', <Evidence>[_s2]),
        BitField(
          3,
          3,
          'LDPC Extra OFDM Symbol',
          'An extra symbol from LDPC encoding',
          <Evidence>[_s2],
        ),
        BitField(
          4,
          7,
          'VHT-MCS (SU) / MU[1-3] Coding',
          'SU: VHT-MCS. MU: MU[1-3] Coding in B4-B6, B7 reserved',
          <Evidence>[
            Evidence('S2', EvidenceLevel.settled, scope: 'SU'),
            Evidence('S1', EvidenceLevel.singleSource, scope: 'MU split'),
          ],
        ),
        BitField(
          8,
          8,
          'Beamformed',
          'Beamformed (SU); reserved (MU)',
          <Evidence>[_s2],
        ),
        BitField(9, 9, 'Reserved', 'Set to 1', <Evidence>[_s2]),
        // The brief's S2 covers "every position through B9 of A2" and gives
        // CRC and Tail no tag of their own.
        BitField(10, 17, 'CRC', '8-bit CRC', <Evidence>[_untagged]),
        BitField(18, 23, 'Tail', 'Zero', <Evidence>[_untagged]),
      ],
    ),
  ],
);

/// VHT-SIG-B, one BPSK symbol; its layout depends on the channel width.
/// SU and MU are shown as alternatives.
SigTable vhtSigBTable(int widthMhz) {
  final bool w20 = widthMhz == 20;
  final Evidence e = w20
      ? _s2
      : const Evidence('S1', EvidenceLevel.singleSource);
  final int suLen = switch (widthMhz) {
    20 => 17,
    40 => 19,
    _ => 21,
  };
  final int suRes = w20 ? 3 : 2;
  final int muLen = switch (widthMhz) {
    20 => 16,
    40 => 17,
    _ => 19,
  };
  final int total = switch (widthMhz) {
    20 => 26,
    40 => 27,
    _ => 29,
  };
  final String wLabel = widthMhz >= 80 ? '80/160 MHz' : '$widthMhz MHz';
  return SigTable(
    title: 'VHT-SIG-B, $wLabel',
    groupsAreAlternatives: true,
    groups: <BitGroup>[
      BitGroup(
        title: 'SU, $wLabel',
        bits: total,
        modulation: 'BPSK',
        fields: <BitField>[
          BitField(0, suLen - 1, 'LENGTH', 'VHT-SIG-B length', <Evidence>[e]),
          BitField(
            suLen,
            suLen + suRes - 1,
            'Reserved',
            w20 ? 'All 1' : 'Reserved',
            <Evidence>[e],
          ),
          BitField(suLen + suRes, total - 1, 'Tail', 'Zero', <Evidence>[e]),
        ],
      ),
      BitGroup(
        title: 'MU, $wLabel',
        bits: total,
        modulation: 'BPSK',
        fields: <BitField>[
          BitField(0, muLen - 1, 'LENGTH', 'VHT-SIG-B length', <Evidence>[e]),
          BitField(muLen, muLen + 3, 'MCS', 'Per-user MCS', <Evidence>[e]),
          BitField(muLen + 4, total - 1, 'Tail', 'Zero', <Evidence>[e]),
        ],
      ),
    ],
    notes: <TableNote>[
      if (!w20)
        const TableNote(
          'The 40 and 80 MHz splits are from memory in the brief, consistent '
          'with MathWorks\' 26/27/29-bit totals. Verify before printing.',
          Evidence('S1', EvidenceLevel.singleSource),
        ),
      const TableNote(
        'Protected by the 8-bit CRC carried in SERVICE B8-B15.',
        _s2,
      ),
    ],
  );
}

// ── HE-SIG-A (brief section 5) ─────────────────────────────────────────────

const Evidence _heCrcTail = _inf;

List<BitField> _heCrcTailFields() => const <BitField>[
  BitField(16, 19, 'CRC', '4-bit CRC', <Evidence>[_heCrcTail]),
  BitField(20, 25, 'Tail', 'Zero', <Evidence>[_heCrcTail]),
];

/// HE-SIG-A for the SU PPDU, or the ER SU PPDU when [erSu].
SigTable heSigASuTable({required bool erSu}) => SigTable(
  title: erSu ? 'HE-SIG-A (HE ER SU)' : 'HE-SIG-A (HE SU)',
  totalBits: 52,
  groups: <BitGroup>[
    BitGroup(
      title: 'HE-SIG-A1',
      bits: 26,
      modulation: 'BPSK',
      fields: <BitField>[
        const BitField(0, 0, 'Format', '1 = SU or ER SU, 0 = TB', <Evidence>[
          _s2,
        ]),
        const BitField(1, 1, 'Beam Change', 'Beam change', <Evidence>[_s2]),
        const BitField(2, 2, 'UL/DL', 'Uplink or downlink', <Evidence>[_s2]),
        const BitField(3, 6, 'MCS', 'HE-MCS', <Evidence>[_s2]),
        const BitField(7, 7, 'DCM', 'Dual carrier modulation', <Evidence>[_s2]),
        const BitField(8, 13, 'BSS Color', '6-bit BSS color', <Evidence>[_s2]),
        const BitField(14, 14, 'Reserved', 'Set to 1', <Evidence>[_s2]),
        const BitField(15, 18, 'Spatial Reuse', 'Spatial reuse', <Evidence>[
          _s2,
        ]),
        if (erSu)
          const BitField(
            19,
            20,
            'Bandwidth',
            'In ER SU: 242-tone vs upper 106-tone, not a channel width',
            <Evidence>[
              Evidence('S2', EvidenceLevel.settled, scope: 'position'),
              Evidence(
                'S1',
                EvidenceLevel.singleSource,
                scope: 'ER SU meaning',
              ),
            ],
          )
        else
          const BitField(19, 20, 'Bandwidth', 'Channel width', <Evidence>[_s2]),
        const BitField(
          21,
          22,
          'GI + LTF Size',
          'Guard interval and HE-LTF size',
          <Evidence>[_s2],
        ),
        const BitField(
          23,
          25,
          'N_STS and Midamble Periodicity',
          'Space-time streams and midamble periodicity',
          <Evidence>[_s2],
        ),
      ],
    ),
    BitGroup(
      title: 'HE-SIG-A2',
      bits: 26,
      modulation: 'BPSK',
      fields: <BitField>[
        const BitField(0, 6, 'TXOP', 'TXOP duration', <Evidence>[_s2]),
        const BitField(7, 7, 'Coding', 'BCC or LDPC', <Evidence>[_s2]),
        const BitField(
          8,
          8,
          'LDPC Extra Symbol Segment',
          'LDPC extra symbol segment',
          <Evidence>[_s2],
        ),
        const BitField(9, 9, 'STBC', 'Space-time block coding', <Evidence>[
          _s2,
        ]),
        const BitField(10, 10, 'Beamformed', 'Beamformed', <Evidence>[_s2]),
        const BitField(
          11,
          12,
          'Pre-FEC Padding Factor',
          'Pre-FEC padding factor',
          <Evidence>[_s2],
        ),
        const BitField(
          13,
          13,
          'PE Disambiguity',
          'Packet extension disambiguity',
          <Evidence>[_s2],
        ),
        const BitField(14, 14, 'Reserved', 'Set to 1', <Evidence>[_s2]),
        const BitField(15, 15, 'Doppler', 'Doppler', <Evidence>[_s2]),
        ..._heCrcTailFields(),
      ],
    ),
  ],
  notes: <TableNote>[
    if (erSu) ...const <TableNote>[
      TableNote(
        'ER SU sends HE-SIG-A over four symbols, 16 µs, and the second '
        'symbol is QBPSK; the others are BPSK.',
        _s2,
      ),
    ],
    const TableNote(
      'CRC and Tail by analogy: a 26-bit symbol, with the same B16-B19 and '
      'B20-B25 split as U-SIG.',
      _inf,
    ),
  ],
);

const SigTable kHeSigAMuTable = SigTable(
  title: 'HE-SIG-A (HE MU)',
  totalBits: 52,
  groups: <BitGroup>[
    BitGroup(
      title: 'HE-SIG-A1',
      bits: 26,
      modulation: 'BPSK',
      fields: <BitField>[
        BitField(
          0,
          0,
          'UL/DL',
          'Uplink or downlink. Placed at B0 by elimination: one driver\'s '
              'header collides here',
          <Evidence>[_pOneVendor],
        ),
        BitField(1, 3, 'SIG-B MCS', '0-5', <Evidence>[_pOneVendor]),
        BitField(
          4,
          4,
          'SIG-B DCM',
          'Dual carrier modulation for HE-SIG-B',
          <Evidence>[_pOneVendor],
        ),
        BitField(5, 10, 'BSS Color', '6-bit BSS color', <Evidence>[
          _pOneVendor,
        ]),
        BitField(11, 14, 'Spatial Reuse', 'Spatial reuse', <Evidence>[
          _pOneVendor,
        ]),
        BitField(
          15,
          17,
          'Bandwidth',
          'Includes preamble-puncturing modes. Values above 3 not recovered',
          <Evidence>[_pOneVendor],
        ),
        BitField(
          18,
          21,
          'Number of HE-SIG-B Symbols',
          'Or MU-MIMO users when compressed',
          <Evidence>[_p],
        ),
        BitField(22, 22, 'SIG-B Compression', 'SIG-B compression', <Evidence>[
          _p,
        ]),
        BitField(
          23,
          24,
          'GI + LTF Size',
          'Guard interval and HE-LTF size',
          <Evidence>[_pOneVendor],
        ),
        BitField(25, 25, 'Doppler', 'Doppler', <Evidence>[_pOneVendor]),
      ],
    ),
    BitGroup(
      title: 'HE-SIG-A2',
      bits: 26,
      modulation: 'BPSK',
      fields: <BitField>[
        BitField(0, 6, 'TXOP', 'TXOP duration', <Evidence>[_pOneVendor]),
        BitField(7, 7, 'Reserved', 'Coding is per user in HE-SIG-B', <Evidence>[
          _inf,
        ]),
        BitField(
          8,
          10,
          'Number of HE-LTF Symbols and Midamble Periodicity',
          'HE-LTF count and midamble periodicity',
          <Evidence>[_pOneVendor],
        ),
        BitField(
          11,
          11,
          'LDPC Extra Symbol Segment',
          'LDPC extra symbol segment',
          <Evidence>[_pOneVendor],
        ),
        BitField(12, 12, 'STBC', 'Space-time block coding', <Evidence>[
          _pOneVendor,
        ]),
        BitField(
          13,
          14,
          'Pre-FEC Padding Factor',
          'Pre-FEC padding factor',
          <Evidence>[_pOneVendor],
        ),
        BitField(
          15,
          15,
          'PE Disambiguity',
          'Packet extension disambiguity',
          <Evidence>[_pOneVendor],
        ),
        BitField(16, 19, 'CRC', '4-bit CRC', <Evidence>[_pOneVendor]),
        BitField(20, 25, 'Tail', 'Zero', <Evidence>[_pOneVendor]),
      ],
    ),
  ],
  notes: <TableNote>[
    TableNote(
      'Positions from Qualcomm\'s ath11k and ath12k drivers: one vendor, two '
      'generations. Intel independently confirms the SIG-B symbol count at '
      'B18-B21 and compression at B22.',
      _p,
    ),
  ],
);

const SigTable kHeSigATbTable = SigTable(
  title: 'HE-SIG-A (HE TB)',
  totalBits: 52,
  groups: <BitGroup>[
    BitGroup(
      title: 'HE-SIG-A1',
      bits: 26,
      modulation: 'BPSK',
      fields: <BitField>[
        BitField(0, 0, 'Format', '0 = TB', <Evidence>[_pSingleVendor]),
        BitField(1, 6, 'BSS Color', '6-bit BSS color', <Evidence>[
          _pSingleVendor,
        ]),
        BitField(
          7,
          10,
          'Spatial Reuse 1',
          'One of four spatial-reuse fields',
          <Evidence>[
            _pSingleVendor,
            Evidence(
              'S2',
              EvidenceLevel.settled,
              scope: 'four fields, as a concept',
            ),
          ],
        ),
        BitField(
          11,
          14,
          'Spatial Reuse 2',
          'One of four spatial-reuse fields',
          <Evidence>[
            _pSingleVendor,
            Evidence(
              'S2',
              EvidenceLevel.settled,
              scope: 'four fields, as a concept',
            ),
          ],
        ),
        BitField(
          15,
          18,
          'Spatial Reuse 3',
          'One of four spatial-reuse fields',
          <Evidence>[
            _pSingleVendor,
            Evidence(
              'S2',
              EvidenceLevel.settled,
              scope: 'four fields, as a concept',
            ),
          ],
        ),
        BitField(
          19,
          22,
          'Spatial Reuse 4',
          'One of four spatial-reuse fields',
          <Evidence>[
            _pSingleVendor,
            Evidence(
              'S2',
              EvidenceLevel.settled,
              scope: 'four fields, as a concept',
            ),
          ],
        ),
        BitField(23, 23, 'Reserved', 'Reserved', <Evidence>[_pSingleVendor]),
        BitField(24, 25, 'Bandwidth', 'Channel width', <Evidence>[
          _pSingleVendor,
        ]),
      ],
    ),
    BitGroup(
      title: 'HE-SIG-A2',
      bits: 26,
      modulation: 'BPSK',
      fields: <BitField>[
        BitField(0, 6, 'TXOP', 'By analogy with SU and MU', <Evidence>[_inf]),
        BitField(7, 15, 'Reserved', 'Reserved space', <Evidence>[_inf]),
        BitField(16, 19, 'CRC', '4-bit CRC', <Evidence>[_inf]),
        BitField(20, 25, 'Tail', 'Zero', <Evidence>[_inf]),
      ],
    ),
  ],
  notes: <TableNote>[
    TableNote(
      'HE-SIG-A1 from Intel\'s iwlwifi driver only. HE-SIG-A2 is inferred '
      'in full.',
      _pSingleVendor,
    ),
  ],
);

// ── HE-SIG-B (brief section 6) ─────────────────────────────────────────────

const SigTable kHeSigBTable = SigTable(
  title: 'HE-SIG-B',
  groupsAreAlternatives: true,
  groups: <BitGroup>[
    BitGroup(
      title: 'Common field, per content channel',
      bits: null,
      fields: <BitField>[
        BitField.unplaced(
          8,
          'RU Allocation',
          'One 8-bit subfield per 20 MHz handled by this content channel',
          <Evidence>[_s2],
        ),
        BitField.unplaced(
          1,
          'Center 26-tone RU',
          'At 80 MHz and wider',
          <Evidence>[_s2],
        ),
        BitField.unplaced(4, 'CRC', '4-bit CRC', <Evidence>[_inf]),
        BitField.unplaced(6, 'Tail', 'Zero', <Evidence>[_inf]),
      ],
    ),
    BitGroup(
      title: 'User field, non-MU-MIMO user (21 bits)',
      bits: 21,
      fields: <BitField>[
        BitField(0, 10, 'STA-ID', 'Station ID', <Evidence>[_pOneVendor]),
        BitField(11, 13, 'N_STS', 'Space-time streams', <Evidence>[
          _pOneVendor,
        ]),
        BitField(
          14,
          14,
          'Beamformed',
          'The only free bit; the driver header collides at B19',
          <Evidence>[_inf],
        ),
        BitField(15, 18, 'MCS', 'Per-user MCS', <Evidence>[_pOneVendor]),
        BitField(19, 19, 'DCM', 'Dual carrier modulation', <Evidence>[
          _pOneVendor,
        ]),
        BitField(20, 20, 'Coding', 'BCC or LDPC', <Evidence>[_pOneVendor]),
      ],
    ),
    BitGroup(
      title: 'User field, MU-MIMO user (21 bits)',
      bits: 21,
      fields: <BitField>[
        BitField(0, 10, 'STA-ID', 'Station ID', <Evidence>[_pOneVendor]),
        BitField(
          11,
          14,
          'Spatial Configuration',
          'Spatial configuration',
          <Evidence>[_pOneVendor],
        ),
        BitField(15, 18, 'MCS', 'Per-user MCS', <Evidence>[_pOneVendor]),
        BitField(19, 19, 'Reserved', 'Reserved', <Evidence>[_inf]),
        BitField(20, 20, 'Coding', 'BCC or LDPC', <Evidence>[_pOneVendor]),
      ],
    ),
  ],
  notes: <TableNote>[
    TableNote(
      'Two content channels (CC1, CC2) at 40 MHz and wider, each with its own '
      'common and user blocks. MCS 0-5, set in HE-SIG-A.',
      _p,
    ),
    TableNote(
      'User fields go two per user block with a shared CRC 4 and Tail 6. '
      'Positions from one vendor; Intel\'s driver confirms the same field set.',
      _pOneVendor,
    ),
    TableNote(
      'Symbol count method: common bits + ceil(users / 2) x (2 x 21 + 10) per '
      'content channel, divided by the bits per symbol at the SIG-B MCS.',
      _inf,
    ),
  ],
);

// ── U-SIG and EHT-SIG (brief section 7) ────────────────────────────────────

/// U-SIG for EHT MU, or EHT TB when [tb].
SigTable uSigTable({required bool tb}) => SigTable(
  title: tb ? 'U-SIG (EHT TB)' : 'U-SIG (EHT MU)',
  totalBits: 52,
  groups: <BitGroup>[
    BitGroup(
      title: 'U-SIG-1',
      bits: 26,
      modulation: 'BPSK',
      fields: <BitField>[
        const BitField(
          0,
          2,
          'PHY Version Identifier',
          '0 = EHT; other values mean a later PHY (802.11bn uses 1). '
              'Version-independent',
          <Evidence>[
            _s2plus,
            Evidence('S1', EvidenceLevel.singleSource, scope: '802.11bn = 1'),
          ],
        ),
        const BitField(
          3,
          5,
          'Bandwidth',
          '0/1/2/3 = 20/40/80/160; 4 = 320-1, 5 = 320-2. Version-independent',
          <Evidence>[_s2plus],
        ),
        const BitField(
          6,
          6,
          'UL/DL',
          'Uplink or downlink. Version-independent',
          <Evidence>[_s2plus],
        ),
        const BitField(
          7,
          12,
          'BSS Color',
          '6-bit BSS color. Version-independent',
          <Evidence>[_s2plus],
        ),
        const BitField(
          13,
          19,
          'TXOP',
          'TXOP duration. Version-independent',
          <Evidence>[_s2plus],
        ),
        if (tb)
          const BitField(
            20,
            25,
            'Disregard',
            'Version-dependent; TB treats B20-B25 as disregard',
            <Evidence>[_s2plus],
          )
        else ...const <BitField>[
          BitField(
            20,
            24,
            'Disregard',
            'Version-dependent. A receiver ignores disregard bits',
            <Evidence>[_s2plus],
          ),
          BitField(
            25,
            25,
            'Validate',
            'Version-dependent. An unexpected value stops decoding',
            <Evidence>[_s2plus],
          ),
        ],
      ],
    ),
    BitGroup(
      title: 'U-SIG-2',
      bits: 26,
      modulation: 'BPSK',
      fields: tb
          ? const <BitField>[
              BitField(0, 1, 'PPDU Type', 'PPDU type', <Evidence>[_s2plus]),
              BitField(2, 2, 'Validate', 'Validate', <Evidence>[_s2plus]),
              BitField(3, 6, 'Spatial Reuse 1', 'Spatial reuse', <Evidence>[
                _s2plus,
              ]),
              BitField(7, 10, 'Spatial Reuse 2', 'Spatial reuse', <Evidence>[
                _s2plus,
              ]),
              BitField(11, 15, 'Disregard', 'Disregard', <Evidence>[_s2plus]),
              BitField(16, 19, 'CRC', '4-bit CRC', <Evidence>[_s2plus]),
              BitField(20, 25, 'Tail', 'Zero', <Evidence>[_s2plus]),
            ]
          : const <BitField>[
              BitField(
                0,
                1,
                'PPDU Type and Compression Mode',
                'PPDU type and compression mode',
                <Evidence>[_s2plus],
              ),
              BitField(2, 2, 'Validate', 'Validate', <Evidence>[_s2plus]),
              BitField(
                3,
                7,
                'Punctured Channel Information',
                'Which 20 MHz subchannels are punctured',
                <Evidence>[_s2plus],
              ),
              BitField(8, 8, 'Validate', 'Validate', <Evidence>[_s2plus]),
              BitField(
                9,
                10,
                'EHT-SIG MCS',
                'Values 0-3 mean EHT-MCS 0, 1, 3, 15',
                <Evidence>[
                  _s2plus,
                  Evidence(
                    'S1',
                    EvidenceLevel.singleSource,
                    scope: 'MCS mapping',
                  ),
                ],
              ),
              BitField(
                11,
                15,
                'Number of EHT-SIG Symbols',
                'Whether this is the count or the count minus one is not '
                    'settled',
                <Evidence>[
                  _s2plus,
                  Evidence('INF', EvidenceLevel.inferred, scope: 'encoding'),
                ],
              ),
              BitField(16, 19, 'CRC', '4-bit CRC', <Evidence>[_s2plus]),
              BitField(20, 25, 'Tail', 'Zero', <Evidence>[_s2plus]),
            ],
    ),
  ],
  notes: const <TableNote>[
    TableNote(
      'The first 20 bits of U-SIG-1 are version-independent: a fixed header '
      'for every future PHY. BSS color sits at B7-B12 in every EHT PPDU.',
      _s2plus,
    ),
  ],
);

const SigTable kEhtSigTable = SigTable(
  title: 'EHT-SIG (summary)',
  groupsAreAlternatives: true,
  groups: <BitGroup>[
    BitGroup(
      title: 'Common field, non-OFDMA',
      bits: null,
      fields: <BitField>[
        BitField(0, 3, 'Spatial Reuse', 'Spatial reuse', <Evidence>[
          Evidence('S2', EvidenceLevel.settled, scope: 'order'),
          _pOneVendor,
        ]),
        BitField(
          4,
          5,
          'GI + LTF Size',
          'Guard interval and EHT-LTF size',
          <Evidence>[
            Evidence('S2', EvidenceLevel.settled, scope: 'order'),
            _pOneVendor,
          ],
        ),
        BitField(6, 8, 'Number of EHT-LTF Symbols', 'EHT-LTF count', <Evidence>[
          Evidence('S2', EvidenceLevel.settled, scope: 'order'),
          _pOneVendor,
        ]),
        BitField(
          9,
          9,
          'LDPC Extra Symbol Segment',
          'LDPC extra symbol segment',
          <Evidence>[
            Evidence('S2', EvidenceLevel.settled, scope: 'order'),
            _pOneVendor,
          ],
        ),
        BitField(
          10,
          11,
          'Pre-FEC Padding Factor',
          'Pre-FEC padding factor',
          <Evidence>[
            Evidence('S2', EvidenceLevel.settled, scope: 'order'),
            _pOneVendor,
          ],
        ),
        BitField(
          12,
          12,
          'PE Disambiguity',
          'Packet extension disambiguity',
          <Evidence>[
            Evidence('S2', EvidenceLevel.settled, scope: 'order'),
            _pOneVendor,
          ],
        ),
        BitField(13, 16, 'Disregard', 'Disregard', <Evidence>[
          Evidence('S2', EvidenceLevel.settled, scope: 'order'),
          _pOneVendor,
        ]),
        BitField(
          17,
          19,
          'Number of Non-OFDMA Users',
          'Users in a non-OFDMA PPDU',
          <Evidence>[
            Evidence('S2', EvidenceLevel.settled, scope: 'order'),
            _pOneVendor,
          ],
        ),
      ],
    ),
    BitGroup(
      title: 'User field, non-MU-MIMO (field level only)',
      bits: null,
      fields: <BitField>[
        BitField.unplaced(11, 'STA-ID', 'Station ID', <Evidence>[
          _pSingleVendor,
        ]),
        BitField.unplaced(4, 'MCS', 'Per-user MCS', <Evidence>[_pSingleVendor]),
        BitField.unplaced(4, 'N_SS', 'Spatial streams', <Evidence>[
          _pSingleVendor,
        ]),
        BitField.unplaced(1, 'Beamformed', 'Beamformed', <Evidence>[
          _pSingleVendor,
        ]),
        BitField.unplaced(1, 'Coding', 'BCC or LDPC', <Evidence>[
          _pSingleVendor,
        ]),
      ],
    ),
    BitGroup(
      title: 'User field, MU-MIMO (field level only)',
      bits: null,
      fields: <BitField>[
        BitField.unplaced(11, 'STA-ID', 'Station ID', <Evidence>[
          _pSingleVendor,
        ]),
        BitField.unplaced(4, 'MCS', 'Per-user MCS', <Evidence>[_pSingleVendor]),
        BitField.unplaced(1, 'Coding', 'BCC or LDPC', <Evidence>[
          _pSingleVendor,
        ]),
        BitField.unplaced(
          6,
          'Spatial Configuration',
          'Spatial configuration',
          <Evidence>[_pSingleVendor],
        ),
      ],
    ),
  ],
  notes: <TableNote>[
    TableNote(
      'The common field ends with a CRC and Tail; the brief gives no widths '
      'for them here.',
      _untagged,
    ),
    TableNote(
      'OFDMA PPDUs add 9-bit RU Allocation subfields (HE used 8).',
      _pSingleVendor,
    ),
  ],
);

// ── PPDU types, blocks and durations (brief section 1) ─────────────────────

/// The PPDU formats this reference draws.
enum PpduType {
  nonHt('Legacy (non-HT)', 'Legacy', 'Non-HT OFDM, 802.11a/g'),
  htMixed('HT mixed (802.11n)', 'HT', 'HT mixed format, 802.11n'),
  vht('VHT (802.11ac)', 'VHT', 'VHT, 802.11ac'),
  heSu('HE SU (802.11ax)', 'HE SU', 'HE single user, 802.11ax'),
  heErSu('HE ER SU (802.11ax)', 'HE ER SU', 'HE extended range single user'),
  heMu('HE MU (802.11ax)', 'HE MU', 'HE multi-user, downlink OFDMA or MU-MIMO'),
  heTb(
    'HE TB (802.11ax)',
    'HE TB',
    'HE trigger-based, the uplink response to a trigger',
  ),
  ehtMu('EHT MU (802.11be)', 'EHT MU', 'EHT multi-user, 802.11be'),
  ehtTb('EHT TB (802.11be)', 'EHT TB', 'EHT trigger-based, 802.11be');

  const PpduType(this.label, this.shortLabel, this.description);

  final String label;
  final String shortLabel;
  final String description;

  bool get isHe =>
      this == heSu || this == heErSu || this == heMu || this == heTb;
  bool get isEht => this == ehtMu || this == ehtTb;

  /// HE and EHT: an HE-LTF / EHT-LTF size and guard interval apply.
  bool get hasHeLtf => isHe || isEht;

  /// Streams the controls offer: HT stops at 4, non-HT has none.
  int get maxStreams => switch (this) {
    nonHt => 1,
    htMixed => 4,
    _ => 8,
  };

  /// HE MU carries HE-SIG-B, EHT MU carries EHT-SIG; both have a symbol count.
  bool get hasSigBSymbols => this == heMu || this == ehtMu;

  /// Where the width changes the tables (VHT-SIG-B only).
  bool get widthChangesLayout => this == vht;
}

/// LTF size and guard interval for HE and EHT. The brief lists these four
/// pairs for EHT (S1); HE-LTF durations are 3.2, 6.4 or 12.8 us plus GI.
enum HeLtfMode {
  x2gi08(2, 8, '2x, 0.8 µs GI'),
  x2gi16(2, 16, '2x, 1.6 µs GI'),
  x4gi08(4, 8, '4x, 0.8 µs GI'),
  x4gi32(4, 32, '4x, 3.2 µs GI');

  const HeLtfMode(this.size, this.giTenths, this.label);

  /// 2 or 4 (the "x" size).
  final int size;

  final int giTenths;
  final String label;

  /// One LTF symbol, tenths of a us: 3.2 us x size, plus GI.
  int get ltfTenths => 32 * size + giTenths;
}

/// What part of the preamble a block belongs to.
enum BlockRole {
  /// L-STF, L-LTF, L-SIG: the 20 us every PHY sends.
  legacy,

  /// A field the PHY adds after L-SIG.
  added,

  /// The start of the Data field (not to scale).
  data,
}

/// Signal field (bits you can read) or training field (a known pattern).
enum BlockForm { signal, training, data }

/// Constellation of one SIG symbol, as a receiver sees it.
enum SymbolModulation {
  bpsk('BPSK', 'B'),
  qbpsk('QBPSK', 'Q');

  const SymbolModulation(this.label, this.letter);

  final String label;
  final String letter;
}

/// One labeled block of the preamble.
class PreambleBlock {
  const PreambleBlock({
    required this.name,
    required this.shortName,
    required this.role,
    required this.form,
    required this.count,
    required this.unitTenths,
    required this.durationNote,
    required this.durationEvidence,
    required this.purpose,
    this.modulations = const <SymbolModulation>[],
    this.modulationNote,
    this.table,
    this.countEvidence,
  });

  final String name;

  /// Used when [name] does not fit.
  final String shortName;

  final BlockRole role;
  final BlockForm form;

  /// Symbols (SIG) or repeats (LTFs). 1 for single fields.
  final int count;

  /// One symbol or repeat, tenths of a us.
  final int unitTenths;

  /// "10 x 0.8 µs".
  final String durationNote;

  final List<Evidence> durationEvidence;

  /// What the field is for, one or two sentences.
  final String purpose;

  /// BPSK or QBPSK per symbol, for SIG fields sent that way.
  final List<SymbolModulation> modulations;

  /// For SIG fields whose modulation is an MCS, not BPSK or QBPSK.
  final String? modulationNote;

  /// The bit table this block opens.
  final SigTable? table;

  /// For LTFs: where the repeat count comes from.
  final Evidence? countEvidence;

  int get tenths => count * unitTenths;
  double get us => tenths / 10;

  /// False for the Data stub, which is drawn at a fixed width.
  bool get isToScale => role != BlockRole.data;

  /// Every tag on the duration and count is settled.
  bool get timingSettled =>
      durationEvidence.every((Evidence e) => e.isSettled) &&
      (countEvidence?.isSettled ?? true);
}

/// Everything the controls set.
class PreambleSettings {
  const PreambleSettings({
    this.type = PpduType.heSu,
    this.streams = 1,
    this.ltf = HeLtfMode.x2gi08,
    this.widthMhz = 20,
    this.sigSymbols = 2,
  }) : assert(streams >= 1 && streams <= 8),
       assert(sigSymbols >= 1 && sigSymbols <= kMaxSigSymbols);

  final PpduType type;

  /// Spatial streams (N_STS). HT: 1-4; VHT, HE, EHT: 1-8. Ignored for non-HT.
  final int streams;

  /// HE and EHT only.
  final HeLtfMode ltf;

  /// 20, 40, 80 or 160. Changes only VHT-SIG-B's layout.
  final int widthMhz;

  /// HE-SIG-B symbols (HE MU) or EHT-SIG symbols (EHT MU), set by the AP.
  final int sigSymbols;

  PreambleSettings copyWith({
    PpduType? type,
    int? streams,
    HeLtfMode? ltf,
    int? widthMhz,
    int? sigSymbols,
  }) => PreambleSettings(
    type: type ?? this.type,
    streams: streams ?? this.streams,
    ltf: ltf ?? this.ltf,
    widthMhz: widthMhz ?? this.widthMhz,
    sigSymbols: sigSymbols ?? this.sigSymbols,
  );

  /// Streams clamped to what [type] allows.
  int get effectiveStreams => streams.clamp(1, type.maxStreams);

  @override
  bool operator ==(Object other) =>
      other is PreambleSettings &&
      other.type == type &&
      other.streams == streams &&
      other.ltf == ltf &&
      other.widthMhz == widthMhz &&
      other.sigSymbols == sigSymbols;

  @override
  int get hashCode => Object.hash(type, streams, ltf, widthMhz, sigSymbols);
}

/// Most HE-SIG-B or EHT-SIG symbols the controls offer.
const int kMaxSigSymbols = 12;

/// Channel widths the controls offer.
const List<int> kPreambleWidthsMhz = <int>[20, 40, 80, 160];

/// HT-LTFs by space-time streams: 1, 2, 4, 4 (brief section 1, S1).
const Map<int, int> kHtLtfCount = <int, int>{1: 1, 2: 2, 3: 4, 4: 4};

/// VHT, HE and EHT LTFs by streams. 1-4 as HT; 5-8 (6, 6, 8, 8) from memory
/// in the brief, not verified. Same table as the Airtime Anatomy service.
const Map<int, int> kVhtLtfCount = <int, int>{
  1: 1,
  2: 2,
  3: 4,
  4: 4,
  5: 6,
  6: 6,
  7: 8,
  8: 8,
};

/// LTF repeats for [s], with where the count comes from.
({int count, Evidence evidence}) ltfCountFor(PreambleSettings s) {
  final int n = s.effectiveStreams;
  switch (s.type) {
    case PpduType.nonHt:
      return (count: 0, evidence: _s2);
    case PpduType.htMixed:
      return (count: kHtLtfCount[n]!, evidence: _s1);
    case PpduType.vht:
      return (
        count: kVhtLtfCount[n]!,
        evidence: n <= 4
            ? const Evidence(
                'S1',
                EvidenceLevel.singleSource,
                scope: 'HT table, same for 1 to 4 streams',
              )
            : _notVerified,
      );
    case PpduType.heSu:
    case PpduType.heErSu:
    case PpduType.heMu:
    case PpduType.heTb:
    case PpduType.ehtMu:
    case PpduType.ehtTb:
      // The brief gives no HE or EHT LTF count; the table is the one the
      // Airtime Anatomy service uses.
      return (
        count: kVhtLtfCount[n]!,
        evidence: n <= 4
            ? const Evidence(
                'INF',
                EvidenceLevel.inferred,
                scope: 'count taken from the VHT table',
              )
            : _notVerified,
      );
  }
}

// Block builders.

const PreambleBlock _lStf = PreambleBlock(
  name: 'L-STF',
  // Never a bare STF: inside the legacy part it reads like HE-STF.
  shortName: 'L-STF',
  role: BlockRole.legacy,
  form: BlockForm.training,
  count: 1,
  unitTenths: 80,
  durationNote: '10 x 0.8 µs',
  durationEvidence: <Evidence>[_s2],
  purpose:
      'Legacy short training field: ten repeats of a 0.8 µs pattern. The '
      'receiver detects that a packet has started and sets its gain.',
);

const PreambleBlock _lLtf = PreambleBlock(
  name: 'L-LTF',
  shortName: 'L-LTF',
  role: BlockRole.legacy,
  form: BlockForm.training,
  count: 1,
  unitTenths: 80,
  durationNote: '1.6 µs GI + 2 x 3.2 µs',
  durationEvidence: <Evidence>[_s2],
  purpose:
      'Legacy long training field: a known pattern the receiver uses to '
      'estimate the channel before it decodes L-SIG.',
);

PreambleBlock _lSig() => PreambleBlock(
  name: 'L-SIG',
  shortName: 'L-SIG',
  role: BlockRole.legacy,
  form: BlockForm.signal,
  count: 1,
  unitTenths: 40,
  durationNote: 'one symbol, BPSK 1/2 (6 Mb/s)',
  durationEvidence: const <Evidence>[_s2],
  modulations: const <SymbolModulation>[SymbolModulation.bpsk],
  purpose:
      'Rate and length in one BPSK symbol that every radio since 802.11a can '
      'decode. From L-SIG alone a legacy radio works out how long to defer.',
  table: kLsigTable,
);

PreambleBlock _data(PpduType t) => PreambleBlock(
  name: 'Data',
  shortName: 'Data',
  role: BlockRole.data,
  form: BlockForm.data,
  count: 1,
  unitTenths: 0,
  durationNote: 'continues; not drawn to scale',
  durationEvidence: const <Evidence>[],
  purpose:
      'The Data field starts with the 16-bit SERVICE field, then the PSDU.'
      '${t.isHe || t.isEht ? ' A packet extension (PE) may follow the data: 0 to 16 µs in HE, up to 20 µs in EHT.' : ''}',
  table: serviceTable(vht: t == PpduType.vht),
);

/// Every block of the preamble for [s], in transmit order, ending with a
/// Data stub.
List<PreambleBlock> preambleBlocks(PreambleSettings s) {
  final PpduType t = s.type;
  final ({int count, Evidence evidence}) ltf = ltfCountFor(s);
  final List<PreambleBlock> out = <PreambleBlock>[_lStf, _lLtf, _lSig()];

  switch (t) {
    case PpduType.nonHt:
      break;
    case PpduType.htMixed:
      out.addAll(<PreambleBlock>[
        const PreambleBlock(
          name: 'HT-SIG',
          shortName: 'SIG',
          role: BlockRole.added,
          form: BlockForm.signal,
          count: 2,
          unitTenths: 40,
          durationNote: '2 symbols x 4 µs, both QBPSK',
          durationEvidence: <Evidence>[_s2],
          modulations: <SymbolModulation>[
            SymbolModulation.qbpsk,
            SymbolModulation.qbpsk,
          ],
          purpose:
              'MCS, width, length and coding for 802.11n. Both symbols are '
              'QBPSK, rotated 90 degrees from BPSK, which is how an HT '
              'receiver spots HT at the first symbol after L-SIG.',
          table: kHtSigTable,
        ),
        const PreambleBlock(
          name: 'HT-STF',
          shortName: 'STF',
          role: BlockRole.added,
          form: BlockForm.training,
          count: 1,
          unitTenths: 40,
          durationNote: '4 µs',
          durationEvidence: <Evidence>[_s2],
          purpose: 'HT short training field: resets gain for the MIMO part.',
        ),
        PreambleBlock(
          name: 'HT-LTF',
          shortName: 'LTF',
          role: BlockRole.added,
          form: BlockForm.training,
          count: ltf.count,
          unitTenths: 40,
          durationNote: '${ltf.count} x 4 µs',
          durationEvidence: const <Evidence>[_s2],
          countEvidence: ltf.evidence,
          purpose:
              'HT long training fields, one per stream group: 1, 2, 4, 4 for '
              '1 to 4 streams (three streams need four). The receiver '
              'estimates each stream\'s channel from them.',
        ),
      ]);
    case PpduType.vht:
      out.addAll(<PreambleBlock>[
        const PreambleBlock(
          name: 'VHT-SIG-A',
          shortName: 'SIG-A',
          role: BlockRole.added,
          form: BlockForm.signal,
          count: 2,
          unitTenths: 40,
          durationNote: '2 symbols x 4 µs: BPSK, then QBPSK',
          durationEvidence: <Evidence>[_s2],
          modulations: <SymbolModulation>[
            SymbolModulation.bpsk,
            SymbolModulation.qbpsk,
          ],
          purpose:
              'Width, streams, group ID, MCS and coding for 802.11ac. The '
              'second symbol is QBPSK: an HT receiver sees BPSK first and '
              'does not mistake it for HT.',
          table: kVhtSigATable,
        ),
        const PreambleBlock(
          name: 'VHT-STF',
          shortName: 'STF',
          role: BlockRole.added,
          form: BlockForm.training,
          count: 1,
          unitTenths: 40,
          durationNote: '4 µs',
          durationEvidence: <Evidence>[_s2],
          purpose: 'VHT short training field: resets gain for the MIMO part.',
        ),
        PreambleBlock(
          name: 'VHT-LTF',
          shortName: 'LTF',
          role: BlockRole.added,
          form: BlockForm.training,
          count: ltf.count,
          unitTenths: 40,
          durationNote: '${ltf.count} x 4 µs',
          durationEvidence: const <Evidence>[_s2],
          countEvidence: ltf.evidence,
          purpose:
              'VHT long training fields, one per stream group, for channel '
              'estimation.',
        ),
        PreambleBlock(
          name: 'VHT-SIG-B',
          shortName: 'SIG-B',
          role: BlockRole.added,
          form: BlockForm.signal,
          count: 1,
          unitTenths: 40,
          durationNote: 'one BPSK symbol',
          durationEvidence: const <Evidence>[_s2],
          modulations: const <SymbolModulation>[SymbolModulation.bpsk],
          purpose:
              'Per-user length (and MCS for MU). Its layout depends on the '
              'channel width, and its CRC rides in the SERVICE field.',
          table: vhtSigBTable(s.widthMhz),
        ),
      ]);
    case PpduType.heSu:
    case PpduType.heErSu:
    case PpduType.heMu:
    case PpduType.heTb:
      final bool er = t == PpduType.heErSu;
      out.add(_rlSig(_pS2));
      out.add(
        PreambleBlock(
          name: 'HE-SIG-A',
          shortName: 'SIG-A',
          role: BlockRole.added,
          form: BlockForm.signal,
          count: er ? 4 : 2,
          unitTenths: 40,
          durationNote: er
              ? '4 symbols x 4 µs: BPSK, QBPSK, BPSK, BPSK'
              : '2 symbols x 4 µs, both BPSK',
          durationEvidence: <Evidence>[er ? _s2 : _pS2],
          modulations: er
              ? const <SymbolModulation>[
                  SymbolModulation.bpsk,
                  SymbolModulation.qbpsk,
                  SymbolModulation.bpsk,
                  SymbolModulation.bpsk,
                ]
              : const <SymbolModulation>[
                  SymbolModulation.bpsk,
                  SymbolModulation.bpsk,
                ],
          purpose: switch (t) {
            PpduType.heErSu =>
              'The single-user HE-SIG-A, sent twice as long for range. Its '
                  'second symbol is QBPSK.',
            PpduType.heMu =>
              'Common information for a multi-user PPDU: BSS color, '
                  'bandwidth, and how HE-SIG-B is sent.',
            PpduType.heTb =>
              'The uplink response to a trigger: BSS color, four spatial '
                  'reuse fields and bandwidth.',
            _ =>
              'MCS, BSS color, width, streams and coding for one user. Both '
                  'symbols are BPSK.',
          },
          table: switch (t) {
            PpduType.heMu => kHeSigAMuTable,
            PpduType.heTb => kHeSigATbTable,
            _ => heSigASuTable(erSu: er),
          },
        ),
      );
      if (t == PpduType.heMu) {
        out.add(
          PreambleBlock(
            name: 'HE-SIG-B',
            shortName: 'SIG-B',
            role: BlockRole.added,
            form: BlockForm.signal,
            count: s.sigSymbols,
            unitTenths: 40,
            durationNote: '${s.sigSymbols} x 4 µs (count set by the AP)',
            durationEvidence: const <Evidence>[_pS2],
            modulationNote: 'Sent at HE-SIG-B MCS 0-5, set in HE-SIG-A',
            purpose:
                'Who gets which resource unit: RU allocation, then one user '
                'field per station.',
            table: kHeSigBTable,
          ),
        );
      }
      out.add(
        PreambleBlock(
          name: 'HE-STF',
          shortName: 'STF',
          role: BlockRole.added,
          form: BlockForm.training,
          count: 1,
          unitTenths: t == PpduType.heTb ? 80 : 40,
          durationNote: t == PpduType.heTb ? '8 µs in HE TB' : '4 µs',
          durationEvidence: const <Evidence>[_pS2],
          purpose: t == PpduType.heTb
              ? 'HE short training field, twice as long in a trigger-based '
                    'PPDU.'
              : 'HE short training field: resets gain for the HE part.',
        ),
      );
      out.add(
        PreambleBlock(
          name: 'HE-LTF',
          shortName: 'LTF',
          role: BlockRole.added,
          form: BlockForm.training,
          count: ltf.count,
          unitTenths: s.ltf.ltfTenths,
          durationNote:
              '${ltf.count} x ${_fmtTenths(s.ltf.ltfTenths)} µs '
              '(${s.ltf.size}x = ${_fmtTenths(32 * s.ltf.size)} µs + '
              '${_fmtTenths(s.ltf.giTenths)} µs GI)',
          // The HE row gives the lengths (P/S2), not the legal pairs. 4x with
          // a 0.8 us GI is taken from the brief's EHT list (S1); the Airtime
          // Anatomy service offers the other three for HE.
          durationEvidence: s.ltf == HeLtfMode.x4gi08
              ? const <Evidence>[
                  _pS2,
                  Evidence(
                    'S1',
                    EvidenceLevel.singleSource,
                    scope: '4x with 0.8 µs GI, from the EHT list',
                  ),
                ]
              : const <Evidence>[_pS2],
          countEvidence: ltf.evidence,
          purpose:
              'HE long training fields, one per stream group. Their length '
              'follows the LTF size and guard interval.',
        ),
      );
    case PpduType.ehtMu:
    case PpduType.ehtTb:
      final bool tb = t == PpduType.ehtTb;
      final Evidence e = tb ? _s1 : _s2;
      out.add(_rlSig(e));
      out.add(
        PreambleBlock(
          name: 'U-SIG',
          shortName: 'U-SIG',
          role: BlockRole.added,
          form: BlockForm.signal,
          count: 2,
          unitTenths: 40,
          durationNote: '2 symbols x 4 µs, both BPSK',
          durationEvidence: <Evidence>[e],
          modulations: const <SymbolModulation>[
            SymbolModulation.bpsk,
            SymbolModulation.bpsk,
          ],
          purpose:
              'The universal SIG: its first 20 bits (version, bandwidth, '
              'UL/DL, BSS color, TXOP) keep the same place in every PHY from '
              'EHT on.',
          table: uSigTable(tb: tb),
        ),
      );
      if (!tb) {
        out.add(
          PreambleBlock(
            name: 'EHT-SIG',
            shortName: 'EHT-SIG',
            role: BlockRole.added,
            form: BlockForm.signal,
            count: s.sigSymbols,
            unitTenths: 40,
            durationNote: '${s.sigSymbols} x 4 µs (count set by the AP)',
            durationEvidence: const <Evidence>[_s2],
            modulationNote: 'Sent at the EHT-SIG MCS given in U-SIG',
            purpose:
                'Common field and per-user fields for the multi-user PPDU. '
                'Field level only here.',
            table: kEhtSigTable,
          ),
        );
      }
      out.add(
        PreambleBlock(
          name: 'EHT-STF',
          shortName: 'STF',
          role: BlockRole.added,
          form: BlockForm.training,
          count: 1,
          unitTenths: tb ? 80 : 40,
          durationNote: tb ? '8 µs in EHT TB' : '4 µs',
          durationEvidence: <Evidence>[e],
          purpose: tb
              ? 'EHT short training field, twice as long in a trigger-based '
                    'PPDU.'
              : 'EHT short training field: resets gain for the EHT part.',
        ),
      );
      out.add(
        PreambleBlock(
          name: 'EHT-LTF',
          shortName: 'LTF',
          role: BlockRole.added,
          form: BlockForm.training,
          count: ltf.count,
          unitTenths: s.ltf.ltfTenths,
          durationNote:
              '${ltf.count} x ${_fmtTenths(s.ltf.ltfTenths)} µs '
              '(${s.ltf.size}x = ${_fmtTenths(32 * s.ltf.size)} µs + '
              '${_fmtTenths(s.ltf.giTenths)} µs GI)',
          // The brief says "EHT-LTF variable" and pairs 2x with 0.8 or 1.6 us
          // GI and 4x with 0.8 or 3.2 (S1). The per-symbol length is taken
          // from HE by analogy.
          durationEvidence: const <Evidence>[
            Evidence(
              'S1',
              EvidenceLevel.singleSource,
              scope: 'size and GI pairs',
            ),
            Evidence('INF', EvidenceLevel.inferred, scope: 'length, as HE'),
          ],
          countEvidence: ltf.evidence,
          purpose: 'EHT long training fields, one per stream group, 2x or 4x.',
        ),
      );
  }
  out.add(_data(t));
  return List<PreambleBlock>.unmodifiable(out);
}

PreambleBlock _rlSig(Evidence e) => PreambleBlock(
  name: 'RL-SIG',
  shortName: 'RL',
  role: BlockRole.added,
  form: BlockForm.signal,
  count: 1,
  unitTenths: 40,
  durationNote: 'one BPSK symbol, a repeat of L-SIG',
  durationEvidence: <Evidence>[e],
  modulations: const <SymbolModulation>[SymbolModulation.bpsk],
  purpose:
      'Repeated L-SIG: the same bits again. The exact repeat is how a '
      'receiver spots HE and EHT.',
  table: kLsigTable,
);

/// Preamble total (everything before Data), tenths of a microsecond.
int preambleTenths(PreambleSettings s) => preambleBlocks(s)
    .where((PreambleBlock b) => b.isToScale)
    .fold<int>(0, (int a, PreambleBlock b) => a + b.tenths);

/// The legacy part every PHY sends, tenths of a us.
const int kLegacyPreambleTenths = 200;

// ── L-SIG LENGTH spoofing (brief section 2) ────────────────────────────────

/// Largest value a 12-bit LENGTH can hold.
const int kMaxLsigLength = 4095;

/// Signal extension at 2.4 GHz, us (ERP-OFDM and later).
const int kSignalExtensionUs = 6;

/// The m subtracted in the HE formula. HT, VHT and EHT use 0.
int lsigM(PpduType t) => switch (t) {
  PpduType.heMu || PpduType.heErSu => 1,
  PpduType.heSu || PpduType.heTb => 2,
  _ => 0,
};

/// Evidence for the LENGTH rule of [t].
List<Evidence> lsigRuleEvidence(PpduType t) {
  if (t.isHe) return const <Evidence>[_s2];
  if (t.isEht) {
    return const <Evidence>[
      Evidence('S1', EvidenceLevel.singleSource, scope: 'LENGTH mod 3 = 0'),
      Evidence('INF', EvidenceLevel.inferred, scope: 'm = 0'),
    ];
  }
  return const <Evidence>[
    Evidence('S1', EvidenceLevel.singleSource, scope: 'printed formula'),
    Evidence('INF', EvidenceLevel.inferred, scope: 'proof'),
  ];
}

/// Why a TXTIME cannot be signalled.
enum LsigLengthError {
  /// Non-HT: LENGTH is octets, nothing is spoofed.
  notSpoofed,

  /// Shorter than the PPDU's own preamble.
  shorterThanPreamble,

  /// LENGTH would pass 4095.
  tooLong,
}

/// One LENGTH calculation.
class LsigLengthResult {
  const LsigLengthResult._({
    required this.txtimeTenths,
    required this.signalExtensionUs,
    required this.m,
    required this.k,
    required this.length,
    required this.legacySymbols,
    this.error,
  });

  final int txtimeTenths;
  final int signalExtensionUs;

  /// 0 for HT, VHT and EHT; 1 or 2 for HE.
  final int m;

  /// ceil((TXTIME - SE - 20) / 4): 4 us symbols after L-SIG.
  final int k;

  /// The spoofed L-SIG LENGTH.
  final int length;

  /// N_SYM a legacy radio computes at 6 Mb/s: ceil((16 + 8 x LENGTH + 6) / 24).
  final int legacySymbols;

  final LsigLengthError? error;

  bool get ok => error == null;

  int get lengthMod3 => length % 3;

  /// How long after L-SIG a legacy radio defers, us.
  int get deferAfterLsigUs => 4 * legacySymbols;

  /// From the start of the PPDU: 20 us of legacy preamble, the symbols it
  /// counts, and the signal extension at 2.4 GHz. Tenths of a us.
  int get legacyDeferTenths => (20 + deferAfterLsigUs + signalExtensionUs) * 10;
}

/// N_SYM a legacy radio derives from [length] at 6 Mb/s (3 octets per 4 us
/// symbol): ceil((16 + 8 x LENGTH + 6) / 24).
int legacySymbolsFor(int length) => _ceilDiv(16 + 8 * length + 6, 24);

/// The spoofed L-SIG LENGTH for a PPDU of [txtimeTenths] (true duration,
/// tenths of a us) of type [t]:
/// LENGTH = ceil((TXTIME - SE - 20) / 4) x 3 - 3 - m.
LsigLengthResult spoofLsigLength({
  required int txtimeTenths,
  required PpduType type,
  required int preambleTenthsOfType,
  int signalExtensionUs = 0,
}) {
  final int m = lsigM(type);
  LsigLengthResult fail(LsigLengthError e) => LsigLengthResult._(
    txtimeTenths: txtimeTenths,
    signalExtensionUs: signalExtensionUs,
    m: m,
    k: 0,
    length: 0,
    legacySymbols: 0,
    error: e,
  );
  if (type == PpduType.nonHt) return fail(LsigLengthError.notSpoofed);
  if (txtimeTenths - signalExtensionUs * 10 < preambleTenthsOfType) {
    return fail(LsigLengthError.shorterThanPreamble);
  }
  final int k = _ceilDiv(txtimeTenths - signalExtensionUs * 10 - 200, 40);
  final int length = k * 3 - 3 - m;
  if (length > kMaxLsigLength) {
    return LsigLengthResult._(
      txtimeTenths: txtimeTenths,
      signalExtensionUs: signalExtensionUs,
      m: m,
      k: k,
      length: length,
      legacySymbols: legacySymbolsFor(length),
      error: LsigLengthError.tooLong,
    );
  }
  return LsigLengthResult._(
    txtimeTenths: txtimeTenths,
    signalExtensionUs: signalExtensionUs,
    m: m,
    k: k,
    length: length,
    legacySymbols: legacySymbolsFor(length),
  );
}

/// Longest TXTIME (tenths of a us, before signal extension) whose LENGTH
/// still fits 12 bits, for [m]. INF: 3k - 3 - m <= 4095.
int maxTxtimeTenths(int m) {
  final int k = (kMaxLsigLength + 3 + m) ~/ 3;
  return (20 + 4 * k) * 10;
}

// ── Which PHY is this? (brief section 8) ───────────────────────────────────

/// What a receiver can see after L-STF, L-LTF and L-SIG.
enum SymbolLook {
  bpsk('BPSK'),
  qbpsk('QBPSK'),

  /// A data symbol: whatever the MCS gives, not the rotated QBPSK.
  data('a data symbol, not QBPSK');

  const SymbolLook(this.label);

  final String label;
}

/// The facts the decision tree reads.
class PpduObservation {
  const PpduObservation({
    required this.firstAfterLsig,
    required this.repeatsLsig,
    required this.secondAfterLsig,
    required this.lengthMod3,
    this.heSigA1B0,
    this.secondHeSigA,
    this.uSigVersion,
  });

  final SymbolLook firstAfterLsig;
  final bool repeatsLsig;
  final SymbolLook secondAfterLsig;
  final int lengthMod3;
  final int? heSigA1B0;
  final SymbolLook? secondHeSigA;
  final int? uSigVersion;
}

/// What the receiver sees for [t].
PpduObservation observe(PpduType t) {
  final int mod3 = (3 - lsigM(t)) % 3;
  switch (t) {
    case PpduType.nonHt:
      return const PpduObservation(
        firstAfterLsig: SymbolLook.data,
        repeatsLsig: false,
        secondAfterLsig: SymbolLook.data,
        lengthMod3: 0,
      );
    case PpduType.htMixed:
      return PpduObservation(
        firstAfterLsig: SymbolLook.qbpsk,
        repeatsLsig: false,
        secondAfterLsig: SymbolLook.qbpsk,
        lengthMod3: mod3,
      );
    case PpduType.vht:
      return PpduObservation(
        firstAfterLsig: SymbolLook.bpsk,
        repeatsLsig: false,
        secondAfterLsig: SymbolLook.qbpsk,
        lengthMod3: mod3,
      );
    case PpduType.heSu:
    case PpduType.heTb:
    case PpduType.heMu:
    case PpduType.heErSu:
      return PpduObservation(
        firstAfterLsig: SymbolLook.bpsk,
        repeatsLsig: true,
        secondAfterLsig: SymbolLook.bpsk,
        lengthMod3: mod3,
        heSigA1B0: switch (t) {
          PpduType.heSu || PpduType.heErSu => 1,
          PpduType.heTb => 0,
          _ => null,
        },
        secondHeSigA: t == PpduType.heErSu ? SymbolLook.qbpsk : SymbolLook.bpsk,
      );
    case PpduType.ehtMu:
    case PpduType.ehtTb:
      return PpduObservation(
        firstAfterLsig: SymbolLook.bpsk,
        repeatsLsig: true,
        secondAfterLsig: SymbolLook.bpsk,
        lengthMod3: mod3,
        uSigVersion: 0,
      );
  }
}

/// Where the decision tree ends.
enum DetectedFormat {
  nonHt('Non-HT (legacy OFDM)'),
  htMixed('HT mixed'),
  vht('VHT'),
  heSu('HE SU'),
  heTb('HE TB'),
  heMu('HE MU'),
  heErSu('HE ER SU'),
  eht('EHT'),
  laterThanEht('A PHY later than EHT');

  const DetectedFormat(this.label);

  final String label;

  /// The format the tree should reach for [t].
  static DetectedFormat expectedFor(PpduType t) => switch (t) {
    PpduType.nonHt => nonHt,
    PpduType.htMixed => htMixed,
    PpduType.vht => vht,
    PpduType.heSu => heSu,
    PpduType.heErSu => heErSu,
    PpduType.heMu => heMu,
    PpduType.heTb => heTb,
    PpduType.ehtMu || PpduType.ehtTb => eht,
  };
}

/// One question the receiver asks, with what it saw and where it goes.
class DecisionStep {
  const DecisionStep({
    required this.question,
    required this.answer,
    required this.conclusion,
    required this.evidence,
  });

  final String question;
  final String answer;
  final String conclusion;
  final Evidence evidence;
}

/// The receiver's walk for one PPDU.
class Classification {
  const Classification(this.steps, this.result);

  final List<DecisionStep> steps;
  final DetectedFormat result;
}

/// Walks the brief's section 8 decision tree. All of it happens after L-STF,
/// L-LTF and L-SIG are decoded.
Classification classify(PpduObservation o) {
  final List<DecisionStep> steps = <DecisionStep>[];
  if (o.firstAfterLsig == SymbolLook.qbpsk) {
    steps.add(
      const DecisionStep(
        question: 'Is the first symbol after L-SIG QBPSK?',
        answer: 'Yes, QBPSK.',
        conclusion: 'HT mixed format: that symbol is HT-SIG1.',
        evidence: _s2,
      ),
    );
    return Classification(steps, DetectedFormat.htMixed);
  }
  steps.add(
    DecisionStep(
      question: 'Is the first symbol after L-SIG QBPSK?',
      answer: 'No, ${o.firstAfterLsig.label}.',
      conclusion: 'Not HT. Check whether it repeats L-SIG.',
      evidence: _s2,
    ),
  );
  if (o.repeatsLsig) {
    steps.add(
      const DecisionStep(
        question: 'Does it repeat L-SIG exactly?',
        answer: 'Yes: it is RL-SIG.',
        conclusion: 'HE or EHT. Read L-SIG LENGTH mod 3.',
        evidence: _s2,
      ),
    );
    switch (o.lengthMod3) {
      case 1:
        final bool su = o.heSigA1B0 == 1;
        steps.add(
          const DecisionStep(
            question: 'L-SIG LENGTH mod 3?',
            answer: 'LENGTH mod 3 = 1.',
            conclusion: 'HE SU or HE TB. Read HE-SIG-A1 B0.',
            evidence: _s2,
          ),
        );
        steps.add(
          DecisionStep(
            question: 'HE-SIG-A1 B0 (Format)?',
            answer: su ? 'B0 = 1.' : 'B0 = 0.',
            conclusion: su ? 'HE SU.' : 'HE TB.',
            evidence: _s2,
          ),
        );
        return Classification(
          steps,
          su ? DetectedFormat.heSu : DetectedFormat.heTb,
        );
      case 2:
        final bool er = o.secondHeSigA == SymbolLook.qbpsk;
        steps.add(
          const DecisionStep(
            question: 'L-SIG LENGTH mod 3?',
            answer: 'LENGTH mod 3 = 2.',
            conclusion: 'HE MU, or HE ER SU. Check the second HE-SIG-A symbol.',
            evidence: _s2,
          ),
        );
        steps.add(
          DecisionStep(
            question: 'Is the second HE-SIG-A symbol QBPSK?',
            answer: er ? 'Yes.' : 'No, BPSK.',
            conclusion: er ? 'HE ER SU.' : 'HE MU.',
            evidence: _s1,
          ),
        );
        return Classification(
          steps,
          er ? DetectedFormat.heErSu : DetectedFormat.heMu,
        );
      default:
        final bool eht = o.uSigVersion == 0;
        steps.add(
          const DecisionStep(
            question: 'L-SIG LENGTH mod 3?',
            answer: 'LENGTH mod 3 = 0.',
            conclusion: 'EHT or later. Read U-SIG B0-B2.',
            evidence: _s1,
          ),
        );
        steps.add(
          DecisionStep(
            question: 'U-SIG PHY Version Identifier (B0-B2)?',
            answer: 'Version ${o.uSigVersion ?? '?'}.',
            conclusion: eht ? 'EHT.' : 'A PHY later than EHT.',
            evidence: _s1,
          ),
        );
        return Classification(
          steps,
          eht ? DetectedFormat.eht : DetectedFormat.laterThanEht,
        );
    }
  }
  steps.add(
    const DecisionStep(
      question: 'Does it repeat L-SIG exactly?',
      answer: 'No.',
      conclusion: 'VHT or non-HT. Check the second symbol after L-SIG.',
      evidence: _s2,
    ),
  );
  final bool vht = o.secondAfterLsig == SymbolLook.qbpsk;
  steps.add(
    DecisionStep(
      question: 'Is the second symbol after L-SIG QBPSK?',
      answer: vht ? 'Yes.' : 'No, ${o.secondAfterLsig.label}.',
      conclusion: vht
          ? 'VHT: that symbol is VHT-SIG-A2.'
          : 'Non-HT: the data starts right after L-SIG.',
      evidence: _s2,
    ),
  );
  return Classification(steps, vht ? DetectedFormat.vht : DetectedFormat.nonHt);
}

// ── BSS color (brief section 5) ────────────────────────────────────────────

/// Where the 6-bit BSS color sits for [t], or null when it has none.
({String symbol, int start, int end})? bssColorPosition(PpduType t) {
  final SigTable? table = switch (t) {
    PpduType.heSu => heSigASuTable(erSu: false),
    PpduType.heErSu => heSigASuTable(erSu: true),
    PpduType.heMu => kHeSigAMuTable,
    PpduType.heTb => kHeSigATbTable,
    PpduType.ehtMu => uSigTable(tb: false),
    PpduType.ehtTb => uSigTable(tb: true),
    _ => null,
  };
  if (table == null) return null;
  final ({BitGroup group, BitField field})? hit = table.find('BSS Color');
  if (hit == null) return null;
  return (
    symbol: hit.group.title,
    start: hit.field.start!,
    end: hit.field.end!,
  );
}

// ── Formatting ─────────────────────────────────────────────────────────────

/// 432 -> "43.2", 200 -> "20".
String formatPreambleTenths(int tenths) => _fmtTenths(tenths);

String _fmtTenths(int tenths) {
  if (tenths % 10 == 0) return '${tenths ~/ 10}';
  final String sign = tenths < 0 ? '-' : '';
  final int a = tenths.abs();
  return '$sign${a ~/ 10}.${a % 10}';
}

int _ceilDiv(int a, int b) {
  assert(b > 0);
  return a >= 0 ? (a + b - 1) ~/ b : -((-a) ~/ b);
}
