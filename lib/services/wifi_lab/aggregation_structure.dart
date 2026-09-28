// Frame structure for Airtime Anatomy (Wi-Fi Classroom, 1.11.0,
// aggregation-structure). A pure-Dart model of what is INSIDE the PSDU the
// time view draws: one MPDU, an A-MSDU, an A-MPDU, or an A-MPDU of A-MSDUs,
// byte by byte, and what the sender has to send again when one subframe
// arrives corrupted. No Flutter imports.
//
// THE TWO AGGREGATES (IEEE 802.11-2020, the A-MSDU and A-MPDU formats).
//   A-MSDU (aggregate MAC service data unit): ONE MAC header, several
//     A-MSDU subframes, each a 14-byte subframe header (DA 6, SA 6, Length 2)
//     plus its MSDU, padded to a 4-byte boundary except the last, then ONE
//     FCS over the whole thing. One bad bit fails that FCS, the receiver
//     cannot tell which subframe was hit, and the whole MPDU is resent.
//   A-MPDU (aggregate MAC protocol data unit): several A-MPDU subframes,
//     each a 4-byte MPDU delimiter, a whole MPDU with its OWN MAC header and
//     FCS, and padding to a 4-byte boundary. Each subframe is checked on its
//     own, the Block Ack bitmap reports each one, and only a failed subframe
//     is resent.
//   An A-MPDU of A-MSDUs puts an A-MSDU in each A-MPDU subframe, so one bad
//   MSDU costs the whole A-MSDU it sits in, and nothing more.
//
// LINKED TO THE TIME VIEW. Every size comes from the same AirtimeScenario and
// the same constants as airtime_anatomy.dart (26-byte QoS data header,
// 4-byte FCS, 4-byte delimiter, the encryption bytes), and the same rules for
// when a PSDU is an A-MPDU: VHT and HE always send one (a single MPDU goes as
// a one-subframe A-MPDU); HT only for two or more MPDUs; Legacy never. So the
// A-MPDU arrangement IS the aggregate the time view draws: its PSDU bytes
// equal AirtimeResult.psduBytes, and its PPDU time equals ppduTenths.
//
// LIMITS: the per-PHY maxima Pax pinned (end of this file). LEFT OUT, and
// said so in help: the limits Pax could not pin, the HT Control field, security header
// and MIC shown as one block, a damaged delimiter (the receiver hunting for
// the next delimiter signature), and the retry's own framing (the resent
// bytes are timed as a new PPDU of exactly those bytes).

import 'airtime_anatomy.dart';

/// How the MSDUs are packed into the PSDU.
enum AggregationKind {
  singleMpdu('Single MPDU', 'One MSDU in one MPDU, acknowledged with an ACK'),
  amsdu('A-MSDU', 'Several MSDUs under one MAC header and one FCS'),
  ampdu('A-MPDU', 'Several MPDUs, each with its own header and FCS'),
  ampduOfAmsdus('A-MPDU of A-MSDUs', 'An A-MSDU inside every A-MPDU subframe');

  const AggregationKind(this.label, this.description);

  final String label;
  final String description;

  bool get usesAmsdu =>
      this == AggregationKind.amsdu || this == AggregationKind.ampduOfAmsdus;

  bool get usesAmpduSubframes =>
      this == AggregationKind.ampdu || this == AggregationKind.ampduOfAmsdus;
}

/// Sizes from the 802.11 frame formats, bytes. The header, FCS and
/// delimiter are the airtime sheet's own constants, so the two views cannot
/// drift apart.
class AggregationConstants {
  AggregationConstants._();

  static const int macHeaderBytes = AirtimeConstants.qosDataHeaderBytes;
  static const int fcsBytes = AirtimeConstants.fcsBytes;
  static const int delimiterBytes = AirtimeConstants.ampduDelimiterBytes;

  /// A-MSDU subframe header: DA 6 + SA 6 + Length 2.
  static const int amsduSubframeHeaderBytes = 14;

  /// A-MSDU and A-MPDU subframes pad to a multiple of this.
  static const int alignmentBytes = 4;

  /// MSDUs per A-MSDU the view offers. A teaching choice, not a limit from
  /// the standard; the per-PHY maximum A-MSDU length is not checked.
  static const List<int> msdusPerAmsduChoices = <int>[2, 3, 4];

  static const int defaultMsdusPerAmsdu = 3;
}

/// Whether [phy] can send [kind]. Legacy (802.11a/g) has no aggregation;
/// A-MSDU and A-MPDU both arrived with HT.
bool aggregationSupported(AirtimePhy phy, AggregationKind kind) =>
    phy != AirtimePhy.legacy || kind == AggregationKind.singleMpdu;

/// One piece of an MPDU or an A-MPDU subframe, in transmit order.
enum StructurePartKind {
  delimiter('MPDU delimiter'),
  macHeader('MAC header'),
  security('Security header and MIC'),
  subframeHeader('A-MSDU subframe header'),
  msdu('MSDU'),
  amsduPadding('A-MSDU padding'),
  fcs('FCS'),
  ampduPadding('A-MPDU padding');

  const StructurePartKind(this.label);

  final String label;

  bool get isPadding =>
      this == StructurePartKind.amsduPadding ||
      this == StructurePartKind.ampduPadding;
}

class StructurePart {
  const StructurePart(this.kind, this.bytes, {this.msduIndex});

  final StructurePartKind kind;
  final int bytes;

  /// For an MSDU, its A-MSDU subframe header and its padding: the MSDU's
  /// index within the whole aggregate, 0-based. Null for the rest.
  final int? msduIndex;
}

/// One retransmission unit: an A-MPDU subframe, or the lone MPDU when the
/// PSDU is not an A-MPDU. The receiver checks each unit's FCS on its own, so
/// a unit is also the smallest thing that can be resent.
class StructureUnit {
  const StructureUnit({
    required this.index,
    required this.parts,
    required this.firstMsdu,
    required this.msduCount,
  });

  final int index;
  final List<StructurePart> parts;

  /// Index of the unit's first MSDU in the aggregate, 0-based.
  final int firstMsdu;
  final int msduCount;

  int get bytes => parts.fold<int>(0, (int a, StructurePart p) => a + p.bytes);

  /// The MPDU alone: everything but the delimiter and the A-MPDU padding.
  int get mpduBytes => parts
      .where(
        (StructurePart p) =>
            p.kind != StructurePartKind.delimiter &&
            p.kind != StructurePartKind.ampduPadding,
      )
      .fold<int>(0, (int a, StructurePart p) => a + p.bytes);

  bool holdsMsdu(int m) => m >= firstMsdu && m < firstMsdu + msduCount;

  /// The A-MSDU inside this MPDU: its subframe headers, MSDUs and padding,
  /// without the MAC header, security bytes or FCS. For a plain MPDU, just
  /// the MSDU.
  int get amsduBytes => parts
      .where(
        (StructurePart p) =>
            p.kind == StructurePartKind.subframeHeader ||
            p.kind == StructurePartKind.msdu ||
            p.kind == StructurePartKind.amsduPadding,
      )
      .fold<int>(0, (int a, StructurePart p) => a + p.bytes);
}

/// What one corrupted MSDU costs.
class CorruptionOutcome {
  const CorruptionOutcome({
    required this.corruptedMsdu,
    required this.failedUnit,
    required this.resentBytes,
    required this.resentMsdus,
    required this.blockAckBitmap,
  });

  final int corruptedMsdu;

  /// The unit whose FCS fails.
  final int failedUnit;

  /// Bytes sent again: the failed unit, delimiter and padding included.
  final int resentBytes;

  /// MSDUs sent again, the good ones riding along with the bad one included.
  final int resentMsdus;

  /// Block Ack bitmap, one bit per A-MPDU subframe (true = received), or
  /// null when the response is a plain ACK (one unit). With a plain ACK a
  /// failed FCS means no ACK at all.
  final List<bool>? blockAckBitmap;

  bool get usesBlockAck => blockAckBitmap != null;
}

/// Byte totals by part kind, over the whole aggregate.
class StructureTotals {
  const StructureTotals(this.byKind);

  final Map<StructurePartKind, int> byKind;

  int operator [](StructurePartKind k) => byKind[k] ?? 0;

  int get total => byKind.values.fold<int>(0, (int a, int b) => a + b);

  int get payload => this[StructurePartKind.msdu];

  int get overhead => total - payload;
}

/// The whole PSDU for one arrangement of one scenario.
class AggregateStructure {
  const AggregateStructure._({
    required this.kind,
    required this.scenario,
    required this.inAmpdu,
    required this.msdusPerMpdu,
    required this.units,
  });

  final AggregationKind kind;
  final AirtimeScenario scenario;

  /// True when the PSDU is an A-MPDU, so every unit carries a delimiter and
  /// pads to 4 bytes.
  final bool inAmpdu;

  /// 1, or the MSDUs per A-MSDU.
  final int msdusPerMpdu;
  final List<StructureUnit> units;

  int get unitCount => units.length;
  int get msduCount => units.length * msdusPerMpdu;

  /// PSDU length: every byte the data symbols carry.
  int get psduBytes =>
      units.fold<int>(0, (int a, StructureUnit u) => a + u.bytes);

  /// One unit is acknowledged with an ACK, two or more with a Block Ack,
  /// the time view's rule.
  bool get usesBlockAck => units.length > 1;

  StructureTotals get totals {
    final Map<StructurePartKind, int> m = <StructurePartKind, int>{};
    for (final StructureUnit u in units) {
      for (final StructurePart p in u.parts) {
        m[p.kind] = (m[p.kind] ?? 0) + p.bytes;
      }
    }
    return StructureTotals(m);
  }

  int unitOfMsdu(int m) {
    RangeError.checkValidIndex(m, null, 'm', msduCount);
    return m ~/ msdusPerMpdu;
  }

  /// Corrupts one bit inside MSDU [m] (0-based) and returns what is resent.
  CorruptionOutcome corrupt(int m) {
    final int u = unitOfMsdu(m);
    final StructureUnit unit = units[u];
    return CorruptionOutcome(
      corruptedMsdu: m,
      failedUnit: u,
      resentBytes: unit.bytes,
      resentMsdus: unit.msduCount,
      blockAckBitmap: usesBlockAck
          ? List<bool>.unmodifiable(<bool>[
              for (int i = 0; i < units.length; i++) i != u,
            ])
          : null,
    );
  }
}

/// Builds [kind] from [s]: the same payload, encryption and PHY the time
/// view uses, [AirtimeScenario.framesAggregated] A-MPDU subframes, and
/// [msdusPerAmsdu] MSDUs in each A-MSDU.
///
/// Single MPDU: 1 unit, 1 MSDU. A-MSDU: 1 unit, [msdusPerAmsdu] MSDUs.
/// A-MPDU: framesAggregated units of 1 MSDU. A-MPDU of A-MSDUs:
/// framesAggregated units of [msdusPerAmsdu] MSDUs.
///
/// Throws [ArgumentError] when [aggregationSupported] is false.
AggregateStructure buildAggregateStructure(
  AirtimeScenario s,
  AggregationKind kind, {
  int msdusPerAmsdu = AggregationConstants.defaultMsdusPerAmsdu,
}) {
  if (!aggregationSupported(s.phy, kind)) {
    throw ArgumentError.value(kind, 'kind', 'not available on ${s.phy.label}');
  }
  if (msdusPerAmsdu < 1) {
    throw ArgumentError.value(msdusPerAmsdu, 'msdusPerAmsdu', 'must be >= 1');
  }
  final int perMpdu = kind.usesAmsdu ? msdusPerAmsdu : 1;
  final int unitCount = kind.usesAmpduSubframes ? s.framesAggregated : 1;

  // The time view's rule for when the PSDU is an A-MPDU.
  final bool inAmpdu = switch (s.phy) {
    AirtimePhy.legacy => false,
    AirtimePhy.ht => unitCount >= 2,
    AirtimePhy.vht || AirtimePhy.he => true,
  };

  const int align = AggregationConstants.alignmentBytes;
  final List<StructureUnit> units = <StructureUnit>[];
  for (int u = 0; u < unitCount; u++) {
    final int first = u * perMpdu;
    final List<StructurePart> mpdu = <StructurePart>[
      const StructurePart(
        StructurePartKind.macHeader,
        AggregationConstants.macHeaderBytes,
      ),
      if (s.encryptionBytes > 0)
        StructurePart(StructurePartKind.security, s.encryptionBytes),
    ];
    if (kind.usesAmsdu) {
      for (int j = 0; j < perMpdu; j++) {
        final int m = first + j;
        final int sub =
            AggregationConstants.amsduSubframeHeaderBytes + s.payloadBytes;
        mpdu
          ..add(
            StructurePart(
              StructurePartKind.subframeHeader,
              AggregationConstants.amsduSubframeHeaderBytes,
              msduIndex: m,
            ),
          )
          ..add(
            StructurePart(StructurePartKind.msdu, s.payloadBytes, msduIndex: m),
          );
        // Every A-MSDU subframe but the last pads to 4 bytes.
        final int pad = j == perMpdu - 1 ? 0 : _padTo(sub, align);
        if (pad > 0) {
          mpdu.add(
            StructurePart(StructurePartKind.amsduPadding, pad, msduIndex: m),
          );
        }
      }
    } else {
      mpdu.add(
        StructurePart(StructurePartKind.msdu, s.payloadBytes, msduIndex: first),
      );
    }
    mpdu.add(
      const StructurePart(StructurePartKind.fcs, AggregationConstants.fcsBytes),
    );

    final List<StructurePart> parts;
    if (inAmpdu) {
      final int mpduBytes = mpdu.fold<int>(
        0,
        (int a, StructurePart p) => a + p.bytes,
      );
      final int pad = _padTo(
        AggregationConstants.delimiterBytes + mpduBytes,
        align,
      );
      parts = <StructurePart>[
        const StructurePart(
          StructurePartKind.delimiter,
          AggregationConstants.delimiterBytes,
        ),
        ...mpdu,
        if (pad > 0) StructurePart(StructurePartKind.ampduPadding, pad),
      ];
    } else {
      parts = mpdu;
    }
    units.add(
      StructureUnit(
        index: u,
        parts: List<StructurePart>.unmodifiable(parts),
        firstMsdu: first,
        msduCount: perMpdu,
      ),
    );
  }

  return AggregateStructure._(
    kind: kind,
    scenario: s,
    inAmpdu: inAmpdu,
    msdusPerMpdu: perMpdu,
    units: List<StructureUnit>.unmodifiable(units),
  );
}

/// Bytes of padding that bring [n] up to a multiple of [align].
int _padTo(int n, int align) => (align - n % align) % align;

// ── Limits from the standard (1.11.0 follow-up) ─────────────────────────────
//
// Source: Pax, myPKA Deliverables/2026-09-27-classroom-interferer-and-ds-
// sources/RESEARCH-BRIEF.md Part 3. Only the values Pax marks as held (two
// sources agree) are checked. Not checked, and said so in help: the HE
// Maximum MPDU Length (one source or inference per band), the smaller
// A-MPDU limit an HE receiver advertises in 2.4 and 6 GHz, and everything
// EHT (not modeled here; its A-MPDU maximum is disputed, 15,523,198 vs
// 15,523,200).

/// The pinned caps, octets unless named otherwise.
class AggregationLimits {
  AggregationLimits._();

  /// HT Maximum A-MSDU Length, the two values the 1-bit field selects.
  static const List<int> htAmsdu = <int>[3839, 7935];

  /// HT delimiter MPDU Length is 12 bits: an MPDU in an HT A-MPDU is at
  /// most 2^12 - 1 octets.
  static const int htMpduInAmpdu = 4095;

  /// VHT Maximum MPDU Length, field values 0, 1, 2.
  static const List<int> vhtMpdu = <int>[3895, 7991, 11454];

  /// Maximum A-MPDU length, 2^(13 + exponent) - 1 at the largest exponent.
  static const int htAmpdu = 65535;
  static const int vhtAmpdu = 1048575;

  /// HE PSDU maximum, which an HE A-MPDU cannot exceed.
  static const int hePsdu = 6500631;

  /// aPPDUMaxTime, us: HT-mixed, VHT and HE.
  static const int ppduMaxTimeUs = AirtimeConstants.maxPpduUs;

  /// Delimiter MPDU Length field width, bits.
  static const int htDelimiterLengthBits = 12;
  static const int vhtDelimiterLengthBits = 14;

  /// The largest A-MSDU an HT A-MPDU can carry: the 4,095-octet MPDU less
  /// the MAC header, the security bytes and the FCS. 4,065 unencrypted.
  static int htAmsduInAmpdu(int encryptionBytes) =>
      htMpduInAmpdu -
      AggregationConstants.macHeaderBytes -
      AggregationConstants.fcsBytes -
      encryptionBytes;
}

/// How a value stands against a limit.
enum LimitVerdict {
  /// Within the cap at every setting.
  ok,

  /// Within the cap only if the receiver advertises a larger setting.
  needsLargerSetting,

  /// Over the largest value the standard allows.
  exceeds,
}

enum AggregationLimitKind {
  htAmsdu('A-MSDU length (HT)'),
  htMpduInAmpdu('MPDU length in an HT A-MPDU'),
  vhtMpdu('MPDU length (VHT)'),
  ampdu('A-MPDU length'),
  ppduTime('PPDU duration');

  const AggregationLimitKind(this.label);

  final String label;
}

/// One limit, the value it is measured on, and the verdict.
class AggregationLimitCheck {
  const AggregationLimitCheck({
    required this.kind,
    required this.value,
    required this.cap,
    required this.settings,
    required this.verdict,
  });

  final AggregationLimitKind kind;

  /// Octets, or tenths of a us for [AggregationLimitKind.ppduTime].
  final int value;

  /// The largest value allowed (the top setting where there are several).
  final int cap;

  /// Every setting a receiver can advertise, ascending; just [cap] when
  /// the limit has one value.
  final List<int> settings;

  final LimitVerdict verdict;

  /// The smallest advertised setting that fits, or null when none does.
  int? get smallestFitting {
    for (final int s in settings) {
      if (value <= s) return s;
    }
    return null;
  }
}

AggregationLimitCheck _tiers(
  AggregationLimitKind kind,
  int value,
  List<int> settings,
) {
  final LimitVerdict v = value > settings.last
      ? LimitVerdict.exceeds
      : value > settings.first
      ? LimitVerdict.needsLargerSetting
      : LimitVerdict.ok;
  return AggregationLimitCheck(
    kind: kind,
    value: value,
    cap: settings.last,
    settings: settings,
    verdict: v,
  );
}

AggregationLimitCheck _single(AggregationLimitKind kind, int value, int cap) =>
    _tiers(kind, value, <int>[cap]);

/// HT A-MSDU length against 3,839 / 7,935.
AggregationLimitCheck checkHtAmsdu(int amsduBytes) =>
    _tiers(AggregationLimitKind.htAmsdu, amsduBytes, AggregationLimits.htAmsdu);

/// An MPDU inside an HT A-MPDU against the 12-bit delimiter's 4,095.
AggregationLimitCheck checkHtMpduInAmpdu(int mpduBytes) => _single(
  AggregationLimitKind.htMpduInAmpdu,
  mpduBytes,
  AggregationLimits.htMpduInAmpdu,
);

/// A VHT MPDU against 3,895 / 7,991 / 11,454.
AggregationLimitCheck checkVhtMpdu(int mpduBytes) =>
    _tiers(AggregationLimitKind.vhtMpdu, mpduBytes, AggregationLimits.vhtMpdu);

/// The A-MPDU (the PSDU) against the PHY's maximum, or null for a PHY
/// with no pinned cap (Legacy has no A-MPDU).
AggregationLimitCheck? checkAmpdu(AirtimePhy phy, int psduBytes) {
  final int? cap = switch (phy) {
    AirtimePhy.ht => AggregationLimits.htAmpdu,
    AirtimePhy.vht => AggregationLimits.vhtAmpdu,
    AirtimePhy.he => AggregationLimits.hePsdu,
    AirtimePhy.legacy => null,
  };
  return cap == null
      ? null
      : _single(AggregationLimitKind.ampdu, psduBytes, cap);
}

/// Preamble plus data against aPPDUMaxTime, 5.484 ms (HT, VHT, HE).
AggregationLimitCheck? checkPpduTime(AirtimePhy phy, int ppduTenths) =>
    phy == AirtimePhy.legacy
    ? null
    : _single(
        AggregationLimitKind.ppduTime,
        ppduTenths,
        AggregationLimits.ppduMaxTimeUs * 10,
      );

/// Every pinned limit that applies to [st]. [ppduTenths] is the PSDU's
/// preamble plus data, or null when the scenario has no valid airtime.
List<AggregationLimitCheck> checkAggregationLimits(
  AggregateStructure st, {
  int? ppduTenths,
}) {
  final AirtimePhy phy = st.scenario.phy;
  final StructureUnit u = st.units.first; // every unit is the same size
  final List<AggregationLimitCheck> out = <AggregationLimitCheck>[];
  if (phy == AirtimePhy.ht) {
    if (st.kind.usesAmsdu) out.add(checkHtAmsdu(u.amsduBytes));
    if (st.inAmpdu) out.add(checkHtMpduInAmpdu(u.mpduBytes));
  }
  if (phy == AirtimePhy.vht) out.add(checkVhtMpdu(u.mpduBytes));
  if (st.inAmpdu) {
    final AggregationLimitCheck? a = checkAmpdu(phy, st.psduBytes);
    if (a != null) out.add(a);
  }
  if (ppduTenths != null) {
    final AggregationLimitCheck? t = checkPpduTime(phy, ppduTenths);
    if (t != null) out.add(t);
  }
  return out;
}
